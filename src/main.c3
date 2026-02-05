module ser;

import util;
import std::io;
import std::math::random;
import std::collections::elastic_array;
import std::collections::list;

alias StackString = ElasticArray{char, 32};

struct St
{
	StackString name;
	int         age;
	float       money;
}

struct Entity (Serializable)
{
	StackString name;
	int         age;
	double      money;
	List{int}   textures;
	DString     job_name;
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

	return 0;
}

// Examples

fn void example_simple(Serializer* serializer, bool should_write)
{
	String f_name = ser::acquire_file_fmt_name("test.simple", BIN);

	if (should_write) {
		St[3] s_ces1;
		s_ces1[0].init("hello", 13, 228.5f);
		s_ces1[1].init("world", 95, 1773.5f);
		s_ces1[2].init("third", 7785, 56.0631);

		serializer.push_serialized_data_and_save_to_file(util::to_byte_slice{St}(s_ces1[..]), tmem, BIN, f_name);
	}

	char[] deser_slice = serializer.deserialize_raw_data_from_bin(f_name);
	St[] st_slice = util::from_byte_slice{St}(deser_slice);

	foreach (s : st_slice) {
		s.print();
	}
}

fn void example_list(Serializer* serializer, bool should_write)
{
	List{int} l_ints;
	l_ints.tinit(100);
	defer l_ints.free();

	for (uint i = 0; i < 50; ++i) {
		l_ints.push(i);
	}

	String f_name = ser::acquire_file_fmt_name("test.list", BIN);
	if (should_write) {
		serializer.serialize_and_save_to_file((Serializable)&l_ints, tmem, BIN, f_name);
	}

	serializer.deserialize((Serializable)&l_ints, tmem, BIN, f_name);

	io::printn(l_ints);
}

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

// Implementation

fn void St.init(&new, String name, int age, float money)
{
	mem::copy(new.name.data(), name.ptr, name.len);
	new.name.size = name.len;
	new.age = age;
	new.money = money;
}

fn void St.print(&s)
{
	io::printfn("St: %s %d %f", (String)s.name.array_view(), s.age, s.money);
}

fn void Entity.init(&entity, String name, int age, double money, int[] textures, String job_name, Allocator alloc = mem)
{
	entity.name.push_all(name);
	entity.age = age;
	entity.money = money;
	entity.textures.init(alloc, textures.len);
	entity.textures.push_all(textures);
	entity.job_name.init(alloc, job_name.len);
	entity.job_name.append_string(job_name);
}

fn void Entity.print(&en)
{
	io::printfn("Entity name: %s, age: %d, money: %f, job_name: %s, textures_len: %d",
		(String)en.name.array_view(), en.age, en.money, en.job_name.str_view(), en.textures.size);
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
