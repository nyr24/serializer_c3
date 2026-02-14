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
	@require util::is_kindof($typeof(out_val), POINTER, SLICE) : "Should be a pointer or slice"
*>
macro void Parser.parse_recur_into(&parser, out_val)
{
	parser.parse_any(out_val);
}

// @require !util::is_ptr_to_ptr($typeof(out_val)) : "Should not be a pointer to pointer"
<*
	@require util::is_kindof($typeof(out_val), POINTER, SLICE) : "Should be a pointer or slice"
*>
macro void Parser.parse_any(
	&parser,
	out_val,
	bool $unwrap_distinct = false,
	bool $parse_next_array_as_string = false,
)
{
	parser.skip_ws();

	if (parser.curr_char() == TokenChar.COMMENT) {
		parser.skip_line();
		parser.skip_ws();
	}

	var $Type = $typeof(out_val);
	var $kind = $Type.kindof;

	$if $kind == POINTER:
		$Type = $Type.inner;
		$kind = $Type.kindof;
	$endif

	$if $unwrap_distinct && $kind == DISTINCT:
		$Type = $Type.inner;
		$kind = $Type.kindof;
	$endif

// NOTE: DEBUG
	// io::printfn("curr char: %c, index: %d remain_distance: %d kind: %s, $unwrap_dist: %s, $arr_as_str: %s", parser.curr_char(), parser.curr, parser.end - parser.curr, $kind, $unwrap_distinct, $parse_next_array_as_string);

	$switch ($kind):
	$case DISTINCT:
		$switch:
		$case $Type.has_tagof(CustomFmtTag.SLICE_STRING):
			parser.parse_any(out_val, true, true);
		$case $Type.has_tagof(CustomFmtTag.STRUCT_STRING):
			parser.parse_any(out_val, true, true);
	// TODO: different string handling method
		// $case $Type == DString:
		// 	parser.parse_any(out_val, true, true);
		// $case $Type == String:
		// 	parser.parse_any(out_val, true, true);
		$default:
			parser.parse_any(out_val, true);
		$endswitch
	$case STRUCT:
	$case BITSTRUCT:
		$if $Type.has_tagof(CustomFmtTag.STRUCT_STRING):
			parser.parse_struct(out_val, true);
		$else
			parser.parse_struct(out_val, $parse_next_array_as_string);
		$endif
	$case ARRAY:
		$if $parse_next_array_as_string:
			parser.parse_string(out_val[:out_val.len]);
		$else
			parser.parse_array(out_val[:out_val.len]);
		$endif
	$case SLICE:
		$if $parse_next_array_as_string || $Type.has_tagof(CustomFmtTag.SLICE_STRING):
			parser.parse_string(out_val);
		$else
			parser.parse_array(out_val);
		$endif
	$case SIGNED_INT:
	$case UNSIGNED_INT:
	$case FLOAT:
		parser.parse_number(out_val);
	$case BOOL:
		parser.parse_boolean(out_val);
	$case ENUM:
		parser.parse_plain_enum(out_val);
	$case CONST_ENUM:
		parser.parse_const_enum(out_val);
	$default:
		unreachable("Unsupported type for parsing: %s, value: %s", $Type, out_val);
	$endswitch

	parser.skip_line();
}

<*
	@require util::is_kindof($typeof(out_array), SLICE, POINTER) : "Should be a slice or pointer to array"
	@require parser.curr_char() == TokenChar.ARRAY_START : "Should be at the start of array"
*>
macro void Parser.parse_array(&parser, out_array)
{
	parser.next();
	assert(!parser.is_at_end(), "Shouldn't be at the end here");
	
	foreach (&item : out_array) {
		parser.parse_any(item);
	}

	parser.skip_until_after_curr_char(TokenChar.ARRAY_END);
}

<*
	@require $typeof(out_value).kindof == POINTER : "Should be a pointer"
	@require parser.curr_char() == TokenChar.STRUCT_START : "Should be at the start of struct"
*>
macro void Parser.parse_struct(
	&parser,
	out_value,
	bool $parse_next_array_as_string = false,
)
{
	parser.next();
	assert(!parser.is_at_end(), "Shouldn't be at the end here");

	var $RootType = $typeof(out_value);
	var $Type = util::@get_pointee_type_val(out_value);

	$foreach $mem : $Type.membersof:
		var $MemType = $mem.typeid;
		bool $has_str_tag = $mem.kindof == DISTINCT &&& util::is_kindof($MemType.inner, ARRAY) &&& $MemType.has_tagof(CustomFmtTag.SLICE_STRING);
		$if $has_str_tag:
			parser.parse_any(out_value.$eval($mem.nameof)[..], true, true);
		$else
			$if $mem.kindof == ARRAY:
				parser.parse_any(out_value.$eval($mem.nameof)[..], true, $parse_next_array_as_string);
			$else
				parser.parse_any(&out_value.$eval($mem.nameof));
			$endif
		$endif
	$endforeach

	parser.skip_until_after_curr_char(TokenChar.STRUCT_END);
}

<*
	@require parser.curr_char() == '\"'
	@require parser.end - parser.curr > 1 : "Buffer shouldn't end with a quote"
	@require parser.next_char().is_alpha() : "Next symbol should be an ascii letter [a-zA-Z]"
*>
macro void Parser.parse_string(&parser, out_str)
{
	// step after opening quote
	parser.next();
	usz start = parser.curr;
	parser.skip_until_next_char('\"');
	usz acquired_len = parser.curr - start + 1;
	assert(parser.curr > start, "Should move at least 1 character");
	assert((acquired_len <= out_str.len), "Should not exceed out_str.len");
	mem::copy(out_str, parser.buff_view.ptr + start, acquired_len);
	// step after closing quote
	parser.next();
}

<*
	@require parser.curr_char() == 't' || parser.curr_char() == 'f' : "Should start from 't' for true or from 'f' for false"
	@require parser.end - parser.curr >= "true".len : "Buffer should have enough space"
	@require parser.next_char().is_alpha() : "Next symbol should be an ascii letter [a-zA-Z]"
*>
fn void Parser.parse_boolean(&parser, bool* out_bool)
{
	usz start = parser.curr;
	char[] bool_value =  parser.read_until_value_end();
	assert(parser.curr > start, "Should move at least 1 character");
	assert(parser.curr - start >= "true".len, "Should move at least 4 characters");

	// char[] bool_value = parser.buff_view[start .. parser.curr - 1];
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

	parser.next();
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
			parser.next();
			was_dot = false;
		} else if (c == '.') {
			assert(!was_dot, "Shouldn't be two dots together");
			was_dot = true;
			parser.next();
		} else {
			assert(!was_dot, "Should be digit after dot");
			break;
		}
	}

	assert(parser.curr > start, "Should be at least 1 digit in a number");
	assert((parser.curr - start) < MAX_DIGIT_LEN, "Should be at most 32 characters");
	digit_buff.push_all(parser.buff_view[start .. parser.curr - 1]);
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
		parser.next();
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
		parser.next();
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

fn void Parser.skip_until_next_value_start(&parser) @private
{
	parser.skip_ws_or_comma();
	parser.skip_comment();
	parser.skip_ws();
}

fn void Parser.skip_until_curr_char(&parser, char c) @private
{
	while (parser.curr < parser.end && parser.curr_char() != c)
	{
		parser.next();
	}
}

fn void Parser.skip_until_next_char(&parser, char c) @private
{
	while (parser.curr < parser.end && parser.next_char() != c)
	{
		parser.next();
	}
}

fn void Parser.skip_until_after_curr_char(&parser, char c) @private
{
	while (parser.curr < parser.end && parser.curr_char() != c)
	{
		parser.next();
	}
	parser.next();
}

fn void Parser.skip_until_curr_char_cb(&parser, SkipCallback cb) @private
{
	while (parser.curr < parser.end && !cb(parser.curr_char()))
	{
		parser.next();
	}
}

fn char[] Parser.read_until_curr_char_cb(&parser, SkipCallback cb) @private
{
	usz start = parser.curr;
	while (parser.curr < parser.end && !cb(parser.curr_char()))
	{
		parser.next();
	}
	return parser.buff_view[start : parser.curr - start];
}

fn char[] Parser.read_while_curr_char_cb(&parser, SkipCallback cb) @private
{
	usz start = parser.curr;
	while (parser.curr < parser.end && cb(parser.curr_char()))
	{
		parser.next();
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

fn char Parser.next_char(&parser) @private @inline
{
	return parser.buff_view[parser.curr + 1];
}

fn char Parser.curr_char_and_next(&parser) @private @inline
{
	return parser.buff_view[parser.curr++];
}

fn void Parser.next(&parser) @private @inline
{
	parser.curr++;
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
