extends RefCounted
## In-memory friend list (MockServer session only; no disk persistence).
## Entry shape: {id, name, online}

const MAX_FRIENDS := 50

## Ordered list of {id, name} — online is computed by MockServer snapshot.
var _friends: Array = []


func clear() -> void:
	_friends.clear()


func count() -> int:
	return _friends.size()


func max_friends() -> int:
	return MAX_FRIENDS


func has_id(friend_id: String) -> bool:
	friend_id = str(friend_id).strip_edges()
	if friend_id.is_empty():
		return false
	for e in _friends:
		if typeof(e) == TYPE_DICTIONARY and str(e.get("id", "")) == friend_id:
			return true
	return false


func has_name(display_name: String) -> bool:
	display_name = str(display_name).strip_edges()
	if display_name.is_empty():
		return false
	var low := display_name.to_lower()
	for e in _friends:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var n := str(e.get("name", "")).strip_edges()
		if n == display_name or n.to_lower() == low:
			return true
	return false


func find_index_by_id(friend_id: String) -> int:
	friend_id = str(friend_id).strip_edges()
	for i in range(_friends.size()):
		var e: Variant = _friends[i]
		if typeof(e) == TYPE_DICTIONARY and str(e.get("id", "")) == friend_id:
			return i
	return -1


## Add by resolved id+name. Returns {ok, reason}.
func try_add(friend_id: String, display_name: String) -> Dictionary:
	friend_id = str(friend_id).strip_edges()
	display_name = str(display_name).strip_edges()
	if friend_id.is_empty() or display_name.is_empty():
		return {"ok": false, "reason": "invalid"}
	if has_id(friend_id) or has_name(display_name):
		return {"ok": false, "reason": "duplicate"}
	if _friends.size() >= MAX_FRIENDS:
		return {"ok": false, "reason": "full"}
	_friends.append({"id": friend_id, "name": display_name})
	return {"ok": true, "reason": ""}


func try_remove(friend_id: String) -> Dictionary:
	friend_id = str(friend_id).strip_edges()
	if friend_id.is_empty():
		return {"ok": false, "reason": "invalid"}
	var idx := find_index_by_id(friend_id)
	if idx < 0:
		return {"ok": false, "reason": "not_found"}
	_friends.remove_at(idx)
	return {"ok": true, "reason": ""}


## Snapshot with online flags from a callable or id-set.
## online_ids: Dictionary id->true, or Array of ids; online_names: optional name set.
func snapshot(online_ids: Variant = null, online_names: Variant = null) -> Array:
	var id_set: Dictionary = {}
	var name_set: Dictionary = {}
	if typeof(online_ids) == TYPE_DICTIONARY:
		for k in (online_ids as Dictionary).keys():
			id_set[str(k)] = true
	elif typeof(online_ids) == TYPE_ARRAY:
		for k2 in online_ids:
			id_set[str(k2)] = true
	if typeof(online_names) == TYPE_DICTIONARY:
		for n in (online_names as Dictionary).keys():
			name_set[str(n)] = true
			name_set[str(n).to_lower()] = true
	elif typeof(online_names) == TYPE_ARRAY:
		for n2 in online_names:
			name_set[str(n2)] = true
			name_set[str(n2).to_lower()] = true
	var out: Array = []
	for e in _friends:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var fid := str(e.get("id", ""))
		var fname := str(e.get("name", ""))
		var online := id_set.has(fid) or name_set.has(fname) or name_set.has(fname.to_lower())
		out.append({"id": fid, "name": fname, "online": online})
	return out


func snapshot_state(online_ids: Variant = null, online_names: Variant = null) -> Dictionary:
	var friends: Array = snapshot(online_ids, online_names)
	return {
		"friends": friends,
		"count": friends.size(),
		"max_friends": MAX_FRIENDS,
	}
