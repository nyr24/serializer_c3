module ser;

import util;
import std::io;
import std::math::random;
import std::collections::elastic_array;
import std::collections::list;
import std::collections::map;
import std::hash::fnv64a;

alias StackString = ElasticArray{char, 32};

// Mark type to treat it as string, not array of bytes and format differently
typedef MyString @tag(CustomFmtTag.SLICE_STRING, 1) = char[5];
typedef MyCompositeString @tag(CustomFmtTag.STRUCT_STRING, 1) = ElasticArray{char, 5};

fn void MyCompositeString.init(&self, String str)
{
	mem::copy(&self.entries, str.ptr, str.len);
	self.size = str.len;
}

fn uint MyCompositeString.hash(&self)
{
	return (uint)fnv64a::hash(self.entries[:self.size]);
}

struct St (Printable)
{
	MyCompositeString name;
	int         age;
	float       money;
	bool		is_married;
	Inner		inner;
}

typedef StDistinct = St;

enum InnerType
{
	MONSTER,
	TROLL,
	GOBLIN
}

struct Inner (Printable)
{
	MyString 	name;
	InnerType 	type;
}

struct Entity @tag(CustomFmtTag.STRUCT_STRING, 1)
{
	StackString name;
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

fn int main(String[] args)
{
	Serializer serializer;
	serializer.init(mem);
	defer serializer.destroy();

	const EXAMPLE_SIMPLE = true;
	const EXAMPLE_LIST = true;
	const EXAMPLE_DSTRING = true;
	const EXAMPLE_ENTITY = true;
	const EXAMPLE_TEXT_SIMPLE = true;
	const EXAMPLE_TEXT_LIST = true;
	const EXAMPLE_TEXT_DSTRING = true;
	const EXAMPLE_TEXT_HASHMAP = true;
	const EXAMPLE_TEXT_ENTITY = true;

	bool should_write = args.len > 1;

	if (EXAMPLE_SIMPLE) {
		example_simple(&serializer, should_write);
	}

	if (EXAMPLE_LIST) {
		example_list(&serializer, should_write);
	}

	if (EXAMPLE_DSTRING) {
		example_dstring(&serializer, should_write);
	}

	if (EXAMPLE_ENTITY) {
		example_entity(&serializer, should_write);
	}

	if (EXAMPLE_TEXT_SIMPLE) {
		example_text_simple(&serializer, should_write);
	}

	if (EXAMPLE_TEXT_LIST) {
		example_text_list(&serializer, should_write);
	}

	if (EXAMPLE_TEXT_DSTRING) {
		example_text_dstring(&serializer, should_write);
	}

	if (EXAMPLE_TEXT_HASHMAP) {
		example_text_hashmap(&serializer, should_write);
	}

	if (EXAMPLE_TEXT_ENTITY) {
		example_text_entity(&serializer, should_write);
	}

	return 0;
}

// Examples

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
	usz sz = f.printf("\n\tSt: %s %d %f %s ", (String)s.name.entries[..], s.age, s.money, s.is_married)!;
	s.inner.print();
	return sz;
}

fn void St.print(&s)
{
	io::printfn("St: %s %d %f %s", (String)s.name.entries[..], s.age, s.money, s.is_married);
	s.inner.print();
}

fn void Inner.init(&inner, char[] name, InnerType type)
{
	mem::copy(&inner.name, name.ptr, inner.name.len);
	inner.type = type;
}

fn void Inner.print(&inner)
{
	io::printf("\tInner: %s %s\n", (String)inner.name[..], inner.type);
}

// EXAMPLES

// Binary serialization

fn void example_simple(Serializer* serializer, bool should_write)
{
	String f_name = ser::acquire_file_fmt_name("example.simple", BIN);

	if (should_write) {
		St[3] s_ces;
		s_ces[0].init("hello", 13, 228.5f);
		s_ces[1].init("world", 95, 1773.5f);
		s_ces[2].init("third", 7785, 56.0631);

		serializer.append_bin_data_to_buff_and_save_file(util::to_byte_slice{St}(s_ces[..]), mem, false, f_name);
	}

	char[] deser_slice = serializer.acquire_bin_data_from_file(f_name, mem);
	defer allocator::free(mem, deser_slice.ptr);

	St[] st_slice = util::from_byte_slice{St}(deser_slice);

	foreach (s : st_slice) {
		s.print();
	}
}

fn void example_list(Serializer* serializer, bool should_write)
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

fn void example_dstring(Serializer* serializer, bool should_write)
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

fn void example_entity(Serializer* serializer, bool should_write)
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

// Slice
	St[3] s_ces;
	if (should_write) {
		s_ces[0].init("hello", 8, 16.0f, true, "iner1", MONSTER);
		s_ces[1].init("world", 16, 32.0f, false, "iner2", TROLL);
		s_ces[2].init("third", 32, 64.0f, false, "iner3", GOBLIN);

		serializer.serialize_to_text_and_save_to_file(s_ces[..], tmem, false, f_name, $sizeof(St) * s_ces.len);
	}

	serializer.deserialize_from_text(s_ces[..], tmem, f_name);

	foreach (s : s_ces[..]) {
		s.print();
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
		serializer.serialize_to_text_and_save_to_file(&list, tmem, false, f_name, $sizeof(St) * 4);
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
		serializer.serialize_to_text_and_save_to_file(&map, tmem, false, f_name, $sizeof(*map.table[0]) * keys.len);
	}

	serializer.deserialize_from_text(&map, tmem, f_name);
	io::printn(map);
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
			false,
			f_name,
			Entity.sizeof
			+ en.textures.byte_size()
			+ en.job_name.len()
			+ $sizeof(*en.map.table[0]) * en.map.threshold
		);
	}

	serializer.deserialize_from_text(&en, tmem, f_name);
	en.print();
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

fn void Entity.serialize_to_bin(&entity, Serializer* ser, Allocator alloc) @dynamic
{
	EntityStackPart stack_p;
	stack_p.name = entity.name;
	stack_p.age = entity.age;
	stack_p.money = entity.money;
	char[] stack_p_slice = util::ptr_to_byte_slice{EntityStackPart}(&stack_p);
	
	ser.append_bin_data_to_buff(stack_p_slice, alloc, false);
	ser.serialize_to_bin(&entity.textures, alloc);
	ser.serialize_to_bin(&entity.job_name, alloc);
	ser.serialize_to_bin(&entity.map, alloc);
}

fn void Entity.deserialize_from_bin(&entity, ChunkIterator* chunk_it, Allocator alloc) @dynamic
{
	char[] first_chunk = chunk_it.next();
	mem::copy((char*)entity, first_chunk.ptr, first_chunk.len);
	entity.textures.deserialize_from_bin(chunk_it, alloc);
	entity.job_name.deserialize_from_bin(chunk_it, alloc);
	entity.map.deserialize_from_bin(chunk_it, alloc);
}

fn void Entity.serialize_to_text(&entity, Serializer* ser, Allocator alloc) @dynamic
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

fn void Entity.deserialize_from_text(&entity, Parser* parser, Allocator alloc, String file_path) @dynamic
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
