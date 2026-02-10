module std::core::dstring;

<*
	@require end < dstring.len() : "Should not be more than or equal to length"
*>
fn char[] DString.view_range(&dstring, usz start, usz end)
{
	return dstring.str_view()[start..end];
}

<*
	@require (start + len) <= dstring.len() : "Should not be more than or equal to length"
*>
fn char[] DString.view_range_len(&dstring, usz start, usz len)
{
	return dstring.str_view()[start:len];
}

<*
	@require new_len <= dstring.capacity() : "New len should be less or equal to capacity"
*>
fn void DString.resize(&dstring, usz new_len)
{
	StringData* data = dstring.data();
	data.len = new_len;
}
