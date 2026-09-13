extends SceneTree
## Plan acceptance: pack tree, assets/slots, warp/event/npc, zip roundtrip, EventRuntime.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var PackZip = load("res://scripts/editor/pack_zip.gd")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var EventRuntime = load("res://scripts/net/combat/event_runtime.gd")
	var root := "user://content/packs/plan_test_pack"
	_wipe(root)
	_wipe("user://content/packs/plan_test_pack_imp")
	var pack = ContentPack.new()
	pack.new_blank("plan_test_pack", "计划验收包", 16, 16)
	failed += _expect(pack.add_map("Hall", "大厅", "", 16, 16), "add Hall")
	failed += _expect(pack.add_map("Room", "房间", "Hall", 12, 12), "add Room under Hall")
	failed += _expect(pack.set_parent("Room", "Hall"), "parent Room->Hall")
	failed += _expect(not pack.set_parent("Hall", "Room"), "reject cycle")
	var hall = pack.get_map("Hall")
	hall.set_tile(3, 4, 0, 2816, false)
	var png := "user://content/packs/_tiny_floor.png"
	_write_png(png)
	if pack.root.is_empty():
		pack.root = ContentPack.pack_dir_for(pack.pack_id)
	var sheet_id: String = pack.import_asset_file(png, "tilesheet")
	failed += _expect(sheet_id != "", "import tilesheet id")
	var ogg := "user://content/packs/_tiny.ogg"
	var of := FileAccess.open(ogg, FileAccess.WRITE)
	of.store_buffer(PackedByteArray([0, 1, 2, 3]))
	var audio_id: String = pack.import_asset_file(ogg, "audio")
	failed += _expect(audio_id != "", "import audio id")
	var cs := "user://content/packs/_tiny_char.png"
	_write_png(cs)
	var char_id: String = pack.import_asset_file(cs, "charset")
	failed += _expect(char_id != "", "import charset id")
	var ts_id := str(hall.tileset_id)
	failed += _expect(pack.set_tileset_slot(ts_id, 4, sheet_id), "assign A5 slot")
	hall.add_warp(Vector2i(5, 5), "Room", Vector2i(2, 2), 8)
	hall.add_event(Vector2i(6, 6), "打开了宝箱！")
	var evs: Array = hall.events
	if not evs.is_empty() and typeof(evs[0]) == TYPE_DICTIONARY:
		var pages: Array = evs[0].get("pages", [])
		if not pages.is_empty() and typeof(pages[0]) == TYPE_DICTIONARY:
			pages[0]["commands"] = [
				{"op": "text", "text": "打开了宝箱！"},
				{"op": "give_item", "item_id": "potion_hp_small", "qty": 1},
				{"op": "give_gold", "amount": 10},
				{"op": "set_switch", "id": "chest_hall", "value": true},
				{"op": "set_self_switch", "letter": "A", "value": true},
				{"op": "open_shop", "shop_id": "general"},
				{"op": "transfer", "to_map": "Room", "to_cell": {"x": 2, "y": 2}},
			]
	hall.add_npc(Vector2i(7, 7), char_id, "向导")
	failed += _expect(pack.save_dir(root), "save_dir")
	failed += _expect(not pack.map_is_dirty("Hall"), "dirty cleared after save")
	var listed: Array = ContentPack.list_user_packs()
	var listed_ok := false
	for lp in listed:
		if typeof(lp) == TYPE_DICTIONARY and str(lp.get("id", "")) == "plan_test_pack":
			listed_ok = true
	failed += _expect(listed_ok, "list_user_packs includes pack")
	failed += _expect(pack.save_as("plan_test_pack_as", "另存"), "save_as")
	failed += _expect(str(pack.pack_id) == "plan_test_pack_as", "save_as id")
	failed += _expect(not str(pack.root).begins_with("res://"), "save_as still user://")
	var names: Array = pack.tilesets[ts_id].get("tilesetNames", [])
	failed += _expect(str(names[4]) == sheet_id, "saved tilesetNames A5")
	var sheet_path := root + "/assets/tilesheet/" + sheet_id + ".png"
	failed += _expect(FileAccess.file_exists(sheet_path) or FileAccess.file_exists(ProjectSettings.globalize_path(sheet_path)), "tilesheet file in pack")
	var zip_path := "user://content/packs/plan_test_pack.rmpack"
	failed += _expect(PackZip.export_zip(root, zip_path), "export zip")
	var dest := "user://content/packs/plan_test_pack_imp"
	var imp: Dictionary = PackZip.import_zip(zip_path, dest)
	failed += _expect(bool(imp.get("ok", false)), "import zip ok")
	var pack2 = ContentPack.new()
	failed += _expect(pack2.load_dir(dest), "load imported pack")
	failed += _expect(pack2.maps.has("Hall") and pack2.maps.has("Room"), "imported two maps")
	failed += _expect(str(pack2.get_map("Room").parent_id) == "Hall" or _parent_of(pack2, "Room") == "Hall", "imported parent")
	var hall2 = pack2.get_map("Hall")
	failed += _expect(int(hall2.tile(3, 4, 0)) == 2816, "imported painted tile")
	failed += _expect(not hall2.warps.is_empty(), "imported warp")
	if not hall2.warps.is_empty():
		var w: Dictionary = hall2.warps[0]
		failed += _expect(str(w.get("to_map", w.get("to_map_id", ""))) == "Room", "warp to_map Room")
	failed += _expect(not hall2.events.is_empty(), "imported event")
	failed += _expect(not hall2.npcs.is_empty(), "imported npc")
	if not hall2.npcs.is_empty():
		failed += _expect(str(hall2.npcs[0].get("charset", "")) == char_id, "npc charset")
	var names2: Array = pack2.tilesets[ts_id].get("tilesetNames", []) if pack2.tilesets.has(ts_id) else []
	failed += _expect(str(names2[4]) == sheet_id, "imported slot A5")
	var imp_sheet := dest + "/assets/tilesheet/" + sheet_id + ".png"
	failed += _expect(FileAccess.file_exists(imp_sheet) or FileAccess.file_exists(ProjectSettings.globalize_path(imp_sheet)), "imported tilesheet file")
	var tp = TilemapPack.load_pack(dest, "Hall")
	failed += _expect(tp != null and int(tp.width) == 16, "TilemapPack Hall")
	failed += _expect(not tp.warps.is_empty(), "TilemapPack warps")
	if not tp.warps.is_empty():
		failed += _expect(str(tp.warps[0].get("to_map", tp.warps[0].get("to_map_id", ""))) == "Room", "runtime warp to_map")
	failed += _expect(not tp.events.is_empty(), "TilemapPack events")
	failed += _expect(not tp.npcs.is_empty(), "TilemapPack npcs")
	var rt = EventRuntime.new()
	rt.load_from_pack(tp)
	failed += _expect(not rt.events_by_id.is_empty() or not rt.events_by_cell.is_empty(), "EventRuntime loaded events")
	var demo = TilemapPack.load_pack("res://demo_map")
	failed += _expect(demo != null and int(demo.width) == 30, "res://demo_map still loads")
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)


func _parent_of(pack, id: String) -> String:
	for item in pack.map_tree:
		if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) == id:
			return str(item.get("parent", ""))
	return ""


func _write_png(path: String) -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.8, 0.3, 1))
	img.save_png(path)


func _wipe(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	if DirAccess.dir_exists_absolute(abs_path):
		_rm(abs_path)


func _rm(abs_path: String) -> void:
	var da := DirAccess.open(abs_path)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n != "." and n != "..":
			var p := "%s/%s" % [abs_path, n]
			if da.current_is_dir():
				_rm(p)
			else:
				DirAccess.remove_absolute(p)
		n = da.get_next()
	DirAccess.remove_absolute(abs_path)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1
