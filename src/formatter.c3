module ser;

import std::io;
import std::math::matrix;
import std::collections::maybe;
import util;

// If user wants to apply a custom format to the type
// value should be of type SchemaFormatKind
const SCHEMA_FMT_TAG = "SCHEMA_FMT_TAG";
const INDENT_SYMBOL = '\t';

faultdef NO_TAG_FOUND;

enum SchemaFormatKind
{
	DEFAULT,
	STRING,
	VECTOR,
	MATRIX,
}

struct Newlines
{
	bool top;
	bool bottom;
}

<*
 Infers type from the passed value
	Provides high level wrapper for 'format_any'
	Should be used as entry-point
*>
macro void Formatter.format_to_text(&f, val, Newlines newlines = { true, true })
{
	var $ValType = $typeof(val);
	SchemaFormatKind $root_fmt_kind = $ValType.has_tagof(
		SCHEMA_FMT_TAG
	) ??? $ValType.tagof(SCHEMA_FMT_TAG) : SchemaFormatKind.DEFAULT;
	return f.format_any(val, $root_fmt_kind, 0, false, newlines);
}

macro void Formatter.format_any(
	&f,
	curr_val,
	SchemaFormatKind $fmt_kind = DEFAULT,
	char $indent_count = 0,
	bool $unwrap_distinct = false,
	Newlines newlines = { false, false },
) @private
{
	var $Type = $typeof(curr_val);
	var $kind = $Type.kindof;
	bool $need_cast = false;

	$if $kind == POINTER:
		$Type = $Type.inner;
		$kind = $Type.kindof;
	$endif

	$if $unwrap_distinct:
		$switch ($kind):
			$case TYPEDEF:$case CONSTDEF:$case BITSTRUCT:
				$fmt_kind = $Type.has_tagof(
					SCHEMA_FMT_TAG
				) ??? $Type.tagof(SCHEMA_FMT_TAG) : $fmt_kind;
				$Type = $Type.inner;
				$kind = $Type.kindof;
				$need_cast = true;
		$endswitch
	$endif

	var dereffed_val = $need_cast ??? ($Type)deref_if_ptr(
		curr_val
	) : deref_if_ptr(curr_val);

	// NOTE: DEBUG
	// io::printfn(
	// 	"Formatter:\n\tvalue: %s\n\tkind: %s\n\tcurr_format: %s\n",
	// 	dereffed_val,
	// 	$kind,
	// 	$fmt_kind
	// );

	$switch ($kind):
		$case TYPEDEF:
		$case CONSTDEF:
		$case BITSTRUCT:
			$switch ($Type):
				$case DString:
					f.format_any(
						dereffed_val,
						SchemaFormatKind.STRING,
						$indent_count,
						true,
						newlines,
					);
				$default:
					f.format_any(
						dereffed_val,
						$fmt_kind,
						$indent_count,
						true,
						newlines,
					);
			$endswitch
		$case STRUCT:
			$switch $Type:
				$case Matrix2x2 {float}:
				$case Matrix3x3 {float}:
				$case Matrix4x4 {float}:
				$case Matrix2x2 {double}:
				$case Matrix3x3 {double}:
				$case Matrix4x4 {double}:
					f.format_mat(
						dereffed_val.m[:dereffed_val.m.len],
						$indent_count,
						newlines
					);
				$default:
					f.format_struct(
						dereffed_val,
						$fmt_kind,
						$indent_count,
						newlines
					);
			$endswitch
		$case ARRAY:
			$switch ($fmt_kind):
				$case SchemaFormatKind.STRING:
					f.format_string(
						dereffed_val[:dereffed_val.len],
						$indent_count,
						newlines
					);
				$case SchemaFormatKind.VECTOR:
					f.format_vec(
						dereffed_val[:dereffed_val.len],
						$indent_count,
						newlines
					);
				$case SchemaFormatKind.MATRIX:
					f.format_mat(
						dereffed_val[:dereffed_val.len],
						$indent_count,
						newlines
					);
				$default:
					f.format_array(
						dereffed_val[:dereffed_val.len],
						$fmt_kind,
						$indent_count,
						newlines
					);
			$endswitch
		$case SLICE:
			$switch ($fmt_kind):
				$case SchemaFormatKind.STRING:
					f.format_string(dereffed_val, $indent_count, newlines);
				$case SchemaFormatKind.VECTOR:
					f.format_vec(dereffed_val, $indent_count, newlines);
				$case SchemaFormatKind.MATRIX:
					f.format_mat(dereffed_val, $indent_count, newlines);
				$default:
					f.format_array(
						dereffed_val,
						$fmt_kind,
						$indent_count,
						newlines
					);
			$endswitch
		$case VECTOR:
			f.format_vec(dereffed_val, $indent_count, newlines);
		$case BOOL:
		$case SIGNED_INT:
		$case UNSIGNED_INT:
		$case FLOAT:
		$case TYPEID:
		$case ENUM:
			f.format_primitive(dereffed_val, $kind, $indent_count, newlines);
		$default:
			unreachable("Type kind is not supported for formatting: %s", $kind);
	$endswitch
}

<*
 Introspect struct and print it to a formatter
 @require is_kindof_val(val, STRUCT, TYPEDEF, POINTER) : "TypeKind should be one of: STRUCT, TYPEDEF, POINTER"
*>
macro void Formatter.format_struct(
	&f,
	val,
	SchemaFormatKind $fmt_kind = DEFAULT,
	char $indent_count = 0,
	Newlines newlines = { false, false },
) @private
{
	String $base_indent_s = (String)get_indent($indent_count);
	String $inner_indent_s = $base_indent_s +++ INDENT_SYMBOL;
	var $Type = pointee_type_val(val);

	if (newlines.top)
	{
		f.print("\n" +++ $base_indent_s +++ "{\n")!!;
	}
	else
	{
		f.print($base_indent_s +++ "{\n")!!;
	}

	$for var $i = 0; $i < $Type.membersof.len; ++$i:
		var $member = $Type.membersof[$i];
		var $name = $member.nameof;

		$if $i > 0:
			f.print(",\n")!!;
		$endif
		$if $name != "":
			f.printf($inner_indent_s +++ "; %s\n", $name)!!;
			var $mem_kind = $member.kindof;
			$fmt_kind = $member.has_tagof(
				SCHEMA_FMT_TAG
			) ??? $member.tagof(SCHEMA_FMT_TAG) : $fmt_kind;

			$switch:
				// NOTE: ElasticArray special case
				$case $mem_kind == ARRAY && $defined ( val.array_view() ):
					f.format_any(
						val.array_view(),
						$fmt_kind,
						$indent_count + 1,
						false,
					);
					// NOTE: DString special case
				$case $mem_kind == ARRAY && $defined ( val.str_view() ):
					f.format_any(
						val.str_view(),
						SchemaFormatKind.STRING,
						$indent_count + 1,
						false,
					);
				$default:
					f.format_any(
						val.$eval($name),
						$fmt_kind,
						$indent_count + 1,
						false,
					);
			$endswitch
		$endif
	$endfor

	f.print("\n" +++ $base_indent_s +++ "}")!!;

	if (newlines.bottom)
	{
		f.print("\n")!!;
	}
}

<*
 Introspect array and print it to a formatter
 @require is_kindof_val(val, ARRAY, SLICE, TYPEDEF, POINTER) : "TypeKind should be one of: ARRAY, SLICE, TYPEDEF, POINTER"
*>
macro void Formatter.format_array(
	&f,
	val,
	SchemaFormatKind $fmt_kind = DEFAULT,
	char $indent_count = 0,
	Newlines newlines = { false, false },
) @private
{
	String $indent_str = (String)get_indent($indent_count);

	if (newlines.top)
	{
		f.print("\n" +++ $indent_str +++ "[\n")!!;
	}
	else
	{
		f.print($indent_str +++ "[\n")!!;
	}

	foreach (uint i, member : val)
	{
		if (i > 0)
		{
			f.print(",\n")!!;
		}
		f.format_any(member, $fmt_kind, $indent_count + 1);
	}

	f.print("\n" +++ $indent_str +++ "]")!!;

	if (newlines.bottom)
	{
		f.print("\n")!!;
	}
}

<*
 Introspect a primitive val and print it to a formatter
*>
macro void Formatter.format_primitive(
	&f,
	val,
	TypeKind $kind,
	char $indent_count = 0,
	Newlines newlines = { false, false },
) @private
{
	String $indent_str = (String)get_indent($indent_count);

	if (newlines.top)
	{
		f.print("\n")!!;
	}

	$switch ($kind):
		$case BOOL:
		$case SIGNED_INT:
		$case UNSIGNED_INT:
		$case FLOAT:
		$case TYPEID:
			f.printf($indent_str +++ "%s", val)!!;
		$case ENUM:
			f.printf($indent_str +++ "%d", val.ordinal)!!;
	$endswitch

	if (newlines.bottom)
	{
		f.print("\n")!!;
	}
}

<*
 Introspect string and print it to a formatter
 @require is_kindof_val(val, ARRAY, SLICE, TYPEDEF, POINTER) : "TypeKind should be one of: ARRAY, SLICE, TYPEDEF, POINTER"
 @require innermost_type_val(val) == char : "Should be char as underlying type"
*>
macro void Formatter.format_string(
	&f,
	val,
	char $indent_count = 0,
	Newlines newlines = { false, false },
) @private
{
	String $indent_str = (String)get_indent($indent_count);

	if (newlines.top)
	{
		f.print("\n" +++ $indent_str +++ "\"")!!;
	}
	else
	{
		f.print($indent_str +++ "\"")!!;
	}

	var dereffed_val = deref_if_ptr(val);
	f.printf("%s\"", (String)dereffed_val[:val.len])!!;

	if (newlines.bottom)
	{
		f.print("\n")!!;
	}
}

<*
 Introspect vector and print it to a formatter
 @require is_kindof_val(vec, VECTOR, SLICE, ARRAY, POINTER) : "TypeKind should be VECTOR, SLICE, ARRAY, POINTER"
*>
macro void Formatter.format_vec(
	&f,
	vec,
	char $indent_count = 0,
	Newlines newlines = { false, false },
) @private
{
	String $indent_str = (String)get_indent($indent_count);
	String $vec_start = "[<";
	String $vec_end = ">]";

	if (newlines.top)
	{
		f.print("\n" +++ $indent_str +++ $vec_start)!!;
	}
	else
	{
		f.print($indent_str +++ $vec_start)!!;
	}

	foreach (uint i, item : deref_if_ptr(vec))
	{
		f.printf("%s", item)!!;
		if (i < vec.len - 1)
		{
			f.print(", ")!!;
		}
		else
		{
			f.print($vec_end)!!;
		}
	}

	if (newlines.bottom)
	{
		f.print("\n")!!;
	}
}

<*
 Introspect matrix and print it to a formatter
 @require is_kindof_val(mat, SLICE, ARRAY) : "TypeKind should be SLICE or ARRAY"
*>
macro void Formatter.format_mat(
	&f,
	mat,
	char $indent_count = 0,
	Newlines newlines = { false, false },
) @private
{
	String $base_indent_s = (String)get_indent($indent_count);
	String $inner_indent_s = $base_indent_s +++ INDENT_SYMBOL;
	String $mat_start = "[#";
	String $mat_end = "#]";

	if (newlines.top)
	{
		f.print("\n" +++ $base_indent_s +++ $mat_start +++ "\n")!!;
	}
	else
	{
		f.print($base_indent_s +++ $mat_start +++ "\n")!!;
	}

	uint cols = 2;

	switch (mat.len)
	{
		case 4:
			cols = 2;
		case 9:
			cols = 3;
		case 16:
			cols = 4;
		default:
			unreachable(
				"Unsupported number of elements for matrix: %d",
				mat.len
			);
	}
	uint rows = cols;

	for (uint x = 0; x < rows; ++x)
	{
		for (uint y = 0; y < cols; ++y)
		{
			if (y == 0)
			{
				f.print($inner_indent_s)!!;
			}

			f.printf("%s", mat[x * cols + y])!!;

			if (x * cols + y < mat.len - 1)
			{
				f.printf(", ")!!;
			}
		}

		if (x < rows - 1)
		{
			f.print("\n")!!;
		}
		else
		{
			f.print("\n" +++ $base_indent_s +++ $mat_end)!!;
		}
	}

	if (newlines.bottom)
	{
		f.print("\n")!!;
	}
}

macro get_indent(char $indent_count = 0) @local @const
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
