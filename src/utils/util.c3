module util;

import std::time;
import std::io;

macro void @swap_ptrs(#x, #y) {
	var temp = *#x;
	*#x = *#y;
	*#y = temp;
}

macro @perf(String name = "Current Test"; @body) {
	time::Time start = time::now();
	defer {
		time::Duration dur = time::now() - start;
		io::printfn("Duration of %s: %d", name, dur);
	}
	@body();
}

fn bool nullterm_str_eq(CChar* s1, CChar* s2) {
	assert(s1 != null && s2 != null);

	CChar* s1_p = s1;
	CChar* s2_p = s2;

	while ((*s1_p != '\0') && (*s2_p != '\0') && (*s1_p == *s2_p))
	{
		++s1_p;
		++s2_p;
	}

	return (*s1_p == '\0') && (*s2_p == '\0');
}

fn String nullterm_str_to_slice(CChar* s) {
	assert(s != null);

	usz i = 0;

	while (s[i] != '\0') {
		++i;
	}

	return (String)s[0:(i-1)];
}

fn char[] to_byte_slice(Type[] val) <Type>
{
	return ((char*)val.ptr)[:val.len * Type.sizeof];
}

fn Type[] from_byte_slice(char[] val) <Type>
{
	return ((Type*)val.ptr)[:val.len / Type.sizeof];
}

fn Type[] ptr_to_slice(Type* val) <Type>
{
	return val[:1];
}

fn char[] ptr_to_byte_slice(Type* val) <Type>
{
	return to_byte_slice{Type}(val[:1]);
}
