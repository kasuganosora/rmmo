extends SceneTree
## Headless: craft profession level — gate recipes / XP / level-up.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_craft_skill: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.get("recipe_catalog") == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_craft"), "has try_craft")
	failed += _expect(srv.has_method("snapshot_craft"), "has snapshot_craft")
	failed += _expect("craft_level" in srv, "craft_level property")

	if srv.has_method("_reset_craft_skill"):
		srv._reset_craft_skill()
	else:
		srv.craft_level = 1
		srv.craft_xp = 0
		srv.craft_xp_to_next = 30

	var snap0: Dictionary = srv.snapshot_craft()
	failed += _expect(int(snap0.get("craft_level", -1)) == 1, "default craft_level 1")
	failed += _expect(int(snap0.get("craft_xp", -1)) == 0, "default craft_xp 0")
	failed += _expect(int(snap0.get("craft_xp_to_next", -1)) == 30, "xp_to_next 30 at lv1")

	# Recipe craft_level: leather_cap / copper_ring require 2; potions stay 1
	var cap_def: Dictionary = srv.recipe_catalog.get_recipe("craft_leather_cap")
	failed += _expect(int(cap_def.get("craft_level", 0)) == 2, "leather_cap craft_level 2")
	var ring_def: Dictionary = srv.recipe_catalog.get_recipe("craft_copper_ring")
	failed += _expect(int(ring_def.get("craft_level", 0)) == 2, "copper_ring craft_level 2")
	var pot_def: Dictionary = srv.recipe_catalog.get_recipe("craft_hp_potion")
	failed += _expect(int(pot_def.get("craft_level", 0)) == 1, "hp potion craft_level 1")

	# --- Level 1 cannot craft req-2 recipe ---
	srv.inventory.clear()
	srv.inventory.add_gold(200)
	srv.inventory.add_item("torn_cloth", 3)
	srv.inventory.add_item("monster_fang", 1)
	if srv.combat_stats != null:
		srv.combat_stats.reset_player(99)  # combat level must not bypass
	var blocked: Dictionary = srv.try_craft("craft_leather_cap", 1)
	failed += _expect(not bool(blocked.get("ok", true)), "lv1 cannot craft req-2")
	failed += _expect(str(blocked.get("reason", "")) == "craft_level", "reason craft_level")
	failed += _expect(_msg_has(blocked, "制作等级不足"), "msg 制作等级不足")
	failed += _expect(srv.inventory.get_qty("torn_cloth") == 3, "mats kept on gate fail")
	failed += _expect(int(srv.craft_xp) == 0, "no xp on gate fail")

	# --- Crafting grants xp ---
	srv.inventory.clear()
	srv.inventory.add_gold(200)
	srv.inventory.add_item("wild_herb", 2)
	var ok1: Dictionary = srv.try_craft("craft_hp_potion", 1)
	failed += _expect(bool(ok1.get("ok", false)), "basic craft ok")
	failed += _expect(int(srv.craft_xp) == 5, "xp +5 for qty1")
	failed += _expect(int(srv.craft_level) == 1, "still lv1 after 5 xp")
	failed += _expect(_has(ok1, "craft_update"), "craft_update action")

	srv.inventory.add_item("wild_herb", 4)
	var ok2: Dictionary = srv.try_craft("craft_hp_potion", 2)
	failed += _expect(bool(ok2.get("ok", false)), "qty2 craft ok")
	failed += _expect(int(srv.craft_xp) == 15, "xp +10 → 15 total")

	# --- Enough crafts level up (need 30 at lv1; have 15; need 15 more = 3 crafts) ---
	srv.inventory.clear()
	srv.inventory.add_gold(200)
	srv.inventory.add_item("wild_herb", 6)
	var ok3: Dictionary = srv.try_craft("craft_hp_potion", 3)
	failed += _expect(bool(ok3.get("ok", false)), "qty3 craft ok")
	failed += _expect(int(srv.craft_level) == 2, "leveled to 2")
	failed += _expect(int(srv.craft_xp) == 0, "xp leftover 0 after 30")
	failed += _expect(int(srv.craft_xp_to_next) == 40, "xp_to_next 40 at lv2")
	failed += _expect(_msg_has(ok3, "制作等级提升至 2"), "level-up system msg")

	# --- After level up, req-2 succeeds ---
	srv.inventory.clear()
	srv.inventory.add_gold(200)
	srv.inventory.add_item("torn_cloth", 3)
	srv.inventory.add_item("monster_fang", 1)
	var ok_cap: Dictionary = srv.try_craft("craft_leather_cap", 1)
	failed += _expect(bool(ok_cap.get("ok", false)), "req-2 succeeds after level up")
	failed += _expect(srv.inventory.get_qty("leather_cap") == 1, "leather_cap granted")
	failed += _expect(int(srv.craft_xp) == 5, "xp after cap craft")

	if failed == 0:
		print("test_craft_skill: PASS")
		quit(0)
		return
	print("test_craft_skill: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
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
