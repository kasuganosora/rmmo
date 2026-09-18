extends SceneTree
## Headless: MockServer try_craft — missing mats / success / qty>1 / bag_full.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_craft: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.get("recipe_catalog") == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_craft"), "has try_craft")
	failed += _expect(srv.get("recipe_catalog") != null, "recipe_catalog loaded")
	var recipes: Array = []
	if srv.recipe_catalog != null and srv.recipe_catalog.has_method("list_all"):
		recipes = srv.recipe_catalog.list_all()
	failed += _expect(recipes.size() >= 3, "at least 3 recipes (%d)" % recipes.size())
	failed += _expect(srv.recipe_catalog.has_recipe("craft_hp_potion"), "has craft_hp_potion")

	# --- missing mats ---
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	var miss: Dictionary = srv.try_craft("craft_hp_potion", 1)
	failed += _expect(not bool(miss.get("ok", true)), "missing mats fails")
	failed += _expect(str(miss.get("reason", "")) == "missing_mats", "reason missing_mats")
	failed += _expect(_msg_has(miss, "材料不足"), "msg 材料不足")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 0, "no potion on fail")

	# --- success ---
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	srv.inventory.add_item("wild_herb", 2)
	var ok1: Dictionary = srv.try_craft("craft_hp_potion", 1)
	failed += _expect(bool(ok1.get("ok", false)), "craft success")
	failed += _expect(srv.inventory.get_qty("wild_herb") == 0, "herbs consumed")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 1, "potion granted")
	failed += _expect(srv.inventory.get_gold() == 98, "gold cost 2")
	failed += _expect(_has(ok1, "inventory_update"), "inventory_update")
	failed += _expect(_msg_has(ok1, "制作成功"), "msg 制作成功")

	# --- qty > 1 ---
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	srv.inventory.add_item("wild_herb", 6)
	var ok3: Dictionary = srv.try_craft("craft_hp_potion", 3)
	failed += _expect(bool(ok3.get("ok", false)), "qty=3 success")
	failed += _expect(srv.inventory.get_qty("wild_herb") == 0, "qty=3 herbs gone")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 3, "qty=3 potions")
	failed += _expect(srv.inventory.get_gold() == 94, "qty=3 gold 6")
	failed += _expect(_msg_has(ok3, "×3"), "msg shows ×3")

	# qty>1 missing mats (partial) — all-or-nothing
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	srv.inventory.add_item("wild_herb", 4)  # need 6 for qty=3
	var partial: Dictionary = srv.try_craft("craft_hp_potion", 3)
	failed += _expect(not bool(partial.get("ok", true)), "qty=3 missing mats")
	failed += _expect(srv.inventory.get_qty("wild_herb") == 4, "mats untouched on fail")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 0, "no output on fail")

	# --- bag full / stack full ---
	# Leave leftover herbs in-slot after consume so no free slot opens for a new potion stack.
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	srv.inventory.max_slots = 2
	srv.inventory.add_item("wild_herb", 4)  # consume 2 → 2 left, slot stays
	srv.inventory.add_item("potion_hp_small", 20)  # stack_max 20 — full stack
	var full: Dictionary = srv.try_craft("craft_hp_potion", 1)
	failed += _expect(not bool(full.get("ok", true)), "bag/stack full fails")
	failed += _expect(str(full.get("reason", "")) == "bag_full", "reason bag_full")
	failed += _expect(_msg_has(full, "背包已满"), "msg 背包已满")
	failed += _expect(srv.inventory.get_qty("wild_herb") == 4, "mats restored")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 20, "stack unchanged")
	failed += _expect(srv.inventory.get_gold() == 100, "gold restored")
	srv.inventory.max_slots = 40

	# --- unknown recipe ---
	var unk: Dictionary = srv.try_craft("no_such_recipe", 1)
	failed += _expect(not bool(unk.get("ok", true)), "unknown recipe fails")
	failed += _expect(str(unk.get("reason", "")) == "unknown_recipe", "reason unknown_recipe")

	# --- multi-ingredient success ---
	srv.inventory.clear()
	srv.inventory.add_gold(50)
	srv.inventory.add_item("wild_herb", 1)
	srv.inventory.add_item("slime_jelly", 1)
	var mp: Dictionary = srv.try_craft("craft_mp_potion", 1)
	failed += _expect(bool(mp.get("ok", false)), "mp potion craft")
	failed += _expect(srv.inventory.get_qty("potion_mp_small") == 1, "mp potion granted")
	failed += _expect(srv.inventory.get_qty("wild_herb") == 0, "mp herbs gone")
	failed += _expect(srv.inventory.get_qty("slime_jelly") == 0, "jelly gone")

	# --- craft_level gate (copper ring needs craft Lv.2; combat level irrelevant) ---
	if srv.has_method("_reset_craft_skill"):
		srv._reset_craft_skill()
	else:
		srv.craft_level = 1
		srv.craft_xp = 0
		srv.craft_xp_to_next = 30
	if srv.combat_stats != null:
		srv.combat_stats.reset_player(1)
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	srv.inventory.add_item("rusty_coin", 5)
	srv.inventory.add_item("monster_fang", 1)
	var low: Dictionary = srv.try_craft("craft_copper_ring", 1)
	failed += _expect(not bool(low.get("ok", true)), "craft gate fails at craft lv1")
	failed += _expect(str(low.get("reason", "")) == "craft_level", "reason craft_level")
	failed += _expect(_msg_has(low, "制作等级不足"), "msg 制作等级不足")
	# Combat level 99 still blocked at craft_level 1
	if srv.combat_stats != null:
		srv.combat_stats.reset_player(99)
	var still: Dictionary = srv.try_craft("craft_copper_ring", 1)
	failed += _expect(not bool(still.get("ok", true)), "combat lv irrelevant")
	srv.craft_level = 2
	srv.craft_xp_to_next = 20 + 2 * 10
	var high: Dictionary = srv.try_craft("craft_copper_ring", 1)
	failed += _expect(bool(high.get("ok", false)), "craft gate ok at craft lv2")
	failed += _expect(srv.inventory.get_qty("copper_ring") == 1, "ring granted")

	# --- no gold ---
	srv.inventory.clear()
	srv.inventory.add_gold(0)
	srv.inventory.add_item("wild_herb", 2)
	var nog: Dictionary = srv.try_craft("craft_hp_potion", 1)
	failed += _expect(not bool(nog.get("ok", true)), "no gold fails")
	failed += _expect(str(nog.get("reason", "")) == "no_gold", "reason no_gold")
	failed += _expect(srv.inventory.get_qty("wild_herb") == 2, "mats kept without gold")

	if failed == 0:
		print("test_craft: PASS")
		quit(0)
		return
	print("test_craft: FAIL count=%d" % failed)
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
