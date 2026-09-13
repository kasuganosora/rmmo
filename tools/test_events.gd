extends SceneTree
## Headless: MV-inspired EventRuntime + MockServer chest/switch/door/touch.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var EventRuntime = load("res://scripts/net/combat/event_runtime.gd")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")

	# --- Pack loads events.json ---
	var pack = TilemapPack.load_pack("res://demo_map")
	failed += _expect(pack != null and pack.collision != null, "demo pack loads")
	failed += _expect(typeof(pack.events) == TYPE_ARRAY and pack.events.size() >= 5, "pack.events >= 5")

	var rt = EventRuntime.new()
	rt.load_from_pack(pack)
	failed += _expect(rt.has_event("chest_a"), "has chest_a")
	failed += _expect(rt.has_event("switch"), "has switch")
	failed += _expect(rt.has_event("door"), "has door")
	failed += _expect(rt.has_event("pc"), "has pc")
	failed += _expect(rt.has_event("mat_touch"), "has mat_touch")
	var mat: Dictionary = rt.get_event("mat_touch")
	failed += _expect(str(mat.get("trigger", "")) == "player_touch", "mat trigger player_touch")

	# Minimal inventory stub for give_item / give_gold
	var Inventory = load("res://scripts/net/combat/inventory.gd")
	var ItemCatalog = load("res://scripts/net/combat/item_catalog.gd")
	var inv = Inventory.new()
	var cat = ItemCatalog.new()
	cat.load_catalog()
	inv.set_catalog(cat)
	inv.clear()
	inv.grant_starter()
	var gold0: int = inv.get_gold()
	var pot0: int = inv.get_qty("potion_hp_small")

	var ctx := {
		"inventory": inv,
		"shop_catalog": null,
		"npc_name": "宝箱",
		"transfer_cb": Callable(self, "_stub_transfer"),
		"item_name_cb": func(id: String) -> String: return id,
	}

	# --- chest_a twice ---
	var acts1: Array = rt.run_event("chest_a", ctx)
	failed += _expect(not acts1.is_empty(), "chest first run actions")
	var has_dlg := false
	var has_inv := false
	for a in acts1:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t == "show_npc_dialogue" and str(a.get("body", "")).find("打开了宝箱") >= 0:
			has_dlg = true
		if t == "inventory_update":
			has_inv = true
	failed += _expect(has_dlg, "chest dialogue open")
	failed += _expect(has_inv, "chest inventory_update")
	failed += _expect(inv.get_qty("potion_hp_small") == pot0 + 2, "chest +2 potions")
	failed += _expect(inv.get_gold() == gold0 + 20, "chest +20 gold")
	failed += _expect(rt.get_self_switch("chest_a", "A"), "chest self_switch A")

	var acts2: Array = rt.run_event("chest_a", ctx)
	failed += _expect(acts2.size() >= 1, "chest second page")
	var empty_dlg := false
	for a in acts2:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type")) == "show_npc_dialogue":
			if str(a.get("body", "")).find("空的宝箱") >= 0:
				empty_dlg = true
	failed += _expect(empty_dlg, "chest empty dialogue")
	failed += _expect(inv.get_qty("potion_hp_small") == pot0 + 2, "chest no double loot")

	# --- switch then door transfer ---
	var acts_sw: Array = rt.run_event("switch", ctx)
	failed += _expect(rt.get_switch("demo_door_open"), "global switch demo_door_open")
	failed += _expect(rt.get_self_switch("switch", "A"), "switch self A")
	var sw_text := false
	for a in acts_sw:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type")) == "show_npc_dialogue":
			if str(a.get("body", "")).find("开关") >= 0:
				sw_text = true
	failed += _expect(sw_text, "switch dialogue")

	# Door closed page before switch would be different; after switch → transfer.
	_last_transfer = {}
	var acts_door: Array = rt.run_event("door", ctx)
	var has_xfer := false
	for a in acts_door:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type")) == "map_transfer" and bool(a.get("ok", false)):
			has_xfer = true
			failed += _expect(str(a.get("pack_path", "")).find("street_map") >= 0, "transfer pack street_map")
			var cell_v: Variant = a.get("cell", {})
			failed += _expect(typeof(cell_v) == TYPE_DICTIONARY, "transfer cell dict")
			if typeof(cell_v) == TYPE_DICTIONARY:
				failed += _expect(int(cell_v.get("x", -1)) == 41 and int(cell_v.get("y", -1)) == 23, "transfer cell 41,23")
			failed += _expect(int(a.get("facing", 0)) == 4, "transfer facing 4")
	failed += _expect(has_xfer, "door emits map_transfer")
	failed += _expect(bool(_last_transfer.get("ok", false)), "stub transfer called")

	# --- player_touch mat ---
	rt.set_map_id("demo_map")
	var touch1: Array = rt.run_event("mat_touch", ctx)
	var touch_msg := false
	for a in touch1:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type")) == "system_message":
			if str(a.get("text", "")).find("地毯") >= 0:
				touch_msg = true
	failed += _expect(touch_msg, "mat system_message")
	failed += _expect(rt.get_self_switch("mat_touch", "A"), "mat self A")
	var touch2: Array = rt.run_event("mat_touch", ctx)
	failed += _expect(touch2.is_empty(), "mat second page empty")

	# --- MockServer integration ---
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_events: FAIL no MockServer")
		quit(1)
		return
	if srv.event_runtime == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.event_runtime != null, "server event_runtime")
	failed += _expect(srv.has_method("try_event_choice"), "try_event_choice")
	# Reload demo + register chest NPC adjacent to player.
	srv._load_pack("res://demo_map")
	srv.event_runtime.clear_session()
	# Re-load events after clear_session (defs remain; switches cleared).
	if srv.event_runtime.events_by_id.is_empty():
		srv.event_runtime.load_from_pack(pack)
	srv.set_player_cell(9, 21)  # adjacent to chest_a at 9,22
	if srv.combat_stats == null:
		srv._init_combat_layers()
	srv.register_npc("chest_a", 9, 22, false, false, 2, 0, 0, {"id": "chest_a", "name": "宝箱", "interact_text": "fallback"})
	var ir: Dictionary = srv.try_interact("chest_a", 9, 21)
	failed += _expect(bool(ir.get("ok", false)), "server try_interact chest ok")
	var ia: Array = ir.get("actions", [])
	var server_chest_open := false
	for a in ia:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type")) == "show_npc_dialogue":
			if str(a.get("body", "")).find("打开了宝箱") >= 0:
				server_chest_open = true
	failed += _expect(server_chest_open, "server chest uses event not fallback")
	failed += _expect(srv.event_runtime.get_self_switch("chest_a", "A"), "server chest self A")

	# player_touch via try_move onto mat
	srv.set_player_cell(16, 13)
	# dir 8 = up → 16,12
	var mr: Dictionary = srv.try_move(16, 13, 8)
	failed += _expect(bool(mr.get("ok", false)), "try_move onto mat")
	var ma: Array = mr.get("actions", [])
	var mat_via_move := false
	for a in ma:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type")) == "system_message":
			if str(a.get("text", "")).find("地毯") >= 0:
				mat_via_move = true
	failed += _expect(mat_via_move, "try_move player_touch mat")

	# switch + door via server
	srv.set_player_cell(14, 17)
	srv.register_npc("switch", 14, 18, false, false, 2, 0, 0, {"id": "switch", "name": "开关"})
	var sr: Dictionary = srv.try_interact("switch", 14, 17)
	failed += _expect(bool(sr.get("ok", false)), "server switch ok")
	failed += _expect(srv.event_runtime.get_switch("demo_door_open"), "server demo_door_open")

	srv.set_player_cell(15, 9)
	srv.register_npc("door", 15, 8, false, false, 2, 0, 0, {"id": "door", "name": "门"})
	var dr: Dictionary = srv.try_interact("door", 15, 9)
	failed += _expect(bool(dr.get("ok", false)), "server door ok")
	var door_xfer := false
	for a in dr.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type")) == "map_transfer":
			door_xfer = bool(a.get("ok", false))
	failed += _expect(door_xfer, "server door map_transfer")
	failed += _expect(str(srv.map_pack_id).find("street") >= 0 or str(srv.map_pack_path).find("street") >= 0, "server now on street pack")

	if failed == 0:
		print("test_events: PASS")
		quit(0)
	else:
		print("test_events: FAIL count=%d" % failed)
		quit(1)


var _last_transfer: Dictionary = {}


func _stub_transfer(to_pack: String, to_cell: Dictionary, facing: int = 2, message: String = "", to_map_id: String = "") -> Dictionary:
	_last_transfer = {
		"ok": true,
		"pack_path": to_pack,
		"map_id": to_map_id if to_map_id != "" else to_pack.get_file(),
		"cell": {"x": int(to_cell.get("x", 0)), "y": int(to_cell.get("y", 0))},
		"facing": facing,
		"message": message,
	}
	return _last_transfer


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
