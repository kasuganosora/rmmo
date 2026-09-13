extends SceneTree
## Content pack tree, save, zip roundtrip, nested TilemapPack load.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var PackZip = load("res://scripts/editor/pack_zip.gd")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var pack = ContentPack.new()
	pack.new_blank("unit_test_pack", "测试包", 8, 8)
	failed += _expect(pack.maps.size() == 1, "new pack one map")
	failed += _expect(pack.add_map("Map002", "房间", "Map001", 8, 8), "add child map")
	failed += _expect(pack.set_parent("Map002", "Map001"), "parent set")
	failed += _expect(not pack.set_parent("Map001", "Map002"), "reject cycle")
	var doc = pack.get_map("Map001")
	doc.set_tile(2, 2, 0, 1536)
	failed += _expect(int(doc.tile(2, 2, 0)) == 1536, "set tile z0")
	doc.undo()
	failed += _expect(int(doc.tile(2, 2, 0)) == 0, "undo tile")
	doc.redo()
	failed += _expect(int(doc.tile(2, 2, 0)) == 1536, "redo tile")
	var root: String = "user://content/packs/unit_test_pack"
	failed += _expect(pack.save_dir(root), "save nested pack")
	failed += _expect(FileAccess.file_exists(root + "/pack.json") or FileAccess.file_exists(ProjectSettings.globalize_path(root + "/pack.json")), "pack.json exists")
	var map_json_path := root + "/maps/Map001/map.json"
	var raw: Dictionary = {}
	var fpath := map_json_path
	if not FileAccess.file_exists(fpath):
		fpath = ProjectSettings.globalize_path(map_json_path)
	var f := FileAccess.open(fpath, FileAccess.READ)
	if f:
		raw = JSON.parse_string(f.get_as_text())
	var data: Array = raw.get("data", [])
	failed += _expect(data.size() == 8 * 8 * 6, "map.json is w*h*6")
	var zip_path := "user://content/packs/unit_test_pack.rmpack"
	failed += _expect(PackZip.export_zip(root, zip_path), "export zip")
	var dest := "user://content/packs/unit_test_pack_imp"
	var imp: Dictionary = PackZip.import_zip(zip_path, dest)
	failed += _expect(bool(imp.get("ok", false)), "import zip ok")
	var pack2 = ContentPack.new()
	failed += _expect(pack2.load_dir(dest), "load imported pack")
	failed += _expect(pack2.maps.size() == 2, "imported two maps")
	failed += _expect(int(pack2.get_map("Map001").tile(2, 2, 0)) == 1536, "imported tile preserved")
	# Nested runtime load
	var tp = TilemapPack.load_pack(root, "Map001")
	failed += _expect(tp != null and tp.width == 8, "TilemapPack nested Map001")
	# Legacy flat still loads
	var demo = TilemapPack.load_pack("res://demo_map")
	failed += _expect(demo != null and demo.width == 30, "legacy demo_map still loads")
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1
