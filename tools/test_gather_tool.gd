extends SceneTree
## Headless: gather tool gate — herbs OK without tool; ore needs pickaxe (not consumed).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_gather_tool: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.gather_catalog == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_gather"), "has try_gather")
	failed += _expect(srv.gather_catalog != null, "gather_catalog")
	failed += _expect(srv.gather_catalog.has_node("herb_a"), "catalog herb_a")
	failed += _expect(srv.gather_catalog.has_node("ore_a"), "catalog ore_a")
	failed += _expect(srv.gather_catalog.has_node("ore_b"), "catalog ore_b")

	var ore_def: Dictionary = srv.gather_catalog.get_node("ore_a")
	failed += _expect(str(ore_def.get("tool", "")) == "tool_pickaxe", "ore_a tool=tool_pickaxe")
	var herb_def: Dictionary = srv.gather_catalog.get_node("herb_a")
	failed += _expect(not herb_def.has("tool") or str(herb_def.get("tool", "")).is_empty(), "herb_a tool-free")

	# Catalog item defs
	var ic = srv.item_catalog if "item_catalog" in srv else null
	if ic == null and srv.has_method("item_display_name"):
		pass
	failed += _expect(srv.item_display_name("tool_pickaxe").find("镐") >= 0, "pickaxe display name")
	failed += _expect(srv.item_display_name("iron_ore").find("铁矿") >= 0, "iron_ore display name")

	# Shop sells pickaxe
	var shop = srv.shop_catalog if "shop_catalog" in srv else null
	if shop != null and shop.has_method("get_shop"):
		var goods: Dictionary = shop.get_shop("starter_goods")
		var sold := false
		for row in goods.get("items", []):
			if typeof(row) == TYPE_DICTIONARY and str(row.get("item_id", "")) == "tool_pickaxe":
				sold = true
				break
		failed += _expect(sold, "starter_goods sells tool_pickaxe")
	else:
		# Fallback: load shops.json
		var JsonUtil = load("res://scripts/util/json_util.gd")
		var raw: Variant = JsonUtil.parse_data("combat/shops.json")
		var sold2 := false
		if typeof(raw) == TYPE_DICTIONARY:
			for row2 in raw["shops"]["starter_goods"]["items"]:
				if str(row2.get("item_id", "")) == "tool_pickaxe":
					sold2 = true
		failed += _expect(sold2, "starter_goods sells tool_pickaxe (json)")

	if srv.has_method("_load_pack"):
		srv._load_pack("res://demo_map")
	failed += _expect(srv._gather_nodes.has("herb_a"), "map herb_a")
	failed += _expect(srv._gather_nodes.has("ore_a"), "map ore_a")
	failed += _expect(srv._gather_nodes.has("ore_b"), "map ore_b")

	# Radar POI sample would list ore when present as gather rows
	var RadarPoi = load("res://scripts/ui/radar_poi.gd")
	var markers: Array = RadarPoi.build_markers({
		"npcs": [],
		"gather": [
			{"id": "herb_a", "cell": {"x": 10, "y": 22}, "depleted": false},
			{"id": "ore_a", "cell": {"x": 20, "y": 24}, "depleted": false},
			{"id": "ore_b", "cell": {"x": 22, "y": 22}, "depleted": false},
		],
		"fish": [],
	})
	var ids: Dictionary = {}
	for m in markers:
		ids[str(m.get("id", ""))] = true
	failed += _expect(ids.has("ore_a") and ids.has("ore_b"), "radar POI lists ore_*")
	failed += _expect(ids.has("herb_a"), "radar POI still lists herb")

	# --- Herb without tool still OK ---
	srv.force_gather_respawn("herb_a")
	srv.set_player_cell(10, 21)
	if srv.has_method("register_npc"):
		srv.register_npc("herb_a", 10, 22, false, false, 2, 0, 0, {
			"id": "herb_a", "name": "野生药草", "kind": "object",
		})
	srv.inventory.clear()
	srv.inventory.add_gold(10)
	var herb_ok: Dictionary = srv.try_gather("herb_a")
	failed += _expect(bool(herb_ok.get("ok", false)), "herb without tool OK")
	failed += _expect(str(herb_ok.get("reason", "")) != "need_tool", "herb not need_tool")

	# --- Ore without pickaxe fails need_tool ---
	srv.force_gather_respawn("ore_a")
	srv.set_player_cell(20, 23)
	if srv.has_method("register_npc"):
		srv.register_npc("ore_a", 20, 24, false, false, 2, 0, 0, {
			"id": "ore_a", "name": "铁矿脉", "kind": "object",
		})
	srv.inventory.clear()
	srv.inventory.add_gold(10)
	var no_tool: Dictionary = srv.try_gather("ore_a")
	failed += _expect(not bool(no_tool.get("ok", true)), "ore without pickaxe fails")
	failed += _expect(str(no_tool.get("reason", "")) == "need_tool", "reason need_tool")
	failed += _expect(_msg_has(no_tool, "需要工具："), "msg 需要工具：")
	failed += _expect(_msg_has(no_tool, "矿工镐") or _msg_has(no_tool, "镐"), "msg names pickaxe")
	failed += _expect(srv.inventory.get_qty("iron_ore") == 0, "no ore without tool")
	failed += _expect(not srv.is_gather_depleted("ore_a"), "ore not depleted on need_tool")

	# --- With pickaxe succeeds; qty unchanged ---
	srv.force_gather_respawn("ore_a")
	srv.inventory.clear()
	srv.inventory.add_gold(10)
	srv.inventory.add_item("tool_pickaxe", 1)
	failed += _expect(srv.inventory.get_qty("tool_pickaxe") == 1, "pickaxe in bag")
	var with_tool: Dictionary = srv.try_gather("ore_a")
	failed += _expect(bool(with_tool.get("ok", false)), "ore with pickaxe OK")
	failed += _expect(str(with_tool.get("item_id", "")) == "iron_ore", "yielded iron_ore")
	failed += _expect(int(with_tool.get("qty", 0)) >= 1, "yielded qty>=1")
	failed += _expect(srv.inventory.get_qty("tool_pickaxe") == 1, "pickaxe qty unchanged")
	failed += _expect(srv.inventory.get_qty("iron_ore") >= 1, "bag gained iron_ore")
	failed += _expect(srv.is_gather_depleted("ore_a"), "ore depleted after gather")
	failed += _expect(_msg_has(with_tool, "采集获得："), "msg 采集获得")

	if failed == 0:
		print("test_gather_tool: PASS")
		quit(0)
	else:
		print("test_gather_tool: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _msg_has(result: Dictionary, needle: String) -> bool:
	var acts: Array = result.get("actions", [])
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(needle) >= 0:
			return true
	return false
