module ser;

import std::io;
import std::math::random;

struct St
{
	String name;
	int    age;
	float  money;
}

struct StBig
{
	// St 		s;
	double	money1;
	double	money2;
	bool	is_married;
	float 	money3;
	char  	fav_letter;
	String	name;
}

fn void St.init(&new, String name, int age, float money)
{
	new.name = name;
	new.age = age;
	new.money = money;
}

fn void St.print(&s)
{
	io::printfn("St: %s %d %f", s.name, s.age, s.money);
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
	St[5] s_ces;
	s_ces[0].init("hello", 13, 228.5f);
	s_ces[1].init("world", 95, 1773.5f);
	s_ces[2].init("third", 7785, 56.0631);
	s_ces[3].init("fourth", 4444, 44.228);
	s_ces[4].init("five", 555, 55.333965);

	StBig s_big;
	s_big.init("biggest", 'z', true);

	Serializer serializer;
	serializer.init(mem, "test.txt")!!;
	defer serializer.destroy();

	serializer.ser(s_ces);
	serializer.ser(s_big);

	St[] st_slice = serializer.deser(St);

	foreach (s : st_slice) {
		s.print();
	}

	return 0;
}
