module ser;

import util;
import std::io;
import std::math::random;
import std::collections::elastic_array;

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
	int      age;
	float    money;
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
	serializer.init(mem, 2056);
	defer serializer.destroy();

	if (args.len > 1) {
		St[3] s_ces1;
		s_ces1[0].init("hello", 13, 228.5f);
		s_ces1[1].init("world", 95, 1773.5f);
		s_ces1[2].init("third", 7785, 56.0631);

		serializer.serialize_to_bin_generic(util::to_byte_slice{St}(s_ces1[..]), "test.txt");

		// StBig[3] s_bigs;
		// s_bigs[0].init("biggest", 'z', true);
		// s_bigs[1].init("biggest2", 'w', false);
		// s_bigs[2].init("biggest3", 'x', true);
		// serializer.serialize(s_bigs, "test_big.txt", BIN);

		// St[2] s_ces2;
		// s_ces2[0].init("fourth", 4444, 44.228);
		// s_ces2[1].init("five", 555, 55.333965);
		// serializer.serialize(s_ces2, "test2.txt", bin);
	}

	char[] deser_slice = serializer.deserialize_from_bin_generic("test.txt");
	St[] st_slice = util::from_byte_slice{St}(deser_slice);

	foreach (s : st_slice) {
		s.print();
	}

	// StBig[] st_big_slice = serializer.deser(StBig);
	// foreach (s : st_big_slice) {
	// 	s.print();
	// }

	return 0;
}
