module ser;

import util;
import std::io;
import std::math::random;
import std::collections::elastic_array;
import std::collections::list;

struct StBig
{
	double	money1;
	double	money2;
	bool	is_married;
	float 	money3;
	char  	fav_letter;
	String	name;
}

alias StackString = ElasticArray{char, 32};

struct St
{
	StackString name;
	int         age;
	float       money;
}

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

fn void StBig.init(&new, String name, char fav_letter, bool is_married)
{
	new.name = name;
	new.fav_letter = fav_letter;
	new.is_married = is_married;
	new.money1 = (double)random::rand(256);
	new.money2 = (double)random::rand(256);
	new.money3 = (float)random::rand(256);
}

fn void StBig.print(&s)
{
	io::printfn("StBig: %s %c %b", s.name, s.fav_letter, s.is_married);
}

fn int main(String[] args)
{
	Serializer serializer;
	serializer.init(mem);
	defer serializer.destroy();

	const EXAMPLE_1 = false;
	const EXAMPLE_LIST = false;
	const EXAMPLE_DSTRING = true;

	bool should_write = args.len > 1;

	if (EXAMPLE_1) {
		example_1(&serializer, should_write);
	}

	if (EXAMPLE_LIST) {
		example_list(&serializer, should_write);
	}

	if (EXAMPLE_DSTRING) {
		example_dstring(&serializer, should_write);
	}

	return 0;
}

fn void example_1(Serializer* serializer, bool should_write)
{
	if (should_write) {
		St[3] s_ces1;
		s_ces1[0].init("hello", 13, 228.5f);
		s_ces1[1].init("world", 95, 1773.5f);
		s_ces1[2].init("third", 7785, 56.0631);

		serializer.serialize_to_bin_generic(util::to_byte_slice{St}(s_ces1[..]), "test.txt");
	}

	char[] deser_slice = serializer.deserialize_from_bin_generic("test.txt");
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

	String file_name = "test.list.txt";
	if (should_write) {
		serializer.serialize((Serializable)&l_ints, file_name, BIN, tmem);
	}

	serializer.deserialize((Serializable)&l_ints, file_name, BIN, tmem);

	io::printn(l_ints);
}

fn void example_dstring(Serializer* serializer, bool should_write)
{
	DString dstring;
	dstring.tinit(100);
	defer dstring.free();

	dstring.append_string("hello_world");

	String file_name = "test.dstring.txt";
	if (should_write) {
		serializer.serialize((Serializable)&dstring, file_name, BIN, tmem);
	}

	serializer.deserialize((Serializable)&dstring, file_name, BIN, tmem);
	io::printn(dstring);
}
