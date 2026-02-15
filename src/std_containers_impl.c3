// Implementation of Serializable interface for std collections 

module std::collections::list <Type>;

import ser;
import util;

struct ListSerializedBin
{
	usz     size;
	usz     capacity;
	char[*] entries;
}

fn void ListSerializedBin.free(&ser_repr, Allocator alloc)
{
	allocator::free(alloc, &ser_repr);
}

struct ListSerializedText <Type>
{
	usz     size;
	usz     capacity;
	Type[]	entries;
}

fn void ListSerializedText.free(&ser_repr, Allocator alloc)
{
	allocator::free(alloc, ser_repr.entries.ptr);
}

fn void List.serialize_to_bin(&list, Serializer* ser, Allocator alloc)
{
	usz entries_byte_size = list.byte_size();
	char[] ser_repr_as_bytes = allocator::alloc_array(alloc, char, usz.sizeof * 2 + entries_byte_size);
	ListSerializedBin* ser_repr = (ListSerializedBin*)ser_repr_as_bytes.ptr;
	ser_repr.size = list.size;
	ser_repr.capacity = list.capacity;
	if (ser_repr.size > 0) {
		mem::copy(&ser_repr.entries, list.entries, entries_byte_size);
	}
	ser.append_bin_data_to_buff(ser_repr_as_bytes, alloc, true);
}

fn void List.deserialize_from_bin(&list, ChunkIterator* chunk_it, Allocator alloc)
{
	char[] ser_data = chunk_it.next();
	ListSerializedBin* ser_repr = (ListSerializedBin*)ser_data.ptr;
	list.size = ser_repr.size;
	list.capacity = ser_repr.capacity;
	list.allocator = alloc;
	list.entries = allocator::malloc(alloc, ser_repr.capacity * Type.sizeof);

	if (ser_repr.size > 0) {
		mem::copy(list.entries, &ser_repr.entries, ser_data.len - $offsetof(ser_repr.entries));
	}
}

fn void List.serialize_to_text(&list, Serializer* ser, Allocator alloc)
{
	ListSerializedText ser_repr;
	ser_repr.size = list.size;
	ser_repr.capacity = list.capacity;
	if (list.size > 0) {
		ser_repr.entries = allocator::alloc_array(alloc, Type, list.size);
		mem::copy(ser_repr.entries.ptr, list.entries, list.size * Type.sizeof);
	}
	ser.append_text_data_to_buff(ser_repr, alloc, true, ListSerializedText.sizeof + list.size * Type.sizeof);
}

<*
	@require parser.curr_char() == TokenChar.STRUCT_START : "Should be at '{' symbol at the moment of call"
*>
fn void List.deserialize_from_text(&list, Parser* parser, Allocator alloc, String file_path)
{
	parser.next();
	parser.skip_until_next_value_start();
	parser.parse_number(&list.size);
	parser.skip_until_next_value_start();
	parser.parse_number(&list.capacity);
	parser.skip_until_next_value_start();
	Type[] entries = allocator::alloc_array(alloc, Type, list.capacity); 
	parser.parse_array(entries[:list.size]);
	list.entries = entries.ptr;
	list.allocator = alloc;
	parser.skip_until_struct_end();
}

module std::core::dstring;

import ser;
import util;

struct DStringSerializedBin
{
	usz     len;
	usz     capacity;
	char[*] chars;
}


fn void DStringSerializedBin.free(&ser_repr, Allocator alloc)
{
	allocator::free(alloc, &ser_repr);
}

struct DStringSerializedText @tag(CustomFmtTag.STRUCT_STRING, 1)
{
	usz     len;
	usz     capacity;
	char[] 	chars;
}

fn void DStringSerializedText.free(&ser_repr, Allocator alloc)
{
	allocator::free(alloc, ser_repr.chars.ptr);
}

fn void DString.serialize_to_bin(&dstring, Serializer* ser, Allocator alloc)
{
	StringData* str_data = dstring.data();
	char[] ser_repr_as_bytes = allocator::alloc_array(alloc, char, usz.sizeof * 2 + str_data.len * char.sizeof);
	DStringSerializedBin* ser_repr = (DStringSerializedBin*)ser_repr_as_bytes.ptr;
	ser_repr.len = str_data.len;
	ser_repr.capacity = str_data.capacity;
	if (ser_repr.len > 0) {
		mem::copy(&ser_repr.chars, &str_data.chars, str_data.len);
	}
	ser.append_bin_data_to_buff(ser_repr_as_bytes, alloc, true);
}

fn void DString.deserialize_from_bin(&dstring, ChunkIterator* chunk_it, Allocator alloc)
{
	char[] ser_data = chunk_it.next();
	DStringSerializedBin* ser_repr = (DStringSerializedBin*)ser_data.ptr;
	StringData* data = allocator::alloc_with_padding(alloc, StringData, ser_repr.capacity)!!;
	data.allocator = alloc;
	data.len = ser_repr.len;
	data.capacity = ser_repr.capacity;
	if (ser_repr.len > 0) {
		mem::copy(&data.chars, &ser_repr.chars, ser_repr.len);
	}
	*dstring = (DString)data;
}

fn void DString.serialize_to_text(&dstring, Serializer* ser, Allocator alloc)
{
	StringData* str_data = dstring.data();
	DStringSerializedText ser_repr;
	ser_repr.len = str_data.len;
	ser_repr.capacity = str_data.capacity;
	ser_repr.chars = allocator::alloc_array(alloc, char, str_data.len);
	if (ser_repr.len > 0) {
		mem::copy(ser_repr.chars.ptr, &str_data.chars, str_data.len);
	}
	ser.append_text_data_to_buff(ser_repr, alloc, true, DStringSerializedText.sizeof + str_data.len * char.sizeof);
}

<*
	@require parser.curr_char() == TokenChar.STRUCT_START : "Should be at '{' symbol at the moment of call"
*>
fn void DString.deserialize_from_text(&dstring, Parser* parser, Allocator alloc, String file_path)
{
	usz len;
	usz capacity;
	parser.next();
	parser.skip_until_next_value_start();
	parser.parse_number(&len);
	parser.skip_until_next_value_start();
	parser.parse_number(&capacity);

	StringData* data = allocator::alloc_with_padding(alloc, StringData, capacity)!!;
	data.len = len;
	data.capacity = capacity;
	data.allocator = alloc;
	*dstring = (DString)data;

	parser.skip_until_next_value_start();
	parser.parse_string(data.chars[:data.len]);
	parser.skip_until_struct_end();
}

module std::collections::map <Key, Value>;

import ser;
import util;

struct HashMapSerializedBin
{
	uint    	count;
	uint    	threshold;
	float   	load_factor;
}

struct HashMapSerializedText
{
	uint    	count;
	uint    	threshold;
	float   	load_factor;
	Key[]		keys;
	Value[]		values;
}

fn void HashMapSerializedText.free(&map, Allocator alloc)
{
	allocator::free(alloc, map.keys.ptr);
	allocator::free(alloc, map.values.ptr);
}

fn void HashMap.serialize_to_bin(&map, Serializer* ser, Allocator alloc)
{
	Key[] keys = map.keys(alloc);
	Value[] values = map.values(alloc);
	HashMapSerializedBin ser_map;
	ser_map.count = map.count;
	ser_map.threshold = map.threshold;
	ser_map.load_factor = map.load_factor;
	ser.append_bin_data_to_buff(util::ptr_to_byte_slice{HashMapSerializedBin}(&ser_map), alloc, false);
	if (ser_map.count > 0) {
		ser.append_bin_data_to_buff(util::to_byte_slice{Key}(keys), alloc, true);
		ser.append_bin_data_to_buff(util::to_byte_slice{Value}(values), alloc, true);
	}
}

fn void HashMap.deserialize_from_bin(&map, ChunkIterator* chunk_it, Allocator alloc)
{
	HashMapSerializedBin* ser_map = (HashMapSerializedBin*)chunk_it.next().ptr;
	map.allocator = alloc;
	map.load_factor = ser_map.load_factor;
	map.threshold = ser_map.threshold;
	map.allocator = alloc;
	map.table = allocator::new_array(alloc, void*, (usz)(ser_map.threshold / ser_map.load_factor));

	Key[] keys = util::from_byte_slice{Key}(chunk_it.next());
	Value[] values = util::from_byte_slice{Value}(chunk_it.next());
	assert(keys.len == values.len, "Should be equal");

	for (uint i; i < keys.len; ++i) {
		map.set(keys[i], values[i]);
	}
}

fn void HashMap.serialize_to_text(&map, Serializer* ser, Allocator alloc)
{
	HashMapSerializedText ser_map;
	ser_map.count = map.count;
	ser_map.threshold = map.threshold;
	ser_map.load_factor = map.load_factor;
	if (ser_map.count > 0) {
		ser_map.keys = map.keys(alloc);
		ser_map.values = map.values(alloc);
	}
	ser.append_text_data_to_buff(ser_map, alloc, true, HashMapSerializedText.sizeof + $sizeof(*map.table[0]) * map.count);
}

<*
	@require parser.curr_char() == TokenChar.STRUCT_START : "Should be at '{' symbol at the moment of call"
*>
fn void HashMap.deserialize_from_text(&map, Parser* parser, Allocator alloc, String file_path)
{
	parser.next();
	parser.skip_until_next_value_start();
	parser.parse_number(&map.count);
	parser.skip_until_next_value_start();
	parser.parse_number(&map.threshold);
	parser.skip_until_next_value_start();
	parser.parse_number(&map.load_factor);

	map.allocator = alloc;
	map.table = allocator::new_array(alloc, void*, (usz)(map.threshold / map.load_factor));

	if (map.count > 0) {
		Key[] keys = allocator::alloc_array(alloc, Key, map.count);
		Value[] values = allocator::alloc_array(alloc, Value, map.count);
	
		parser.skip_until_next_value_start();
		parser.parse_array(keys);
		parser.skip_until_next_value_start();
		parser.parse_array(values);

		for (uint i = 0; i < keys.len; ++i) {
			map.set(keys[i], values[i]);
		}
	}
	parser.skip_until_struct_end();
}
