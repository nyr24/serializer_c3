module ser;

import util;
import std::io;
import std::math;
import std::collections::list;

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
	List{char} 	  buff;
	Allocator	  alloc;
	Formatter	  formatter;
	Parser		  parser;
	ChunkIterator chunk_it;
}

alias SerializationMode = FileOpenMode;

// Binary Serialization interface checks

macro implements_serializable_to_bin($Type) @const
{
	return $defined($Type.serialize_to_bin) && $defined($Type.deserialize_from_bin);
}

macro implements_serializable_to_text($Type) @const
{
	return $defined($Type.serialize_to_text) && $defined($Type.deserialize_from_text);
}

// Serializer impl

fn void Serializer.init(&ser, Allocator alloc, usz buff_init_cap = 0)
{
	ser.alloc = alloc;
	buff_init_cap = buff_init_cap > 0 ? buff_init_cap : DEFAULT_BUFF_CAPACITY;
	ser.buff.init(alloc, buff_init_cap);
	ser.formatter.init(&formatter_output_fn, ser);
}

// Serialization Bin
 
macro void Serializer.serialize_to_bin(
	&ser,
	val,
	Allocator alloc,
	bool should_free_memory = false,
)
{
	$if implements_serializable_to_bin(util::@get_pointee_type_val(val)):
		val.serialize_to_bin(ser, alloc);
	$else
		ser.append_bin_data_to_buff(util::to_byte_slice(val), alloc, should_free_memory);
	$endif
}

macro void Serializer.serialize_to_bin_and_save_to_file(
	&ser,
	val,
	Allocator alloc,
	String file_path,
	bool should_free_memory = false,
)
{
	ser.serialize_to_bin(val, alloc, should_free_memory);
	ser.save_serialized_data_to_file(file_path, BIN);
}

fn void Serializer.append_bin_data_to_buff(
	&ser,
	char[] data,
	Allocator alloc,
	bool should_free_memory = false,
)
{
	bool first_chunk = ser.buff.size == 0;
	usz req_capacity = ser.calc_required_capacity_bin(data.len);
	ser.buff.reserve(req_capacity);
	if (first_chunk) {
		ser.write_file_header_to_buff(data.len, BIN);
	}
	ser.write_serialized_chunk_to_buff(data);
	if (should_free_memory) {
		allocator::free(alloc, &data);
	}
}

fn void Serializer.append_bin_data_to_buff_and_save_file(
	&ser,
	char[] data,
	Allocator alloc,
	String file_path,
	bool should_free_memory = false,
) @private
{
	ser.append_bin_data_to_buff(data, alloc, should_free_memory);
	ser.save_serialized_data_to_file(file_path, BIN);
}

// Deserialization Bin

<*
	This call will try to read existing data in current buffer
	If you want to start reading from new file, you should explicitly call 'reset_state' on serializer object
	@require util::is_kindof($typeof(val), POINTER, SLICE) : "Should be a pointer or slice"
*>
macro void Serializer.deserialize_from_bin(
	&ser,
	val,
	Allocator alloc,
	String file_path,
)
{
	$if implements_serializable_to_bin(util::@get_pointee_type_val(val)):
		if (!ser.chunk_it.is_initialized()) {
			usz contents_len = ser.read_file_into_buffer(BIN, file_path);
			ser.chunk_it.init(ser, contents_len);
		}
		val.deserialize_from_bin(&ser.chunk_it, alloc);
	$else
		ser.acquire_bin_data_from_file(alloc, file_path);
	$endif
}

<*
	Caller must free the data
*>
fn char[] Serializer.acquire_bin_data_from_file(&ser, Allocator alloc, String file_path)
{
	usz contents_len = ser.read_file_into_buffer(BIN, file_path);
	char[] buff_view = ser.buff.view_range_len(FileHeader.sizeof + ChunkHeader.sizeof, contents_len - ChunkHeader.sizeof);
	char[] data = allocator::alloc_array(alloc, char, buff_view.len);
	mem::copy(data.ptr, buff_view.ptr, buff_view.len);
	ser.reset_state();
	return data;
}

fn void Serializer.write_serialized_chunk_to_buff(&ser, char[] serialized_chunk) @private
{
	usz padding = ser.write_chunk_header(serialized_chunk.len);
	ser.buff.push_all(serialized_chunk);
	ser.buff.move_forward(padding);

	ser.update_file_contents_len_with_curr_offset();
}

// ChunkIterator

fn void ChunkIterator.init(&chunk_it, Serializer* ser, usz contents_len)
{
	chunk_it.buff_view = ser.buff.view_range_len(0, FileHeader.sizeof + contents_len);
	chunk_it.offset = FileHeader.sizeof;
}

fn void ChunkIterator.reset(&chunk_it)
{
	mem::set(chunk_it, 0, ChunkIterator.sizeof);
}

fn bool ChunkIterator.is_initialized(&chunk_it)
{
	return chunk_it.buff_view.ptr && chunk_it.buff_view.len > 0;
}

fn char[] ChunkIterator.next(&chunk_it)
{
	assert(chunk_it.offset < chunk_it.buff_view.len, "Where is no chunks anymore in buffer, something went wrong");

	ChunkHeader header;
	chunk_it.read_chunk_header_and_move_offset(&header);
	uint chunk_size = header.aligned_size - header.padding;
	char[] chunk_data = chunk_it.buff_view[chunk_it.offset : chunk_size];
	chunk_it.offset += (usz)header.aligned_size;
	return chunk_data;
}

<*
	@param [out] out_header
*>
fn void ChunkIterator.read_chunk_header_and_move_offset(&it, ChunkHeader* out_header) @private
{

	ChunkHeader* header = (ChunkHeader*)(it.buff_view.ptr + it.offset);
	assert(header.chunk_id == CHUNK_ID, "Should be identifiable as chunk");
	*out_header = *header;
	it.offset += ChunkHeader.sizeof;
}

// Serialization Text

macro void Serializer.serialize_to_text(
	&ser,
	val,
	Allocator alloc,
	bool should_free_memory = false,
	usz assumed_serialized_data_size = 0,
)
{
	$if implements_serializable_to_text(util::@get_pointee_type_val(val)):
		if (ser.buff.size == 0) {
			ser.write_file_header_to_buff(0, TEXT);
		}
		val.serialize_to_text(ser, alloc);
		ser.update_file_contents_len_with_curr_offset();
	$else
		ser.append_text_data_to_buff(val, alloc, should_free_memory, assumed_serialized_data_size);
	$endif
}

macro void Serializer.serialize_to_text_and_save_to_file(
	&ser,
	val,
	Allocator alloc,
	String file_path,
	bool should_free_memory = false,
	usz assumed_serialized_data_size = 0,
)
{
	ser.serialize_to_text(val, alloc, should_free_memory, assumed_serialized_data_size);
	ser.save_serialized_data_to_file(file_path, TEXT);
}

macro void Serializer.append_text_data_to_buff(
	&ser,
	data,
	Allocator alloc,
	bool should_free_memory = false,
	usz assumed_serialized_data_size = 0,
)
{
	assumed_serialized_data_size = math::max($sizeof(data), assumed_serialized_data_size);
	usz assumed_req_capacity = ser.calc_required_capacity_text(assumed_serialized_data_size);
	ser.buff.reserve(assumed_req_capacity);
	if (ser.buff.size == 0) {
		ser.write_file_header_to_buff(0, TEXT);
	}
	ser.formatter.format_any(data, 0, true);
	ser.update_file_contents_len_with_curr_offset();

	if (should_free_memory) {
		$if $defined(data.free(alloc)):
			data.free(alloc);
		$else
			allocator::free(alloc, &data);
		$endif
	}
}

// Deserialization Text

<*
	This call will try to read existing data in current buffer
	If you want to start reading from new file, you should explicitly call 'reset_state' on serializer object
	@require util::is_kindof($typeof(val), POINTER, SLICE) : "Should be a pointer or slice"
*>
macro void Serializer.deserialize_from_text(
	&ser,
	val,
	Allocator alloc,
	String file_path,
)
{
	if (!ser.buff.entries || !ser.parser.is_initialized()) {
		ser.read_file_into_buffer(TEXT, file_path);
	}

	$if implements_serializable_to_text(util::@get_pointee_type_val(val)):
		val.deserialize_from_text(&ser.parser, alloc, file_path);
	$else
		ser.parser.parse_recur_into(val);
	$endif
}

// Utils

<*
	Should be called explicitly before calling 'deserialize_from_text'
	or call 'read_file_and_deserialize_from_text' as another option
*>
fn usz Serializer.read_file_into_buffer(&ser, SerializationMode mode, String file_path)
{
	File file = file::open_read(file_path, mode);
	defer (void)file.close();
	usz file_len = file.get_len();
	ser.buff.reserve(file_len);
	ser.buff.resize(file_len);

	file.read_all_buff(ser.buff.array_view());
	FileHeader header;
	read_file_header_from_buff(ser.buff.array_view(), &header)!!;
	assert(header.contents_len > 0, "Should have some contents");
	assert(header.contents_len <= file_len, "Should be less or equal to the file size");
	assert((SerializationMode)header.mode == mode, "Serialization mode is not correct");

	if (mode == TEXT) {
		ser.parser.init(ser.buff.view_range_len(FileHeader.sizeof, header.contents_len));
	}
	
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
	char[] header_as_bytes = util::to_byte_slice(&header);
	ser.buff.push_all(header_as_bytes);
}

<*
	Returns aligned chunk size
*>
fn usz Serializer.write_chunk_header(&ser, usz chunk_size) @private
{
	ChunkHeader header;
	header.chunk_id = CHUNK_ID;
	uint chunk_with_header_common_aligned_size = (uint)mem::aligned_offset(chunk_size + ChunkHeader.sizeof, ALIGNMENT);
	header.aligned_size = chunk_with_header_common_aligned_size - ChunkHeader.sizeof;
	header.padding = header.aligned_size - (uint)chunk_size;
	char[] header_as_bytes = util::to_byte_slice(&header);

	ser.buff.push_all(header_as_bytes);

	return header.padding;
}

fn void Serializer.update_file_contents_len_with_curr_offset(&ser) @private
{
	FileHeader* file_header = (FileHeader*)&ser.buff[0];
	file_header.contents_len = (uint)ser.buff.size - FileHeader.sizeof;
}

fn void Serializer.save_serialized_data_to_file(&ser, String file_path, FileOpenMode mode)
{
	assert(ser.buff.size > 0, "Should have some data in buffer");

	File file = file::open_write(file_path, mode);
	defer (void)file.close();
	file.write_all(ser.buff.array_view());
	ser.buff.clear();
}

fn usz Serializer.calc_required_capacity_bin(&ser, usz data_len) @private
{
	bool first_chunk = ser.buff.size == 0;
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

fn void Serializer.reset_state(&ser)
{
	ser.buff.clear();
	ser.parser.reset();
	ser.chunk_it.reset();
}

fn void Serializer.destroy(&ser)
{
	ser.buff.free();
}

fn void? formatter_output_fn(void* data, char c) @local
{
	Serializer* ser = data;
	ser.buff.push(c);
}
