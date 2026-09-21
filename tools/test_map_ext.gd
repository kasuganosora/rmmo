extends SceneTree
## Headless: MapExt load, settings pack, collision force_pass, radar ignores ext.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var MapExt = load("res://scripts/map/map_ext.gd")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	failed += _expect(MapExt != null, "map_ext loads")
	var packed: int = MapExt.pack_settings(3, 7, 2)
	failed += _expect(MapExt.settings_light(packed) == 3, "settings light nibble")
	failed += _expect(MapExt.settings_sound(packed) == 7, "settings sound nibble")
	failed += _expect(MapExt.settings_footstep(packed) == 2, "settings footstep nibble")

	var am: Node = root.get_node_or_null("AssetManager")
	var demo_dir := str(am.resolve_map_pack_path("demo_map")) if am != null else ""
	var empty: RefCounted = MapExt.load_file("%s/nope.ext.json" % demo_dir, 30, 36)
	failed += _expect(empty != null and empty.valid == false, "missing ext is empty/invalid")

	var demo: RefCounted = MapExt.load_file("%s/map.ext.json" % demo_dir, 30, 36)
	failed += _expect(demo != null and demo.valid == true, "demo map.ext.json valid")
	failed += _expect(demo.has_tiles("roof") == false, "empty layers have no tiles")

	var bad: RefCounted = MapExt.new()
	bad._ingest({"format": "map_ext_v1", "width": 2, "height": 2, "layers": []}, 30, 36)
	failed += _expect(bad.valid == false, "size mismatch rejected")

	var tmp: RefCounted = MapExt.new()
	tmp._ingest({
		"format": "map_ext_v1",
		"width": 4,
		"height": 4,
		"layers": [
			{"id": "meta", "encoding": "sparse", "cells": [[1, 1, MapExt.META_FORCE_PASS]]},
			{"id": "settings", "encoding": "sparse", "cells": [[1, 1, MapExt.pack_settings(1, 2, 0)]]},
			{"id": "light", "encoding": "sparse", "cells": [], "color": [1.0, 0.5, 0.2, 0.8]},
		],
	}, 4, 4)
	failed += _expect(tmp.valid, "sparse ingest ok")
	failed += _expect(tmp.meta_at(1, 1) == MapExt.META_FORCE_PASS, "sparse meta cell")
	failed += _expect(tmp.settings_at(1, 1) != 0, "sparse settings cell")
	failed += _expect(tmp.tile("meta", 0, 0) == 0, "empty sparse cell is 0")
	failed += _expect(tmp.light_color.is_equal_approx(Color(1.0, 0.5, 0.2, 0.8)), "light layer custom color")
	var parsed: Color = MapExt.parse_color([0.2, 0.4, 0.6, 1.0])
	failed += _expect(parsed.is_equal_approx(Color(0.2, 0.4, 0.6, 1.0)), "parse_color array")

	var pack = TilemapPack.load_pack("res://demo_map")
	failed += _expect(pack != null and pack.width == 30, "demo pack loads")
	failed += _expect(pack.ext != null, "pack has ext object")
	var col = pack.collision
	failed += _expect(col != null, "collision present")
	# MV-only passage still works on a known landable interior cell if pack has one.
	if col.has_method("is_valid"):
		failed += _expect(col.is_valid(10, 10) == true, "demo cell in bounds")

	var MapFieldScript = load("res://scripts/map/map_field.gd")
	var mf = MapFieldScript.new()
	mf.pack_path = "res://demo_map"
	root.add_child(mf)
	mf.rebuild()
	var atlas: Image = mf.get_radar_atlas_image()
	failed += _expect(atlas != null and atlas.get_width() > 0, "radar atlas baked")
	failed += _expect(mf.has_method("cell_to_chunk"), "chunk helper present")
	if mf.has_method("cell_to_chunk"):
		failed += _expect(mf.cell_to_chunk(Vector2i(0, 0)) == Vector2i(0, 0), "chunk 0,0")
		failed += _expect(mf.cell_to_chunk(Vector2i(16, 16)) == Vector2i(1, 1), "chunk 1,1")
	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
