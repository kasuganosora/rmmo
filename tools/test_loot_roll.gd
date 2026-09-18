extends SceneTree
## Headless: party need/greed loot roll — mode, try_loot_roll, timeout auto-pass, winner owner_id.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_loot_roll: FAIL no MockServer")
		quit(1)
		return

	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.combat_stats != null, "combat_stats ready")
	failed += _expect(srv.has_method("try_party_set_loot_mode"), "has try_party_set_loot_mode")
	failed += _expect(srv.has_method("try_loot_roll"), "has try_loot_roll")
	failed += _expect(srv.has_method("try_loot_roll_for"), "has try_loot_roll_for")
	failed += _expect(srv.has_method("debug_start_loot_roll"), "has debug_start_loot_roll")
	failed += _expect(srv.has_method("debug_force_loot_roll_timeout"), "has debug_force_timeout")
	failed += _expect(srv.has_method("snapshot_loot_rolls"), "has snapshot_loot_rolls")

	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._session_character_id = "1"
	if srv.combat_stats.has_method("set_player_actor_id"):
		srv.combat_stats.set_player_actor_id("1")
	srv.combat_stats.reset_player(3)
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""
	srv._loot_rolls.clear()
	srv.loot_roll_rng_fn = Callable()
	if srv.inventory != null:
		srv.inventory.clear()
		srv.inventory.grant_starter()
		srv.inventory.max_slots = 40
	srv.set_player_cell(5, 5)

	# --- Mode set ---
	var cr: Dictionary = srv.try_party_create()
	failed += _expect(bool(cr.get("ok", false)), "create ok")
	var set_ng: Dictionary = srv.try_party_set_loot_mode("need_greed")
	failed += _expect(bool(set_ng.get("ok", false)), "set need_greed ok")
	failed += _expect(_has_msg(set_ng, "需求/贪婪"), "need_greed system_message")
	failed += _expect(str(srv.party_loot_mode) == "need_greed", "party_loot_mode need_greed")
	failed += _expect(str(srv.snapshot_party().get("loot_mode", "")) == "need_greed", "snap loot_mode")

	var set_alias: Dictionary = srv.try_party_set_loot_mode("roll")
	failed += _expect(bool(set_alias.get("ok", false)), "alias roll → need_greed")
	failed += _expect(str(srv.party_loot_mode) == "need_greed", "alias stored need_greed")

	# --- Solo / N=1: skip roll ---
	srv._party_members = [{"id": "1", "name": "我", "hp": 10, "hp_max": 10, "online": true, "statuses": []}]
	var solo: Dictionary = srv.debug_start_loot_roll("enhance_stone", 1)
	failed += _expect(bool(solo.get("ok", false)), "solo start ok")
	failed += _expect(bool(solo.get("skipped", false)), "solo skipped roll")
	failed += _expect(int(srv.loot_roll_count()) == 0, "solo no active roll")
	failed += _expect(srv.ground_bag_count() >= 1, "solo spawned bag")
	srv._ground_bags.clear()

	# --- N>1: start roll + need wins over greed ---
	srv._party_members = [
		{"id": "1", "name": "甲", "hp": 10, "hp_max": 10, "online": true, "statuses": []},
		{"id": "stub_b", "name": "乙", "hp": 10, "hp_max": 10, "online": true, "statuses": []},
		{"id": "stub_c", "name": "丙", "hp": 10, "hp_max": 10, "online": true, "statuses": []},
	]
	srv.party_leader_id = "1"
	srv.party_id = "party_test_ng"
	srv.party_loot_mode = "need_greed"
	# Dice sequence: 甲 need 40, 乙 greed 99, 丙 need 70 → 丙 wins
	var dice: Array = [40, 99, 70]
	srv.loot_roll_rng_fn = func() -> int:
		if dice.is_empty():
			return 1
		return int(dice.pop_front())

	var started: Dictionary = srv.debug_start_loot_roll("enhance_stone", 1, ["1", "stub_b", "stub_c"])
	failed += _expect(bool(started.get("ok", false)), "start roll ok")
	failed += _expect(_has_msg(started, "开始掷骰"), "start msg 开始掷骰")
	var rid := str(started.get("roll_id", ""))
	failed += _expect(rid != "", "roll_id")
	failed += _expect(int(srv.loot_roll_count()) == 1, "one active roll")

	var r_a: Dictionary = srv.try_loot_roll("need", rid)
	failed += _expect(bool(r_a.get("ok", false)), "甲 need ok")
	failed += _expect(_has_msg(r_a, "需求 40"), "甲 需求 40")
	failed += _expect(int(srv.loot_roll_count()) == 1, "still open after 1 vote")

	var r_b: Dictionary = srv.try_loot_roll_for("stub_b", "greed", rid)
	failed += _expect(bool(r_b.get("ok", false)), "乙 greed ok")
	failed += _expect(_has_msg(r_b, "贪婪 99"), "乙 贪婪 99")

	var r_c: Dictionary = srv.try_loot_roll_for("stub_c", "need", rid)
	failed += _expect(bool(r_c.get("ok", false)), "丙 need ok")
	failed += _expect(_has_msg(r_c, "需求 70"), "丙 需求 70")
	# All voted → resolved; need 70 > need 40 beats greed 99
	failed += _expect(int(srv.loot_roll_count()) == 0, "resolved after all votes")
	failed += _expect(_has_msg(r_c, "获得了"), "winner msg 获得了")
	failed += _expect(_has_msg(r_c, "丙"), "winner is 丙")

	var bag_owner := ""
	for bid in srv._ground_bags.keys():
		bag_owner = str(srv._ground_bags[bid].get("owner_id", ""))
	failed += _expect(bag_owner == "stub_c", "bag owner stub_c (got %s)" % bag_owner)
	srv._ground_bags.clear()

	# --- Greed wins when no need ---
	dice = [55, 80]
	srv.loot_roll_rng_fn = func() -> int:
		if dice.is_empty():
			return 1
		return int(dice.pop_front())
	var gstart: Dictionary = srv.debug_start_loot_roll("fish_shiny", 1, ["1", "stub_b"])
	var grid := str(gstart.get("roll_id", ""))
	var g1: Dictionary = srv.try_loot_roll("greed", grid)
	failed += _expect(_has_msg(g1, "贪婪 55"), "甲 greed 55")
	var g2: Dictionary = srv.try_loot_roll_for("stub_b", "greed", grid)
	failed += _expect(_has_msg(g2, "乙 获得了") or _has_msg(g2, "获得了"), "greed winner msg")
	var gowner := ""
	for bid2 in srv._ground_bags.keys():
		gowner = str(srv._ground_bags[bid2].get("owner_id", ""))
	failed += _expect(gowner == "stub_b", "greed bag owner stub_b")
	srv._ground_bags.clear()

	# --- Timeout auto-pass: only one greed votes, other times out → voter wins ---
	dice = [66]
	srv.loot_roll_rng_fn = func() -> int:
		if dice.is_empty():
			return 1
		return int(dice.pop_front())
	var tstart: Dictionary = srv.debug_start_loot_roll("enhance_stone", 1, ["1", "stub_b"])
	var tid := str(tstart.get("roll_id", ""))
	var t1: Dictionary = srv.try_loot_roll("greed", tid)
	failed += _expect(bool(t1.get("ok", false)), "timeout path greed ok")
	failed += _expect(int(srv.loot_roll_count()) == 1, "open until timeout")
	var tforce: Dictionary = srv.debug_force_loot_roll_timeout(tid)
	failed += _expect(bool(tforce.get("ok", false)), "force timeout ok")
	failed += _expect(int(srv.loot_roll_count()) == 0, "cleared after timeout")
	failed += _expect(_has_msg(tforce, "获得了"), "timeout winner msg")
	var towner := ""
	for bid3 in srv._ground_bags.keys():
		towner = str(srv._ground_bags[bid3].get("owner_id", ""))
	failed += _expect(towner == "1", "timeout owner is voter self")
	srv._ground_bags.clear()

	# --- All pass → free owner ---
	srv.loot_roll_rng_fn = Callable()
	var pstart: Dictionary = srv.debug_start_loot_roll("rusty_coin", 1, ["1", "stub_b"])
	var pid := str(pstart.get("roll_id", ""))
	srv.try_loot_roll("pass", pid)
	var p2: Dictionary = srv.try_loot_roll_for("stub_b", "pass", pid)
	failed += _expect(int(srv.loot_roll_count()) == 0, "all-pass resolved")
	failed += _expect(_has_msg(p2, "无人认领") or _has_msg(p2, "自由拾取"), "all-pass free msg")
	var powner := "x"
	for bid4 in srv._ground_bags.keys():
		powner = str(srv._ground_bags[bid4].get("owner_id", ""))
	failed += _expect(powner == "", "all-pass owner empty")
	srv._ground_bags.clear()

	# --- Duplicate vote rejected ---
	dice = [10, 20]
	srv.loot_roll_rng_fn = func() -> int:
		if dice.is_empty():
			return 1
		return int(dice.pop_front())
	var dstart: Dictionary = srv.debug_start_loot_roll("enhance_stone", 1, ["1", "stub_b"])
	var did := str(dstart.get("roll_id", ""))
	srv.try_loot_roll("need", did)
	var dup: Dictionary = srv.try_loot_roll("greed", did)
	failed += _expect(not bool(dup.get("ok", true)), "duplicate vote denied")
	srv.debug_force_loot_roll_timeout(did)
	srv._ground_bags.clear()

	# --- Kill path: need_greed N>1 opens roll instead of immediate bag ---
	srv._ground_bags.clear()
	srv._loot_rolls.clear()
	srv.party_loot_mode = "need_greed"
	srv._party_members = [
		{"id": "1", "name": "甲", "hp": 10, "hp_max": 10, "online": true, "statuses": []},
		{"id": "stub_b", "name": "乙", "hp": 10, "hp_max": 10, "online": true, "statuses": []},
	]
	if srv.loot_catalog != null:
		srv.loot_catalog.rng_roll = func() -> float: return 0.0
	srv.npc_spawn_templates["ng_loot_slime"] = {
		"id": "ng_loot_slime",
		"charset": "retira_slime",
		"hostile": true,
	}
	var kill_acts: Array = srv._roll_and_grant_loot("ng_loot_slime", {"x": 6, "y": 6})
	var saw_start := false
	for ka in kill_acts:
		if typeof(ka) != TYPE_DICTIONARY:
			continue
		if str(ka.get("type", "")) == "loot_roll_start":
			saw_start = true
		if str(ka.get("type", "")) == "system_message" and str(ka.get("text", "")).find("开始掷骰") >= 0:
			saw_start = true
	if kill_acts.is_empty():
		print("  SKIP kill-path loot empty (table miss)")
	else:
		failed += _expect(saw_start or srv.loot_roll_count() > 0, "kill path opened roll")
		failed += _expect(srv.ground_bag_count() == 0 or srv.loot_roll_count() > 0, "no premature free bag without roll")
	if srv.loot_catalog != null:
		srv.loot_catalog.rng_roll = Callable()
	srv.debug_force_loot_roll_timeout("")

	# cleanup
	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""
	srv.loot_roll_rng_fn = Callable()


	# --- Client playable path: world request + HUD Need/Greed/Pass ---
	var world_src := FileAccess.get_file_as_string("res://scripts/game/world.gd")
	failed += _expect("func request_loot_roll" in world_src, "world request_loot_roll")
	failed += _expect("loot_roll_start" in world_src, "world handles loot_roll_start")
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	failed += _expect("func show_loot_roll" in hud_src, "hud show_loot_roll")
	failed += _expect("需求" in hud_src and "贪婪" in hud_src, "hud Need/Greed Chinese")
	failed += _expect("request_loot_roll" in hud_src or "try_loot_roll" in hud_src, "hud submits roll")

	if failed == 0:
		print("test_loot_roll: PASS")
		quit(0)
	else:
		print("test_loot_roll: FAIL count=%d" % failed)
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
