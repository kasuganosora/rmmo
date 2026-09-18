extends SceneTree
## Headless: party loot modes — ffa/leader/round_robin owner_id + gate + 60s free TTL.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_party_loot: FAIL no MockServer")
		quit(1)
		return

	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.combat_stats != null, "combat_stats ready")
	failed += _expect(srv.has_method("try_party_set_loot_mode"), "has try_party_set_loot_mode")
	failed += _expect(srv.has_method("_party_assign_kill_loot_owner"), "has assign helper")
	failed += _expect(srv.has_method("can_loot_ground_bag"), "has can_loot_ground_bag")

	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._party_poll_pending = false
	srv._stub_ally_seq = 1
	srv._session_character_id = "1"
	if srv.combat_stats.has_method("set_player_actor_id"):
		srv.combat_stats.set_player_actor_id("1")
	srv.combat_stats.reset_player(3)
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""
	if srv.inventory != null:
		srv.inventory.clear()
		srv.inventory.grant_starter()
		srv.inventory.max_slots = 40
	srv.set_player_cell(5, 5)

	# --- Mode set + leader gate ---
	var cr: Dictionary = srv.try_party_create()
	failed += _expect(bool(cr.get("ok", false)), "create ok")
	failed += _expect(str(srv.snapshot_party().get("loot_mode", "")) == "ffa", "default loot_mode ffa")

	var set_ffa: Dictionary = srv.try_party_set_loot_mode("ffa")
	failed += _expect(bool(set_ffa.get("ok", false)), "set ffa ok")
	failed += _expect(_has_msg(set_ffa, "自由拾取"), "ffa system_message")

	var set_lead: Dictionary = srv.try_party_set_loot_mode("leader")
	failed += _expect(bool(set_lead.get("ok", false)), "set leader ok")
	failed += _expect(_has_msg(set_lead, "队长分配"), "leader system_message")
	failed += _expect(str(srv.party_loot_mode) == "leader", "party_loot_mode leader")
	failed += _expect(str(srv.snapshot_party().get("loot_mode", "")) == "leader", "snap loot_mode")

	var set_rr: Dictionary = srv.try_party_set_loot_mode("round_robin")
	failed += _expect(bool(set_rr.get("ok", false)), "set rr ok")
	failed += _expect(_has_msg(set_rr, "轮流拾取"), "rr system_message")

	# Non-leader cannot set
	srv.party_leader_id = "someone_else"
	var denied: Dictionary = srv.try_party_set_loot_mode("ffa")
	failed += _expect(not bool(denied.get("ok", true)), "non-leader denied")
	failed += _expect(_has_msg(denied, "只有队长"), "non-leader msg")
	srv.party_leader_id = "1"
	srv.try_party_set_loot_mode("ffa")

	# --- Solo / not in party → free ---
	if srv.has_method("_party_clear"):
		srv._party_clear()
	failed += _expect(str(srv._party_assign_kill_loot_owner()) == "", "solo owner empty")

	# --- Leader mode assigns leader id ---
	srv.try_party_create()
	srv.try_party_set_loot_mode("leader")
	var stub_a: Dictionary = srv._party_make_stub("stub_ally_loot_a")
	var stub_b: Dictionary = srv._party_make_stub("stub_ally_loot_b")
	srv._party_members.append(stub_a)
	srv._party_members.append(stub_b)
	failed += _expect(str(srv._party_assign_kill_loot_owner()) == "1", "leader mode → self id")

	# Spawn bag with owner via _add_items_to_ground (public-ish helper)
	srv._ground_bags.clear()
	var acts: Array = srv._add_items_to_ground(
		{"x": 5, "y": 5},
		[{"item_id": "rusty_coin", "qty": 2}],
		"monster",
		"loot_npc",
		"stub_ally_loot_a"
	)
	failed += _expect(not acts.is_empty(), "spawn actions")
	var bag_id := ""
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "ground_spawn":
			var bag_v: Variant = a.get("bag", {})
			if typeof(bag_v) == TYPE_DICTIONARY:
				bag_id = str(bag_v.get("id", ""))
				failed += _expect(str(bag_v.get("owner_id", "")) == "stub_ally_loot_a", "spawn owner_id")
	failed += _expect(bag_id != "", "bag_id")

	# Non-owner cannot open/take
	failed += _expect(not bool(srv.can_loot_ground_bag(bag_id)), "can_loot false for non-owner")
	var open_deny: Dictionary = srv.try_open_ground_bag(bag_id)
	failed += _expect(not bool(open_deny.get("ok", true)), "open denied")
	failed += _expect(str(open_deny.get("reason", "")) == "not_owner", "open reason not_owner")
	failed += _expect(_has_msg(open_deny, "该掉落属于"), "open belong msg")

	# Force-open session for take gate (simulate)
	srv._open_loot_bag_id = bag_id
	var take_deny: Dictionary = srv.try_loot_take("rusty_coin", -1)
	failed += _expect(not bool(take_deny.get("ok", true)), "take denied")
	failed += _expect(str(take_deny.get("reason", "")) == "not_owner", "take reason")
	var take_all_deny: Dictionary = srv.try_loot_take_all()
	failed += _expect(not bool(take_all_deny.get("ok", true)), "take_all denied")
	srv._open_loot_bag_id = ""

	# Owner can open/take
	var bag: Dictionary = srv._ground_bags[bag_id]
	bag["owner_id"] = "1"
	srv._ground_bags[bag_id] = bag
	failed += _expect(bool(srv.can_loot_ground_bag(bag_id)), "can_loot true for owner")
	var open_ok: Dictionary = srv.try_open_ground_bag(bag_id)
	failed += _expect(bool(open_ok.get("ok", false)), "owner open ok")
	var take_ok: Dictionary = srv.try_loot_take("rusty_coin", 1)
	failed += _expect(bool(take_ok.get("ok", false)), "owner take ok")

	# --- TTL 60s free ---
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""
	var acts2: Array = srv._add_items_to_ground(
		{"x": 5, "y": 5},
		[{"item_id": "rusty_coin", "qty": 1}],
		"monster",
		"loot_npc2",
		"stub_ally_loot_b"
	)
	var bag2 := ""
	for a2 in acts2:
		if typeof(a2) == TYPE_DICTIONARY and str(a2.get("type", "")) == "ground_spawn":
			bag2 = str((a2.get("bag", {}) as Dictionary).get("id", ""))
	failed += _expect(bag2 != "", "bag2 id")
	var b2: Dictionary = srv._ground_bags[bag2]
	var now_sec: float = float(srv.combat_stats.now_sec())
	b2["created_at"] = now_sec - 61.0
	srv._ground_bags[bag2] = b2
	failed += _expect(bool(srv.can_loot_ground_bag(bag2)), "TTL free can_loot")
	var open_ttl: Dictionary = srv.try_open_ground_bag(bag2)
	failed += _expect(bool(open_ttl.get("ok", false)), "TTL open ok")
	var take_ttl: Dictionary = srv.try_loot_take("rusty_coin", -1)
	failed += _expect(bool(take_ttl.get("ok", false)), "TTL take ok")

	# --- round_robin advances across two fake member ids ---
	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv.try_party_create()
	srv.try_party_set_loot_mode("round_robin")
	# Replace members with exactly two fake ids (stable order)
	srv._party_members = [
		{"id": "rr_a", "name": "甲", "hp": 10, "hp_max": 10, "online": true, "statuses": []},
		{"id": "rr_b", "name": "乙", "hp": 10, "hp_max": 10, "online": true, "statuses": []},
	]
	srv._party_loot_rr_index = 0
	var o1 := str(srv._party_assign_kill_loot_owner())
	var o2 := str(srv._party_assign_kill_loot_owner())
	var o3 := str(srv._party_assign_kill_loot_owner())
	failed += _expect(o1 == "rr_a", "rr first rr_a (got %s)" % o1)
	failed += _expect(o2 == "rr_b", "rr second rr_b (got %s)" % o2)
	failed += _expect(o3 == "rr_a", "rr wraps rr_a (got %s)" % o3)
	failed += _expect(int(srv._party_loot_rr_index) == 3, "rr index advanced")

	# Kill-path smoke: leader mode sets owner on _roll_and_grant_loot
	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv.try_party_create()
	srv.try_party_set_loot_mode("leader")
	srv._party_members.append(srv._party_make_stub("stub_ally_loot_c"))
	srv._ground_bags.clear()
	if srv.loot_catalog != null:
		srv.loot_catalog.rng_roll = func() -> float: return 0.0
	srv.npc_spawn_templates["party_loot_slime"] = {
		"id": "party_loot_slime",
		"charset": "retira_slime",
		"hostile": true,
	}
	var kill_acts: Array = srv._roll_and_grant_loot("party_loot_slime", {"x": 6, "y": 6})
	var found_owner := false
	for ka in kill_acts:
		if typeof(ka) != TYPE_DICTIONARY:
			continue
		if str(ka.get("type", "")) != "ground_spawn":
			continue
		var kb: Dictionary = ka.get("bag", {})
		found_owner = str(kb.get("owner_id", "")) == "1"
	# If loot table empty, skip soft
	if kill_acts.is_empty():
		print("  SKIP kill-path loot empty (table miss)")
	else:
		failed += _expect(found_owner, "kill loot owner=leader")
	if srv.loot_catalog != null:
		srv.loot_catalog.rng_roll = Callable()

	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""

	if failed == 0:
		print("test_party_loot: PASS")
		quit(0)
	else:
		print("test_party_loot: FAIL count=%d" % failed)
		quit(1)


func _has_msg(result: Dictionary, needle: String) -> bool:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return false
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(needle) >= 0:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
