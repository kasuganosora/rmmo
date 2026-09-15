extends SceneTree
## Sparse 10000×10000: chunk files, local radar, offline overview, no dense RAM.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_chunk_store_roundtrip()
	failed += _test_continent_pack()
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


func _test_chunk_store_roundtrip() -> int:
	var failed := 0
	var Store = load("res://scripts/map/map_chunk_store.gd")
	failed += _expect(Store.should_chunk(10000, 10000), "10000 is chunked")
	failed += _expect(not Store.should_chunk(96, 96), "96 is dense")
	var buf: PackedInt32Array = Store.empty_buf()
	buf[Store.local_index(3, 4, 0)] = 1536
	var dir := "user://content/packs/_chunk_unit"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	failed += _expect(Store.save_chunk(dir, 2, 3, buf), "save chunk")
	var loaded: PackedInt32Array = Store.load_chunk(dir, 2, 3)
	failed += _expect(loaded.size() == buf.size(), "load size")
	failed += _expect(int(loaded[Store.local_index(3, 4, 0)]) == 1536, "load tile")
	failed += _expect(Store.load_chunk(dir, 9, 9).is_empty(), "missing chunk empty")
	return failed


func _test_continent_pack() -> int:
	var failed := 0
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var Store = load("res://scripts/map/map_chunk_store.gd")
	var pack = ContentPack.new()
	pack.new_blank("continent_pack", "大陆", 10000, 10000)
	var doc = pack.get_map("Map001")
	failed += _expect(doc != null and int(doc.width) == 10000, "blank 10000")
	failed += _expect(bool(doc.uses_chunks()), "doc chunked")
	failed += _expect(int(doc.data.size()) == 0, "no 2.4GB buffer")
	doc.set_tile(40, 40, 0, 2816, false)
	doc.set_tile(41, 40, 0, 2816, false)
	doc.set_ext_tile("meta", 40, 40, 4, false)
	var t0 := Time.get_ticks_usec()
	failed += _expect(pack.save_dir(), "save continent")
	var save_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH save 10000x10000 %.1f ms" % save_ms)
	failed += _expect(save_ms < 5000.0, "save continent < 5s")
	var mdir: String = "%s/maps/Map001" % pack.root
	failed += _expect(Store.load_chunk(mdir, 2, 2).size() > 0, "chunk stored for cell 40,40")
	failed += _expect(
		not FileAccess.file_exists("%s/map.data.bin" % mdir) and not FileAccess.file_exists(ProjectSettings.globalize_path("%s/map.data.bin" % mdir)),
		"no dense data.bin"
	)
	var ov: String = str(Store.overview_path(mdir))
	failed += _expect(FileAccess.file_exists(ov) or FileAccess.file_exists(ProjectSettings.globalize_path(ov)), "overview.png baked")
	if FileAccess.file_exists(ov) or FileAccess.file_exists(ProjectSettings.globalize_path(ov)):
		var oimg := Image.new()
		var opath: String = ov if FileAccess.file_exists(ov) else ProjectSettings.globalize_path(ov)
		failed += _expect(oimg.load(opath) == OK, "overview loads")
		failed += _expect(oimg.get_width() <= 1024 and oimg.get_height() <= 1024, "overview capped 1024")

	var pack2 = ContentPack.new()
	failed += _expect(pack2.load_dir(pack.root), "reload continent")
	var doc2 = pack2.get_map("Map001")
	failed += _expect(bool(doc2.uses_chunks()), "reloaded chunked")
	failed += _expect(int(doc2.tile(40, 40, 0)) == 2816, "chunk tile survived")
	failed += _expect(int(doc2.tile(5000, 5000, 0)) == 0, "far cell empty without RAM")
	failed += _expect(int(doc2.ext_tile("meta", 40, 40)) == 4, "sparse ext survived")

	var tp = TilemapPack.load_pack(pack.root, "Map001")
	failed += _expect(tp != null and bool(tp.streaming), "runtime streaming pack")
	failed += _expect(int(tp.data.size()) == 0, "pack has no dense data")
	failed += _expect(tp.collision != null and bool(tp.collision.streaming), "collision streaming")

	var field: Node2D = MapField.new()
	failed += _expect(field != null, "MapField script loads")
	if field == null:
		return failed
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc2
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.edit_start_cell = Vector2i(40, 40)
	t0 = Time.get_ticks_usec()
	field.rebuild()
	var bake_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH field 10000x10000 rebuild %.1f ms radar=%dx%d chunks=%d" % [
		bake_ms,
		field.get_radar_atlas_image().get_width() if field.get_radar_atlas_image() else 0,
		field.get_radar_atlas_image().get_height() if field.get_radar_atlas_image() else 0,
		field._chunks.size(),
	])
	failed += _expect(bake_ms < 4000.0, "rebuild continent < 4s")
	failed += _expect(field._chunks.size() <= 1, "editor loads only current chunk (%d)" % field._chunks.size())
	var cr: Rect2i = field.current_chunk_rect()
	failed += _expect(cr.position == Vector2i(32, 32), "chunk origin 32,32")
	failed += _expect(cr.size.x == 16 and cr.size.y == 16, "chunk is 16x16")
	var wanted: Dictionary = field._wanted_chunks(Vector2i(40, 40), 2)
	failed += _expect(wanted.size() == 1, "wanted 1 chunk in continent editor")
	var atlas: Image = field.get_radar_atlas_image()
	failed += _expect(atlas != null, "radar atlas")
	failed += _expect(atlas != null and atlas.get_width() <= 48 and atlas.get_height() <= 48, "radar is current-chunk window not 10000")
	failed += _expect(field.get_radar_origin_cell() != Vector2i(-1, -1), "radar origin cell")
	var shot: Image = field.render_preview(cr.position.x, cr.position.y, cr.size.x, cr.size.y)
	failed += _expect(shot != null and shot.get_width() == 16 * 48, "chunk preview 768px")
	var clamped: Image = field.render_preview(0, 0, 10000, 10000)
	failed += _expect(clamped != null and clamped.get_width() <= 16 * 48, "full-map preview clamps to chunk")
	field.set_edit_camera_cell(Vector2i(40, 40))
	field._rebuild_radar_window()
	failed += _expect(int(field._src_tile(field.collision, 40, 40, 0)) == 2816 or int(doc2.tile(40, 40, 0)) == 2816, "src tile in window")

	var ov_path: String = str(Store.overview_path(mdir))
	var ov_abs: String = ov_path if FileAccess.file_exists(ov_path) else ProjectSettings.globalize_path(ov_path)
	if FileAccess.file_exists(ov_abs):
		DirAccess.remove_absolute(ov_abs)
	field._wm_complete = false
	field._lofi_image = null
	field._world_map_tex = null
	failed += _expect(not bool(field.world_map_complete()), "overview missing after delete")
	field.ensure_world_map()
	var guard := 0
	while not bool(field.world_map_complete()) and guard < 80:
		field.world_map_step(8)
		guard += 1
	failed += _expect(bool(field.world_map_complete()), "JIT overview finishes")
	var jit: Image = field.get_lofi_image()
	failed += _expect(jit != null and jit.get_width() <= 1024, "JIT overview capped")
	var lit := 0
	if jit != null:
		for yy in range(jit.get_height()):
			for xx in range(jit.get_width()):
				var pc: Color = jit.get_pixel(xx, yy)
				if pc.r > 0.08 or pc.g > 0.08 or pc.b > 0.08:
					lit += 1
	failed += _expect(lit > 0, "JIT stamped painted chunk")
	var ch_img: Image = field.sample_world_chunk(2, 2)
	failed += _expect(ch_img != null and ch_img.get_width() == 16, "stream chunk 16x16")
	var MapOverview = load("res://scripts/ui/map_overview.gd")
	var ovui: Control = MapOverview.new()
	root.add_child(ovui)
	ovui.size = Vector2(400, 300)
	ovui.bind(field, null, "Map001")
	ovui.set_cells_across(48)
	ovui.set_pan_cell(Vector2(40, 40))
	ovui.step_live(8)
	failed += _expect(bool(ovui.has_stream_chunk(2, 2)), "drag view streams current chunk")
	ovui.queue_free()

	var Editor = load("res://scripts/editor/content_editor.gd")
	var EditorMcp = load("res://scripts/editor/editor_mcp.gd")
	var ed = Editor.new()
	ed.pack = pack2
	ed.doc = doc2
	ed.current_map_id = "Map001"
	ed._cursor = Vector2i(40, 40)
	ed.map_field = field
	var mcp = EditorMcp.new()
	root.add_child(mcp)
	mcp.editor = ed
	var prev: Dictionary = mcp.call_tool("preview_map", {})
	failed += _expect(bool(prev.get("ok", false)), "mcp default preview ok")
	failed += _expect(int(prev.get("w", 0)) == 16, "mcp preview current chunk w")
	failed += _expect(int(prev.get("h", 0)) == 16, "mcp preview current chunk h")
	failed += _expect(int(prev.get("x", -1)) == 32, "mcp preview chunk origin x")
	var ovp: Dictionary = mcp.call_tool("preview_map", {"overview": true, "max_px": 256, "grid": false})
	failed += _expect(bool(ovp.get("ok", false)), "mcp overview uses offline png")
	failed += _expect(int(ovp.get("px_w", 99999)) <= 1024, "overview not 10000px")
	mcp.queue_free()
	ed.free()
	field.queue_free()
	return failed
