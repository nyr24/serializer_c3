module ser;

import std::io;

/*
	In-Memory representation:
	[typeid] 8bytes
	[size_bytes_aligned:padding] 8bytes(4bytes:4bytes)
	[...body...]: size_bytes_aligned
*/

const DEFAULT_BUFF_CAPACITY = 4096u;
const DEFAULT_DESER_BUFF_CAPACITY = DEFAULT_BUFF_CAPACITY / 2;
const TERM = usz.max;
const ALIGNMENT = uptr.alignof;
const HEADER_SIZE = usz.sizeof * 2;

faultdef
	BYTE_SIZE_NOT_IMPLEMENTED,
	CANT_ACCESS_DATA_PTR;

struct Serializer
{
	Allocator	alloc;
	File		file;
	char[] 	    buff;
	char[]		deser_buff;
	uint	    offset;
	uint	    deser_offset;
}

fn void? Serializer.init(&ser, Allocator alloc, String file_path, usz buff_init_cap = 0, usz deser_buff_init_cap = 0)
{
	buff_init_cap = buff_init_cap == 0 ? DEFAULT_BUFF_CAPACITY : buff_init_cap;
	deser_buff_init_cap = deser_buff_init_cap == 0 ? DEFAULT_DESER_BUFF_CAPACITY : deser_buff_init_cap;
	ser.alloc = alloc;
	ser.file = file::open(file_path, "rub")!;
	ser.buff = allocator::alloc_array(alloc, char, buff_init_cap);
	ser.deser_buff = allocator::alloc_array(alloc, char, deser_buff_init_cap);
	ser.offset = 0;
	ser.deser_offset = 0;
}

macro void Serializer.ser(&ser, value)
{
	var $Type = @get_pointee_type_val(value);
	// for typeid
	var $InnerType = get_innermost_type($Type);

	uint req_ser_space = @calc_required_ser_space(value);
	int extra_space = req_ser_space - ((uint)ser.buff.len - ser.offset);
	if (extra_space > 0) {
		ser.grow(ser.buff.len + (uint)extra_space);
	}

	bool $heap_allocated = is_heap_allocated($Type);

	char* curr = ser.buff.ptr + ser.offset;
	*(usz*)curr = (usz)$InnerType.typeid;
	curr += usz.sizeof;

	$if !$heap_allocated:
		uint size = @calc_stack_body_size(value);
		uint aligned_size = align(size);
		// store aligned_size
		*(uint*)curr = aligned_size;
		curr += uint.sizeof;
		// store padding
		*(uint*)curr = aligned_size - size;
		curr += uint.sizeof;
		// store body
		mem::copy(curr, (char*)&value, size);
	$else
		uint size = (uint)@calc_heap_body_size(value)!!;
		uint aligned_size = align(size);
		// store aligned_size
		*(uint*)curr = aligned_size;
		curr += uint.sizeof;
		// store padding
		*(uint*)curr = aligned_size - size;
		curr += uint.sizeof;
		// store body
		mem::copy(curr, @get_heap_object_data_ptr(value), size)!!;
	$endif
	
	ser.offset += req_ser_space;
}

macro Serializer.deser(&ser, $Type)
{
	var $InnerType = get_innermost_type($Type);
	
	char* curr = ser.buff.ptr;
	ser.deser_offset = 0;

	while (curr < ser.buff.ptr + ser.offset) {
		usz stored_typeid = *(usz*)curr;
		curr += usz.sizeof;
		if (stored_typeid != (usz)$InnerType.typeid) {
			// step through header + body
			curr += usz.sizeof + *(uint*)curr;
			continue;
		}

		// size = aligned_size - padding
		uint aligned_size = *(uint*)(curr);
		uint size = (aligned_size - (*(uint*)(curr + uint.sizeof)));
		curr += usz.sizeof;

		if (size > (ser.deser_buff.len - ser.deser_offset)) {
			ser.grow_deser_buff(ser.deser_buff.len + size);
		}

		mem::copy((ser.deser_buff.ptr + ser.deser_offset), curr, size);
		ser.deser_offset += size;

		// step through body
		curr += aligned_size;
	}

	usz len = ser.deser_offset / $InnerType.sizeof;
	return bitcast(ser.deser_buff[:ser.deser_offset], $InnerType[])[:len];
}

// Calculates required space in memory-buffer for data deserialization 
macro usz Serializer.query_required_deser_space(&ser, $Type)
{
	usz res_bytes = 0;
	char* curr = ser.buff.ptr;
	var $InnerType = get_innermost_type($Type);

	while (curr < ser.buff.ptr + ser.offset) {
		usz stored_typeid = *(usz*)curr;
		curr += usz.sizeof;
		uint aligned_size = *(uint*)curr;
		if (stored_typeid == (usz)$InnerType.typeid) {
			// size = aligned_size - padding
			uint size = aligned_size - (*(uint*)(curr + uint.sizeof));
			res_bytes += size;
		}
		// step through header + body
		assert(aligned_size > 0, "Aligned size of object must be > 0");
		curr += usz.sizeof + aligned_size;
	}
	
	return res_bytes;
}

macro uint @calc_required_ser_space(#val) @local
{
	var $Type = @get_pointee_type_val(#val);
	$if is_heap_allocated($Type):
		return (uint)@calc_heap_full_size(#val)!!;
	$else
		return (uint)@calc_stack_full_size(#val);
	$endif
}

<*
	@require is_heap_allocated(@get_pointee_type_val(#val)) : "Must be heap-allocated object"
*>
macro uint? @calc_heap_full_size(#val) @local
{
	uint body_size = (uint)mem::aligned_offset(
		@calc_heap_body_size(#val)!, ALIGNMENT
	);
	return body_size + HEADER_SIZE;
}

<*
	@require is_heap_allocated(@get_pointee_type_val(#val)) : "Must be heap-allocated object"
*>
macro uint? @calc_heap_body_size(#val) @local
{
	$if ($defined(#val.byte_size())):
		return (uint)#val.byte_size();
	$endif
	return BYTE_SIZE_NOT_IMPLEMENTED~;
}

macro uint @calc_stack_full_size(#val) @local
{
	return @calc_stack_body_size(#val) + HEADER_SIZE;
}

macro uint @calc_stack_body_size(#val) @local
{
	return (uint)$sizeof(@deref_if_ptr(#val));
}

macro uint align(uint size, usz alignment = ALIGNMENT) @local
{
	return (uint)mem::aligned_offset((usz)size, alignment);
}

<*
	@require ser.buff.len > 0 : "Should not be zero"
	@require needed_cap > ser.buff.len : "Should be more than current capacity"
*>
fn void Serializer.grow(&ser, usz needed_cap) @local
{
	usz new_cap = ser.buff.len * 2;
	while (new_cap < needed_cap) {
		new_cap *= 2;
	}
	ser.buff = allocator::realloc_array(ser.alloc, ser.buff.ptr, char, new_cap);
}

<*
	@require ser.deser_buff.len > 0 : "Should not be zero"
	@require needed_cap > ser.deser_buff.len : "Should be more than current capacity"
*>
fn void Serializer.grow_deser_buff(&ser, usz needed_cap) @local
{
	usz new_cap = ser.deser_buff.len * 2;
	while (new_cap < needed_cap) {
		new_cap *= 2;
	}
	ser.deser_buff = allocator::realloc_array(ser.alloc, ser.deser_buff.ptr, char, new_cap);
}

fn void? Serializer.flush(&ser, String file_path)
{
	file::save(file_path, ser.buff[:ser.offset])!;
}

fn void Serializer.reset(&ser)
{
	ser.offset = 0;
}

fn void Serializer.destroy(&ser)
{
	(void)ser.file.close();
	allocator::free(ser.alloc, ser.buff.ptr);
	allocator::free(ser.alloc, ser.deser_buff.ptr);
}

macro char*? @get_heap_object_data_ptr(#val) @local
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

macro bool is_heap_allocated($Type) @const @local
{
	$switch:
	$case $defined($Type.allocator):
		return true;
	$case $Type == DString:
		return true;
	$endswitch
	return false;
}

macro get_innermost_type($Type) @const @local
{
	var $InnerType = $Type;
	$if $defined($Type.inner):
		$InnerType = $Type.inner;
		$if $InnerType.kindof == POINTER || $InnerType.kindof == SLICE:
			$InnerType = $InnerType.inner;
		$endif
	$endif
	return $InnerType;
}

macro @get_pointee_type_val(#val) @const @local
{
	var $Type = $typeof(#val);
	return get_pointee_type($Type);
}

macro get_pointee_type($Type) @const @local
{
	$if $Type.kindof == POINTER:
		var $Inner = $Type.inner;
		return $Inner;
	$else
		return $Type;
	$endif
}

macro @deref_if_ptr(#val) @local
{
	var $Type = $typeof(#val);
	$if $Type.kindof == POINTER:
		return *#val;
	$else
		return #val;
	$endif
}
