extends SceneTree
## Headless: gather profession level — gate nodes/spots / XP / level-up (shared gather+fish).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_gather_skill: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.gather_catalog == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.fish_catalog == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_gather"), "has try_gather")
	failed += _expect(srv.has_method("try_fish"), "has try_fish")
	failed += _expect(srv.has_method("snapshot_gather"), "has snapshot_gather")
	failed += _expect("gather_level" in srv, "gather_level property")

	if srv.has_method("_reset_gather_skill"):
		srv._reset_gather_skill()
	else:
		srv.gather_level = 1
		srv.gather_xp = 0
		srv.gather_xp_to_next = 30

	var snap0: Dictionary = srv.snapshot_gather()
	failed += _expect(int(snap0.get("gather_level", -1)) == 1, "default gather_level 1")
	failed += _expect(int(snap0.get("gather_xp", -1)) == 0, "default gather_xp 0")
	failed += _expect(int(snap0.get("gather_xp_to_next", -1)) == 30, "xp_to_next 30 at lv1")

	# Catalog reqs: ore_b / fish_pond_b = 2; herbs / ore_a / fish_pond_a = 1
	var ore_b: Dictionary = srv.gather_catalog.get_node("ore_b")
	failed += _expect(int(ore_b.get("gather_level", 0)) == 2, "ore_b gather_level 2")
	var ore_a: Dictionary = srv.gather_catalog.get_node("ore_a")
	failed += _expect(int(ore_a.get("gather_level", 0)) == 1, "ore_a gather_level 1")
	var herb: Dictionary = srv.gather_catalog.get_node("herb_a")
	failed += _expect(int(herb.get("gather_level", 0)) == 1, "herb_a gather_level 1")
	var pond_b: Dictionary = srv.fish_catalog.get_spot("fish_pond_b")
	failed += _expect(int(pond_b.get("gather_level", 0)) == 2, "fish_pond_b gather_level 2")
	var pond_a: Dictionary = srv.fish_catalog.get_spot("fish_pond_a")
	failed += _expect(int(pond_a.get("gather_level", 0)) == 1, "fish_pond_a gather_level 1")

	if srv.has_method("_load_pack"):
		srv._load_pack("res://demo_map")
	failed += _expect(srv._gather_nodes.has("herb_a"), "map herb_a")
	failed += _expect(srv._gather_nodes.has("ore_b"), "map ore_b")
	failed += _expect(srv._fish_spots.has("fish_pond_a"), "map fish_pond_a")
	failed += _expect(srv._fish_spots.has("fish_pond_b"), "map fish_pond_b")

	# --- Lv1 cannot gather ore_b (req 2) even with pickaxe ---
	if srv.has_method("force_gather_respawn"):
		srv.force_gather_respawn("ore_b")
	srv.set_player_cell(22, 21)
	if srv.has_method("register_npc"):
		srv.register_npc("ore_b", 22, 22, false, false, 2, 0, 0, {
			"id": "ore_b", "name": "铁矿脉", "kind": "object",
		})
	srv.inventory.clear()
	srv.inventory.add_gold(50)
	srv.inventory.add_item("tool_pickaxe", 1)
	if srv.combat_stats != null and srv.combat_stats.has_method("reset_player"):
		srv.combat_stats.reset_player(99)
	var blocked: Dictionary = srv.try_gather("ore_b")
	failed += _expect(not bool(blocked.get("ok", true)), "lv1 cannot gather ore_b req-2")
	failed += _expect(str(blocked.get("reason", "")) == "gather_level", "reason gather_level")
	failed += _expect(_msg_has(blocked, "采集等级不足"), "msg 采集等级不足")
	failed += _expect(srv.inventory.get_qty("iron_ore") == 0, "no ore on gate fail")
	failed += _expect(int(srv.gather_xp) == 0, "no xp on gate fail")

	# --- Lv1 cannot fish fish_pond_b ---
	if srv.has_method("force_fish_respawn"):
		srv.force_fish_respawn("fish_pond_b")
	srv._fish_busy_until = 0.0
	srv.set_player_cell(18, 10)
	if srv.has_method("register_npc"):
		srv.register_npc("fish_pond_b", 18, 11, false, false, 2, 0, 0, {
			"id": "fish_pond_b", "name": "浅水塘", "kind": "object",
		})
	var blocked_f: Dictionary = srv.try_fish("fish_pond_b")
	failed += _expect(not bool(blocked_f.get("ok", true)), "lv1 cannot fish pond_b req-2")
	failed += _expect(str(blocked_f.get("reason", "")) == "gather_level", "fish reason gather_level")

	# --- Herb gather grants +5 xp + gather_update skill packet ---
	if srv.has_method("force_gather_respawn"):
		srv.force_gather_respawn("herb_a")
	srv.set_player_cell(10, 21)
	if srv.has_method("register_npc"):
		srv.register_npc("herb_a", 10, 22, false, false, 2, 0, 0, {
			"id": "herb_a", "name": "野生药草", "kind": "object",
		})
	srv.inventory.clear()
	srv.inventory.add_gold(10)
	var ok1: Dictionary = srv.try_gather("herb_a")
	failed += _expect(bool(ok1.get("ok", false)), "herb gather ok")
	failed += _expect(int(srv.gather_xp) == 5, "xp +5 for gather")
	failed += _expect(int(srv.gather_level) == 1, "still lv1 after 5 xp")
	failed += _expect(_has_skill_update(ok1), "gather_update skill action")

	# --- Fish also shares gather_level XP ---
	if srv.has_method("force_fish_respawn"):
		srv.force_fish_respawn("fish_pond_a")
	srv._fish_busy_until = 0.0
	srv.set_player_cell(16, 10)
	if srv.has_method("register_npc"):
		srv.register_npc("fish_pond_a", 16, 11, false, false, 2, 0, 0, {
			"id": "fish_pond_a", "name": "小水塘", "kind": "object",
		})
	var ok_f: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(bool(ok_f.get("ok", false)), "fish ok shares gather xp")
	failed += _expect(int(srv.gather_xp) == 10, "xp +5 fish → 10 total")
	failed += _expect(_has_skill_update(ok_f), "fish emits gather_update skill")

	# --- Level up: need 30 at lv1; have 10; need 20 more = 4 gathers ---
	var ok_i: Dictionary = {}
	for i in range(4):
		if srv.has_method("force_gather_respawn"):
			srv.force_gather_respawn("herb_a")
		srv.set_player_cell(10, 21)
		srv.inventory.clear()
		srv.inventory.add_gold(10)
		ok_i = srv.try_gather("herb_a")
		failed += _expect(bool(ok_i.get("ok", false)), "level-up gather %d ok" % (i + 1))

	failed += _expect(int(srv.gather_level) == 2, "leveled to 2")
	failed += _expect(int(srv.gather_xp) == 0, "xp leftover 0 after 30")
	failed += _expect(int(srv.gather_xp_to_next) == 40, "xp_to_next 40 at lv2")
	# Last gather should have carried the level-up message
	failed += _expect(_msg_has(ok_i, "采集等级提升至 2"), "level-up system msg")

	# --- After level up, ore_b + fish_pond_b succeed ---
	if srv.has_method("force_gather_respawn"):
		srv.force_gather_respawn("ore_b")
	srv.set_player_cell(22, 21)
	srv.inventory.clear()
	srv.inventory.add_gold(50)
	srv.inventory.add_item("tool_pickaxe", 1)
	var ok_ore: Dictionary = srv.try_gather("ore_b")
	failed += _expect(bool(ok_ore.get("ok", false)), "req-2 ore succeeds after level up")
	failed += _expect(srv.inventory.get_qty("iron_ore") >= 1, "iron_ore granted")
	failed += _expect(int(srv.gather_xp) == 5, "xp after ore")

	if srv.has_method("force_fish_respawn"):
		srv.force_fish_respawn("fish_pond_b")
	srv._fish_busy_until = 0.0
	srv.set_player_cell(18, 10)
	var ok_fb: Dictionary = srv.try_fish("fish_pond_b")
	failed += _expect(bool(ok_fb.get("ok", false)), "req-2 fish succeeds after level up")

	if failed == 0:
		print("test_gather_skill: PASS")
		quit(0)
		return
	print("test_gather_skill: FAIL count=%d" % failed)
	quit(1)


func _has_skill_update(result: Dictionary) -> bool:
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "gather_update":
			continue
		if a.has("gather_level"):
			return true
	return false


func _msg_has(result: Dictionary, needle: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if needle in str(a.get("text", "")):
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
