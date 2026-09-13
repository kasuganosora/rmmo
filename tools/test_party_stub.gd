extends SceneTree
## Headless: MockServer party shell — create/fill/leave/kick + party_update shape.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_party_stub: FAIL no MockServer")
		quit(1)
		return

	# Fresh shell state
	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._party_poll_pending = false
	srv._stub_ally_seq = 1
	srv._session_character_id = "1"
	# Ensure combat HP for self member snapshot
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.combat_stats != null:
		srv.combat_stats.reset_player(3)
		if srv.combat_stats.has_method("set_player_actor_id"):
			srv.combat_stats.set_player_actor_id("1")

	failed += _expect(srv.has_method("try_party_create"), "has try_party_create")
	failed += _expect(srv.has_method("try_party_invite"), "has try_party_invite")
	failed += _expect(srv.has_method("try_party_leave"), "has try_party_leave")
	failed += _expect(srv.has_method("try_party_kick"), "has try_party_kick")
	failed += _expect(srv.has_method("try_party_debug_fill"), "has try_party_debug_fill")
	failed += _expect(srv.has_method("snapshot_party"), "has snapshot_party")

	var snap0: Dictionary = srv.snapshot_party()
	failed += _expect(str(snap0.get("party_id", "")) == "", "empty party_id")
	failed += _expect((snap0.get("members", []) as Array).is_empty(), "empty members")

	# create
	var cr: Dictionary = srv.try_party_create()
	failed += _expect(bool(cr.get("ok", false)), "create ok")
	failed += _expect(_has_action(cr, "party_update"), "create emits party_update")
	failed += _expect(_has_action(cr, "system_message"), "create emits system_message")
	var pu := _first_action(cr, "party_update")
	failed += _expect(_valid_party_shape(pu.get("party", {})), "create party shape")
	failed += _expect(srv.in_party(), "in_party after create")
	failed += _expect(str(srv.party_leader_id) == "1", "leader is self")
	failed += _expect(srv._party_members.size() == 1, "create has self only")

	# create again fails
	var cr2: Dictionary = srv.try_party_create()
	failed += _expect(not bool(cr2.get("ok", true)), "create twice fails")

	# debug fill → stubs
	var fill: Dictionary = srv.try_party_debug_fill()
	failed += _expect(bool(fill.get("ok", false)), "debug_fill ok")
	failed += _expect(_has_action(fill, "party_update"), "fill party_update")
	var fill_party: Dictionary = _first_action(fill, "party_update").get("party", {})
	failed += _expect(_valid_party_shape(fill_party), "fill party shape")
	var mems: Array = fill_party.get("members", [])
	failed += _expect(mems.size() >= 3, "fill has self+2 stubs (got %d)" % mems.size())
	var stub_ids := {}
	for m in mems:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mid := str(m.get("id", ""))
		if mid.begins_with("stub_ally_"):
			stub_ids[mid] = true
			failed += _expect(int(m.get("hp_max", 0)) > 0, "stub hp_max>0 %s" % mid)
			failed += _expect(int(m.get("hp", -1)) >= 0, "stub hp>=0 %s" % mid)
	failed += _expect(stub_ids.size() >= 2, "at least 2 stub ids")

	# kick one stub
	var kick_id := str(stub_ids.keys()[0])
	var kick: Dictionary = srv.try_party_kick(kick_id)
	failed += _expect(bool(kick.get("ok", false)), "kick ok")
	failed += _expect(_has_action(kick, "party_update"), "kick party_update")
	var after_kick: Array = _first_action(kick, "party_update").get("party", {}).get("members", [])
	var still := false
	for m2 in after_kick:
		if typeof(m2) == TYPE_DICTIONARY and str(m2.get("id", "")) == kick_id:
			still = true
	failed += _expect(not still, "kicked member gone")

	# invite by name spawns stub
	var inv: Dictionary = srv.try_party_invite("测试盟友")
	failed += _expect(bool(inv.get("ok", false)), "invite ok")
	var inv_mems: Array = _first_action(inv, "party_update").get("party", {}).get("members", [])
	var found_name := false
	for m3 in inv_mems:
		if typeof(m3) == TYPE_DICTIONARY and str(m3.get("name", "")) == "测试盟友":
			found_name = true
	failed += _expect(found_name, "invite name present")

	# leave dissolves
	var leave: Dictionary = srv.try_party_leave()
	failed += _expect(bool(leave.get("ok", false)), "leave ok")
	failed += _expect(not srv.in_party(), "not in party after leave")
	var leave_party: Dictionary = _first_action(leave, "party_update").get("party", {})
	failed += _expect(str(leave_party.get("party_id", "")) == "", "leave clears party_id")
	failed += _expect((leave_party.get("members", []) as Array).is_empty(), "leave clears members")

	# leave when empty
	var leave2: Dictionary = srv.try_party_leave()
	failed += _expect(not bool(leave2.get("ok", true)), "leave empty fails")

	# debug_fill from empty creates+fills
	var fill2: Dictionary = srv.try_party_debug_fill()
	failed += _expect(bool(fill2.get("ok", false)), "fill from empty ok")
	failed += _expect(srv.in_party(), "in party after fill2")
	failed += _expect(srv._party_members.size() >= 3, "fill2 size>=3")

	# poll injects party_update when pending
	srv._mark_party_poll()
	var polled: Array = srv.poll_combat_tick()
	var poll_has := false
	for a in polled:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "party_update":
			poll_has = true
			failed += _expect(_valid_party_shape(a.get("party", {})), "poll party shape")
	failed += _expect(poll_has, "poll emits party_update when pending")

	# shared target
	var st: Dictionary = srv.try_party_set_target("npc_wolf_1", "森林狼")
	failed += _expect(bool(st.get("ok", false)), "set_target ok")
	failed += _expect(str(srv.party_shared_target_id) == "npc_wolf_1", "shared id")
	failed += _expect(str(srv.party_shared_target_name) == "森林狼", "shared name")
	var snap_t: Dictionary = srv.snapshot_party()
	failed += _expect(str(snap_t.get("shared_target_id", "")) == "npc_wolf_1", "snap shared id")
	failed += _expect(_has_action(st, "system_message"), "set_target message first time")
	var st2: Dictionary = srv.try_party_set_target("npc_wolf_1", "森林狼")
	failed += _expect(bool(st2.get("ok", false)), "set same target ok")
	failed += _expect(not _has_action(st2, "system_message"), "no spam on same target")
	var clr: Dictionary = srv.try_party_clear_target()
	failed += _expect(bool(clr.get("ok", false)), "clear_target ok")
	failed += _expect(str(srv.party_shared_target_id) == "", "cleared id")

	# self HP refresh fingerprint
	if srv.combat_stats != null and not srv.combat_stats.player.is_empty():
		srv.combat_stats.player["hp"] = maxi(int(srv.combat_stats.player.get("hp", 50)) - 7, 1)
		var changed: bool = bool(srv._party_refresh_self_member())
		failed += _expect(changed, "hp refresh detects change")
		var self_row := {}
		for m4 in srv._party_members:
			if typeof(m4) == TYPE_DICTIONARY and str(m4.get("id", "")) == "1":
				self_row = m4
		failed += _expect(int(self_row.get("hp", -1)) == int(srv.combat_stats.player.get("hp", -2)), "self hp synced")

	# HUD-less path: actions consumable without GameHud
	var leave3: Dictionary = srv.try_party_leave()
	failed += _expect(typeof(leave3.get("actions", null)) == TYPE_ARRAY, "HUD-less actions array")
	for a2 in leave3.get("actions", []):
		failed += _expect(typeof(a2) == TYPE_DICTIONARY, "HUD-less action dict")
		failed += _expect(str(a2.get("type", "")) in ["party_update", "system_message"], "HUD-less known type")

	if failed == 0:
		print("test_party_stub: PASS")
		quit(0)
	else:
		print("test_party_stub: FAIL count=%d" % failed)
		quit(1)


func _has_action(result: Dictionary, typ: String) -> bool:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return false
	for a in actions_v:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _first_action(result: Dictionary, typ: String) -> Dictionary:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return {}
	for a in actions_v:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return a
	return {}


func _valid_party_shape(party: Variant) -> bool:
	if typeof(party) != TYPE_DICTIONARY:
		return false
	var p: Dictionary = party
	if not p.has("party_id") or not p.has("leader") or not p.has("members"):
		return false
	var mem_v: Variant = p.get("members", null)
	if typeof(mem_v) != TYPE_ARRAY:
		return false
	for m in mem_v:
		if typeof(m) != TYPE_DICTIONARY:
			return false
		var md: Dictionary = m
		for k in ["id", "name", "hp", "hp_max", "online"]:
			if not md.has(k):
				return false
	return true


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
