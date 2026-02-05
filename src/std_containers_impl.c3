// Implementation of Serializable interface for std collections 

module std::collections::list;

import ser;

struct ListSerialized
{
	usz     size;
	usz     capacity;
	char[*] entries;
}

fn void List.serialize_to_bin(&list, Serializer* ser, Allocator alloc, SerializationMode mode) @dynamic
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
	ser.push_serialized_data(data, alloc, mode);
}

fn void List.deserialize_from_chunks_bin(&list, ChunkIterator chunk_it, Allocator alloc) @dynamic
{
	char[] ser_data = chunk_it.next();
	ListSerialized* ser_repr = (ListSerialized*)ser_data.ptr;
	list.size = ser_repr.size;
	list.capacity = ser_repr.capacity;
	list.allocator = alloc;
	list.entries = allocator::malloc(alloc, ser_repr.capacity);

	if (ser_repr.size > 0) {
		mem::copy(list.entries, &ser_repr.entries, ser_data.len - $offsetof(ser_repr.entries));
	}
}

fn void List.deserialize_from_data_bin(&list, char[] ser_data, Allocator alloc) @dynamic
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

import ser;

struct DStringSerialized
{
	usz     len;
	usz     capacity;
	char[*] chars;
}

fn void DString.serialize_to_bin(&dstring, Serializer* ser, Allocator alloc, SerializationMode mode) @dynamic
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
	ser.push_serialized_data(ser_data, alloc, mode);
}

fn void DString.deserialize_from_chunks_bin(&dstring, ChunkIterator chunk_it, Allocator alloc) @dynamic
{
	char[] ser_data = chunk_it.next();
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

fn void DString.deserialize_from_data_bin(&dstring, char[] ser_data, Allocator alloc) @dynamic
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
