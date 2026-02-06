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

/*
	Chunk in-memory representation
	[CHUNK_ID] 8bytes
	[CHUNK_CONTENTS_LEN:PADDING_LEN] 8bytes[4bytes:4bytes]
	[..contents:padding..]
*/

const usz FILE_FORMAT_ID        @private = 0x123456789abcdeff;
const usz CHUNK_ID              @private = 0xffedcba987654321;
const usz DEFAULT_BUFF_CAPACITY @private = 4096u;
const usz ALIGNMENT             @private = uptr.alignof;
const String BIN_EXT			= ".c3fmt_bin";
const String TEXT_EXT			= ".c3fmt_txt";

faultdef
	NOT_PROPER_FILE_FORMAT;

struct FileHeader
{
	usz  format_id;
	uint contents_len;
	uint mode;
}

struct ChunkHeader
{
	usz  chunk_id;
	uint aligned_size;
	uint padding;
}

struct ChunkIterator
{
	char[] 		buff_view;
	usz    		offset;
}

struct Serializer
{
	Allocator	alloc;
	char[] 	    buff;
	usz			offset;
}

alias SerializationMode = FileOpenMode;

interface Serializable
{
	fn void 	serialize_to_bin(Serializer* ser, Allocator alloc, SerializationMode mode);
	fn void   	deserialize_from_chunks_bin(ChunkIterator chunk_it, Allocator alloc);
	fn void   	deserialize_from_bytes_bin(char[] data, Allocator alloc) @optional;
	// fn char[] serialize_to_text(Allocator alloc);
	// fn void   deserialize_from_text(char[]);
}

macro implements_serializable($Type) @const
{
	return $defined($Type.serialize_to_bin) && $defined($Type.deserialize_from_chunks_bin);
		// && $defined($Type.deserialize_from_bytes_bin);
}

fn void Serializer.init(&ser, Allocator alloc, usz buff_init_cap = 0)
{
	ser.alloc = alloc;
	buff_init_cap = buff_init_cap > 0 ? buff_init_cap : DEFAULT_BUFF_CAPACITY;
	ser.buff = allocator::alloc_array(alloc, char, buff_init_cap);
	ser.offset = 0;
}

// Serialization
 
<*
	@require implements_serializable(util::@get_pointee_type_val(value)) : "Should implement serializable"
*>
macro void Serializer.serialize(
	&ser,
	value,
	Allocator alloc,
	SerializationMode mode,
)
{
	if (mode == BIN) {
		value.serialize_to_bin(ser, alloc, mode);
	} else {
		unreachable("TODO: text serialization!");
	}
}

<*
	@require implements_serializable(util::@get_pointee_type_val(value)) : "Should implement serializable"
*>
macro void Serializer.serialize_and_save_to_file(
	&ser,
	value,
	Allocator alloc,
	SerializationMode mode,
	String file_path,
)
{
	if (mode == BIN) {
		value.serialize_to_bin(ser, alloc, mode);
		ser.save_serialized_data_to_file(file_path, mode);
	} else {
		unreachable("TODO: text serialization!");
	}
}

<*
	Expected to be called on objects which are trivial to serialize (don't contain any pointers),
	Without the need to implement Serializable interface on them,
	Or from Serializable implementations
*>
fn void Serializer.serialize_raw_bytes(
	&ser,
	char[] bytes,
	Allocator alloc,
	SerializationMode mode,
	bool should_free,
)
{
	if (mode == BIN) {
		bool first_chunk = ser.offset == 0;
		usz req_capacity = ser.calc_required_capacity(bytes.len);
		ser.grow_if_needed(req_capacity);
		if (first_chunk) {
			ser.write_file_header_to_buff(bytes.len, mode);
		}
		ser.write_serialized_chunk_to_buff(bytes);
		if (should_free) {
			allocator::free(alloc, bytes.ptr);
		}
	} else {
		unreachable("TODO: text serialization!");
	}
}

<*
	Expected to be called on objects which are trivial to serialize (don't contain any pointers),
	Without the need to implement Serializable interface on them,
	Or from Serializable implementations
*>
fn void Serializer.serialize_raw_bytes_and_save_to_file(
	&ser,
	char[] chunk_data,
	Allocator alloc,
	SerializationMode mode,
	String file_path,
)
{
	if (mode == BIN) {
		bool first_chunk = ser.offset == 0;
		usz req_capacity = ser.calc_required_capacity(chunk_data.len);
		ser.grow_if_needed(req_capacity);
		if (first_chunk) {
			ser.write_file_header_to_buff(chunk_data.len, mode);
		}
		ser.write_serialized_chunk_to_buff(chunk_data);
		ser.save_serialized_data_to_file(file_path, mode);
	} else {
		unreachable("TODO: text serialization!");
	}
}

fn void Serializer.write_serialized_chunk_to_buff(&ser, char[] serialized_chunk) @private
{
	usz aligned_chunk_size = ser.write_chunk_header(serialized_chunk.len);
	mem::copy(ser.buff.ptr + ser.offset, serialized_chunk.ptr, serialized_chunk.len);
	ser.offset += aligned_chunk_size;
	ser.update_file_contents_len_with_curr_offset();
}

// Deserialization

<*
	@require implements_serializable(util::@get_pointee_type_val(value)) : "Should implement serializable"
*>
macro void Serializer.deserialize(
	&ser,
	value,
	Allocator alloc,
	SerializationMode mode,
	String file_path,
)
{
	File file = file::open_read(file_path, mode);
	defer (void)file.close();
	usz file_len = file.get_len();
	ser.grow_if_needed(file_len);
	file.read_all_buff(ser.buff);

	FileHeader header;
	read_file_header_from_buff(ser.buff, &header)!!;
	assert(header.contents_len > 0, "Should have some contents");
	assert(header.contents_len <= file_len, "Should be less or equal to the file size");
	assert((SerializationMode)header.mode == mode, "Serialization mode is not correct");

	ChunkIterator chunk_it;
	chunk_it.buff_view = ser.buff[:FileHeader.sizeof + header.contents_len];
	chunk_it.offset = FileHeader.sizeof;

	if (mode == BIN) {
		value.deserialize_from_chunks_bin(chunk_it, alloc);
	} else {
		unreachable("TODO: text serialization");
	}
}

<*
	Returns a temporary view to the data, you shoud memcpy it after this call,
	use this only if 'serialize_raw_bytes' was called for serialization
*>
fn char[] Serializer.deserialize_raw_bytes(&ser, String file_path, SerializationMode mode)
{
	if (mode == BIN) {
		File file = file::open_read(file_path, BIN);
		defer (void)file.close();
		usz file_len = file.get_len();
		ser.grow_if_needed(file_len);

		file.read_all_buff(ser.buff);
		FileHeader header;
		read_file_header_from_buff(ser.buff, &header)!!;
		assert(header.contents_len > 0, "Should have some contents");
		assert(header.contents_len <= file_len, "Should be less or equal to the file size");
		assert((SerializationMode)header.mode == BIN, "Serialization mode is not correct");

		return ser.buff[FileHeader.sizeof + ChunkHeader.sizeof : header.contents_len];
	} else {
		unreachable("TODO: text deserialization!");
	}
}

fn char[] ChunkIterator.next(&chunk_it)
{
	assert(chunk_it.offset < chunk_it.buff_view.len, "Where is no chunks anymore in buffer, something went wrong");

	ChunkHeader header;
	read_chunk_header_and_move_offset(chunk_it.buff_view, &chunk_it.offset, &header);
	uint chunk_size = header.aligned_size - header.padding;
	char[] chunk_data = chunk_it.buff_view[chunk_it.offset : chunk_size];
	chunk_it.offset += (usz)header.aligned_size;
	return chunk_data;
}

// Headers
<*
	Returns stored the length of file at time of last write
	(actual length of the file can be different)
	@param [out] out_header
*>
fn void? read_file_header_from_buff(char[] buff, FileHeader* out_header) @private
{
	FileHeader* header = (FileHeader*)buff.ptr;
	if (header.format_id != FILE_FORMAT_ID) {
		return NOT_PROPER_FILE_FORMAT~;
	}
	*out_header = *header;
}

fn void Serializer.write_file_header_to_buff(&ser, usz contents_len, SerializationMode mode) @private
{
	FileHeader* header = (FileHeader*)ser.buff.ptr;
	header.format_id = FILE_FORMAT_ID;
	header.contents_len = (uint)contents_len;
	header.mode = (uint)mode;
	ser.offset = FileHeader.sizeof;
}

<*
	Returns aligned chunk size
*>
fn usz Serializer.write_chunk_header(&ser, usz chunk_size) @private
{
	ChunkHeader* header = (ChunkHeader*)(ser.buff.ptr + ser.offset);
	header.chunk_id = CHUNK_ID;
	header.aligned_size = (uint)mem::aligned_offset(chunk_size, ALIGNMENT);
	header.padding = header.aligned_size - (uint)chunk_size;
	ser.offset += ChunkHeader.sizeof;
	return header.aligned_size;
}

<*
	@param [out] out_header
*>
fn void read_chunk_header_and_move_offset(char[] buff, usz* offset, ChunkHeader* out_header) @private
{
	ChunkHeader* header = (ChunkHeader*)(buff.ptr + *offset);
	assert(header.chunk_id == CHUNK_ID, "Should be identifiable as chunk");
	*out_header = *header;
	*offset += ChunkHeader.sizeof;
}

fn void Serializer.update_file_contents_len_with_curr_offset(&ser) @private
{
	FileHeader* file_header = (FileHeader*)ser.buff.ptr;
	file_header.contents_len = (uint)ser.offset - FileHeader.sizeof;
}

fn void Serializer.save_serialized_data_to_file(&ser, String file_path, FileOpenMode mode)
{
	assert(ser.offset > 0, "Should have some data in buffer");

	File file = file::open_write(file_path, mode);
	defer (void)file.close();
	file.write_all(ser.buff[:ser.offset]);
	ser.offset = 0;
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

fn usz Serializer.calc_required_capacity(&ser, usz data_len) @private
{
	bool first_chunk = ser.offset == 0;
	usz aligned_len = mem::aligned_offset(data_len, ALIGNMENT);
	return first_chunk
		? aligned_len + FileHeader.sizeof + ChunkHeader.sizeof
		: aligned_len + ChunkHeader.sizeof;
}

macro String acquire_file_fmt_name(String $base_name, SerializationMode mode)
{
	if (mode == BIN) {
		return $base_name +++ BIN_EXT;
	} else {
		return $base_name +++ TEXT_EXT;
	}
}

fn void Serializer.destroy(&ser)
{
	allocator::free(ser.alloc, ser.buff.ptr);
}
