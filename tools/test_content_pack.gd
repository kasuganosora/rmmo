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
	var grass0: int = int(doc.tile(2, 2, 0))
	doc.set_tile(2, 2, 0, 1536)
	failed += _expect(int(doc.tile(2, 2, 0)) == 1536, "set tile z0")
	doc.undo()
	failed += _expect(int(doc.tile(2, 2, 0)) == grass0, "undo tile")
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
	var bin_path := root + "/maps/Map001/map.data.bin"
	var has_bin := FileAccess.file_exists(bin_path) or FileAccess.file_exists(ProjectSettings.globalize_path(bin_path))
	var data: Array = raw.get("data", [])
	failed += _expect(has_bin or data.size() == 8 * 8 * 6, "map data stored (bin or json)")
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
	var am: Node = Engine.get_main_loop().root.get_node_or_null("AssetManager")
	failed += _expect(am != null, "AssetManager for default pack")
	if am != null and am.has_method("resolve_map_pack_path"):
		var rp: String = str(am.resolve_map_pack_path("default"))
		failed += _expect(rp.find("res://") < 0, "default pack is external")
		failed += _expect(rp.find("map_pack") >= 0 or rp.find("default") >= 0, "resolve id default")
		failed += _expect(FileAccess.file_exists("%s/pack.json" % rp) or FileAccess.file_exists(rp.replace("\\", "/") + "/pack.json"), "external pack.json")
		var ground := "%s/assets/tilesheet/Ground.png" % rp
		failed += _expect(FileAccess.file_exists(ground) or FileAccess.file_exists(ground.replace("\\", "/")), "external Ground sheet")
		var defp = TilemapPack.load_pack(rp, "Map001")
		failed += _expect(defp != null and int(defp.width) >= 20, "default pack Map001 loads")
		var cref: String = str(am.resolve_map_pack_path("content://map_pack/default"))
		failed += _expect(cref.find("default") >= 0, "resolve content://map_pack/default")
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
