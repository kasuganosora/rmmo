extends SceneTree
## Tile palette A/B cell → tile_id mapping + RTP tileset defs.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var TilePalette = load("res://scripts/editor/tile_palette.gd")
	var TileId = load("res://scripts/map/tile_id.gd")
	var Rtp = load("res://scripts/editor/rtp.gd")
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	failed += _expect(TilePalette.a_cell_to_id(0, 0) == TileId.TILE_ID_A1, "A tab (0,0) is A1")
	failed += _expect(TilePalette.a_cell_to_id(0, 2) == TileId.TILE_ID_A2, "A tab (0,2) is A2")
	failed += _expect(TilePalette.a_cell_to_id(0, 6) == TileId.TILE_ID_A3, "A tab (0,6) is A3")
	failed += _expect(TilePalette.a_cell_to_id(0, 10) == TileId.TILE_ID_A4, "A tab (0,10) is A4")
	failed += _expect(TilePalette.a_cell_to_id(0, 16) == TileId.TILE_ID_A5, "A tab (0,16) is A5")
	failed += _expect(TilePalette.a_cell_to_id(3, 16) == TileId.TILE_ID_A5 + 3, "A5 col 3")
	failed += _expect(TilePalette.sheet_cell_to_id(0, 0, 0) == 0, "B (0,0) empty")
	failed += _expect(TilePalette.sheet_cell_to_id(1, 0, 0) == 1, "B (1,0) is 1")
	failed += _expect(TilePalette.sheet_cell_to_id(8, 0, 0) == 128, "B right half")
	failed += _expect(TilePalette.sheet_cell_to_id(0, 1, 256) == 264, "C row 1")
	var cell_a2: Vector2i = TilePalette.a_id_to_cell(TileId.TILE_ID_A2)
	failed += _expect(cell_a2 == Vector2i(0, 2), "A2 id back to cell")
	var rtp: Dictionary = Rtp.load_tilesets()
	failed += _expect(rtp.has("outside"), "rtp has outside")
	failed += _expect(rtp.has("inside"), "rtp has inside")
	if rtp.has("outside"):
		var ts: Dictionary = rtp["outside"]
		var names: Variant = ts.get("tilesetNames", [])
		failed += _expect(typeof(names) == TYPE_ARRAY and names.size() >= 6, "outside tilesetNames")
		if typeof(names) == TYPE_ARRAY:
			failed += _expect(str(names[0]) == "Outside_A1", "outside A1 sheet name")
			failed += _expect(str(names[5]) == "Outside_B", "outside B sheet name")
		var flags: Variant = ts.get("flags", [])
		failed += _expect(typeof(flags) == TYPE_ARRAY and (flags as Array).size() == 8192, "outside flags 8192")
	var pack = ContentPack.new()
	pack.new_blank("unit_palette_pack", "palette", 8, 8)
	failed += _expect(pack.tilesets.has("outside"), "new pack includes RTP outside")
	failed += _expect(str(pack.map_tree[0].get("tileset", "")) == "outside", "start map uses outside")
	var root := "D:/code/rmmo_runtime"
	failed += _expect(FileAccess.file_exists(root + "/assets/tilesheet/Outside_A1.png"), "runtime has Outside_A1")
	failed += _expect(FileAccess.file_exists(root + "/assets/charset/Actor1.png"), "runtime has Actor1 charset")
	failed += _expect(FileAccess.file_exists(root + "/assets/system/IconSet.png"), "runtime has IconSet")
	var pal = TilePalette.new()
	get_root().add_child(pal)
	pal.set_catalog(rtp, "outside")
	failed += _expect(pal.sheets.size() == 9, "palette 9 sheet slots")
	failed += _expect(pal.sheets[0] != null, "Outside_A1 sheet loaded")
	failed += _expect(pal.sheets[1] != null, "Outside_A2 sheet loaded")
	failed += _expect(pal.sheets[4] != null, "Outside_A5 sheet loaded")
	failed += _expect(pal.sheets[5] != null, "Outside_B sheet loaded")
	failed += _expect(pal._tex != null and pal._tex.texture != null, "A tab atlas built")
	if pal._tex and pal._tex.texture:
		var tex: Texture2D = pal._tex.texture
		failed += _expect(tex.get_width() == 384 and tex.get_height() == 1536, "A atlas 8x32 tiles")
	failed += _expect(pal._pass_layer != null, "passage overlay exists")
	failed += _expect(not pal.show_passage, "passage mode off by default")
	failed += _expect(not pal._pass_layer.visible, "passage overlay hidden in map paint")
	pal.set_show_passage(true)
	failed += _expect(bool(pal._pass_layer.visible), "passage overlay shown")
	pal.set_show_passage(false)
	failed += _expect(not pal._pass_layer.visible, "set_show_passage(false) hides overlay")
	pal.free()
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
