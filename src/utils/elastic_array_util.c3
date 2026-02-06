module std::collections::elastic_array <Type, MAX_SIZE>;

import util;

<*
	@require new_cap <= MAX_SIZE : "Would exceed maximum capacity"
*>
fn void ElasticArray.resize(&arr, usz new_cap)
{
	arr.size = new_cap;
}

fn void ElasticArray.resize_to_cap(&arr)
{
	arr.size = MAX_SIZE;
}

fn Type* ElasticArray.data(&arr)
{
	return &arr.entries;
}

fn void ElasticArray.fill(&arr, Type val)
{
	foreach (&entry : arr.array_view()) {
		*entry = val;
	}
}

fn void ElasticArray.remove_unordered(&arr, usz ind)
{
	assert(ind < arr.size);
	util::@swap_ptrs(&arr[ind], &arr[arr.size - 1]);
	arr.size--;
}
