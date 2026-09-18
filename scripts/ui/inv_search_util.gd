extends RefCounted
## Pure helpers for client-side inventory search (name / id substring).


## True when query is empty, or item_id / display_name contains query (case-insensitive).
static func matches(query: String, item_id: String, display_name: String) -> bool:
	var q := query.strip_edges()
	if q.is_empty():
		return true
	if str(item_id).containsn(q):
		return true
	if str(display_name).containsn(q):
		return true
	return false
