## Binary data serializer implemented in C3 programming language

## Download
- ssh
	`git clone git@github.com:nyr24/serializer_c3.git`
- http
	`git clone https://github.com/nyr24/serializer_c3.git`

## Examples
```cpp

// Simple stack array
struct St
{
	StackString name;
	int         age;
	float       money;
}

fn void example_simple(Serializer* serializer, bool should_write)
{
	String f_name = ser::acquire_file_fmt_name("test.simple", BIN);

	if (should_write) {
		St[3] s_ces;
		s_ces[0].init("hello", 13, 228.5f);
		s_ces[1].init("world", 95, 1773.5f);
		s_ces[2].init("third", 7785, 56.0631);

		serializer.push_serialized_data_and_save_to_file(util::to_byte_slice{St}(s_ces[..]), tmem, BIN, f_name);
	}

	char[] deser_slice = serializer.deserialize_raw_data_from_bin(f_name);
	St[] st_slice = util::from_byte_slice{St}(deser_slice);

	foreach (s : st_slice) {
		s.print();
	}
}

// Heap-allocated object (std::core::dstring)
fn void example_dstring(Serializer* serializer, bool should_write)
{
	DString dstring;
	dstring.tinit(100);
	defer dstring.free();

	dstring.append_string("hello_world");

	String f_name = ser::acquire_file_fmt_name("test.dstring", BIN);
	if (should_write) {
		serializer.serialize((Serializable)&dstring, tmem, BIN);
		serializer.save_serialized_data_to_file(f_name, BIN);
	}

	serializer.deserialize((Serializable)&dstring, tmem, BIN, f_name);
	io::printn(dstring);
}


// Complex Entity object:

struct Entity (Serializable)
{
	StackString name;
	int         age;
	double      money;
	List{int}   textures;
	DString     job_name;
}

// Serializable interface implementation for Entity struct
// chunked serialization - 1. stack part; 2. dynamic list; 3. dynamic string;

fn void Entity.serialize_to_bin(&entity, Serializer* ser, Allocator alloc, SerializationMode mode) @dynamic
{
	EntityStackPart stack_p;
	stack_p.name = entity.name;
	stack_p.age = entity.age;
	stack_p.money = entity.money;
	char[] stack_p_slice = util::ptr_to_byte_slice{EntityStackPart}(&stack_p);
	
	ser.push_serialized_data(stack_p_slice, alloc, mode);
	ser.serialize((Serializable)&entity.textures, alloc, mode);
	ser.serialize((Serializable)&entity.job_name, alloc, mode);
}

fn void Entity.deserialize_from_chunks_bin(&entity, ChunkIterator chunk_it, Allocator alloc) @dynamic
{
	char[] first_chunk = chunk_it.next();
	char[] textures_data = chunk_it.next();
	char[] job_name_data = chunk_it.next();
	mem::copy((char*)entity, first_chunk.ptr, first_chunk.len);
	entity.textures.deserialize_from_data_bin(textures_data, alloc);
	entity.job_name.deserialize_from_data_bin(job_name_data, alloc);
}

// Usage
fn void example_entity(Serializer* serializer, bool should_write)
{
	String f_name = ser::acquire_file_fmt_name("test.entity", BIN);
	Entity en;

	if (should_write) {
		int[*] textures = {1,2,3,4,5};
		en.init("Vasya", 13, 666.77, textures[..], "Gamburger Builder", tmem);

		serializer.serialize_and_save_to_file((Serializable)&en, tmem, BIN, f_name);
	}

	serializer.deserialize((Serializable)&en, tmem, BIN, f_name);
	en.print();
}

````
