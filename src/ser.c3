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

const usz FILE_FORMAT_ID_BIN    @private = 0x123456789abcdeff;
const usz FILE_FORMAT_ID_TXT    @private = 0x123456789abcdeaa;
const usz CHUNK_ID              @private = 0xffedcba987654321;
const usz DEFAULT_BUFF_CAPACITY @private = 4096u;
const usz ALIGNMENT             @private = uptr.alignof;
const String BIN_EXT			= ".bin";
const String TEXT_EXT			= ".txt";

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
	DString 	buff;
	Allocator	alloc;
	Formatter	formatter;
	Parser		parser;
}

alias SerializationMode = FileOpenMode;

// No runtime dispatch because of religious views
// code gen forever, compile times also forever
	// interface Serializable
	// {
	// 	fn void 	serialize_to_bin(Serializer* ser, Allocator alloc, SerializationMode mode);
	// 	fn void   	deserialize_from_chunks_bin(ChunkIterator chunk_it, Allocator alloc);
	// 	fn void   	deserialize_from_bytes_bin(char[] data, Allocator alloc) @optional;
		// fn char[] serialize_to_text(Allocator alloc);
		// fn void   deserialize_from_text(char[]);
	// }

macro implements_serializable_to_bin($Type) @const
{
	return $defined($Type.serialize_to_bin) && $defined($Type.deserialize_from_chunks_bin);
}

macro implements_serializable_to_text($Type) @const
{
	return $defined($Type.serialize_to_text) && $defined($Type.deserialize_from_text);
}

macro deserializable_from_chunks_bin($Type) @const
{
	return $defined($Type.deserialize_from_chunks_bin);
}

macro deserializable_from_bytes_bin($Type) @const
{
	return $defined($Type.deserialize_from_bytes_bin);
}

fn void Serializer.init(&ser, Allocator alloc, usz buff_init_cap = 0)
{
	ser.alloc = alloc;
	buff_init_cap = buff_init_cap > 0 ? buff_init_cap : DEFAULT_BUFF_CAPACITY;
	ser.buff.init(alloc, buff_init_cap);
	ser.formatter.init(&formatter_output_fn, ser);
}

// Serialization Bin
 
<*
	@require implements_serializable_to_bin(util::@get_pointee_type_val(val)) : "Should implement serializable to binary"
*>
macro void Serializer.serialize_to_bin(
	&ser,
	val,
	Allocator alloc,
)
{
	val.serialize_to_bin(ser, alloc);
}

<*
	@require implements_serializable_to_bin(util::@get_pointee_type_val(val)) : "Should implement serializable to binary"
*>
macro void Serializer.serialize_to_bin_and_save_to_file(
	&ser,
	val,
	Allocator alloc,
	String file_path,
)
{
	val.serialize_to_bin(ser, alloc);
	ser.save_serialized_data_to_file(file_path, BIN);
}

<*
	Expected to be called on objects which are trivial to serialize (don't contain any pointers),
	Without the need to implement Serializable interface on them,
	Or from Serializable implementations
*>
fn void Serializer.serialize_to_bin_trivial(
	&ser,
	char[] bytes,
	Allocator alloc,
	bool should_free,
)
{
	bool first_chunk = ser.buff.len() == 0;
	usz req_capacity = ser.calc_required_capacity_bin(bytes.len);
	ser.buff.reserve(req_capacity);
	if (first_chunk) {
		ser.write_file_header_to_buff(bytes.len, BIN);
	}
	ser.write_serialized_chunk_to_buff(bytes);
	if (should_free) {
		allocator::free(alloc, bytes.ptr);
	}
}

<*
	Expected to be called on objects which are trivial to serialize (don't contain any pointers),
	Without the need to implement Serializable interface on them,
	Or from Serializable implementations
*>
fn void Serializer.serialize_to_bin_trivial_and_save_to_file(
	&ser,
	char[] bytes,
	Allocator alloc,
	bool should_free,
	String file_path,
)
{
	ser.serialize_to_bin_trivial(bytes, alloc, should_free);
	ser.save_serialized_data_to_file(file_path, BIN);
}

// Deserialization Bin

<*
	@require implements_serializable_to_bin(util::@get_pointee_type_val(val)) : "Should implement serializable to binary"
*>
macro void Serializer.deserialize_from_bin(
	&ser,
	val,
	Allocator alloc,
	String file_path,
)
{
	usz contents_len = ser.read_file_into_buffer(BIN, file_path);
	
	ChunkIterator chunk_it;
	chunk_it.buff_view = ser.buff.view_range_len(0, FileHeader.sizeof + contents_len);
	chunk_it.offset = FileHeader.sizeof;

	val.deserialize_from_chunks_bin(chunk_it, alloc);
}

<*
	Returns a temporary view to the data, you shoud memcpy it after this call,
	use this only if 'serialize_to_bin_trivial' was called for serialization
*>
fn char[] Serializer.deserialize_from_bin_trivial(&ser, String file_path)
{
	usz contents_len = ser.read_file_into_buffer(BIN, file_path);
	return ser.buff.view_range_len(FileHeader.sizeof + ChunkHeader.sizeof, contents_len);
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

fn void Serializer.write_serialized_chunk_to_buff(&ser, char[] serialized_chunk) @private
{
	usz aligned_chunk_size = ser.write_chunk_header(serialized_chunk.len);
	ser.buff.append_string((String)serialized_chunk);
	ser.update_file_contents_len_with_curr_offset();
}

// Serialization Text

macro void Serializer.serialize_to_text_trivial(
	&ser,
	val,
	Allocator alloc,
	usz assumed_data_size = 0,
)
{
	assumed_data_size = math::max($sizeof(val), assumed_data_size);
	usz assumed_req_capacity = ser.calc_required_capacity_text(assumed_data_size);
	ser.buff.reserve(assumed_req_capacity);
	ser.write_file_header_to_buff(0, TEXT);
	ser.formatter.format_any(val, 0, true);
	ser.update_file_contents_len_with_curr_offset();
}

macro void Serializer.serialize_to_text_trivial_and_save_to_file(
	&ser,
	val,
	Allocator alloc,
	String file_path,
	usz assumed_data_size = 0,
)
{
	ser.serialize_to_text_trivial(val, alloc, assumed_data_size);
	ser.save_serialized_data_to_file(file_path, TEXT);
}

// Deserialization Text

<*
	@require util::is_kindof($typeof(val), POINTER, SLICE) : "Should be a pointer or slice"
*>
macro void Serializer.deserialize_from_text_trivial(
	&ser,
	val,
	Allocator alloc,
	String file_path,
)
{
	usz contents_len = ser.read_file_into_buffer(TEXT, file_path);
	ser.parser.init(ser.buff.view_range_len(FileHeader.sizeof, contents_len));
	ser.parser.start(val);
}

// Utils

fn usz Serializer.read_file_into_buffer(&ser, SerializationMode mode, String file_path) @private
{
	File file = file::open_read(file_path, mode);
	defer (void)file.close();
	usz file_len = file.get_len();
	ser.buff.reserve(file_len);
	ser.buff.resize(file_len);

	file.read_all_buff(ser.buff.str_view());
	FileHeader header;
	read_file_header_from_buff(ser.buff.str_view(), &header)!!;
	assert(header.contents_len > 0, "Should have some contents");
	assert(header.contents_len <= file_len, "Should be less or equal to the file size");
	assert((SerializationMode)header.mode == mode, "Serialization mode is not correct");
	return header.contents_len;
}
 
<*
	Returns stored the length of file at time of last write
	(actual length of the file can be different)
	@param [out] out_header
*>
fn void? read_file_header_from_buff(char[] buff, FileHeader* out_header) @private
{
	FileHeader* header = (FileHeader*)buff.ptr;
	if (header.format_id != FILE_FORMAT_ID_BIN && header.format_id != FILE_FORMAT_ID_TXT) {
		return NOT_PROPER_FILE_FORMAT~;
	}
	*out_header = *header;
}

fn void Serializer.write_file_header_to_buff(&ser, usz contents_len, SerializationMode mode) @private
{
	FileHeader header;
	header.format_id = mode == BIN ? FILE_FORMAT_ID_BIN : FILE_FORMAT_ID_TXT;
	header.contents_len = (uint)contents_len;
	header.mode = (uint)mode;
	char[] header_as_bytes = util::ptr_to_byte_slice{FileHeader}(&header);
	ser.buff.append_string((String)header_as_bytes);
}

<*
	Returns aligned chunk size
*>
fn usz Serializer.write_chunk_header(&ser, usz chunk_size) @private
{
	ChunkHeader header;
	header.chunk_id = CHUNK_ID;
	header.aligned_size = (uint)mem::aligned_offset(chunk_size, ALIGNMENT);
	header.padding = header.aligned_size - (uint)chunk_size;
	char[] header_as_bytes = util::ptr_to_byte_slice{ChunkHeader}(&header);
	ser.buff.append_string((String)header_as_bytes);
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
	FileHeader* file_header = (FileHeader*)&ser.buff[0];
	file_header.contents_len = (uint)ser.buff.len() - FileHeader.sizeof;
}

fn void Serializer.save_serialized_data_to_file(&ser, String file_path, FileOpenMode mode)
{
	assert(ser.buff.len() > 0, "Should have some data in buffer");

	File file = file::open_write(file_path, mode);
	defer (void)file.close();
	file.write_all(ser.buff.str_view());
	ser.buff.clear();
}

fn usz Serializer.calc_required_capacity_bin(&ser, usz data_len) @private
{
	bool first_chunk = ser.buff.len() == 0;
	usz aligned_len = mem::aligned_offset(data_len, ALIGNMENT);
	return first_chunk
		? aligned_len + FileHeader.sizeof + ChunkHeader.sizeof
		: aligned_len + ChunkHeader.sizeof;
}

fn usz Serializer.calc_required_capacity_text(&ser, usz data_len) @private
{
	usz aligned_len = mem::aligned_offset(data_len, ALIGNMENT);
	return aligned_len + FileHeader.sizeof;
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
	ser.buff.free();
}

fn void? formatter_output_fn(void* data, char c) @local
{
	Serializer* ser = data;
	ser.buff.append_char(c);
}
