module ser;

import std::io;
import util;

enum CustomFmtTag : const inline String
{
// for char slices/arrays that user wants to format as strings
	SLICE_STRING 	= "FMT_SLICE_STRING",
// for structs which have char arrays inside (ElasticArray{char, 20})
	STRUCT_STRING 	= "FMT_STRUCT_STRING",
}

const INDENT_SYMBOL = '\t';

macro void Formatter.format_any(
	&f,
	val,
	char $indent_count = 0,
	bool $top_level = false,
	bool $unwrap_distinct = false,
	bool $parse_next_array_as_string = false,
) @private
{
	var $Type = $typeof(val);
	var $kind = $Type.kindof;

	$if $kind == POINTER:
		$Type = $Type.inner;
		$kind = $Type.kindof;
	$endif

	$if $unwrap_distinct && $kind == DISTINCT:
		$Type = $Type.inner;
		$kind = $Type.kindof;
	$endif

	// var val = util::@deref_if_ptr(input_val);

 	$switch $kind:
	$case DISTINCT:
		$switch:
		$case $Type.has_tagof(CustomFmtTag.SLICE_STRING):
			f.format_any(val, $indent_count, $top_level, true, true);
		$case $Type.has_tagof(CustomFmtTag.STRUCT_STRING):
			f.format_any(val, $indent_count, $top_level, true, true);
		$default:
			f.format_any(val, $indent_count, $top_level, true);
		$endswitch
	$case STRUCT:
	$case BITSTRUCT:
		f.format_struct(val, $indent_count, $top_level, $parse_next_array_as_string);
	$case ARRAY:
	$case SLICE:
		$if $parse_next_array_as_string:
			f.format_string(val, $indent_count, $top_level);
		$else
			f.format_array(val, $indent_count, $top_level);
		$endif
	$case BOOL:
	$case SIGNED_INT:
	$case UNSIGNED_INT:
	$case FLOAT:
	$case TYPEID:
	$case ENUM:
	$case CONST_ENUM:
		f.format_primitive(val, $kind, $indent_count, $top_level);
	$default:
		unreachable("Type kind is not supported for formatting: %s", $kind);
	$endswitch
}

<*
	Introspect a primitive val and print it to a formatter
*>
macro void Formatter.format_primitive(
	&f,
	val,
	TypeKind $kind,
	char $indent_count = 0,
	bool $top_level = false,
) @private
{
	String $indent_str = @get_indent($indent_count);

	$if $top_level:
		f.print("\n")!!;
	$endif

	$switch ($kind):
	$case BOOL:
	$case SIGNED_INT:
	$case UNSIGNED_INT:
	$case FLOAT:
	$case TYPEID:
		f.printf($indent_str +++ "%s", val)!!;
	$case ENUM:
		f.printf($indent_str +++ "%d", val.ordinal)!!;
	$case CONST_ENUM:
		f.printf($indent_str +++ "%d", val)!!;
	$endswitch

	$if $top_level:
		f.print("\n")!!;
	$endif
}

<*
	Introspect a struct and print it to a formatter
	@require util::@is_kindof_val(val, STRUCT, BITSTRUCT, DISTINCT) : `This macro is only valid on STRUCT, BITSTRUCT or DISTINCT`
*>
macro void Formatter.format_struct(
	&f,
	val,
	char $indent_count = 0,
	bool $top_level = false,
	bool $parse_next_array_as_string = false,
) @private 
{
	String $base_indent_s = @get_indent($indent_count);
	String $inner_indent_s = $base_indent_s +++ INDENT_SYMBOL;
	var $Type = $typeof(val); 

	$if $top_level:
	    f.print("\n" +++ $base_indent_s +++ "{\n")!!;
	$else
	    f.print($base_indent_s +++ "{\n")!!;
	$endif
	
    $foreach $i, $member : $Type.membersof:
        $if $i > 0:
            f.print(",\n")!!;
        $endif
        $if $member.nameof != "":
            f.printf($inner_indent_s +++ "; %s\n", $member.nameof)!!;
		$endif
		f.format_any($member.get(val), $indent_count + 1, false, false, $parse_next_array_as_string);
	$endforeach

	f.print("\n" +++ $base_indent_s +++ "}")!!;

	$if $top_level:
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
	char $indent_count = 0,
	bool $top_level = false,
) @private
{
	String $indent_str = @get_indent($indent_count);

	$if $top_level:
	    f.print("\n" +++ $indent_str +++ "[\n")!!;
	$else
	    f.print($indent_str +++ "[\n")!!;
	$endif

	foreach (uint i, member : val) {
		if (i > 0) {
            f.print(",\n")!!;
		}
		f.format_any(member, $indent_count + 1);
	}

	f.print("\n" +++ $indent_str +++ "]")!!;

	$if $top_level:
		f.print("\n")!!;
	$endif
}

<*
	Introspect an array and print it to a formatter
	@require util::is_kindof($typeof(val), ARRAY, SLICE, DISTINCT) : "Should be ARRAY or SLICE"
	@require util::@get_innermost_type_val(val) == char : "Should be char as underlying type"
*>
macro void Formatter.format_string(
	&f,
	val,
	char $indent_count = 0,
	bool $top_level = true,
) @private
{
	String $indent_str = @get_indent($indent_count);

	$if $top_level:
	    f.print("\n" +++ $indent_str +++ "\"")!!;
	$else
	    f.print($indent_str +++ "\"")!!;
	$endif

	f.printf("%s", (String)val[..])!!;

	f.print("\"")!!;

	$if $top_level:
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
