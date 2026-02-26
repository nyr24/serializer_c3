// Implementation of Serializable interface for std collections

module ser::std_containers;

import std::collections::list;
import std::collections::map;
import std::core::dstring @public;
import util;

// ---- List ----

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

struct ListSerializedText
{
	usz     size;
	usz     capacity;
}

macro void List.serialize_to_bin(&list, Serializer* ser, Allocator alloc)
{
	usz entries_byte_size = list.byte_size();
	char[] ser_repr_as_bytes = allocator::alloc_array(alloc, char, usz.sizeof * 2 + entries_byte_size);
	ListSerializedBin* ser_repr = (ListSerializedBin*)ser_repr_as_bytes.ptr;
	ser_repr.size = list.size;
	ser_repr.capacity = list.capacity;
	if (ser_repr.size > 0) {
		mem::copy(&ser_repr.entries, list.entries, entries_byte_size);
	}
	ser.serialize_to_bin(ser_repr_as_bytes, alloc, true);
}

macro void List.deserialize_from_bin(&list, ChunkIterator* chunk_it, Allocator alloc)
{
	var $ItemType = $typeof(*list.entries);
	char[] ser_data = chunk_it.next();
	ListSerializedBin* ser_repr = (ListSerializedBin*)ser_data.ptr;
	list.size = ser_repr.size;
	list.capacity = ser_repr.capacity;
	list.allocator = alloc;
	list.entries = allocator::malloc(alloc, ser_repr.capacity * $ItemType.sizeof);

	if (ser_repr.size > 0) {
		mem::copy(list.entries, &ser_repr.entries, ser_data.len - $offsetof(ser_repr.entries));
	}
}

macro void List.serialize_to_text(&list, Serializer* ser, Allocator alloc)
{
	var $ItemType = $typeof(*list.entries);
	ListSerializedText ser_repr;
	ser_repr.size = list.size;
	ser_repr.capacity = list.capacity;
	ser.serialize_to_text(ser_repr, alloc, false, ListSerializedText.sizeof);
	if (list.size > 0) {
		$ItemType[] entries = allocator::alloc_array(alloc, $ItemType, list.size);
		mem::copy(entries.ptr, list.entries, list.size * $ItemType.sizeof);
		ser.serialize_to_text(entries, alloc, true, list.size * $ItemType.sizeof);
	}
}

<*
	@require parser.curr_char() == TokenChar.STRUCT_START : "Should be at '{' symbol at the moment of call"
*>
macro void List.deserialize_from_text(&list, Parser* parser, Allocator alloc, String file_path)
{
	var $ItemType = $typeof(*list.entries);
	parser.step();
	parser.skip_until_next_value_start();
	parser.parse_number(&list.size);
	parser.skip_until_next_value_start();
	parser.parse_number(&list.capacity);
	parser.skip_until_next_value_start();
	parser.skip_until_struct_end();
	$ItemType[] entries = allocator::alloc_array(alloc, $ItemType, list.capacity);
	parser.parse_array(entries[:list.size]);
	list.entries = entries.ptr;
	list.allocator = alloc;
	parser.skip_until_array_end();
}

// ---- DString ----

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

struct DStringSerializedText @tag(ser::SCHEMA_FMT_TAG, SchemaFormatKind.STRING)
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
	ser.serialize_to_bin(ser_repr_as_bytes, alloc, true);
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
	ser.serialize_to_text(ser_repr, alloc, true, DStringSerializedText.sizeof + str_data.len * char.sizeof);
}

<*
	@require parser.curr_char() == TokenChar.STRUCT_START : "Should be at '{' symbol at the moment of call"
*>
fn void DString.deserialize_from_text(&dstring, Parser* parser, Allocator alloc, String file_path)
{
	usz len;
	usz capacity;
	parser.step();
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

// ---- HashMap ----

struct HashMapSerialized
{
	uint    	count;
	uint    	threshold;
	float   	load_factor;
}

macro void HashMap.serialize_to_bin(&map, Serializer* ser, Allocator alloc)
{
	var $KeyType = $typeof(map.table[0].key);
	var $ValType = $typeof(map.table[0].value);

	HashMapSerialized ser_map;
	ser_map.count = map.count;
	ser_map.threshold = map.threshold;
	ser_map.load_factor = map.load_factor;
	ser.serialize_to_bin(to_byte_slice(&ser_map), alloc, false);

	if (ser_map.count > 0) {
		$KeyType[] keys = map.keys(alloc);
		$ValType[] values = map.values(alloc);
		ser.serialize_to_bin(to_byte_slice(keys), alloc, true);
		ser.serialize_to_bin(to_byte_slice(values), alloc, true);
	}
}

macro void HashMap.deserialize_from_bin(&map, ChunkIterator* chunk_it, Allocator alloc)
{
	var $KeyType = $typeof(map.table[0].key);
	var $ValType = $typeof(map.table[0].value);

	HashMapSerialized* ser_map = (HashMapSerialized*)chunk_it.next().ptr;
	map.allocator = alloc;
	map.count = ser_map.count;
	map.threshold = ser_map.threshold;
	map.load_factor = ser_map.load_factor;
	map.allocator = alloc;
	map.table = allocator::new_array(alloc, void*, (usz)(ser_map.threshold / ser_map.load_factor));

	if (map.count > 0) {
		$KeyType[] keys = from_byte_slice(chunk_it.next(), $KeyType[]);
		$ValType[] values = from_byte_slice(chunk_it.next(), $ValType[]);
		assert(keys.len == values.len, "Should be equal");

		for (uint i; i < keys.len; ++i) {
			map.set(keys[i], values[i]);
		}
	}
}

macro void HashMap.serialize_to_text(&map, Serializer* ser, Allocator alloc)
{
	var $KeyType = $typeof(map.table[0].key);
	var $ValType = $typeof(map.table[0].value);

	HashMapSerialized ser_map;
	ser_map.count = map.count;
	ser_map.threshold = map.threshold;
	ser_map.load_factor = map.load_factor;
	ser.serialize_to_text(ser_map, alloc, false, HashMapSerialized.sizeof);

	if (ser_map.count > 0) {
		$KeyType[] keys = map.keys(alloc);
		$ValType[] vals = map.values(alloc);
		ser.serialize_to_text(keys, alloc, true, $KeyType.sizeof * map.count);
		ser.serialize_to_text(vals, alloc, true, $ValType.sizeof * map.count);
	}
}

<*
	@require parser.curr_char() == TokenChar.STRUCT_START : "Should be at '{' symbol at the moment of call"
*>
macro void HashMap.deserialize_from_text(&map, Parser* parser, Allocator alloc, String file_path)
{
	var $KeyType = $typeof(map.table[0].key);
	var $ValType = $typeof(map.table[0].value);

	parser.step();
	parser.skip_until_next_value_start();
	parser.parse_number(&map.count);
	parser.skip_until_next_value_start();
	parser.parse_number(&map.threshold);
	parser.skip_until_next_value_start();
	parser.parse_number(&map.load_factor);

	map.allocator = alloc;
	map.table = allocator::new_array(alloc, void*, (usz)(map.threshold / map.load_factor));

	if (map.count > 0) {
		$KeyType[] keys = allocator::alloc_array(alloc, $KeyType, map.count);
		$ValType[] values = allocator::alloc_array(alloc, $ValType, map.count);

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
