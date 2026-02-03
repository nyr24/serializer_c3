module ser;

import util;
import std::io;
import std::math;

/*
	File in-memory representation:
	[FILE_FORMAT_ID] 8bytes
	[FILE_CONTENTS_LEN:FORMAT_TYPE] 8bytes[4bytes:4bytes]
	[..contents..] [FILE_CONTENTS_LEN]bytes
*/

const usz FILE_FORMAT_ID = 0x123456789abcdeff;
const usz DEFAULT_BUFF_CAPACITY = 4096u;

faultdef
	NOT_PROPER_FILE_FORMAT;

struct FileHeader
{
	usz  format_id;
	uint contents_len;
	uint mode;
}

struct Serializer
{
	Allocator	alloc;
	char[] 	    buff;
}

alias SerializationMode = FileOpenMode;

// TODO: choose between interface and contract
interface Serializable
{
	fn char[] serialize_to_bin();
	fn void   deserialize_from_bin(char[]);
	fn char[] serialize_to_text();
	fn void   deserialize_from_text(char[]);
}

macro bool implements_serializable($Type)
{
	return $defined($Type.serialize_to_bin) && $defined($Type.serialize_to_text)
		&& $defined($Type.deserialize_from_bin) && $defined($Type.deserialize_from_text);
}

fn void Serializer.init(&ser, Allocator alloc, usz buff_init_cap)
{
	ser.alloc = alloc;
	buff_init_cap = buff_init_cap > 0 ? buff_init_cap : DEFAULT_BUFF_CAPACITY;
	ser.buff = allocator::alloc_array(alloc, char, buff_init_cap);
}

// Serialization
 
<*
	@require implements_serializable(Type) : "Type must implement serializable interface"
*>
fn void Serializer.serialize(&ser, Type val, String file_path, SerializationMode mode) <Type>
{
	if (mode == BIN) {
		char[] data = val.serialize_to_bin();
	} else {
		char[] data = val.serialize_to_text();
	}
	ser.save_data(data, file_path, mode);
}

<*
	Input type must be trivially serializable (mustn't contain any pointers)
*>
fn void Serializer.serialize_to_bin_generic(&ser, char[] data, String file_path) @private
{
	ser.save_data(data, file_path, BIN);
}

fn void Serializer.save_data(&ser, char[] serialized_data, String file_path, FileOpenMode mode) @private
{
	File file = file::open_write(file_path, mode);
	defer (void)file.close();
	ser.grow_if_needed(serialized_data.len + FileHeader.sizeof);
	ser.write_header_to_buff(serialized_data.len, mode);
	mem::copy(ser.buff.ptr + FileHeader.sizeof, serialized_data.ptr, serialized_data.len);
	file.write_all(ser.buff[:(FileHeader.sizeof + serialized_data.len)]);
}

// Deserialization

<*
	@require implements_serializable(Type) : "Type must implement serializable interface"
*>
fn char[] Serializer.deserialize(&ser, Type value, String file_path, SerializationMode mode) <Type>
{
	File file = file::open_read(file_path, mode);
	defer (void)file.close();
	usz file_len = file.get_len();
	ser.grow_if_needed(file_len);
	file.read_all(ser.buff);

	FileHeader header;
	ser.read_header_from_buff(&header)!!;
	assert(header.contents_len > 0, "Should have some contents");
	assert(header.contents_len + FileHeader.sizeof <= file_len, "Should be less or equal to the file size");
	assert(header.mode == mode, "Serialization mode is not correct");

	if (mode == BIN) {
		return value.deserialize_from_bin(ser.buff[FileHeader.sizeof : header.contents_len]);
	} else {
		return value.deserialize_from_text(ser.buff[FileHeader.sizeof : header.contents_len]);
	}
}

<*
	Returns a temporary view to the data, you shoud memcpy it after this call
*>
fn char[] Serializer.deserialize_from_bin_generic(&ser, String file_path)
{
	File file = file::open_read(file_path, BIN);
	defer (void)file.close();
	usz file_len = file.get_len();
	ser.grow_if_needed(file_len);

	file.read_all_buff(ser.buff);
	FileHeader header;
	ser.read_header_from_buff(&header)!!;
	assert(header.contents_len > 0 && header.contents_len > FileHeader.sizeof, "Should have some contents");
	assert(header.contents_len <= file_len, "Should be less or equal to the file size");
	assert((SerializationMode)header.mode == BIN, "Serialization mode is not correct");

	return ser.buff[FileHeader.sizeof : header.contents_len];
}

<*
	@require ser.buff.len > 0 : "Should not be zero"
	@param add_cap : "Size of the data that needs be added to the buffer"
*>
fn void Serializer.grow_if_needed(&ser, usz add_cap) @private
{
	usz curr_cap = ser.buff.len;
	if (add_cap <= curr_cap) {
		return;
	}

	usz need_cap = add_cap - curr_cap;
	usz new_cap = curr_cap * 2;
	while (new_cap < (curr_cap + need_cap)) {
		new_cap *= 2;
	}
	ser.buff = allocator::realloc_array(ser.alloc, ser.buff.ptr, char, new_cap);
}

fn void Serializer.destroy(&ser)
{
	allocator::free(ser.alloc, ser.buff.ptr);
}

<*
	Returns stored the length of file at time of last write
	(actual length of the file can be different)
	@param [out] out_header
*>
fn void? Serializer.read_header_from_buff(&ser, FileHeader* out_header) @private
{
	FileHeader* header = (FileHeader*)ser.buff.ptr;
	if (header.format_id != FILE_FORMAT_ID) {
		return NOT_PROPER_FILE_FORMAT~;
	}
	*out_header = *header;
}

fn void Serializer.write_header_to_buff(&ser, usz contents_len, SerializationMode mode) @private
{
	FileHeader* header = (FileHeader*)ser.buff.ptr;
	header.format_id = FILE_FORMAT_ID;
	header.contents_len = (uint)contents_len;
	header.mode = (uint)mode;
}
