module ser;

module ser::std_collections::list;

import std::collections::list;

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
