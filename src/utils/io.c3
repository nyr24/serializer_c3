module std::io::file;

enum FileOpenMode
{
	BIN,
	TEXT
}

fn File open_read(String path, FileOpenMode mode)
{
	String opts = mode == BIN ? "r+b" : "r+t";
	return open(path, opts)!!;
}

fn File open_write(String path, FileOpenMode mode)
{
	String opts = mode == BIN ? "w+b" : "w+t";
	return open(path, opts)!!;
}

fn void File.write_all(&file, char[] buff)
{
	usz written = 0;
	while (written < buff.len)
	{
		written += file.write(buff[written..buff.len - 1])!!;
	}
}

<*
	Caller responsible for freeing return buffer with 'alloc' param
*>
fn char[] File.read_all(&file, Allocator alloc, usz* out_read_bytes = null)
{
	usz file_len = file.seek(0, END)!!;
	file.seek(0, SET)!!;
	usz read = 0;

	char[] buff = allocator::alloc_array(alloc, char, file_len);
	defer catch allocator::free(alloc, buff.ptr);

	while (read < buff.len) {
		read += file.read(buff[read..buff.len-1])!!;
	}

	if (out_read_bytes) {
		*out_read_bytes = read;
	}
	return buff;
}

fn usz File.read_all_buff(&file, char[] buff)
{
	usz read = 0;
	while (read < buff.len) {
		usz curr_read = file.read(buff[read..buff.len-1])!!;
		if (!curr_read) {
			return read;
		}
		read += curr_read;
	}
	return read;
}

fn usz File.get_len(&file)
{
	usz len = file.seek(0, END)!!;
	file.seek(0, SET)!!;
	return len;
}
