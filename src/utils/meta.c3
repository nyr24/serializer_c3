module util;

// Metaprogramming utils

macro bool is_heap_allocated($Type) @const
{
	return $defined($Type.allocator) || $defined($Type.capacity);
}

macro bool is_kindof($Type, TypeKind... $kinds) @const
{
	$foreach $k : $kinds:
		$if $Type.kindof == $k:
			return true;
		$endif
	$endforeach
	return false;
}

macro unwrap_if_distinct_or_ptr_type($Type) @const
{
	$if $Type.kindof == DISTINCT || $Type.kindof == POINTER:
		return $Type.inner;
	$else
		return $Type;
	$endif
}

macro unwrap_if_distinct_type($Type) @const
{
	$if $Type.kindof == DISTINCT:
		return $Type.inner;
	$else
		return $Type;
	$endif
}

macro bool is_primitive_type($Type) @const
{
	$Type = unwrap_if_distinct_type($Type);
	return !is_kindof($Type, STRUCT, UNION, SLICE, ARRAY, BITSTRUCT);
}

macro bool is_array_like($Type) @const
{
	return is_kindof($Type, ARRAY, SLICE);
}

macro get_innermost_type($Type) @const
{
	var $InnerType = $Type;
	$if $defined($Type.inner):
		$InnerType = $Type.inner;
		return get_innermost_type($InnerType);
	$endif
	return $InnerType;
}

macro @get_innermost_type_val(#val) @const
{
	var $Type = $typeof(#val);
	return get_innermost_type($Type);
}

<*
	$defined(#val.$field_name)
*>
macro @get_field_type_from_val(#val, String $field_name) @const
{
	var $FieldType = $typeof(#val.$eval($field_name));
	return $FieldType;
}

macro @get_pointee_type_val(#val) @const
{
	var $Type = $typeof(#val);
	return get_pointee_type($Type);
}

macro get_pointee_type($Type) @const
{
	$if $Type.kindof == POINTER:
		var $Inner = $Type.inner;
		return $Inner;
	$else
		return $Type;
	$endif
}

macro @deref_if_ptr(#val)
{
	var $Type = $typeof(#val);
	$if $Type.kindof == POINTER:
		return *#val;
	$else
		return #val;
	$endif
}

macro @take_address(#val)
{
	var $Type = $typeof(#val);
	$switch:
	$case is_kindof($Type, POINTER):
		return #val;
	$case is_kindof($Type, SLICE):
		return #val.ptr;
	$default:
		return &#val;
	$endswitch
}

macro char*? @get_heap_object_data_ptr(#val)
{
	$switch:
	$case $defined(#val.entries):
		return (char*)&#val.entries;
	$case $defined(#val.str_view()):
		return #val.str_view().ptr;
	$case $defined(#val.array_view()):
		return (char*)#val.array_view().ptr;
	$case $defined(#val.data()):
		return (char*)#val.data();
	$default:
		return CANT_ACCESS_DATA_PTR~;
	$endswitch
}

macro has_field($Type, String $name) @const
{
	return $defined($Type.$name);
}
