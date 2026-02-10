module ser;

import libc;
import std::collections::elastic_array;
import util;

const MAX_STR_LEN = 64;
const MAX_DIGIT_LEN = 32;
const char[*] FORMAT_TOKEN_CHARSET = {'[', ']', '{', '}', ';'};
alias SkipCallback = fn bool(char);

/* TODO:
	1. handle DISTINCT
	2. handle booleans
*/

/* Example format
	; comment or field_name
	123,      // int
	"hello",  // string
	d"hello", // dstring
	228.0,	  // float/double
	[			// array open
		{		// table open
			; table inner content
			123,      // int
			"hello",  // string
			d"hello", // dstring
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

fn void Parser.init(&parser, char[] data) @private
{
	parser.buff_view = data;
	parser.curr = 0;
	parser.end = data.len - 1;
	parser.curr_line = 0;
}

<*
	@require util::is_kindof($typeof(out_val), POINTER, SLICE) : "Should be a pointer or slice"
*>
macro void Parser.start(&parser, out_val) @private
{
	parser.parse_any(out_val);
}

<*
	@require util::is_kindof($typeof(out_val), POINTER, SLICE) : "Should be a pointer or slice"
*>
macro void Parser.parse_any(&parser, out_val) @private
{
	parser.skip_ws();

	if (parser.curr_char() == TokenChar.COMMENT) {
		parser.skip_line();
		parser.skip_ws();
	}

	var $RootType = $typeof(out_val);
	var $kind = $RootType.kindof;
	var $Type = $kind == POINTER ? util::get_pointee_type($typeof(out_val)) : $RootType;
	
	$switch ($kind):
	$case STRUCT:
	$case BITSTRUCT:
		parser.parse_struct(out_val);
	$case ARRAY:
		if (parser.curr_char() == TokenChar.STRING_START) {
			parser.parse_str_val(out_val[..]);
		} else {
			parser.parse_array(out_val[..]);
		}
	$case SLICE:
		$if $RootType == char[]:
			parser.parse_str_value(out_val);
		$else
			parser.parse_array(out_val);
		$endif
	$case SIGNED_INT:
	$case UNSIGNED_INT:
	$case FLOAT:
		parser.parse_numeric_value(out_val);
// TODO: parse boolean values
	$case BOOL:
		unreachable("TODO: parse boolean values");
	$endswitch

	parser.skip_line();
}

<*
	@require $typeof(out_array).kindof == SLICE : "Should be a slice"
	@require parser.curr_char() == TokenChar.ARRAY_START : "Should be at the start of array"
*>
macro void Parser.parse_array(&parser, out_array) @private
{
	parser.next();
	assert(!parser.is_at_end(), "Shouldn't be at the end here");
	
	foreach (&item : out_array) {
		parser.parse_any(item);
	}

	parser.skip_until_after_char(TokenChar.ARRAY_END);
}

<*
	@require $typeof(out_value).kindof == POINTER : "Should be a pointer"
	@require parser.curr_char() == TokenChar.STRUCT_START : "Should be at the start of struct"
*>
macro void Parser.parse_struct(&parser, out_value) @private
{
	parser.next();
	assert(!parser.is_at_end(), "Shouldn't be at the end here");

	var $Type = util::@get_pointee_type_val(out_value);
	$foreach $mem : $Type.membersof:
		$if $mem.kindof == ARRAY:
			parser.parse_any(out_value.$eval($mem.nameof)[..]);
		$else
			parser.parse_any(&out_value.$eval($mem.nameof));
		$endif
	$endforeach

	parser.skip_until_after_char(TokenChar.STRUCT_END);
}

<*
	@require parser.curr_char() == '\"'
	@require parser.end - parser.curr > 1 : "Buffer shouldn't end with a quote"
	@require parser.next_char().is_alpha() : "Next symbol should be an ascii letter [a-zA-Z]"
*>
fn void Parser.parse_str_value(&parser, char[] out_str) @private
{
	usz start = parser.curr;
	parser.skip_until_char('\"');
	assert(parser.curr > start, "Should move at least 1 character");
	assert((parser.curr - start < out_str.len), "Should not exceed out_str.len");
	mem::copy(out_str, parser.buff_view.ptr + start, (parser.curr - start));
}

<*
	@require $typeof(out_value).kindof == POINTER : "Should be a pointer"
	@require parser.curr_char().is_digit() || is_digit_sign(parser.curr_char()) : "Character we currently on should be either a digit or a sign"
*>
macro void Parser.parse_numeric_value(&parser, out_value) @private
{
	usz digit_end = parser.curr;
	bool is_digit = false;
	bool was_dot = false;
	ElasticArray{char, MAX_DIGIT_LEN} digit_buff;

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
		digit_end++;
	}

	assert(digit_end > parser.curr, "Should be at least 1 digit in a number");
	assert((digit_end - parser.curr) < MAX_DIGIT_LEN, "Should be at most 32 characters");

	digit_buff.resize(digit_end - parser.curr);
	char[] digit_as_chars = digit_buff.array_view();

	var $Type = util::@get_pointee_type_val(out_value);
	$switch ($sizeof($Type)):
	$case $sizeof(int):
		$if types::is_int($Type):
			*out_value = libc::atoi(digit_as_chars.ptr);
		$else
			*out_value = libc::strtof(digit_as_chars.ptr, null);
		$endif
	$case $sizeof(long):
		$if types::is_int($Type):
			*out_value = libc::atoll(digit_as_chars.ptr);
		$else
			*out_value = libc::strtod(digit_as_chars.ptr, null);
		$endif
	$default:
		unreachable("Type must be one of this: SIGNED_INT, UNSIGNED_INT, FLOAT, DOUBLE");
	$endswitch
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

fn bool Parser.skip_line(&parser) @private
{
	parser.skip_until_after_char('\n');
	return parser.is_at_end();
}

fn void Parser.skip_until_char(&parser, char c) @private
{
	while (parser.curr < parser.end && parser.curr_char() != c)
	{
		parser.next();
	}
}

fn void Parser.skip_until_after_char(&parser, char c) @private
{
	while (parser.curr < parser.end && parser.curr_char() != c)
	{
		parser.next();
	}
	parser.next();
}

fn void Parser.skip_while_char(&parser, char c) @private
{
	while (parser.curr < parser.end && parser.curr_char() == c)
	{
		parser.next();
	}
}

fn void Parser.skip_until_cb(&parser, SkipCallback cb) @private
{
	while (parser.curr < parser.end && !cb(parser.curr_char()))
	{
		parser.next();
	}
}

fn void Parser.skip_while_cb(&parser, SkipCallback cb) @private
{
	while (parser.curr < parser.end && cb(parser.curr_char()))
	{
		parser.next();
	}
}

fn void Parser.skip_until_in_charset(&parser, char[] charset) @private
{
	while (parser.curr < parser.end && !is_in_charset(parser.curr_char(), charset)) {
		parser.next();
	}
}

fn void Parser.skip_while_in_charset(&parser, char[] charset) @private
{
	while (parser.curr < parser.end && is_in_charset(parser.curr_char(), charset)) {
		parser.next();
	}
}

fn bool Parser.is_curr_char_in_charset(&parser, char[] charset) @private
{
	return is_in_charset(parser.buff_view[parser.curr], charset);
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

fn bool is_in_charset(char c, char[] charset) @private
{
	return array::contains(charset, c);
}

fn bool is_digit_sign(char c) @private
{
	return c == '-' || c == '+';
}
