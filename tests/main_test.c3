module ser;

import util;
import std::io;
import std::math;
import std::collections::elastic_array;
import std::collections::list;
import std::collections::map;

fn void main_test() @test
{
	Serializer serializer;
	serializer.init(mem);
	defer serializer.destroy();

	const EXAMPLE_BIN_SIMPLE = true;
	const EXAMPLE_BIN_MATH = true;
	const EXAMPLE_BIN_LIST = true;
	const EXAMPLE_BIN_DSTRING = true;
	const EXAMPLE_BIN_ENTITY = true;
	const EXAMPLE_TEXT_SIMPLE = true;
	const EXAMPLE_TEXT_MATH = true;
	const EXAMPLE_TEXT_LIST = true;
	const EXAMPLE_TEXT_DSTRING = true;
	const EXAMPLE_TEXT_HASHMAP = true;
	const EXAMPLE_TEXT_ENTITY = true;
	const EXAMPLE_TEXT_DIFF_FORMATS = true;
	const EXAMPLE_MULTIPLE = true;

	const SHOULD_WRITE = true;

	if (EXAMPLE_BIN_SIMPLE) {
		example_bin_simple(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_BIN_MATH) {
		example_bin_math(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_BIN_LIST) {
		example_bin_list(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_BIN_DSTRING) {
		example_bin_dstring(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_BIN_ENTITY) {
		example_bin_entity(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_TEXT_SIMPLE) {
		example_text_simple(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_TEXT_MATH) {
		example_text_math(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_TEXT_LIST) {
		example_text_list(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_TEXT_DSTRING) {
		example_text_dstring(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_TEXT_HASHMAP) {
		example_text_hashmap(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_TEXT_ENTITY) {
		example_text_entity(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_TEXT_DIFF_FORMATS) {
		example_text_diff_formats(&serializer, SHOULD_WRITE);
	}

	if (EXAMPLE_MULTIPLE) {
		example_multiple_writes_and_reads(&serializer, SHOULD_WRITE);
	}
}

// EXAMPLES

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

fn void example_bin_math(Serializer* serializer, bool should_write)
{
	serializer.reset_state();
	String f_name = ser::acquire_file_fmt_name("example.math", BIN);
	int[3] init_params = { 1, 2, 3 };

// Slice
	MathStruct[3] vals;
	if (should_write) {
		foreach (uint i, &v : vals) {
			v.init(init_params[i]);
		}

		serializer.serialize_to_bin_and_save_to_file(vals[..], tmem, f_name);
	}

	serializer.deserialize_from_bin(vals[..], tmem, f_name);

	foreach (v : vals[..]) {
		v.print();
	}
}

fn void example_bin_list(Serializer* serializer, bool should_write)
{
	serializer.reset_state();
	List{int} l_ints;
	l_ints.tinit(100);
	defer l_ints.free();

	for (uint i = 0; i < 50; ++i) {
		l_ints.push(i);
	}

	String f_name = ser::acquire_file_fmt_name("example.list", BIN);
	if (should_write) {
		serializer.serialize_to_bin_and_save_to_file(&l_ints, tmem, f_name);
	}

	serializer.deserialize_from_bin(&l_ints, tmem, f_name);

	io::printn(l_ints);
}

fn void example_bin_dstring(Serializer* serializer, bool should_write)
{
	serializer.reset_state();
	DString dstring;
	dstring.tinit(100);
	defer dstring.free();

	dstring.append_string("hello_world");

	String f_name = ser::acquire_file_fmt_name("example.dstring", BIN);
	if (should_write) {
		serializer.serialize_to_bin(&dstring, tmem);
		serializer.save_serialized_data_to_file(f_name, BIN);
	}

	serializer.deserialize_from_bin(&dstring, tmem, f_name);
	io::printn(dstring);
}

fn void example_bin_entity(Serializer* serializer, bool should_write)
{
	serializer.reset_state();
	String f_name = ser::acquire_file_fmt_name("example.entity", BIN);
	Entity en;

	if (should_write) {
		int[*] textures = {1,2,3,4,5};
		en.init(
			"Vasya",
			13,
			666.77,
			textures[..],
			"Gamburger Builder",
			tmem
		);

		serializer.serialize_to_bin_and_save_to_file(&en, tmem, f_name);
	}

	serializer.deserialize_from_bin(&en, tmem, f_name);
	en.print();
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

fn void example_text_math(Serializer* serializer, bool should_write)
{
	serializer.reset_state();
	String f_name = ser::acquire_file_fmt_name("example.math", TEXT);
	int[3] init_params = { 1, 2, 3 };

// Slice
	MathStruct[3] vals;
	if (should_write) {
		foreach (uint i, &v : vals) {
			v.init(init_params[i]);
		}

		serializer.serialize_to_text_and_save_to_file(vals[..], tmem, f_name, false, $sizeof(St) * vals.len);
	}

	serializer.deserialize_from_text(vals[..], tmem, f_name);

	foreach (v : vals[..]) {
		v.print();
	}
}

fn void example_text_list(Serializer* serializer, bool should_write)
{
	serializer.reset_state();
	String f_name = ser::acquire_file_fmt_name("example.list", TEXT);
	List{St} list;
	list.tinit(3);
	defer list.free();

	if (should_write) {
		St[3] s_ces;
		s_ces[0].init("hello", 13, 228.5f, true, "iner1", MONSTER);
		s_ces[1].init("world", 95, 1773.5f, false, "iner2", GOBLIN);
		s_ces[2].init("third", 7785, 56.0631, true, "iner3", TROLL);
		list.push_all(s_ces[..]);
		serializer.serialize_to_text_and_save_to_file(&list, tmem, f_name, false, $sizeof(St) * 4);
	}

	serializer.deserialize_from_text(&list, tmem, f_name);
	io::printn(list);
}

fn void example_text_dstring(Serializer* serializer, bool should_write)
{
	serializer.reset_state();
	DString dstring;
	dstring.tinit(100);
	defer dstring.free();

	dstring.append_string("hello_world");

	String f_name = ser::acquire_file_fmt_name("example.dstring", TEXT);
	if (should_write) {
		serializer.serialize_to_text(&dstring, tmem, false, $sizeof(dstring.data()) + dstring.len());
		serializer.save_serialized_data_to_file(f_name, TEXT);
	}

	serializer.deserialize_from_text(&dstring, tmem, f_name);
	io::printn(dstring);
}

fn void example_text_hashmap(Serializer* serializer, bool should_write)
{
	serializer.reset_state();
	String f_name = ser::acquire_file_fmt_name("example.map", TEXT);
	HashMap{int, int} map;
	map.tinit(12);
	defer map.free();

	if (should_write) {
		int[3] keys = { 12, 23, 34 };
		int[3] values = { 99, 177, 288 };

		for (uint i = 0; i < keys.len; ++i) {
			map.set(keys[i], values[i]);
		}
		serializer.serialize_to_text_and_save_to_file(&map, tmem, f_name, false, $sizeof(*map.table[0]) * keys.len);
	}

	serializer.deserialize_from_text(&map, tmem, f_name);
	io::printn(map);
}

// it would be easier / performant to write this slices of data in 1 pass
// as it is done in previous examples
// but this is just a test of api robustness
fn void example_multiple_writes_and_reads(Serializer* serializer, bool should_write)
{
	serializer.reset_state();

	String f_name_bin = ser::acquire_file_fmt_name("example.multiple", BIN);
	String f_name_txt = ser::acquire_file_fmt_name("example.multiple", TEXT);

	if (should_write) {
		St[3] s_ces;
		s_ces[0].init("sim_1", 8, 16.0f, true, "iner1", GOBLIN);
		serializer.serialize_to_bin(&s_ces[0], mem);

		s_ces[1].init("sim_2", 16, 32.0f, false, "iner2", TROLL);
		serializer.serialize_to_bin(&s_ces[1], mem);

		s_ces[2].init("sim_3", 32, 64.0f, false, "iner3", MONSTER);
		serializer.serialize_to_bin(&s_ces[2], mem);

		serializer.save_serialized_data_to_file(f_name_bin, BIN);

		serializer.reset_state();

		St[3] s_ces_txt;
		s_ces_txt[0].init("sim_1", 8, 16.0f, true, "iner1", GOBLIN);
		serializer.serialize_to_text(&s_ces_txt[0], mem);

		s_ces_txt[1].init("sim_2", 16, 32.0f, false, "iner2", TROLL);
		serializer.serialize_to_text(&s_ces_txt[1], mem);

		s_ces_txt[2].init("sim_3", 32, 64.0f, false, "iner3", MONSTER);
		serializer.serialize_to_text(&s_ces_txt[2], mem);

		serializer.save_serialized_data_to_file(f_name_txt, TEXT);
	}

	ChunkIterator* chunk_it = serializer.acquire_bin_data_from_file_as_chunks(mem, f_name_bin);
	St[3] st_bin_slice;
	foreach (&st : st_bin_slice) {
		char[] bytes = chunk_it.next();
		mem::copy(st, bytes.ptr, bytes.len);
	}

	foreach (s : st_bin_slice) {
		s.print();
	}

	St[3] st_slice_text;

	foreach (&s : st_slice_text) {
		serializer.deserialize_from_text(s, mem, f_name_txt);
	}

	foreach (s : st_slice_text) {
		s.print();
	}
}

fn void example_text_entity(Serializer* serializer, bool should_write)
{
	serializer.reset_state();
	String f_name = ser::acquire_file_fmt_name("example.entity", TEXT);
	Entity en;

	if (should_write) {
		int[*] textures = {5,4,3,2,1};
		en.init(
			"John_Doe",
			28,
			777.66,
			textures[..],
			"Gamburger Inspector",
			tmem
		);

		serializer.serialize_to_text_and_save_to_file(
			&en,
			tmem,
			f_name,
			false,
			Entity.sizeof
			+ en.textures.byte_size()
			+ en.job_name.len()
			+ $sizeof(*en.map.table[0]) * en.map.threshold
		);
	}

	serializer.deserialize_from_text(&en, tmem, f_name);
	en.print();
}

fn void example_text_diff_formats(Serializer* serializer, bool should_write)
{
	serializer.reset_state();
	String f_name = ser::acquire_file_fmt_name("example.diff_formats", TEXT);

	DiffFormat diff_fmt;
		
	if (should_write) {
		diff_fmt.init("hello", &&{1,2,3,4,5}, &&{1,2,3,4,5}, &&{1,2,3,4,5,6,7,8,9});
		serializer.serialize_to_text_and_save_to_file(&diff_fmt, tmem, f_name, false, $sizeof(diff_fmt));
	}

	serializer.deserialize_from_text(&diff_fmt, tmem, f_name);
	diff_fmt.print();
}

// Implementation on complex structure (some part - stack, some part - heap)

fn void Entity.init(
	&entity,
	String name,
	int age,
	double money,
	int[] textures,
	String job_name,
	Allocator alloc = mem
)
{
	entity.name.push_all(name);
	entity.age = age;
	entity.money = money;
	entity.textures.init(alloc, textures.len);
	entity.textures.push_all(textures);
	entity.job_name.init(alloc, job_name.len);
	entity.job_name.append_string(job_name);
	entity.map.init_from_keys_and_values(alloc, { 1, 2, 3, 4 }, { 0.1f, 0.2f, 0.3f, 0.4f }, 20);
}

fn void Entity.print(&en)
{
	io::printfn("Entity name: %s, age: %d, money: %f, job_name: %s, textures_len: %d, map item count: %d, map third item: %f",
		(String)en.name.array_view(),
		en.age,
		en.money,
		en.job_name.str_view(),
		en.textures.size,
		en.map.count,
		en.map.get(3)!!
	);
}

// Serializable interface implementation for Entity struct
// chunked serialization - 1. stack part; 2. list (heap); 3. dstring (heap); 4. hashmap (heap);

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

fn void Entity.serialize_to_text(&entity, Serializer* ser, Allocator alloc)
{
	EntityStackPart stack_p;
	stack_p.name = entity.name;
	stack_p.age = entity.age;
	stack_p.money = entity.money;
	
	ser.append_text_data_to_buff(&stack_p, alloc, false);
	ser.serialize_to_text(&entity.textures, alloc, false, entity.textures.byte_size());
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

// Type definitions

alias StackString = ElasticArray{char, 32};

struct St (Printable)
{
	// Mark member to treat it as string, not array of bytes and format differently
	StackString name @tag(SCHEMA_FMT_TAG, SchemaFormatKind.STRING);
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

struct Inner (Printable)
{
	StackString name @tag(SCHEMA_FMT_TAG, SchemaFormatKind.STRING);
	InnerType 	type;
}

fn void St.init(&new, char[5]* name, int age, float money, bool is_married = true, char[] inner_name = "inner1", InnerType inner_type = TROLL)
{
	mem::copy(&new.name.entries, name, name.len);
	new.name.size = name.len;
	new.age = age;
	new.money = money;
	new.is_married = is_married;
	new.inner.init(inner_name, inner_type);
}

fn usz? St.to_format(&s, Formatter* f) @dynamic
{
	usz sz = f.printf("\n\tSt: %s %d %f %s ", (String)s.name.array_view(), s.age, s.money, s.is_married)!;
	s.inner.print();
	return sz;
}

fn void St.print(&s)
{
	io::printfn("St: %s %d %f %s", (String)s.name.array_view(), s.age, s.money, s.is_married);
	s.inner.print();
}

fn void Inner.init(&inner, char[] name, InnerType type)
{
	mem::copy(&inner.name.entries, name.ptr, name.len);
	inner.name.size = name.len;
	inner.type = type;
}

fn void Inner.print(&inner)
{
	io::printf("\tInner: %s %s\n", (String)inner.name.array_view(), inner.type);
}

struct Entity
{
	StackString name @tag(SCHEMA_FMT_TAG, SchemaFormatKind.STRING);
	int         age;
	double      money;
	List{int}   textures;
	DString     job_name;
	HashMap{int, float} map;
}

struct EntityStackPart
{
	StackString name;
	int         age;
	double      money;
}

struct MathStruct
{
	Matrix4x4{float} mat4;
	float[<4>] vec4;
}

fn void MathStruct.init(&self, int i)
{
	self.mat4 = math::MATRIX4F_IDENTITY;
	self.mat4.m11 = i;
	self.vec4 = { 2, 2, 2, 8 };
}

fn void MathStruct.print(&self)
{
	io::printfn("MatStruct:");
	io::printfn("%s", self.mat4.m);
	io::printfn("%s\n", self.vec4);
}

struct DiffFormat
{
	char[5] 	str  @tag(SCHEMA_FMT_TAG, SchemaFormatKind.STRING);
	char[5]		def  @tag(SCHEMA_FMT_TAG, SchemaFormatKind.DEFAULT);
	char[5]     vec  @tag(SCHEMA_FMT_TAG, SchemaFormatKind.VECTOR);
	char[9]     mat  @tag(SCHEMA_FMT_TAG, SchemaFormatKind.MATRIX);
}

fn void DiffFormat.init(&diff_fmt, char[5]* str, char[5]* nums, char[5]* vec, char[9]* mat)
{
	mem::copy(&diff_fmt.str, str, str.len);
	mem::copy(&diff_fmt.def, nums, nums.len);
	mem::copy(&diff_fmt.vec, vec, vec.len);
	mem::copy(&diff_fmt.mat, mat, mat.len);
}

fn void DiffFormat.print(&diff_fmt)
{
	io::printfn("DiffFormat: %s, %s, %s, %s", diff_fmt.str, diff_fmt.def, diff_fmt.vec, diff_fmt.mat);
}
