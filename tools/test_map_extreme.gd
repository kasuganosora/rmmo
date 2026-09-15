extends SceneTree
## Functional + stress: streaming continent, JIT overview, collision, path, editor chunk.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _func_dense_unchanged()
	failed += _func_collision_stream()
	failed += _func_path_budget()
	failed += _stress_paint_and_jit()
	failed += _stress_sample_cache()
	failed += _stress_pan_stream()
	failed += _stress_town_1500()
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


func _func_dense_unchanged() -> int:
	var failed := 0
	var MapField = load("res://scripts/map/map_field.gd")
	var mf = MapField.new()
	mf.pack_path = "res://demo_map"
	root.add_child(mf)
	mf.rebuild()
	failed += _expect(mf.grid_width == 30, "demo still 30 wide")
	failed += _expect(mf.get_radar_atlas_image() != null, "demo radar")
	failed += _expect(mf.get_lofi_image() != null and mf.get_lofi_image().get_width() == 30, "demo lofi full map")
	failed += _expect(bool(mf.world_map_complete()), "small map overview complete")
	failed += _expect(mf._chunks.size() > 0, "demo high-res chunks")
	mf.queue_free()
	return failed


func _func_collision_stream() -> int:
	var failed := 0
	var MapCollision = load("res://scripts/map/map_collision.gd")
	var Store = load("res://scripts/map/map_chunk_store.gd")
	var col = MapCollision.new()
	var flags := PackedInt32Array()
	flags.resize(8)
	col.setup_streaming(10000, 10000, flags, 16)
	failed += _expect(bool(col.streaming), "collision streaming")
	failed += _expect(int(col.tile_id(40, 40, 0)) == 0, "unloaded is 0")
	var buf: PackedInt32Array = Store.empty_buf()
	buf[Store.local_index(8, 8, 0)] = 1
	flags[1] = 0
	col.flags = flags
	col.ingest_stream_chunk(2, 2, buf)
	failed += _expect(int(col.tile_id(40, 40, 0)) == 1, "ingested chunk readable")
	failed += _expect(int(col.tile_id(0, 0, 0)) == 0, "other chunk still empty")
	col.drop_stream_chunk(2, 2)
	failed += _expect(int(col.tile_id(40, 40, 0)) == 0, "drop unloads")
	failed += _expect(int(col.path_search_budget()) <= 200000, "path budget capped")
	return failed


func _func_path_budget() -> int:
	var failed := 0
	var MapCollision = load("res://scripts/map/map_collision.gd")
	var Store = load("res://scripts/map/map_chunk_store.gd")
	var GridPath = load("res://scripts/map/grid_path.gd")
	var col = MapCollision.new()
	var flags := PackedInt32Array()
	flags.resize(16)
	col.setup_streaming(512, 512, flags, 16)
	var buf: PackedInt32Array = Store.empty_buf()
	for ly in range(16):
		for lx in range(16):
			buf[Store.local_index(lx, ly, 0)] = 1
	col.ingest_stream_chunk(0, 0, buf)
	var t0 := Time.get_ticks_usec()
	var path: Array = GridPath.find_path(col, Vector2i(1, 1), Vector2i(10, 10))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH streamed path %.2f ms len=%d" % [ms, path.size()])
	failed += _expect(path.size() > 0, "path inside loaded chunk")
	failed += _expect(ms < 50.0, "streamed path < 50ms")
	var far: Array = GridPath.find_path(col, Vector2i(1, 1), Vector2i(400, 400))
	failed += _expect(far.is_empty() or far.size() < 512 * 512, "far path does not explode")
	return failed


func _stress_paint_and_jit() -> int:
	var failed := 0
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var Store = load("res://scripts/map/map_chunk_store.gd")
	var pack = ContentPack.new()
	pack.new_blank("stress_pack", "压力", 2048, 2048)
	var doc = pack.get_map("Map001")
	failed += _expect(bool(doc.uses_chunks()), "2048 is chunked")
	failed += _expect(int(doc.data.size()) == 0, "no dense RAM")
	var dirt := 2816
	var t0 := Time.get_ticks_usec()
	doc.begin_undo_batch()
	for y in range(0, 128):
		for x in range(0, 128):
			doc.set_tile(x, y, 0, dirt, false)
	if doc.has_method("end_undo_batch"):
		doc.end_undo_batch()
	var paint_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH paint 128x128 on 2048 %.1f ms" % paint_ms)
	failed += _expect(paint_ms < 2500.0, "paint 16k cells < 2.5s")
	t0 = Time.get_ticks_usec()
	failed += _expect(pack.save_dir(), "save stress pack")
	var save_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH save 2048 with 64 chunks %.1f ms" % save_ms)
	failed += _expect(save_ms < 4000.0, "save < 4s")
	var nfiles: int = Store.list_chunk_coords("%s/maps/Map001" % pack.root).size()
	failed += _expect(nfiles >= 8, "multiple chunk files (%d)" % nfiles)
	failed += _expect(int(doc.tile(100, 100, 0)) == dirt, "painted cell")
	failed += _expect(int(doc.tile(2000, 2000, 0)) == 0, "far empty")

	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.edit_start_cell = Vector2i(64, 64)
	t0 = Time.get_ticks_usec()
	field.rebuild()
	var rebuild_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH rebuild 2048 editor %.1f ms chunks=%d" % [rebuild_ms, field._chunks.size()])
	failed += _expect(rebuild_ms < 3000.0, "rebuild < 3s")
	failed += _expect(field._chunks.size() <= 1, "editor one chunk")
	var ov: String = str(Store.overview_path("%s/maps/Map001" % pack.root))
	var ov_abs: String = ov if FileAccess.file_exists(ov) else ProjectSettings.globalize_path(ov)
	if FileAccess.file_exists(ov_abs):
		DirAccess.remove_absolute(ov_abs)
	field._wm_complete = false
	field._lofi_image = null
	t0 = Time.get_ticks_usec()
	field.ensure_world_map()
	var g := 0
	while not bool(field.world_map_complete()) and g < 200:
		field.world_map_step(16)
		g += 1
	var jit_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH JIT overview %d chunks %.1f ms steps=%d" % [nfiles, jit_ms, g])
	failed += _expect(bool(field.world_map_complete()), "JIT complete")
	failed += _expect(jit_ms < 2000.0, "JIT < 2s")
	var img: Image = field.get_lofi_image()
	failed += _expect(img != null and img.get_width() <= 1024, "overview capped")
	field.queue_free()
	return failed


func _stress_sample_cache() -> int:
	var failed := 0
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var pack = ContentPack.new()
	pack.new_blank("cache_pack", "缓存", 512, 512)
	var doc = pack.get_map("Map001")
	for y in range(0, 48):
		for x in range(0, 48):
			doc.set_tile(x, y, 0, 2816, false)
	pack.save_dir()
	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.rebuild()
	var t0 := Time.get_ticks_usec()
	for i in range(32):
		field.sample_world_chunk(0, 0)
		field.sample_world_chunk(1, 1)
	var cold := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	for i in range(32):
		field.sample_world_chunk(0, 0)
		field.sample_world_chunk(1, 1)
	var hot := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH sample_world_chunk cold %.2f ms hot %.2f ms" % [cold, hot])
	failed += _expect(hot <= cold + 0.05, "cached sample not slower")
	failed += _expect(hot < 20.0, "hot sample 64 calls < 20ms")
	field.queue_free()
	return failed


func _stress_pan_stream() -> int:
	var failed := 0
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var MapOverview = load("res://scripts/ui/map_overview.gd")
	var pack = ContentPack.new()
	pack.new_blank("pan_pack", "拖动", 10000, 10000)
	var doc = pack.get_map("Map001")
	for y in range(0, 64, 8):
		for x in range(0, 64, 8):
			doc.set_tile(x, y, 0, 2816, false)
	pack.save_dir()
	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.edit_start_cell = Vector2i(16, 16)
	field.rebuild()
	var ov: Control = MapOverview.new()
	root.add_child(ov)
	ov.size = Vector2(400, 300)
	ov.bind(field, null, "Map001")
	ov.set_cells_across(48)
	var t0 := Time.get_ticks_usec()
	for i in range(20):
		ov.set_pan_cell(Vector2(8.0 + float(i) * 4.0, 8.0))
		ov.step_live(4)
	var pan_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH 20 pans %.1f ms tex=%d" % [pan_ms, ov.visible_chunk_count()])
	failed += _expect(pan_ms < 1500.0, "20 pans < 1.5s")
	failed += _expect(ov.visible_chunk_count() <= 48, "stream tex capped")
	failed += _expect(bool(ov.has_stream_chunk(1, 0)) or bool(ov.has_stream_chunk(0, 0)) or bool(ov.has_stream_chunk(2, 0)), "panned chunks streamed")
	ov.queue_free()
	field.queue_free()
	return failed


func _stress_town_1500() -> int:
	## Fully painted 1500×1500 town (~7× the 96 town, ~8836 chunks).
	var failed := 0
	var Store = load("res://scripts/map/map_chunk_store.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var counts: Vector2i = Store.chunk_counts(1500, 1500)
	failed += _expect(counts.x * counts.y >= 8000, "1500 map has ~8k chunks")
	var dir := "user://content/packs/_town1500/maps/Map001"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	Store.invalidate_index(dir)
	var buf: PackedInt32Array = Store.empty_buf()
	for ly in range(16):
		for lx in range(16):
			buf[Store.local_index(lx, ly, 0)] = 2816
	var t0 := Time.get_ticks_usec()
	failed += _expect(Store.save_uniform_grid(dir, 1500, 1500, buf), "pack 1500 grid")
	var save_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH 1500x1500 pack %d chunks %.1f ms" % [counts.x * counts.y, save_ms])
	failed += _expect(save_ms < 8000.0, "1500 pack write < 8s")
	var n: int = Store.list_chunk_coords(dir).size()
	failed += _expect(n == counts.x * counts.y, "index lists all chunks (%d)" % n)
	t0 = Time.get_ticks_usec()
	var loaded: PackedInt32Array = Store.load_chunk(dir, 50, 40)
	var load_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH load one packed chunk %.2f ms" % load_ms)
	failed += _expect(int(loaded[Store.local_index(0, 0, 0)]) == 2816, "packed chunk tile")
	failed += _expect(load_ms < 15.0, "random chunk load < 15ms")
	t0 = Time.get_ticks_usec()
	var ov: Image = Store.bake_overview_dir(dir, 1500, 1500, [], PackedInt32Array(), {})
	var bake_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH 1500 overview bake %.1f ms %dx%d" % [bake_ms, ov.get_width() if ov else 0, ov.get_height() if ov else 0])
	failed += _expect(ov != null and ov.get_width() <= 1024, "1500 overview capped")
	failed += _expect(bake_ms < 12000.0, "1500 overview < 12s")
	var pack = ContentPack.new()
	pack.new_blank("town1500", "大城镇", 1500, 1500)
	failed += _expect(pack.save_dir(), "save 1500 pack json")
	Store.invalidate_index("%s/maps/Map001" % pack.root)
	failed += _expect(Store.save_uniform_grid("%s/maps/Map001" % pack.root, 1500, 1500, buf), "overwrite 1500 chunks")
	var doc = pack.get_map("Map001")
	doc._store_dir = "%s/maps/Map001" % pack.root
	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.edit_start_cell = Vector2i(40, 40)
	t0 = Time.get_ticks_usec()
	field.rebuild()
	var reb_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH 1500 editor rebuild %.1f ms chunks=%d" % [reb_ms, field._chunks.size()])
	failed += _expect(reb_ms < 2500.0, "1500 editor open < 2.5s")
	failed += _expect(field._chunks.size() <= 1, "1500 editor one high-res chunk")
	var ch_img: Image = field.sample_world_chunk(50, 40)
	failed += _expect(ch_img != null, "1500 stream sample")
	field.queue_free()
	return failed
