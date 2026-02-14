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

<*
	@require new_cap <= list.capacity : "Should not exceed current capacity"
*>
fn void List.resize(&list, usz new_cap)
{
	list.size = new_cap;
}

fn void List.resize_to_cap(&list)
{
	list.size = list.capacity;
}


fn void List.remove_unordered(&list, usz ind)
{
	assert(ind < list.size);
	util::@swap_ptrs(&list[ind], &list[list.size - 1]);
	list.size--;
}

<*
	@require list.size + move_count <= list.capacity : "Should not exceed bounds"
*>
fn void List.move_forward(&list, usz move_count)
{
	list.size += move_count;
}

<*
	@require end < list.size : "Should not be more than or equal to size"
*>
fn Type[] List.view_range(&list, usz start, usz end)
{
	return list.entries[start..end];
}

<*
	@require (start + len) <= list.size : "Should not be more than or equal to size"
*>
fn Type[] List.view_range_len(&list, usz start, usz len)
{
	return list.entries[start:len];
}
