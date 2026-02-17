## Data serializer (binary & text) implemented in C3 programming language

## Notes
- Supported std::collections for know (List, DString, HashMap)
- Serialization of data without pointers should work out of the box 
- To serialize data with pointers (heap-allocated data, interfaces, etc.) you should implement interface yourself (watch implementations for std::collections in std_containers_impl.c3)

## Download
- ssh
	`git clone --recurse-submodules git@github.com:nyr24/serializer_c3.git`
- http
	`git clone --recurse-submodules https://github.com/nyr24/serializer_c3.git`

## Build
-	static-lib
	`c3c build`
-	executable (for tests/examples)
	- `c3c build ser_test && c3c run ser_test -- 1` // write output to files + read from them
	- `c3c run ser_test` // only read from the files (Note: you should execute previous command first for this to work properly)

## Examples
```cpp

alias StackString = ElasticArray{char, 32};

// Mark type to treat it as string, not array of bytes and format differently
struct St @tag(CustomFmtTag.STRUCT_STRING, 1)
{
	StackString name;
	int         age;
	float       money;
	bool		is_married;
	Inner		inner;
}

enum InnerType
{
	MONSTER,
	TROLL,
	GOBLIN
}

struct Inner @tag(CustomFmtTag.STRUCT_STRING, 1)
{
	StackString name;
	InnerType 	type;
}

// Binary serialization

fn void example_bin_simple(Serializer* serializer, bool should_write)
{
	String f_name = ser::acquire_file_fmt_name("example.simple", BIN);

	if (should_write) {
		St[3] s_ces;
		s_ces[0].init("sim_1", 8, 16.0f, true, "iner1", GOBLIN);
		s_ces[1].init("sim_2", 16, 32.0f, false, "iner2", TROLL);
		s_ces[2].init("sim_3", 32, 64.0f, false, "iner3", MONSTER);

		serializer.serialize_to_bin_and_save_to_file(util::to_byte_slice(s_ces[..]), mem, f_name);
	}

	char[] deser_slice = serializer.acquire_bin_data_from_file(mem, f_name);
	defer allocator::free(mem, deser_slice.ptr);

	St[] st_slice = util::from_byte_slice(deser_slice, St[]);

	foreach (s : st_slice) {
		s.print();
	}
}

// Text serialization

fn void example_text_simple(Serializer* serializer, bool should_write)
{
	serializer.reset_state();
	String f_name = ser::acquire_file_fmt_name("example.simple", TEXT);

	St[3] s_ces;
	if (should_write) {
		s_ces[0].init("hello", 8, 16.0f, true, "iner1", MONSTER);
		s_ces[1].init("world", 16, 32.0f, false, "iner2", TROLL);
		s_ces[2].init("third", 32, 64.0f, false, "iner3", GOBLIN);

		serializer.serialize_to_text_and_save_to_file(s_ces[..], tmem, f_name, false, $sizeof(St) * s_ces.len);
	}

	serializer.deserialize_from_text(s_ces[..], tmem, f_name);

	foreach (s : s_ces[..]) {
		s.print();
	}
}

// More Complex example (object with heap-allocated data - requires implementation of the interface)

struct Entity @tag(CustomFmtTag.STRUCT_STRING, 1)
{
	StackString name;
	int         age;
	double      money;
	List{int}   textures; // NOTE: this implements interface too
	DString     job_name; // NOTE: this implements interface too
	HashMap{int, float} map; // NOTE: this implements interface too
}

struct EntityStackPart
{
	StackString name;
	int         age;
	double      money;
}

// Binary mode implementation

fn void Entity.serialize_to_bin(&entity, Serializer* ser, Allocator alloc)
{
	EntityStackPart stack_p;
	stack_p.name = entity.name;
	stack_p.age = entity.age;
	stack_p.money = entity.money;
	char[] stack_p_slice = util::to_byte_slice(&stack_p);
	
	ser.append_bin_data_to_buff(stack_p_slice, alloc, false);
	ser.serialize_to_bin(&entity.textures, alloc);
	ser.serialize_to_bin(&entity.job_name, alloc);
	ser.serialize_to_bin(&entity.map, alloc);
}

fn void Entity.deserialize_from_bin(&entity, ChunkIterator* chunk_it, Allocator alloc)
{
	char[] first_chunk = chunk_it.next();
	mem::copy((char*)entity, first_chunk.ptr, first_chunk.len);
	entity.textures.deserialize_from_bin(chunk_it, alloc);
	entity.job_name.deserialize_from_bin(chunk_it, alloc);
	entity.map.deserialize_from_bin(chunk_it, alloc);
}

// Text mode implementation

fn void Entity.serialize_to_text(&entity, Serializer* ser, Allocator alloc)
{
	EntityStackPart stack_p;
	stack_p.name = entity.name;
	stack_p.age = entity.age;
	stack_p.money = entity.money;
	
	ser.append_text_data_to_buff(&stack_p, alloc, false);
	ser.serialize_to_text(&entity.textures, alloc, false, entity.textures.byte_size()); // last argument is an optional hint how much memory will take text representation of this object
	ser.serialize_to_text(&entity.job_name, alloc, false, entity.job_name.capacity() * char.sizeof);
	ser.serialize_to_text(&entity.map, alloc, false, entity.map.threshold * $sizeof(*entity.map.table[0]));
}

fn void Entity.deserialize_from_text(&entity, Parser* parser, Allocator alloc, String file_path)
{
	EntityStackPart stack_p;
	parser.parse_struct(&stack_p);
	entity.name = stack_p.name;
	entity.age = stack_p.age;
	entity.money = stack_p.money;
	
	parser.skip_until_next_value_start();
	entity.textures.deserialize_from_text(parser, alloc, file_path);
	parser.skip_until_next_value_start();
	entity.job_name.deserialize_from_text(parser, alloc, file_path);
	parser.skip_until_next_value_start();
	entity.map.deserialize_from_text(parser, alloc, file_path);
}

/* File format for Text serialization example:
{ (struct)
	; field_1 (int)
	123,
	; field_2 (string)
	"hello",
	; field_3 (float)
	228.0,
	; field_4 (array)
	[
		{
			123,
			"hello",
			228.0,
		}
	]
	; field_5 (vector)
	[<1, 2, 3>]
	; field_6 (matrix)
	[#
		1, 1
		2, 3
	#]
}
*/

````
