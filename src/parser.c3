module ser;

import libc;
import std::collections::elastic_array;
import util;
import std::math;
import std::io;

const MAX_STR_LEN   = 64;
const MAX_DIGIT_LEN = 32;
const MAX_COMMENT_LEN = 64;
alias SkipCallback  = fn bool(char);
alias CommentString = ElasticArray{char, MAX_COMMENT_LEN};

/* Example format
	; field_name
	123,      // int
	"hello",  // string
	228.0,	  // float/double
	[			// array open
		{		// table open
			123,      // int
			"hello",  // string
			228.0,	  // float/double
		}		// table close
	]			// array close
*/

struct Parser
{
	char[]    buff_view;
	usz       curr;
	usz       end;
	usz	      curr_line;
}

enum TokenChar : const inline char
{
	ARRAY_START 	= '[',
	ARRAY_END   	= ']',
	STRUCT_START	= '{',
	STRUCT_END  	= '}',
	STRING_START	= '"',
	STRING_END		= '"',
	VEC_START		= '<',
	VEC_END			= '>',
	MAT_START		= '#',
	MAT_END			= '#',
	COMMENT			= ';',
	COMMA			= ',',
}

enum BoolAsString : const inline char[]
{
	TRUE  = "true",
	FALSE = "false",
}

fn void Parser.init(&parser, char[] data)
{
	parser.buff_view = data;
	parser.curr = 0;
	parser.end = data.len - 1;
	parser.curr_line = 0;
	parser.skip_ws();
}

fn void Parser.reset(&parser)
{
	mem::set(parser, 0, Parser.sizeof);
}

fn bool Parser.is_initialized(&parser)
{
	return parser.buff_view.ptr && parser.buff_view.len > 0;
}

<*
	High level wrapper over 'parse_any'
*>
macro void Parser.parse_curr_value_and_skip_to_next(&parser, out_val, bool is_last = false)
{
	parser.parse_recur_into(out_val);
	if (!is_last) {
		parser.skip_until_next_value_start();
	}
}

<*
	High level wrapper over 'parse_any'
*>
macro void Parser.parse_recur_into(&parser, out_val)
{
	var $ValType = $typeof(out_val);
	SchemaFormatKind $root_fmt_kind = $ValType.has_tagof(SCHEMA_FMT_TAG) ??? $ValType.tagof(SCHEMA_FMT_TAG) : SchemaFormatKind.DEFAULT;
	parser.parse_any(out_val, $root_fmt_kind);
}

macro void Parser.parse_any(
	&parser,
	curr_val,
	SchemaFormatKind $fmt_kind = DEFAULT,
	bool $unwrap_distinct = false,
)
{
	parser.skip_ws();

	if (parser.curr_char() == TokenChar.COMMENT) {
		parser.skip_line();
		parser.skip_ws();
	}

	var $Type = $typeof(curr_val);
	var $kind = $Type.kindof;

	$if $kind == POINTER:
		$Type = $Type.inner;
		$kind = $Type.kindof;
	$endif

	$if $unwrap_distinct && $kind == DISTINCT:
		$fmt_kind = $Type.has_tagof(SCHEMA_FMT_TAG) ??? $Type.tagof(SCHEMA_FMT_TAG) : $fmt_kind;
		$Type = $Type.inner;
		$kind = $Type.kindof;
	$endif

// NOTE: DEBUG
	// io::printfn("Parser: curr char: %c, index: %d remain_distance: %d kind: %s, $unwrap_dist: %s", parser.curr_char(), parser.curr, parser.end - parser.curr, $kind, $unwrap_distinct);

	$switch ($kind):
	$case DISTINCT:
		parser.parse_any(curr_val, $fmt_kind, true);
	$case STRUCT:
	$case BITSTRUCT:
		$switch $Type:
		$case Matrix2x2{float}:
		$case Matrix3x3{float}:
		$case Matrix4x4{float}:
		$case Matrix2x2{double}:
		$case Matrix3x3{double}:
		$case Matrix4x4{double}:
			parser.parse_mat(curr_val.m[:curr_val.m.len]);
		$default:
			parser.parse_struct(curr_val, $fmt_kind);
		$endswitch
	$case ARRAY:
		$switch ($fmt_kind):
		$case SchemaFormatKind.STRING:
			parser.parse_string(curr_val[:curr_val.len]);
		$case SchemaFormatKind.VECTOR:
			parser.parse_vec(curr_val[:curr_val.len]);
		$case SchemaFormatKind.MATRIX:
			parser.parse_mat(curr_val[:curr_val.len]);
		$default:
			parser.parse_array(curr_val[:curr_val.len], $fmt_kind);
		$endswitch
	$case SLICE:
		$switch ($fmt_kind):
		$case SchemaFormatKind.STRING:
			parser.parse_string(curr_val);
		$case SchemaFormatKind.VECTOR:
			parser.parse_vec(curr_val);
		$case SchemaFormatKind.MATRIX:
			parser.parse_mat(curr_val);
		$default:
			parser.parse_array(curr_val, $fmt_kind);
		$endswitch
	$case VECTOR:
		parser.parse_vec(curr_val);
	$case SIGNED_INT:
	$case UNSIGNED_INT:
	$case FLOAT:
		parser.parse_number(curr_val);
	$case BOOL:
		parser.parse_boolean(curr_val);
	$case ENUM:
		parser.parse_plain_enum(curr_val);
	$case CONST_ENUM:
		parser.parse_const_enum(curr_val);
	$default:
		unreachable("Unsupported type for parsing: %s, value: %s", $Type, curr_val);
	$endswitch

	if (parser.skip_until_next_value_start()) {
		return;
	}
}

<*
	@require $typeof(out_value).kindof == POINTER : "Should be a pointer"
	@require parser.curr_char() == TokenChar.STRUCT_START : "Should be at the start of struct"
*>
macro void Parser.parse_struct(
	&parser,
	out_value,
	SchemaFormatKind $fmt_kind = DEFAULT,
)
{
	parser.step();
	assert(!parser.is_at_end(), "Shouldn't be at the end here");

	var $RootType = $typeof(out_value);
	var $Type = util::@get_pointee_type_val(out_value);

	$foreach $mem : $Type.membersof:
		var $name = $mem.nameof;
		$if $name.len:
			bool $is_distinct = $mem.kindof == DISTINCT;
			$fmt_kind = $mem.has_tagof(SCHEMA_FMT_TAG) ??? $mem.tagof(SCHEMA_FMT_TAG) : $fmt_kind;

			$if $is_distinct:
				parser.parse_any(&out_value.$eval($name), $fmt_kind, true);
			$else
				$if $mem.kindof == ARRAY:
					$switch:
						// NOTE: ElasticArray special case
					$case $defined(out_value.array_view()):
						parser.parse_any(out_value.array_view(), $fmt_kind);
						// NOTE: DString special case
					$case $defined(out_value.str_view()):
						parser.parse_any(out_value.str_view(), STRING);
					$default:
						parser.parse_any(out_value.$eval($name)[..], $fmt_kind);
					$endswitch
				$else
					parser.parse_any(&out_value.$eval($name), $fmt_kind);
				$endif
			$endif
		$endif
	$endforeach

	parser.skip_until_struct_end();
}

<*
	@require util::is_kindof($typeof(out_array), SLICE, POINTER, DISTINCT) : "Should be a slice or pointer to array"
	@require parser.curr_char() == TokenChar.ARRAY_START : "Should be at the start of array"
*>
macro void Parser.parse_array(
	&parser,
	out_array,
	SchemaFormatKind $fmt_kind = DEFAULT,
) @local
{
	parser.step();
	assert(!parser.is_at_end(), "Shouldn't be at the end here");

	foreach (&item : out_array) {
		parser.parse_any(item, $fmt_kind);
	}

	parser.skip_until_array_end();
}

<*
	@require parser.curr_char() == '\"'
	@require parser.end - parser.curr > 1 : "Buffer shouldn't end with a quote"
	@require parser.next_char().is_alpha() : "Next symbol should be an ascii letter [a-zA-Z]"
*>
macro void Parser.parse_string(&parser, out_str)
{
	// step after opening quote
	parser.step();
	char[] contents = parser.read_until_curr_char(TokenChar.STRING_END);
	assert(contents.len > 0, "Should move at least 1 character");
	assert((contents.len <= out_str.len), "Should not exceed out_str.len");
	mem::copy(out_str, contents.ptr, contents.len);
	assert(parser.curr_char() == TokenChar.STRING_END, "String should end with a quote");
	assert(parser.remain_dist() >= 1);
	// step after closing quote
	parser.step();
}

<*
	@require parser.curr_char() == TokenChar.ARRAY_START
	@require parser.next_char() == TokenChar.VEC_START
	@require parser.end - parser.curr > 2 : "Buffer shouldn't end that fast"
*>
macro void Parser.parse_vec(&parser, out_vec)
{
	parser.step_n(2);

	foreach (&vec_el : out_vec) {
		parser.parse_number(vec_el);
		parser.skip_ws_or_comma();
	}

	assert(parser.remain_dist() >= 2, "Vector should end with <]");
	assert(parser.curr_char() == TokenChar.VEC_END, "Vector should end with <]");
	assert(parser.next_char() == TokenChar.ARRAY_END, "Vector should end with <]");
	parser.step_n(2);
}

<*
	@require parser.curr_char() == TokenChar.ARRAY_START : "Matrix should start with [#"
	@require parser.next_char() == TokenChar.MAT_START : "Matrix should start with [#"
	@require parser.end - parser.curr > 1 : "Buffer shouldn't end that fast"
*>
macro void Parser.parse_mat(&parser, out_mat)
{
	parser.step_n(2);
	parser.skip_ws();

	foreach (&mat_el : out_mat) {
		parser.parse_number(mat_el);
		parser.skip_ws_or_comma();
	}

	assert(parser.remain_dist() >= 2, "Matrix should end with 2 symbols");
	assert(parser.curr_char() == TokenChar.MAT_END, "Matrix should end with #");
	assert(parser.next_char() == TokenChar.ARRAY_END, "Matrix should end with ]");

	parser.step_n(2);
}

<*
	@require parser.curr_char() == 't' || parser.curr_char() == 'f' : "Should start from 't' for true or from 'f' for false"
	@require parser.end - parser.curr >= "true".len : "Buffer should have enough space"
	@require parser.next_char().is_alpha() : "Next symbol should be an ascii letter [a-zA-Z]"
*>
fn void Parser.parse_boolean(&parser, bool* out_bool)
{
	usz start = parser.curr;
	char[] bool_value = parser.read_until_value_end();
	assert(bool_value.len > 0, "Should move at least 1 character");
	assert(bool_value.len >= "true".len, "Should move at least 4 == \"true\".len characters");

	if (mem::equals((char[])BoolAsString.TRUE, bool_value)) {
		*out_bool = true;
	}
	else if (mem::equals((char[])BoolAsString.FALSE, bool_value)) {
		*out_bool = false;
	}
	else {
		unreachable("unrecognized value for boolean: %s", (String)bool_value);
	}
}


<*
	@require $typeof(out_value).kindof == POINTER : "Should be a pointer"
	@require util::is_kindof($typeof(out_value).inner, UNSIGNED_INT, SIGNED_INT, FLOAT) : "Should be of number type"
	@require parser.curr_char().is_digit() || is_digit_sign(parser.curr_char()) : "Character we currently on should be either a digit or a sign"
*>
macro void Parser.parse_number(&parser, out_value)
{
	ElasticArray{char, MAX_DIGIT_LEN} digit_buff;
	parser.parse_num_private(&digit_buff);
	char[] digit_as_chars = digit_buff.array_view();

	var $Type = util::@get_pointee_type_val(out_value);
	$switch $Type.sizeof:
	$case char.sizeof:
	$case short.sizeof:
	$case int.sizeof:
		$if types::is_int($Type):
			*out_value = ($Type)libc::atoi(digit_as_chars);
		$else
			*out_value = libc::strtof(digit_as_chars, null);
		$endif
	$case long.sizeof:
		$if types::is_int($Type):
			*out_value = ($Type)libc::atoll(digit_as_chars);
		$else
			*out_value = libc::strtod(digit_as_chars, null);
		$endif
	$default:
		unreachable("Type must be one of this: SIGNED_INT, UNSIGNED_INT, FLOAT, DOUBLE");
	$endswitch
}

<*
	@require $typeof(out_value).kindof == POINTER : "Should be a pointer"
	@require parser.curr_char().is_digit() : "Character we currently on should be either a digit or a sign"
*>
macro void Parser.parse_const_enum(&parser, out_value)
{
	ElasticArray{char, MAX_DIGIT_LEN} digit_buff;
	parser.parse_num_private(&digit_buff);
	char[] digit_as_chars = digit_buff.array_view();

	var $EnumType = util::@get_pointee_type_val(out_value);
	var $InnerType = $EnumType.inner;

	$switch ($InnerType.sizeof):
	$case char.sizeof:
	$case short.sizeof:
	$case int.sizeof:
		*out_value = ($EnumType)libc::atoi(digit_as_chars);
	$case long.sizeof:
		*out_value = ($EnumType)libc::atoll(digit_as_chars);
	$default:
		unreachable("Unknown size of type of const enum: %d", $InnerType.sizeof);
	$endswitch
}

<*
	@require $typeof(out_value).kindof == POINTER : "Should be a pointer"
	@require parser.curr_char().is_digit() : "Character we currently on should be either a digit or a sign"
*>
macro void Parser.parse_plain_enum(&parser, out_value)
{
	ElasticArray{char, MAX_DIGIT_LEN} digit_buff;
	parser.parse_num_private(&digit_buff);
	char[] digit_as_chars = digit_buff.array_view();

	var $EnumType = util::@get_pointee_type_val(out_value);
	var $OrdinalType = $EnumType.inner;

	$switch ($OrdinalType.sizeof):
	$case char.sizeof:
	$case short.sizeof:
	$case int.sizeof:
		*out_value = $EnumType.from_ordinal(($OrdinalType)libc::atoi(digit_as_chars));
	$case long.sizeof:
		*out_value = $EnumType.from_ordinal(($OrdinalType)libc::atoll(digit_as_chars));
	$default:
		unreachable("Unknown size of type of plain enum: %d", $OrdinalType.sizeof);
	$endswitch
}

fn void Parser.skip_comment(&parser)
{
	parser.skip_ws();
	if (parser.curr_char() != TokenChar.COMMENT) {
		return;
	}
	parser.skip_line();
	parser.skip_ws();
}

<*
	@require out_comment_value.size == 0 : "Should have zero values"
*>
fn char[] Parser.read_comment(&parser, CommentString* out_comment_value)
{
	if (parser.curr_char() != TokenChar.COMMENT) {
		return {};
	}

	parser.step();
	parser.skip_ws();
	char[] value = parser.read_while_curr_char_cb(&ascii::is_alpha);
	parser.skip_ws();
	return value;
}

fn void Parser.parse_num_private(&parser, ElasticArray{char, MAX_DIGIT_LEN}* digit_buff) @local
{
	usz start = parser.curr;
	bool is_digit = false;
	bool was_dot = false;

	while (parser.curr < parser.end)
	{
		char c = parser.curr_char();
		if (c.is_digit()) {
			parser.step();
			was_dot = false;
		} else if (c == '.') {
			assert(!was_dot, "Shouldn't be two dots together");
			was_dot = true;
			parser.step();
		} else {
			assert(!was_dot, "Should be digit after dot");
			break;
		}
	}

	assert(parser.curr > start, "Should be at least 1 digit in a number");
	assert((parser.curr - start) < MAX_DIGIT_LEN, "Should be at most 32 characters");
	digit_buff.push_all(parser.buff_view[start .. parser.curr - 1]);
}

fn void Parser.skip_until_struct_end(&parser)
{
	parser.skip_until_after_curr_char(TokenChar.STRUCT_END);
}

fn void Parser.skip_until_array_end(&parser)
{
	parser.skip_until_after_curr_char(TokenChar.ARRAY_END);
}

<*
	Returns true if end reached
*>
fn bool Parser.skip_ws(&parser) @private
{
	while (parser.curr < parser.end)
	{
		char c = parser.curr_char();
		if (!c.is_space()) {
			return false;
		}
		if (c == '\n') {
			parser.curr_line++;
		}
		parser.step();
	}
	return true;
}

<*
	Returns true if end reached
*>
fn bool Parser.skip_ws_or_comma(&parser) @private
{
	while (parser.curr < parser.end)
	{
		char c = parser.curr_char();
		if (!is_space_or_comma(c)) {
			return false;
		}
		if (c == '\n') {
			parser.curr_line++;
		}
		parser.step();
	}
	return true;
}

fn bool Parser.skip_line(&parser) @private
{
	parser.skip_until_after_curr_char('\n');
	return parser.is_at_end();
}

fn char[] Parser.read_until_value_end(&parser) @private
{
	usz start = parser.curr;
	parser.skip_until_curr_char_cb(&is_space_or_comma);
	return parser.buff_view[start : parser.curr - start];
}

fn bool Parser.skip_until_next_value_start(&parser) @private
{
	if (parser.curr < parser.end) {
		char c = parser.curr_char();
		while (parser.curr < parser.end) {
			if (!ascii::is_space(c) && c != TokenChar.COMMA && c != TokenChar.COMMENT) {
				break;
			}
			parser.skip_ws_or_comma();
			parser.skip_comment();
			c = parser.curr_char();
		}
	}
	return parser.is_at_end();
}

fn char[] Parser.read_until_curr_char(&parser, char c) @private
{
	usz start = parser.curr;
	while (parser.curr < parser.end && parser.curr_char() != c)
	{
		parser.step();
	}
	return parser.buff_view[start : parser.curr - start];
}

fn void Parser.skip_until_curr_char(&parser, char c) @private
{
	while (parser.curr < parser.end && parser.curr_char() != c)
	{
		parser.step();
	}
}

fn void Parser.skip_until_next_char(&parser, char c) @private
{
	while (parser.curr < parser.end && parser.next_char() != c)
	{
		parser.step();
	}
}

fn void Parser.skip_until_after_curr_char(&parser, char c) @private
{
	while (parser.curr < parser.end && parser.curr_char() != c)
	{
		parser.step();
	}
	if (parser.curr < parser.end) {
		parser.step();
	}
}

fn void Parser.skip_until_curr_char_cb(&parser, SkipCallback cb) @private
{
	while (parser.curr < parser.end && !cb(parser.curr_char()))
	{
		parser.step();
	}
}

fn char[] Parser.read_until_curr_char_cb(&parser, SkipCallback cb) @private
{
	usz start = parser.curr;
	while (parser.curr < parser.end && !cb(parser.curr_char()))
	{
		parser.step();
	}
	return parser.buff_view[start : parser.curr - start];
}

fn char[] Parser.read_while_curr_char_cb(&parser, SkipCallback cb) @private
{
	usz start = parser.curr;
	while (parser.curr < parser.end && cb(parser.curr_char()))
	{
		parser.step();
	}
	return parser.buff_view[start : parser.curr - start];
}

fn void Parser.debug_view(&parser, usz len = 50) @if(env::COMPILER_OPT_LEVEL.ordinal == 0)
{
	len = math::min(len, (usz)(parser.end - parser.curr + 1));
	io::printfn("Parser: closest values in buffer:\n\t%s", (String)parser.buff_view[parser.curr:len]);
}

fn char Parser.curr_char(&parser) @private @inline
{
	return parser.buff_view[parser.curr];
}

fn char Parser.next_char(&parser, uint offset = 0) @private @inline
{
	return parser.buff_view[parser.curr + 1 + offset];
}

fn char Parser.curr_char_and_next(&parser) @private @inline
{
	return parser.buff_view[parser.curr++];
}

fn void Parser.step(&parser) @private @inline
{
	parser.curr++;
}

<*
	@require count <= (parser.end - parser.curr) : "Shouldn't exceed bounds"
*>
fn void Parser.step_n(&parser, uint count) @private @inline
{
	parser.curr += count;
}

fn usz Parser.remain_dist(&parser) @private @inline
{
	return parser.end - parser.curr;
}

fn bool Parser.is_at_end(&parser) @private @inline
{
	return parser.curr == parser.end;
}

fn bool is_space_or_comma(char c)
{
	return ascii::is_space(c) || c == ',';
}

fn bool is_in_charset(char c, char[] charset) @private
{
	return array::contains(charset, c);
}

fn bool is_digit_sign(char c) @private
{
	return c == '-' || c == '+';
}
