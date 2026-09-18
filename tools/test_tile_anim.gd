extends SceneTree
## A1 seawater / waterfall: blit frames differ; chunk overlay advances.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var TileId = load("res://scripts/map/tile_id.gd")
	var TileBlit = load("res://scripts/map/tile_blit.gd")
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")

	failed += _expect(TileId.is_animated_a1(TileId.TILE_ID_A1), "kind 0 sea animates")
	failed += _expect(TileId.is_animated_a1(TileId.TILE_ID_A1 + 48), "kind 1 water animates")
	failed += _expect(not TileId.is_animated_a1(TileId.TILE_ID_A1 + 96), "kind 2 static")
	failed += _expect(not TileId.is_animated_a1(TileId.TILE_ID_A1 + 144), "kind 3 static")
	failed += _expect(TileId.is_animated_a1(TileId.TILE_ID_A1 + 48 * 4), "kind 4 water animates")
	failed += _expect(TileId.is_animated_a1(TileId.TILE_ID_A1 + 48 * 5), "kind 5 waterfall animates")
	failed += _expect(not TileId.is_animated_a1(TileId.TILE_ID_A2), "A2 does not animate")
	failed += _expect(not TileId.is_animated_a1(1), "B tile does not animate")

	var pack = ContentPack.new()
	pack.new_blank("unit_tile_anim", "anim", 16, 16)
	var a1_path := _runtime_root() + "/assets/tilesheet/Outside_A1.png"
	failed += _expect(FileAccess.file_exists(a1_path), "runtime Outside_A1")
	var a1: Image = Image.load_from_file(a1_path)
	failed += _expect(a1 != null and a1.get_width() > 0, "Outside_A1 sheet")
	var sheets: Array = [a1]

	var sea_id: int = TileId.TILE_ID_A1
	var img0 := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img0.fill(Color(0, 0, 0, 0))
	var img1 := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img1.fill(Color(0, 0, 0, 0))
	var flags := PackedInt32Array()
	TileBlit.blit_tile(img0, sea_id, 0, 0, sheets, 48, 48, flags, 0)
	TileBlit.blit_tile(img1, sea_id, 0, 0, sheets, 48, 48, flags, 1)
	failed += _expect(_used(img0), "sea frame 0 has pixels")
	failed += _expect(_images_differ(img0, img1), "sea frame 0 vs 1 differ")

	var wf_id: int = TileId.TILE_ID_A1 + 48 * 5
	var wf0 := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	wf0.fill(Color(0, 0, 0, 0))
	var wf1 := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	wf1.fill(Color(0, 0, 0, 0))
	TileBlit.blit_tile(wf0, wf_id, 0, 0, sheets, 48, 48, flags, 0)
	TileBlit.blit_tile(wf1, wf_id, 0, 0, sheets, 48, 48, flags, 1)
	failed += _expect(_used(wf0), "waterfall frame 0 has pixels")
	failed += _expect(_images_differ(wf0, wf1), "waterfall frame 0 vs 1 differ")

	var static_id: int = TileId.TILE_ID_A1 + 96
	var st0 := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	st0.fill(Color(0, 0, 0, 0))
	var st1 := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	st1.fill(Color(0, 0, 0, 0))
	TileBlit.blit_tile(st0, static_id, 0, 0, sheets, 48, 48, flags, 0)
	TileBlit.blit_tile(st1, static_id, 0, 0, sheets, 48, 48, flags, 1)
	failed += _expect(not _images_differ(st0, st1), "kind 2 frame 0 vs 1 match")

	var doc = pack.get_map("Map001")
	doc.set_tile(2, 2, 0, sea_id, false)
	doc.set_tile(3, 2, 0, sea_id, false)
	failed += _expect(pack.save_dir(), "save anim pack")
	var field: Node2D = MapField.new()
	get_root().add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.rebuild()
	while not field._chunk_queue.is_empty():
		field._bake_next_chunk()
	var spr0: Sprite2D = _anim_sprite(field)
	failed += _expect(spr0 != null and spr0.texture != null, "GroundAnim sprite after bake")
	var ch: Node = _first_chunk(field)
	var jobs_n: int = 0
	if ch != null:
		jobs_n = (ch.anim_jobs as Array).size()
	failed += _expect(jobs_n > 0, "chunk stored anim jobs")
	var cpu0: Image = ch.anim_images.get("Ground") if ch != null else null
	failed += _expect(cpu0 != null and _used(cpu0), "GroundAnim has sea pixels")
	var cell0 := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	if cpu0 != null:
		cell0.blit_rect(cpu0, Rect2i(96, 96, 48, 48), Vector2i.ZERO)
	var frame1: int = int(field.tick_tile_anim())
	failed += _expect(frame1 == 1, "tick advances to frame 1")
	var cpu1: Image = ch.anim_images.get("Ground") if ch != null else null
	var cell1 := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	if cpu1 != null:
		cell1.blit_rect(cpu1, Rect2i(96, 96, 48, 48), Vector2i.ZERO)
	failed += _expect(_images_differ(cell0, cell1), "chunk overlay pixels change")
	var nxt: Image = ch.anim_images_next.get("Ground") if ch != null else null
	failed += _expect(nxt != null and _used(nxt), "next keyframe image exists")
	failed += _expect(_images_differ(cpu1, nxt), "current keyframe != next keyframe")
	var spr: Sprite2D = _anim_sprite(field)
	failed += _expect(spr != null and spr.material is ShaderMaterial, "anim uses blend shader")
	if ch != null:
		ch.refresh_anim(0, field.pack.sheets if field.pack else [], field.pack.flags if field.pack else PackedInt32Array(), field.tile_size, 0.5)
	var mat := spr.material as ShaderMaterial if spr else null
	failed += _expect(mat != null and absf(float(mat.get_shader_parameter("mix_t")) - 0.5) < 0.001, "mix_t 0.5 between keyframes")
	failed += _expect(mat != null and mat.get_shader_parameter("next_tex") != null, "next keyframe bound")
	field.free()

	failed += _bench_walk_anim_ticks()

	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)


func _bench_walk_anim_ticks() -> int:
	## Town hitch: A1 water covering a 32×32 plaza. After bake, advancing keyframes
	## must be a texture swap — not a full CPU blit of every cell (that stutters
	## about every 3 walk steps at 0.16s/step × 0.5s anim).
	var failed := 0
	var TileId = load("res://scripts/map/tile_id.gd")
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var pack = ContentPack.new()
	pack.new_blank("unit_tile_anim_walk", "walk", 32, 32)
	var a1_path := _runtime_root() + "/assets/tilesheet/Outside_A1.png"
	if not FileAccess.file_exists(a1_path):
		print("SKIP walk-anim bench (no Outside_A1)")
		return 0
	var doc = pack.get_map("Map001")
	var sea_id: int = TileId.TILE_ID_A1
	for y in range(32):
		for x in range(32):
			doc.set_tile(x, y, 0, sea_id, false)
	failed += _expect(pack.save_dir(), "save walk-anim pack")
	var field: Node2D = MapField.new()
	get_root().add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	var t_bake := Time.get_ticks_usec()
	field.rebuild()
	while not field._chunk_queue.is_empty():
		field._bake_next_chunk()
	var bake_ms := float(Time.get_ticks_usec() - t_bake) / 1000.0
	print("BENCH water 32x32 bake %.1f ms chunks=%d" % [bake_ms, field._chunks.size()])
	var jobs_total := 0
	for key in field._chunks.keys():
		var ch: Node = field._chunks[key]
		if ch != null:
			jobs_total += (ch.anim_jobs as Array).size()
	failed += _expect(jobs_total >= 32 * 32, "every cell queued as A1 anim")
	var t0 := Time.get_ticks_usec()
	var worst := 0.0
	for _i in range(4):
		var s := Time.get_ticks_usec()
		field.tick_tile_anim()
		var one := float(Time.get_ticks_usec() - s) / 1000.0
		if one > worst:
			worst = one
	var tick_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH 4 anim ticks %.2f ms (worst %.2f)" % [tick_ms, worst])
	failed += _expect(worst < 12.0, "single keyframe swap < 12ms (no full blit hitch)")
	failed += _expect(tick_ms < 24.0, "4 keyframe swaps < 24ms")
	field.free()
	return failed


func _first_chunk(field: Node2D) -> Node:
	for key in field._chunks.keys():
		var node: Node = field._chunks[key]
		if node != null:
			return node
	return null


func _anim_sprite(field: Node2D) -> Sprite2D:
	var node: Node = _first_chunk(field)
	if node == null:
		return null
	return node.get_node_or_null("GroundAnim") as Sprite2D


func _used(img: Image) -> bool:
	if img == null:
		return false
	var r: Rect2i = img.get_used_rect()
	return r.size.x > 0 and r.size.y > 0


func _images_differ(a: Image, b: Image) -> bool:
	if a == null or b == null:
		return true
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return true
	var step: int = 4
	for y in range(0, a.get_height(), step):
		for x in range(0, a.get_width(), step):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				return true
	return false


func _px_hash(img: Image) -> int:
	if img == null:
		return 0
	var h: int = 0
	var step: int = 6
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c: Color = img.get_pixel(x, y)
			h = (h * 16777619) ^ int(c.r * 255.0)
			h = (h * 16777619) ^ int(c.g * 255.0)
			h = (h * 16777619) ^ int(c.b * 255.0)
	return h





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
