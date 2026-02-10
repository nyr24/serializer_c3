module ser;

import std::io;
import util;

const FMT_PLAIN_STRING_TAG = "FMT_STRING";
const INDENT_SYMBOL = '\t';

/* TODO:
	1. maybe rework arguments to the context sysmtem
*/

struct ParseContext
{
	char indent_count;
	bool top_level;
	bool unwrap_distinct;
	bool parse_next_array_as_string; // !important
}

// fn void ParseContext.init(&ctx)
// {
// 	ctx.indent_count = 0;
// 	ctx.indent_symbol = ;
// }

macro void Formatter.format_any(
	&f,
	val,
	bool $print_field_names = false,
	char $indent_count = 0,
	bool $top_level = false,
	bool $unwrap_distinct = false,
) @private
{
	var $Type = $typeof(val);
	var $kind = $Type.kindof;
	$if $unwrap_distinct:
		$kind = $Type.inner.kindof;
	$endif

 	$switch $kind:
	$case STRUCT:
	$case BITSTRUCT:
		f.format_struct(val, $print_field_names, $indent_count, $top_level, $top_level);
	$case ARRAY:
	$case SLICE:
		f.format_array(val, $print_field_names, $indent_count, $top_level, $top_level);
	$case DISTINCT:
		$switch:
		$case $Type.has_tagof(FMT_PLAIN_STRING_TAG):
			f.format_string(val, $print_field_names, $indent_count, $top_level, $top_level);
		$default:
			$kind = $Type.inner.kindof;
			f.format_any(val, $print_field_names, $indent_count,  $top_level, true);
		$endswitch
	$default:
		f.format_primitive(val, $indent_count);
	$endswitch
}

<*
	Introspect a primitive val and print it to a formatter
	@require util::is_primitive_type($typeof(val))
*>
macro usz Formatter.format_primitive(
	&f,
	val,
	char $indent_count = 0,
	bool $start_newline = false,
	bool $end_newline = false,
) @private
{
	String $indent_str = @get_indent($indent_count);

	usz written;
	$if $start_newline:
		written += f.print("\n")!!;
	$endif
	written += f.printf($indent_str +++ "%s", val)!!;
	$if $end_newline:
		written += f.print("\n")!!;
	$endif
	return written;
}

<*
	Introspect a struct and print it to a formatter
	@require util::@is_kindof_val(val, STRUCT, BITSTRUCT, DISTINCT) : `This macro is only valid on STRUCT and BITSTRUCT`
*>
macro void Formatter.format_struct(
	&f,
	val,
	bool $print_field_names = false,
	char $indent_count = 0,
	bool $start_newline = false,
	bool $end_newline = false,
) @private 
{
	String $base_indent_s = @get_indent($indent_count);
	String $inner_indent_s = $base_indent_s +++ INDENT_SYMBOL;
	var $Type = $typeof(val); 

	$if $start_newline:
	    f.print("\n" +++ $base_indent_s +++ "{\n")!!;
	$else
	    f.print($base_indent_s +++ "{\n")!!;
	$endif
	
    $foreach $i, $member : $Type.membersof:
        $if $i > 0:
            f.print(",\n")!!;
        $endif
        $if $print_field_names && $member.nameof != "":
            f.printf($inner_indent_s +++ "; %s\n", $member.nameof)!!;
		$endif
		f.format_any($member.get(val), $print_field_names, $indent_count + 1);
	$endforeach

	f.print("\n" +++ $base_indent_s +++ "}")!!;
	$if $end_newline:
		f.print("\n")!!;
	$endif
}

<*
	Introspect an array and print it to a formatter
	@require util::@is_kindof_val(val, ARRAY, SLICE, DISTINCT) : "Should be ARRAY or SLICE"
*>
macro void Formatter.format_array(
	&f,
	val,
	bool $print_field_names = false,
	char $indent_count = 0,
	bool $start_newline = false,
	bool $end_newline = false,
) @private
{
	String $indent_str = @get_indent($indent_count);

	$if $start_newline:
	    f.print("\n" +++ $indent_str +++ "[\n")!!;
	$else
	    f.print($indent_str +++ "[\n")!!;
	$endif

	foreach (uint i, member : val) {
		if (i > 0) {
            f.print(",\n")!!;
		}
		f.format_any(member, $print_field_names, $indent_count + 1);
	}

	f.print("\n" +++ $indent_str +++ "]")!!;
	$if $end_newline:
		f.print("\n")!!;
	$endif
}

<*
	Introspect an array and print it to a formatter
	@require util::is_kindof($typeof(val).inner, ARRAY, SLICE) : "Should be ARRAY or SLICE"
	@require util::@get_innermost_type_val(val) == char : "Should be char as underlying type"
*>
macro void Formatter.format_string(
	&f,
	val,
	bool $print_field_names = false,
	char $indent_count = 0,
	bool $start_newline = true,
	bool $end_newline = true,
) @private
{
	String $indent_str = @get_indent($indent_count);

	$if $start_newline:
	    f.print("\n" +++ $indent_str +++ "\"")!!;
	$else
	    f.print($indent_str +++ "\"")!!;
	$endif

	f.printf("%s", (String)val[..])!!;

	f.print("\"")!!;
	$if $end_newline:
		f.print("\n")!!;
	$endif
}

macro @get_indent(char $indent_count = 0) @local @const
{
	String $indent_str;
	$if $indent_count > 0:
		char[$indent_count] $indent;
		$for var $i = 0; $i < $indent_count; ++$i:
			$indent[$i] = INDENT_SYMBOL;
		$endfor
		$indent_str = $indent[..];
	$else
		$indent_str = "";
	$endif
	return $indent_str;
}
