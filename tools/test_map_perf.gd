extends SceneTree
## Lofi overview, chunk cap, map size ceiling. Town-sized maps must not 48px-bake.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_size_cap()
	failed += _test_town_lofi_and_chunk_cap()
	failed += _test_lofi_samples_real_tile_colors()
	failed += _test_town_lofi_matches_hd()
	failed += _test_editor_preview_lofi()
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


func _test_size_cap() -> int:
	var failed := 0
	var MapDocument = load("res://scripts/editor/map_document.gd")
	failed += _expect(int(MapDocument.MAX_SIDE) >= 10000, "MAX_SIDE allows 10000")
	failed += _expect(int(MapDocument.clamp_side(10000)) == 10000, "10000 allowed")
	failed += _expect(int(MapDocument.clamp_side(0)) == 1, "0 clamps to 1")
	var doc = MapDocument.new()
	doc.setup_blank("Huge", "huge", 10000, 10000)
	failed += _expect(int(doc.width) == 10000 and int(doc.height) == 10000, "setup_blank 10000x10000")
	failed += _expect(bool(doc.uses_chunks()), "10000 map is chunked")
	failed += _expect(int(doc.data.size()) == 0, "chunked map has no dense buffer")
	doc.setup_blank("Ok", "ok", 96, 96)
	failed += _expect(int(doc.width) == 96, "96x96 still allowed")
	failed += _expect(not bool(doc.uses_chunks()), "96 stays dense")
	doc.resize(10000, 8)
	failed += _expect(int(doc.width) == 10000 and int(doc.height) == 8, "resize to continent width")
	return failed


func _test_town_lofi_and_chunk_cap() -> int:
	var failed := 0
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var pack = ContentPack.new()
	pack.new_blank("perf_town", "城镇性能", 96, 96)
	failed += _expect(pack.save_dir(), "save 96 pack")
	var doc = pack.get_map("Map001")
	failed += _expect(int(doc.width) == 96 and int(doc.height) == 96, "town 96x96")
	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	var t0 := Time.get_ticks_usec()
	field.rebuild()
	var bake_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH 96x96 rebuild %.1f ms chunks=%d" % [bake_ms, field._chunks.size()])
	failed += _expect(bake_ms < 2500.0, "96x96 rebuild < 2.5s (%.1f)" % bake_ms)
	var lofi: Image = field.get_lofi_image()
	failed += _expect(lofi != null, "lofi exists")
	failed += _expect(lofi != null and lofi.get_width() == 96 and lofi.get_height() == 96, "lofi 1px/cell")
	var atlas: Image = field.get_radar_atlas_image()
	failed += _expect(atlas != null and atlas.get_width() == 96, "radar atlas is lofi not 48px")
	failed += _expect(field.get_radar_atlas_scale() < 0.1, "radar scale 1/tile_size")
	failed += _expect(field.get_ground_texture() != null, "overview tex from lofi")
	var lofi_spr: Node = field.get_node_or_null("Lofi")
	failed += _expect(lofi_spr != null and (lofi_spr as CanvasItem).visible, "lofi sprite shown")
	var prev: Image = field.render_preview(0, 0, 96, 96, 2)
	failed += _expect(prev != null and prev.get_width() == 192 and prev.get_height() == 192, "lofi preview 2px")
	failed += _expect(field._chunks.size() <= 25, "spawn high-res chunks capped (%d)" % field._chunks.size())

	var cam := Camera2D.new()
	cam.enabled = true
	cam.zoom = Vector2(0.04, 0.04)
	cam.position = Vector2(96.0 * 24.0, 96.0 * 24.0)
	root.add_child(cam)
	field.set_edit_camera_cell(Vector2i(48, 48))
	var wanted: Dictionary = field._wanted_chunks(Vector2i(48, 48), 2)
	print("BENCH zoomed-out wanted_chunks=", wanted.size())
	failed += _expect(wanted.size() > 0, "wanted some chunks")
	failed += _expect(wanted.size() <= 25, "zoomed-out cap <= 5x5 (%d)" % wanted.size())
	cam.queue_free()
	field.queue_free()
	return failed


func _test_lofi_samples_real_tile_colors() -> int:
	## 4px sample reads autotile corners (dirt). Native 48px center is the tile face.
	var failed := 0
	var TileId = load("res://scripts/map/tile_id.gd")
	var TileBlit = load("res://scripts/map/tile_blit.gd")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var pack = TilemapPack.load_pack("res://street_map")
	failed += _expect(pack != null and pack.sheets.size() > 0, "street pack sheets")
	if pack == null:
		return failed
	var sheets: Array = pack.sheets
	var flags: PackedInt32Array = pack.flags
	TileBlit._color_cache.clear()
	var sea: Color = TileBlit.sample_color(TileId.TILE_ID_A1, sheets, flags)
	print("sample A1 sea ", sea)
	failed += _expect(sea.a > 0.5, "sea sample opaque")
	failed += _expect(sea.b >= sea.r * 0.85, "sea is not a dirt-corner sample")
	var a2_path := "D:/code/rmmo_runtime/assets/tilesheet/Outside_A2.png"
	failed += _expect(FileAccess.file_exists(a2_path), "RTP Outside_A2")
	if FileAccess.file_exists(a2_path):
		var a2_img: Image = Image.load_from_file(a2_path)
		var rtp_sheets: Array = []
		rtp_sheets.resize(9)
		rtp_sheets[1] = a2_img
		var a2_id: int = TileId.TILE_ID_A2 + 47
		var tiny := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		tiny.fill(Color(0, 0, 0, 0))
		TileBlit.blit_tile(tiny, a2_id, 0, 0, rtp_sheets, 4, 4, flags, 0)
		var full := Image.create(48, 48, false, Image.FORMAT_RGBA8)
		full.fill(Color(0, 0, 0, 0))
		TileBlit.blit_tile(full, a2_id, 0, 0, rtp_sheets, 48, 48, flags, 0)
		var c4: Color = tiny.get_pixel(1, 1)
		var c48: Color = full.get_pixel(24, 24)
		print("Outside_A2 4px corner ", c4, " 48px center ", c48)
		var delta: float = absf(c4.r - c48.r) + absf(c4.g - c48.g) + absf(c4.b - c48.b)
		failed += _expect(delta > 0.08, "48px grass face differs from 4px dirt corner")
		failed += _expect(c48.g > c48.r * 0.9, "RTP A2 center is greenish")
		TileBlit._color_cache.clear()
		var face: Color = TileBlit.sample_color(a2_id, rtp_sheets, flags)
		print("sample_color A2 ", face)
		failed += _expect(face.g > face.r * 0.9, "sample_color uses grass face not dirt corner")
	return failed


func _test_town_lofi_matches_hd() -> int:
	var failed := 0
	var MapField = load("res://scripts/map/map_field.gd")
	var path := "user://content/packs/default"
	if not FileAccess.file_exists(path + "/pack.json") and not FileAccess.file_exists(ProjectSettings.globalize_path(path + "/pack.json")):
		print("SKIP town pack missing")
		return 0
	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = false
	field.pack_path = path
	field.edit_map_id = "Town"
	field.rebuild()
	while not field._chunk_queue.is_empty():
		field._bake_next_chunk()
	field._publish_lofi_atlas()
	var lofi: Image = field.get_lofi_image()
	failed += _expect(lofi != null and lofi.get_width() == 96, "town lofi 96")
	var greenish := 0
	var brownish := 0
	var blueish := 0
	if lofi != null:
		for y in range(lofi.get_height()):
			for x in range(lofi.get_width()):
				var c: Color = lofi.get_pixel(x, y)
				if c.b > c.r + 0.04 and c.b > c.g:
					blueish += 1
				elif c.g > c.r + 0.05 and c.g > c.b:
					greenish += 1
				elif c.r > c.g + 0.08:
					brownish += 1
	print("town HD-lofi green=", greenish, " brown=", brownish, " blue=", blueish)
	failed += _expect(greenish > brownish * 2, "town overview is grassy like the HD map")
	failed += _expect(greenish + blueish > 4000, "town has a large vegetated/water interior")
	var px: Color = lofi.get_pixel(45, 78) if lofi else Color()
	print("lofi (45,78)=", px)
	failed += _expect(px.g > px.r, "player-cell grass is green on minimap")
	field.queue_free()
	return failed


func _test_editor_preview_lofi() -> int:
	## Editor only bakes the camera chunk in HD; minimap/preview must still look like grass.
	var failed := 0
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var pack = ContentPack.new()
	if not pack.load_dir("user://content/packs/default"):
		print("SKIP editor town pack")
		return 0
	var doc = pack.get_map("Town")
	if doc == null:
		print("SKIP no Town map")
		return 0
	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc
	field.pack_path = pack.root
	field.edit_map_id = "Town"
	field.rebuild()
	failed += _expect(field._chunks.size() <= 2, "editor still one HD chunk (%d)" % field._chunks.size())
	var lofi: Image = field.get_lofi_image()
	failed += _expect(lofi != null and lofi.get_width() == 96, "editor lofi 96")
	var greenish := 0
	var brownish := 0
	if lofi != null:
		for y in range(lofi.get_height()):
			for x in range(lofi.get_width()):
				var c: Color = lofi.get_pixel(x, y)
				if c.g > c.r + 0.05 and c.g > c.b:
					greenish += 1
				elif c.r > c.g + 0.08:
					brownish += 1
	print("editor preview lofi green=", greenish, " brown=", brownish, " chunks=", field._chunks.size())
	failed += _expect(greenish > brownish * 2, "editor minimap is grassy without baking every chunk")
	if lofi != null:
		var px: Color = lofi.get_pixel(45, 78)
		print("editor lofi (45,78)=", px)
		failed += _expect(px.g > px.r, "editor preview grass cell is green")
	var chip: Image = field.render_preview(40, 72, 16, 16, 2)
	failed += _expect(chip != null and chip.get_width() == 32, "editor lofi preview chip")
	if chip != null:
		var cg: Color = chip.get_pixel(10, 12)
		print("preview chip px=", cg)
		failed += _expect(cg.g > cg.r * 0.9, "render_preview lofi chip is green")
	field.queue_free()
	return failed




