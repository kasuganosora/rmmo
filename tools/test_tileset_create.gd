extends SceneTree
## Blank / duplicate / rename / delete pack tilesets.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var TileId = load("res://scripts/map/tile_id.gd")
	var pack = ContentPack.new()
	pack.new_blank("unit_tileset", "tileset", 8, 8)
	failed += _expect(pack.tilesets.has("outside"), "blank pack has RTP outside")
	var n0: int = pack.tilesets.size()
	var blank_id: String = pack.create_tileset("", "自定义海")
	failed += _expect(blank_id.begins_with("ts_"), "blank id ts_N")
	failed += _expect(pack.tilesets.has(blank_id), "blank stored")
	failed += _expect(pack.tileset_label(blank_id) == "自定义海", "blank display name")
	failed += _expect(pack.tilesets.size() == n0 + 1, "count +1")
	var ts: Dictionary = pack.tilesets[blank_id]
	var names: Array = ts.get("tilesetNames", [])
	failed += _expect(names.size() == 9, "9 slots")
	var empty := true
	for n in names:
		if str(n) != "":
			empty = false
	failed += _expect(empty, "blank slots empty")
	var flags_v: Variant = ts.get("flags", [])
	failed += _expect(typeof(flags_v) == TYPE_ARRAY and (flags_v as Array).size() >= TileId.TILE_ID_MAX, "flags sized")
	if typeof(flags_v) == TYPE_ARRAY and (flags_v as Array).size() > TileId.TILE_ID_A3:
		var a3: int = int((flags_v as Array)[TileId.TILE_ID_A3])
		failed += _expect(TileId.passage_kind(a3) == TileId.PASS_X, "A3 default ×")
		var a5: int = int((flags_v as Array)[TileId.TILE_ID_A5])
		failed += _expect(TileId.passage_kind(a5) == TileId.PASS_O, "A5 default ○")
	var dup_id: String = pack.duplicate_tileset("outside")
	failed += _expect(dup_id != "" and dup_id != "outside", "dup id")
	failed += _expect(str(pack.tilesets[dup_id].get("tilesetNames", [])[0]) == "Outside_A1", "dup keeps A1 sheet")
	failed += _expect(pack.tileset_label(dup_id).ends_with("复制"), "dup name suffix")
	failed += _expect(pack.rename_tileset(dup_id, "海边"), "rename")
	failed += _expect(pack.tileset_label(dup_id) == "海边", "renamed label")
	failed += _expect(pack.set_map_tileset("Map001", blank_id), "map uses blank")
	failed += _expect(pack.maps_using_tileset(blank_id).size() == 1, "maps_using")
	failed += _expect(pack.delete_tileset(blank_id), "delete in-use")
	failed += _expect(not pack.tilesets.has(blank_id), "erased")
	failed += _expect(str(pack.get_map("Map001").tileset_id) != blank_id, "map reassigned")
	failed += _expect(not pack.delete_tileset("missing"), "delete missing fails")
	failed += _expect(pack.save_dir(), "save pack")
	failed += _expect(FileAccess.file_exists("%s/tilesets/%s.json" % [pack.root, dup_id]) or FileAccess.file_exists(ProjectSettings.globalize_path("%s/tilesets/%s.json" % [pack.root, dup_id])), "dup json written")
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
