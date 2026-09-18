extends SceneTree
## Headless: MockServer friend add/remove/duplicate/full + online flag + session reset.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_friends: FAIL no MockServer")
		quit(1)
		return
	if srv.friend_list == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.friend_list == null:
		print("test_friends: FAIL no friend_list after init")
		quit(1)
		return

	# Fresh friends + remotes
	srv.friend_list.clear()
	if srv.has_method("try_remote_despawn"):
		srv.try_remote_despawn("")
	srv._party_poll_pending = false
	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._session_character_id = "1"
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_friend_add"), "has try_friend_add")
	failed += _expect(srv.has_method("try_friend_remove"), "has try_friend_remove")
	failed += _expect(srv.has_method("snapshot_friends"), "has snapshot_friends")

	var snap0: Dictionary = srv.snapshot_friends()
	failed += _expect(typeof(snap0.get("friends", null)) == TYPE_ARRAY, "snap friends array")
	failed += _expect(int(snap0.get("count", -1)) == 0, "empty count")
	failed += _expect(int(snap0.get("max_friends", 0)) >= 50, "cap >= 50")

	# Spawn remote 旅人甲
	var sp: Dictionary = srv.try_remote_debug_spawn("旅人甲")
	failed += _expect(bool(sp.get("ok", false)), "spawn 旅人甲")
	var remotes: Array = srv.snapshot_remote_players()
	failed += _expect(remotes.size() >= 1, "has remote")
	var rid := ""
	var rname := ""
	for r in remotes:
		if typeof(r) == TYPE_DICTIONARY and str(r.get("name", "")) == "旅人甲":
			rid = str(r.get("id", ""))
			rname = str(r.get("name", ""))
			break
	failed += _expect(rid != "", "remote id")
	failed += _expect(rname == "旅人甲", "remote name")

	# Add by display name
	var add1: Dictionary = srv.try_friend_add("旅人甲")
	failed += _expect(bool(add1.get("ok", false)), "add by name ok")
	failed += _expect(_has(add1, "friends_update"), "add friends_update")
	failed += _expect(_has(add1, "system_message"), "add system_message")
	var fu := _first(add1, "friends_update")
	var friends: Array = fu.get("friends", {}).get("friends", []) if typeof(fu.get("friends", null)) == TYPE_DICTIONARY else []
	if friends.is_empty() and typeof(fu.get("friends", null)) == TYPE_ARRAY:
		friends = fu.get("friends", [])
	failed += _expect(friends.size() == 1, "one friend after add")
	var row: Dictionary = friends[0] if friends.size() > 0 and typeof(friends[0]) == TYPE_DICTIONARY else {}
	failed += _expect(str(row.get("id", "")) == rid, "friend id is remote id")
	failed += _expect(str(row.get("name", "")) == "旅人甲", "friend name")
	failed += _expect(bool(row.get("online", false)) == true, "online while spawned")

	# Duplicate
	var dup: Dictionary = srv.try_friend_add("旅人甲")
	failed += _expect(not bool(dup.get("ok", true)), "duplicate rejected")
	failed += _expect(str(dup.get("reason", "")) == "duplicate", "reason duplicate")
	failed += _expect(srv.friend_list.count() == 1, "still one after dup")

	# Add by id also rejected as duplicate
	var dup2: Dictionary = srv.try_friend_add(rid)
	failed += _expect(not bool(dup2.get("ok", true)), "dup by id rejected")

	# Not found
	var miss: Dictionary = srv.try_friend_add("不存在的旅人")
	failed += _expect(not bool(miss.get("ok", true)), "not found rejected")
	failed += _expect(str(miss.get("reason", "")) == "not_found", "reason not_found")
	failed += _expect(_has(miss, "system_message"), "not found message")

	# Known shell name offline (旅人乙 may not be spawned)
	var add_known: Dictionary = srv.try_friend_add("旅人乙")
	failed += _expect(bool(add_known.get("ok", false)), "add known shell name")
	var snap1: Dictionary = srv.snapshot_friends()
	var list1: Array = snap1.get("friends", [])
	failed += _expect(list1.size() == 2, "two friends")
	var eth_online := true
	for e in list1:
		if typeof(e) == TYPE_DICTIONARY and str(e.get("name", "")) == "旅人乙":
			eth_online = bool(e.get("online", true))
	failed += _expect(eth_online == false, "旅人乙 offline when not spawned")

	# Remove
	var rem: Dictionary = srv.try_friend_remove(rid)
	failed += _expect(bool(rem.get("ok", false)), "remove ok")
	failed += _expect(_has(rem, "friends_update"), "remove friends_update")
	failed += _expect(srv.friend_list.count() == 1, "one left after remove")
	var still := false
	for e2 in srv.snapshot_friends().get("friends", []):
		if typeof(e2) == TYPE_DICTIONARY and str(e2.get("id", "")) == rid:
			still = true
	failed += _expect(not still, "removed id gone")

	# Remove missing
	var rem2: Dictionary = srv.try_friend_remove(rid)
	failed += _expect(not bool(rem2.get("ok", true)), "remove missing fails")

	# Full list cap
	srv.friend_list.clear()
	var cap: int = int(srv.friend_list.max_friends())
	failed += _expect(cap == 50, "cap is 50")
	for i in range(cap):
		var r: Dictionary = srv.friend_list.try_add("fill_%d" % i, "填充%d" % i)
		if not bool(r.get("ok", false)):
			failed += _expect(false, "fill %d" % i)
			break
	failed += _expect(srv.friend_list.count() == cap, "filled to cap")
	var full: Dictionary = srv.try_friend_add("旅人丙")
	failed += _expect(not bool(full.get("ok", true)), "full rejected")
	failed += _expect(str(full.get("reason", "")) == "full", "reason full")
	failed += _expect(_has(full, "system_message"), "full message")

	# Survives "transfer" (in-memory not cleared except enter_world)
	srv.friend_list.clear()
	srv.try_friend_add("旅人甲")
	failed += _expect(srv.friend_list.count() == 1, "pre-transfer count")
	# Simulate transfer: remotes may refresh but friends stay
	failed += _expect(srv.friend_list.count() == 1, "survives session transfer")

	# enter_world-style reset
	srv.friend_list.clear()
	failed += _expect(srv.friend_list.count() == 0, "cleared for new session")

	# PCM has 加为好友
	var PCM = load("res://scripts/ui/player_context_menu.gd")
	failed += _expect(PCM != null, "load PCM")
	if PCM != null:
		failed += _expect(PCM.Action.ADD_FRIEND == 6, "ADD_FRIEND id=6")
		failed += _expect(PCM.label_for(PCM.Action.ADD_FRIEND) == "加为好友", "ADD_FRIEND label")
		failed += _expect(PCM.Action.INVITE == 2, "INVITE unchanged")
		failed += _expect(PCM.label_for(PCM.Action.INVITE) == "邀请组队", "INVITE label unchanged")

	if failed == 0:
		print("test_friends: PASS")
		quit(0)
		return
	print("test_friends: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _first(result: Dictionary, typ: String) -> Dictionary:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return a
	return {}


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
