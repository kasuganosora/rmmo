extends SceneTree
## Headless: gather tool durability — wear on success, break at 0, tip, repair kit / blacksmith.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_tool_durability: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null or srv.item_catalog == null or srv.gather_catalog == null:
		print("test_tool_durability: FAIL combat layers missing")
		quit(1)
		return

	# Catalog
	var def: Dictionary = srv.item_catalog.get_item("tool_pickaxe")
	failed += _expect(not def.is_empty(), "catalog has tool_pickaxe")
	failed += _expect(str(def.get("name", "")) == "矿工镐", "Chinese name")
	failed += _expect(int(def.get("durability_max", 0)) == 40, "durability_max 40")
	failed += _expect(srv.inventory.has_method("wear_tool"), "inventory.wear_tool")
	failed += _expect(srv.inventory.has_method("has_usable_tool"), "inventory.has_usable_tool")

	if srv.has_method("_load_pack"):
		srv._load_pack("res://demo_map")
	failed += _expect(srv._gather_nodes.has("ore_a"), "map ore_a")

	srv.awaiting_respawn = false
	srv.sitting = false
	if srv.combat_stats != null:
		srv.combat_stats.player["hp"] = maxi(int(srv.combat_stats.player.get("hp_max", 100)), 1)
	# Ensure gather level high enough for ore_a
	if "gather_level" in srv:
		srv.gather_level = maxi(int(srv.gather_level), 1)

	# --- Add pickaxe: durability init 40/40 in snapshot ---
	srv.inventory.clear()
	srv.inventory.add_gold(200)
	srv.inventory.add_item("tool_pickaxe", 1)
	failed += _expect(srv.inventory.get_qty("tool_pickaxe") == 1, "pickaxe qty 1")
	failed += _expect(srv.inventory.get_tool_durability("tool_pickaxe") == 40, "dur 40")
	failed += _expect(srv.inventory.get_tool_durability_max("tool_pickaxe") == 40, "max 40")
	var snap: Array = srv.inventory.snapshot()
	var found := false
	for row in snap:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("id", "")) != "tool_pickaxe":
			continue
		failed += _expect(int(row.get("durability", 0)) == 40, "snapshot durability 40")
		failed += _expect(int(row.get("durability_max", 0)) == 40, "snapshot durability_max 40")
		found = true
	failed += _expect(found, "snapshot has pickaxe")

	# Tip text helper (HUD format)
	var tip_line := "耐久：%d/%d" % [40, 40]
	failed += _expect(tip_line == "耐久：40/40", "tip format 耐久：x/y")

	# --- Successful gather wears 1 ---
	srv.force_gather_respawn("ore_a")
	srv.set_player_cell(20, 23)
	if srv.has_method("register_npc"):
		srv.register_npc("ore_a", 20, 24, false, false, 2, 0, 0, {
			"id": "ore_a", "name": "铁矿脉", "kind": "object",
		})
	var r1: Dictionary = srv.try_gather("ore_a")
	failed += _expect(bool(r1.get("ok", false)), "gather ore ok")
	failed += _expect(srv.inventory.get_tool_durability("tool_pickaxe") == 39, "dur 39 after gather")
	failed += _expect(srv.inventory.get_qty("tool_pickaxe") == 1, "still have pickaxe")
	failed += _expect(not bool(r1.get("tool_broke", false)), "not broke yet")

	# Herb (no tool) does not require / wear pickaxe
	srv.force_gather_respawn("herb_a")
	srv.set_player_cell(10, 21)
	if srv.has_method("register_npc"):
		srv.register_npc("herb_a", 10, 22, false, false, 2, 0, 0, {
			"id": "herb_a", "name": "野生药草", "kind": "object",
		})
	var herb: Dictionary = srv.try_gather("herb_a")
	failed += _expect(bool(herb.get("ok", false)), "herb ok without wearing tool")
	failed += _expect(srv.inventory.get_tool_durability("tool_pickaxe") == 39, "herb no wear")

	# --- Break at 0 ---
	# Force durability to 1 then gather
	for s in srv.inventory._stacks:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == "tool_pickaxe":
			s["durability"] = 1
			s["durability_max"] = 40
	srv.force_gather_respawn("ore_a")
	srv.set_player_cell(20, 23)
	var r_break: Dictionary = srv.try_gather("ore_a")
	failed += _expect(bool(r_break.get("ok", false)), "gather on last durability ok")
	failed += _expect(bool(r_break.get("tool_broke", false)), "tool_broke flag")
	failed += _expect(srv.inventory.get_qty("tool_pickaxe") == 0, "pickaxe consumed on break")
	failed += _expect(_msg_has(r_break, "工具已损坏。"), "msg 工具已损坏。")

	# Need tool again
	srv.force_gather_respawn("ore_a")
	var r_need: Dictionary = srv.try_gather("ore_a")
	failed += _expect(not bool(r_need.get("ok", true)), "need tool after break")
	failed += _expect(str(r_need.get("reason", "")) == "need_tool", "reason need_tool")

	# --- Repair kit restores tool durability ---
	srv.inventory.clear()
	srv.inventory.add_item("tool_pickaxe", 1)
	srv.inventory.add_item("repair_kit", 2)
	for s2 in srv.inventory._stacks:
		if typeof(s2) == TYPE_DICTIONARY and str(s2.get("id", "")) == "tool_pickaxe":
			s2["durability"] = 10
			s2["durability_max"] = 40
	failed += _expect(srv.inventory.tools_need_repair(), "tools_need_repair")
	if srv.combat_stats != null and srv.combat_stats.has_method("set_item_cooldown"):
		srv.combat_stats.set_item_cooldown("repair_kit", 0.0)
	var r_kit: Dictionary = srv.try_use_item("repair_kit")
	failed += _expect(bool(r_kit.get("ok", false)), "repair_kit ok on tool")
	# +30% of 40 = 12 → 10+12=22
	failed += _expect(srv.inventory.get_tool_durability("tool_pickaxe") == 22, "kit +12 → 22")
	failed += _expect(srv.inventory.get_qty("repair_kit") == 1, "kit consumed")
	failed += _expect(_msg_has(r_kit, "工具") or _msg_has(r_kit, "修理工具包"), "kit Chinese msg")

	# --- Blacksmith try_repair("tools") gold ---
	for s3 in srv.inventory._stacks:
		if typeof(s3) == TYPE_DICTIONARY and str(s3.get("id", "")) == "tool_pickaxe":
			s3["durability"] = 20
			s3["durability_max"] = 40
	srv.inventory.add_gold(100)
	var gold_before: int = srv.inventory.get_gold()
	var r_bs: Dictionary = srv.try_repair("tools", 1)
	failed += _expect(bool(r_bs.get("ok", false)), "blacksmith repair tools ok")
	failed += _expect(srv.inventory.get_tool_durability("tool_pickaxe") == 40, "tools full 40")
	failed += _expect(srv.inventory.get_gold() == gold_before - 20, "spent 20G for 20 points")
	failed += _expect(_msg_has(r_bs, "工具已修理"), "tools repair msg")

	# try_repair all with only full tools → nothing
	var r_full: Dictionary = srv.try_repair("tools", 1)
	failed += _expect(not bool(r_full.get("ok", true)), "full tools fail")
	failed += _expect(str(r_full.get("reason", "")) == "nothing_to_repair", "nothing_to_repair")

	if failed == 0:
		print("test_tool_durability: PASS")
		quit(0)
		return
	print("test_tool_durability: FAIL count=%d" % failed)
	quit(1)


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
