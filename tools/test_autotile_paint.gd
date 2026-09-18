extends SceneTree
## Autotile neighbor shapes (KilloZapit / MV editor).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var TileId = load("res://scripts/map/tile_id.gd")
	var PaintTools = load("res://scripts/editor/paint_tools.gd")
	var MapDocument = load("res://scripts/editor/map_document.gd")
	failed += _expect(TileId.floor_shape(false, false, false, false, false, false, false, false) == 0, "surrounded floor shape 0")
	failed += _expect(TileId.floor_shape(true, true, true, true, true, true, true, true) == 46, "isolated floor shape 46")
	failed += _expect(TileId.wall_shape(false, false, false, false) == 0, "wall surrounded 0")
	failed += _expect(TileId.waterfall_shape(false, false) == 0, "waterfall no edge 0")
	var doc = MapDocument.new()
	doc.setup_blank("Map001", "t", 8, 8, 48)
	var paint = PaintTools.new()
	paint.tool = PaintTools.Tool.PENCIL
	paint.layer_z = 0
	paint.tile_id = TileId.TILE_ID_A2
	paint.apply_cell(doc, Vector2i(3, 3), false)
	var iso: int = int(doc.tile(3, 3, 0))
	failed += _expect(TileId.is_tile_a2(iso), "isolated is A2")
	failed += _expect(TileId.autotile_kind(iso) == 16, "isolated kind 16")
	failed += _expect(TileId.autotile_shape(iso) == 46, "isolated shape 46")
	for y in range(2, 5):
		for x in range(2, 5):
			paint.apply_cell(doc, Vector2i(x, y), false)
	var center: int = int(doc.tile(3, 3, 0))
	failed += _expect(TileId.autotile_shape(center) == 0, "3x3 interior shape 0")
	var corner: int = int(doc.tile(2, 2, 0))
	failed += _expect(TileId.autotile_kind(corner) == 16, "corner same kind")
	failed += _expect(TileId.autotile_shape(corner) != 0, "3x3 corner not interior")
	failed += _expect(TileId.autotile_shape(corner) != 46, "3x3 corner not isolated")
	# 2-wide sand (kind 24) on grass (kind 16): inner seam must not be a double edge.
	var grass: int = TileId.make_autotile_id(16, 0)
	var sand: int = TileId.make_autotile_id(24, 0)
	var field_doc = MapDocument.new()
	field_doc.setup_blank("S", "s", 8, 8, 48)
	paint.layer_z = 0
	paint.tile_id = grass
	for y in range(8):
		for x in range(8):
			paint.apply_cell(field_doc, Vector2i(x, y), false)
	paint.tile_id = sand
	for y in range(2, 6):
		for x in range(2, 4):
			paint.apply_cell(field_doc, Vector2i(x, y), false)
	var left_mid: int = int(field_doc.tile(2, 3, 0))
	var right_mid: int = int(field_doc.tile(3, 3, 0))
	failed += _expect(TileId.autotile_kind(left_mid) == 24, "left col is sand")
	failed += _expect(TileId.autotile_kind(right_mid) == 24, "right col is sand")
	failed += _expect(TileId.autotile_shape(left_mid) != 32, "2-wide left is not left+right strip")
	failed += _expect(TileId.autotile_shape(right_mid) != 32, "2-wide right is not left+right strip")
	failed += _expect(TileId.autotile_shape(left_mid) == 16, "2-wide left is left-edge only")
	failed += _expect(TileId.autotile_shape(right_mid) == 24, "2-wide right is right-edge only")
	# Overlay: sand on z0, adjacent sand on z1 must join (no grass fringe between).
	var ov = MapDocument.new()
	ov.setup_blank("O", "o", 8, 8, 48)
	paint.layer_z = 0
	paint.tile_id = grass
	for y2 in range(8):
		for x2 in range(8):
			paint.apply_cell(ov, Vector2i(x2, y2), false)
	paint.tile_id = sand
	paint.apply_cell(ov, Vector2i(3, 3), false)
	paint.layer_z = 1
	paint.apply_cell(ov, Vector2i(4, 3), false)
	var z0s: int = int(ov.tile(3, 3, 0))
	var z1s: int = int(ov.tile(4, 3, 1))
	failed += _expect(TileId.autotile_kind(z0s) == 24, "z0 sand")
	failed += _expect(TileId.autotile_kind(z1s) == 24, "z1 sand")
	failed += _expect(TileId.autotile_shape(z1s) != 32, "z1 overlay not a 1-wide strip")
	var z0_shape: int = TileId.autotile_shape(z0s)
	var z1_shape: int = TileId.autotile_shape(z1s)
	# Right-of-z0 and left-of-z1 should not both be edges (that was the grass seam).
	failed += _expect(z1_shape != 16 and z1_shape != 32 and z1_shape != 46, "z1 does not treat z0 sand as empty left")
	failed += _expect(z0_shape != 24 and z0_shape != 32, "z0 does not keep right-edge against z1 sand")
	# RTP dirt-with-tufts (17) next to plain sand (24) must join — no grass seam.
	failed += _expect(TileId.a2_floors_connect(17, 24), "dirt+sand family")
	failed += _expect(TileId.a2_floors_connect(24, 32), "sand+dark-sand family")
	failed += _expect(not TileId.a2_floors_connect(17, 16), "dirt does not join grass")
	failed += _expect(not TileId.a2_floors_connect(17, 18), "dirt does not join cobble")
	failed += _expect(not TileId.a2_floors_connect(24, 25), "plain sand does not join grass-on-sand")
	var mix = MapDocument.new()
	mix.setup_blank("M", "m", 8, 8, 48)
	paint.layer_z = 0
	paint.tile_id = grass
	for ym in range(8):
		for xm in range(8):
			paint.apply_cell(mix, Vector2i(xm, ym), false)
	paint.tile_id = TileId.make_autotile_id(24, 0)
	for ym2 in range(2, 6):
		for xm2 in range(2, 5):
			paint.apply_cell(mix, Vector2i(xm2, ym2), false)
	paint.tile_id = TileId.make_autotile_id(17, 0)
	for ym3 in range(2, 6):
		paint.apply_cell(mix, Vector2i(5, ym3), false)
	var d17: int = int(mix.tile(5, 3, 0))
	var d24: int = int(mix.tile(4, 3, 0))
	failed += _expect(TileId.autotile_kind(d17) == 17, "strip is dirt 17")
	failed += _expect(TileId.autotile_kind(d24) == 24, "field is sand 24")
	failed += _expect(TileId.autotile_shape(d17) != 32, "dirt strip not double-edged")
	failed += _expect(TileId.autotile_shape(d17) == 24, "dirt strip right-edge only (against grass)")
	failed += _expect(TileId.autotile_shape(d24) == 0, "sand interior next to dirt")
	var TileBlit = load("res://scripts/map/tile_blit.gd")
	var a2_path := _runtime_root() + "/assets/tilesheet/Outside_A2.png"
	if FileAccess.file_exists(a2_path):
		var a2: Image = Image.load_from_file(a2_path)
		var sheets: Array = [null, a2]
		var img := Image.create(96, 48, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var left_id: int = TileId.make_autotile_id(24, 16)
		var right_id: int = TileId.make_autotile_id(24, 24)
		TileBlit.blit_tile(img, left_id, 0, 0, sheets, 48, 48, PackedInt32Array(), 0)
		TileBlit.blit_tile(img, right_id, 48, 0, sheets, 48, 48, PackedInt32Array(), 0)
		var seam_green := 0
		var seam_sand := 0
		for y in range(48):
			var c: Color = img.get_pixel(47, y)
			var c2: Color = img.get_pixel(48, y)
			if c.g > c.r + 0.08 and c.g > c.b + 0.08:
				seam_green += 1
			if c2.g > c2.r + 0.08 and c2.g > c2.b + 0.08:
				seam_green += 1
			if c.r > 0.45 and c.g > 0.35 and c.g < 0.7:
				seam_sand += 1
		failed += _expect(seam_green < 8, "2-wide sand seam is not a grass column")
	# Refresh-all joins already-saved dirt strip next to sand (editor map-open path).
	var stale = MapDocument.new()
	stale.setup_blank("stale", "s", 8, 8, 48)
	for y in range(8):
		for x in range(8):
			stale.set_tile(x, y, 0, grass, false)
	for y4 in range(2, 6):
		for x4 in range(2, 5):
			stale.set_tile(x4, y4, 0, sand, false)
		stale.set_tile(5, y4, 0, TileId.make_autotile_id(17, 32), false)
	var nfix: int = int(paint.refresh_all_floor_autotiles(stale))
	failed += _expect(nfix > 0, "refresh rewrites stale dirt/sand seam")
	failed += _expect(TileId.autotile_shape(int(stale.tile(5, 3, 0))) == 24, "refresh dirt strip right-edge only")
	failed += _expect(TileId.autotile_shape(int(stale.tile(4, 3, 0))) == 0, "refresh sand interior next to dirt")

	# A1 waterfall / A3 wall / A4 wall+floor 3x3 neighbor shapes.
	failed += _expect(_paint_blob_interior(paint, MapDocument, TileId, 5) == 0, "waterfall 3x3 interior 0")
	failed += _expect(_paint_blob_shape(paint, MapDocument, TileId, 5, 2, 3) == 1, "waterfall left edge 1")
	failed += _expect(_paint_blob_shape(paint, MapDocument, TileId, 5, 4, 3) == 2, "waterfall right edge 2")
	var a3id: int = TileId.make_autotile_id(48, 0)
	failed += _expect(TileId.is_wall_autotile(a3id), "A3 kind 48 is wall")
	failed += _expect(_paint_blob_interior(paint, MapDocument, TileId, 48) == 0, "A3 3x3 interior 0")
	failed += _expect(_paint_blob_shape(paint, MapDocument, TileId, 48, 2, 2) == TileId.wall_shape(true, true, false, false), "A3 TL wall shape")
	failed += _expect(_paint_blob_interior(paint, MapDocument, TileId, 80) == 0, "A4 floor 3x3 interior 0")
	failed += _expect(_paint_blob_interior(paint, MapDocument, TileId, 88) == 0, "A4 wall 3x3 interior 0")
	failed += _expect(TileId.is_wall_autotile(TileId.make_autotile_id(88, 0)), "A4 kind 88 is wall")

	var a1_path := _runtime_root() + "/assets/tilesheet/Outside_A1.png"
	var a3_path := _runtime_root() + "/assets/tilesheet/Outside_A3.png"
	var a4_path := _runtime_root() + "/assets/tilesheet/Outside_A4.png"
	if FileAccess.file_exists(a1_path) and FileAccess.file_exists(a2_path) and FileAccess.file_exists(a3_path) and FileAccess.file_exists(a4_path):
		var sheets_all: Array = [
			Image.load_from_file(a1_path),
			Image.load_from_file(a2_path),
			Image.load_from_file(a3_path),
			Image.load_from_file(a4_path),
		]
		failed += _expect(_blob_has_pixels(paint, MapDocument, TileId, TileBlit, sheets_all, 5), "waterfall blit has pixels")
		failed += _expect(_blob_has_pixels(paint, MapDocument, TileId, TileBlit, sheets_all, 48), "A3 wall blit has pixels")
		failed += _expect(_blob_has_pixels(paint, MapDocument, TileId, TileBlit, sheets_all, 80), "A4 floor blit has pixels")
		failed += _expect(_blob_has_pixels(paint, MapDocument, TileId, TileBlit, sheets_all, 88), "A4 wall blit has pixels")
		# Kind 17 5x4 on grass: interior must stay dirt, not a grass column.
		var t17 = MapDocument.new()
		t17.setup_blank("t17", "t", 10, 8, 48)
		paint.layer_z = 0
		paint.tile_id = grass
		paint.apply_rect(t17, Vector2i(0, 0), Vector2i(9, 7), false)
		paint.tile_id = TileId.make_autotile_id(17, 0)
		paint.apply_rect(t17, Vector2i(2, 2), Vector2i(6, 5), false)
		var img17 := Image.create(10 * 48, 8 * 48, false, Image.FORMAT_RGBA8)
		img17.fill(Color(0, 0, 0, 0))
		for y5 in range(8):
			for x5 in range(10):
				TileBlit.blit_tile(img17, int(t17.tile(x5, y5, 0)), x5 * 48, y5 * 48, sheets_all, 48, 48, PackedInt32Array(), 0)
		var g17 := 0
		for py in range(3 * 48, 4 * 48):
			for px in range(3 * 48, 5 * 48):
				var pc: Color = img17.get_pixel(px, py)
				if pc.g > pc.r + 0.08 and pc.g > pc.b + 0.08:
					g17 += 1
		failed += _expect(g17 < 8, "kind 17 blob interior is dirt not grass")

	# Table-flag A2 (Inside RTP kind 23): paint + hanging edge blit.
	var inside_flags_path := "res://data/rtp/inside.json"
	var inside_a2_path := _runtime_root() + "/assets/tilesheet/Inside_A2.png"
	if FileAccess.file_exists(inside_flags_path) and FileAccess.file_exists(inside_a2_path):
		var ff := FileAccess.open(inside_flags_path, FileAccess.READ)
		var parsed_f: Variant = JSON.parse_string(ff.get_as_text())
		var farr: Array = parsed_f.get("flags", [])
		var flags := PackedInt32Array()
		flags.resize(farr.size())
		for fi in range(farr.size()):
			flags[fi] = int(farr[fi])
		var table_id: int = TileId.make_autotile_id(23, 0)
		failed += _expect(TileBlit.is_table_tile(table_id, flags), "kind 23 is table-flagged")
		var tdoc = MapDocument.new()
		tdoc.setup_blank("tbl", "t", 8, 8, 48)
		paint.tile_id = table_id
		paint.apply_rect(tdoc, Vector2i(2, 2), Vector2i(5, 4), false)
		failed += _expect(TileId.autotile_kind(int(tdoc.tile(3, 3, 0))) == 23, "table blob kind 23")
		failed += _expect(TileId.autotile_shape(int(tdoc.tile(3, 3, 0))) == 0, "table interior shape 0")
		var ia2: Image = Image.load_from_file(inside_a2_path)
		var isheets: Array = [null, ia2]
		var timg := Image.create(8 * 48, 8 * 48, false, Image.FORMAT_RGBA8)
		timg.fill(Color(0, 0, 0, 0))
		for y6 in range(8):
			for x6 in range(8):
				var tid: int = int(tdoc.tile(x6, y6, 0))
				if tid > 0:
					TileBlit.blit_tile(timg, tid, x6 * 48, y6 * 48, isheets, 48, 48, flags, 0)
		TileBlit.blit_table_edge(timg, int(tdoc.tile(3, 4, 0)), 3 * 48, 5 * 48, isheets, 48, 48)
		var wood := 0
		for py2 in range(3 * 48, 3 * 48 + 24):
			for px2 in range(3 * 48, 3 * 48 + 24):
				var tc: Color = timg.get_pixel(px2, py2)
				if tc.a > 0.5 and tc.r > tc.g and tc.r > 0.3:
					wood += 1
		failed += _expect(wood > 20, "table surface has wood pixels")
		var lip := 0
		for px3 in range(3 * 48, 4 * 48):
			var lc: Color = timg.get_pixel(px3, 5 * 48 + 4)
			if lc.a > 0.3:
				lip += 1
		failed += _expect(lip > 4, "table edge hangs into cell below")

	# A-tab: drag across two autotile kinds stays one autotile (no sand/grass stamp).
	var TilePalette = load("res://scripts/editor/tile_palette.gd")
	var pal = TilePalette.new()
	pal.tab = "A"
	var a3_prev: int = pal._preview_id(TileId.TILE_ID_A3)
	failed += _expect(TileId.autotile_shape(a3_prev) < 16, "A3 palette preview is a valid wall shape")
	failed += _expect(TileId.autotile_shape(pal._preview_id(TileId.make_autotile_id(16, 0))) == 46, "A2 preview is isolated floor")
	pal._drag_a = Vector2i(0, 3)
	pal._drag_b = Vector2i(1, 3)
	pal._commit_stamp(false)
	failed += _expect(pal.stamp_w == 1 and pal.stamp_h == 1, "A autotile drag is 1x1")
	failed += _expect(TileId.autotile_kind(pal.selected_id) == 24, "A drag keeps click-origin sand kind")
	pal.free()
	var pal2 = TilePalette.new()
	get_root().add_child(pal2)
	failed += _expect(pal2._pass_layer != null, "passage overlay exists")
	failed += _expect(not pal2._pass_layer.visible, "passage overlay hidden in map paint")
	pal2.set_show_passage(true)
	failed += _expect(bool(pal2._pass_layer.visible), "passage overlay shown")
	pal2.set_show_passage(false)
	failed += _expect(not pal2._pass_layer.visible, "set_show_passage(false) hides overlay")
	pal2.free()

	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var pack = ContentPack.new()
	pack.new_blank("unit_autotile_vis", "at", 16, 16)
	var d2 = pack.get_map("Map001")
	failed += _expect(TileId.autotile_kind(int(d2.tile(0, 0, 0))) == 16, "new_blank starter is grass")
	failed += _expect(TileId.autotile_kind(int(d2.tile(8, 8, 0))) == 16, "new_blank grass covers map")
	paint.tile_id = TileId.TILE_ID_A2
	for y in range(4, 8):
		for x in range(4, 8):
			paint.apply_cell(d2, Vector2i(x, y), false)
	failed += _expect(pack.save_dir(), "save autotile pack")
	var field: Node2D = MapField.new()
	get_root().add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = d2
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.rebuild()
	while not field._chunk_queue.is_empty():
		field._bake_next_chunk()
	failed += _expect(_chunk_has_pixels(field), "autotile patch is visible")
	field.free()
	var ed_src := FileAccess.get_file_as_string("res://scripts/editor/content_editor.gd")
	failed += _expect(ed_src.find("地面 z0（先铺草地）") >= 0, "z0 labeled starter grass")
	failed += _expect(ed_src.find("叠层 z1（路/沙盖在草上）") >= 0, "z1 labeled overlay")
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)


func _paint_blob_interior(paint, MapDocument, TileId, kind: int) -> int:
	return _paint_blob_shape(paint, MapDocument, TileId, kind, 3, 3)


func _paint_blob_shape(paint, MapDocument, TileId, kind: int, x: int, y: int) -> int:
	var doc = MapDocument.new()
	doc.setup_blank("b", "b", 8, 8, 48)
	paint.layer_z = 0
	paint.tile_id = TileId.make_autotile_id(kind, 0)
	for yy in range(2, 5):
		for xx in range(2, 5):
			paint.apply_cell(doc, Vector2i(xx, yy), false)
	return TileId.autotile_shape(int(doc.tile(x, y, 0)))


func _blob_has_pixels(paint, MapDocument, TileId, TileBlit, sheets: Array, kind: int) -> bool:
	var doc = MapDocument.new()
	doc.setup_blank("b", "b", 8, 8, 48)
	paint.layer_z = 0
	paint.tile_id = TileId.make_autotile_id(kind, 0)
	for yy in range(2, 5):
		for xx in range(2, 5):
			paint.apply_cell(doc, Vector2i(xx, yy), false)
	var img := Image.create(3 * 48, 3 * 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for yy2 in range(2, 5):
		for xx2 in range(2, 5):
			TileBlit.blit_tile(img, int(doc.tile(xx2, yy2, 0)), (xx2 - 2) * 48, (yy2 - 2) * 48, sheets, 48, 48, PackedInt32Array(), 0)
	var used: Rect2i = img.get_used_rect()
	return used.size.x > 80 and used.size.y > 80


func _chunk_has_pixels(field: Node2D) -> bool:
	for key in field._chunks.keys():
		var node: Node = field._chunks[key]
		if node == null:
			continue
		var spr: Sprite2D = node.get_node_or_null("Ground") as Sprite2D
		if spr == null or spr.texture == null:
			continue
		var img: Image = spr.texture.get_image()
		if img == null:
			continue
		var used: Rect2i = img.get_used_rect()
		if used.size.x > 8 and used.size.y > 8:
			return true
	return false





func _runtime_root() -> String:
	for cand in ["/workspace/rmmo_runtime", "D:/code/rmmo_runtime"]:
		if DirAccess.dir_exists_absolute(cand):
			return cand
	return "/workspace/rmmo_runtime"

func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1
