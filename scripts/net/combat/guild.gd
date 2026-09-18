extends RefCounted
## In-memory guild session (MockServer only; no disk persistence).
## Snapshot shape: {id, name, leader_id, members:[{id,name,rank}]}

const MAX_MEMBERS := 20
const RANK_LEADER := "leader"
const RANK_MEMBER := "member"

var id: String = ""
var guild_name: String = ""
var leader_id: String = ""
## Ordered [{id, name, rank}, ...] — leader first when created.
var members: Array = []


func clear() -> void:
	id = ""
	guild_name = ""
	leader_id = ""
	members.clear()


func in_guild() -> bool:
	return id.strip_edges() != "" and not members.is_empty()


func max_members() -> int:
	return MAX_MEMBERS


func member_count() -> int:
	return members.size()


func is_leader(actor_id: String) -> bool:
	return in_guild() and str(actor_id).strip_edges() == leader_id


func find_index_by_id(member_id: String) -> int:
	member_id = str(member_id).strip_edges()
	if member_id.is_empty():
		return -1
	for i in range(members.size()):
		var e: Variant = members[i]
		if typeof(e) == TYPE_DICTIONARY and str(e.get("id", "")) == member_id:
			return i
	return -1


func find_index_by_name(display_name: String) -> int:
	display_name = str(display_name).strip_edges()
	if display_name.is_empty():
		return -1
	var low := display_name.to_lower()
	for i in range(members.size()):
		var e: Variant = members[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var n := str(e.get("name", "")).strip_edges()
		if n == display_name or n.to_lower() == low:
			return i
	return -1


func has_member(member_id: String) -> bool:
	return find_index_by_id(member_id) >= 0


func has_member_name(display_name: String) -> bool:
	return find_index_by_name(display_name) >= 0


## Create guild with leader. Returns {ok, reason}.
func try_create(guild_id: String, name: String, leader_actor_id: String, leader_name: String) -> Dictionary:
	guild_id = str(guild_id).strip_edges()
	name = str(name).strip_edges()
	leader_actor_id = str(leader_actor_id).strip_edges()
	leader_name = str(leader_name).strip_edges()
	if in_guild():
		return {"ok": false, "reason": "already_in_guild"}
	if guild_id.is_empty() or name.is_empty() or leader_actor_id.is_empty():
		return {"ok": false, "reason": "invalid"}
	if name.length() < 2 or name.length() > 12:
		return {"ok": false, "reason": "bad_name"}
	id = guild_id
	guild_name = name
	leader_id = leader_actor_id
	members = [{
		"id": leader_actor_id,
		"name": leader_name if leader_name != "" else "你",
		"rank": RANK_LEADER,
	}]
	return {"ok": true, "reason": ""}


## Add member (rank defaults to member). Returns {ok, reason}.
func try_add_member(member_id: String, display_name: String, rank: String = RANK_MEMBER) -> Dictionary:
	member_id = str(member_id).strip_edges()
	display_name = str(display_name).strip_edges()
	rank = str(rank).strip_edges()
	if not in_guild():
		return {"ok": false, "reason": "no_guild"}
	if member_id.is_empty() or display_name.is_empty():
		return {"ok": false, "reason": "invalid"}
	if has_member(member_id) or has_member_name(display_name):
		return {"ok": false, "reason": "already_member"}
	if members.size() >= MAX_MEMBERS:
		return {"ok": false, "reason": "full"}
	if rank != RANK_LEADER and rank != RANK_MEMBER:
		rank = RANK_MEMBER
	members.append({"id": member_id, "name": display_name, "rank": rank})
	return {"ok": true, "reason": ""}


func try_remove_member(member_id: String) -> Dictionary:
	member_id = str(member_id).strip_edges()
	if not in_guild():
		return {"ok": false, "reason": "no_guild"}
	var idx := find_index_by_id(member_id)
	if idx < 0:
		return {"ok": false, "reason": "not_found"}
	members.remove_at(idx)
	if members.is_empty():
		clear()
		return {"ok": true, "reason": "cleared"}
	# If leader left/removed, promote first remaining member.
	if leader_id == member_id or find_index_by_id(leader_id) < 0:
		var first: Dictionary = members[0]
		leader_id = str(first.get("id", ""))
		first["rank"] = RANK_LEADER
		members[0] = first
		for i in range(1, members.size()):
			var m: Variant = members[i]
			if typeof(m) == TYPE_DICTIONARY:
				var md: Dictionary = m
				md["rank"] = RANK_MEMBER
				members[i] = md
	return {"ok": true, "reason": ""}


func try_disband() -> Dictionary:
	if not in_guild():
		return {"ok": false, "reason": "no_guild"}
	clear()
	return {"ok": true, "reason": ""}


func snapshot() -> Dictionary:
	if not in_guild():
		return {"id": "", "name": "", "leader_id": "", "members": []}
	var out_members: Array = []
	for e in members:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		out_members.append({
			"id": str(e.get("id", "")),
			"name": str(e.get("name", "")),
			"rank": str(e.get("rank", RANK_MEMBER)),
		})
	return {
		"id": id,
		"name": guild_name,
		"leader_id": leader_id,
		"members": out_members,
	}
