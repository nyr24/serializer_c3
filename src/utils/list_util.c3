module std::collections::list <Type>;

import util;

fn Type* List.data(&list)
{
	return list.entries;
}

fn void List.fill(&list, Type val)
{
	foreach (&entry : list.array_view()) {
		*entry = val;
	}
}

fn void List.remove_unordered(&list, usz ind)
{
	assert(ind < list.size);
	util::@swap_ptrs(&list[ind], &list[list.size - 1]);
	list.size--;
}
