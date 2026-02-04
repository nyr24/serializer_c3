module ser;

// Implementation of Serializable interface for std collections 

module std::collections::list;

struct ListSerialized
{
	usz     size;
	usz     capacity;
	char[*] entries;
}

fn char[] List.serialize_to_bin(&list, Allocator alloc) @dynamic
{
	usz entries_byte_size = list.byte_size();
	usz mem_requirement = usz.sizeof * 2 + entries_byte_size;
	char[] data = allocator::alloc_array(alloc, char, mem_requirement);
	ListSerialized* ser_repr = (ListSerialized*)data.ptr;
	ser_repr.size = list.size;
	ser_repr.capacity = list.capacity;
	if (mem_requirement > 0) {
		mem::copy(&ser_repr.entries, list.entries, entries_byte_size);
	}
	return data;
}

fn void List.deserialize_from_bin(&list, char[] ser_data, Allocator alloc) @dynamic
{
	ListSerialized* ser_repr = (ListSerialized*)ser_data.ptr;
	list.size = ser_repr.size;
	list.capacity = ser_repr.capacity;
	list.allocator = alloc;
	list.entries = allocator::malloc(alloc, ser_repr.capacity);

	if (ser_repr.size > 0) {
		mem::copy(list.entries, &ser_repr.entries, ser_data.len - $offsetof(ser_repr.entries));
	}
}

module std::core::dstring;

struct DStringSerialized
{
	usz     len;
	usz     capacity;
	char[*] chars;
}

fn char[] DString.serialize_to_bin(&dstring, Allocator alloc) @dynamic
{
	usz cap = dstring.capacity();
	StringData* str_data = dstring.data();
	
	usz mem_requirement = usz.sizeof * 2 + str_data.capacity;
	char[] ser_data = allocator::alloc_array(alloc, char, mem_requirement);
	DStringSerialized* ser_repr = (DStringSerialized*)ser_data.ptr;
	ser_repr.len = str_data.len;
	ser_repr.capacity = str_data.capacity;
	if (mem_requirement > 0) {
		mem::copy(&ser_repr.chars, &str_data.chars, str_data.len);
	}
	return ser_data;
}

fn void DString.deserialize_from_bin(&dstring, char[] ser_data, Allocator alloc) @dynamic
{
	DStringSerialized* ser_repr = (DStringSerialized*)ser_data.ptr;
	StringData* data = allocator::alloc_with_padding(alloc, StringData, ser_repr.capacity)!!;
	data.allocator = alloc;
	data.len = ser_repr.len;
	data.capacity = ser_repr.capacity;
	if (ser_repr.len > 0) {
		mem::copy(&data.chars, &ser_repr.chars, ser_repr.len);
	}
	*dstring = (DString)data;
}
