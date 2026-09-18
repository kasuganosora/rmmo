extends SceneTree
## Blank-map editor paint must show up (void cull used to skip all-zero packs).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var pack = ContentPack.new()
	pack.new_blank("unit_paint_pack", "paint", 16, 16)
	var doc = pack.get_map("Map001")
	var TileId = load("res://scripts/map/tile_id.gd")
	failed += _expect(TileId.autotile_kind(int(doc.tile(3, 4, 0))) == 16, "blank map starts as grass")
	doc.set_tile(3, 4, 0, 2816)
	failed += _expect(int(doc.tile(3, 4, 0)) == 2816, "edit_doc stores A2 grass")
	failed += _expect(pack.save_dir(), "save paint pack")
	var field: Node2D = MapField.new()
	get_root().add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc
	field.show_grid = true
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.rebuild()
	while not field._chunk_queue.is_empty():
		field._bake_next_chunk()
	failed += _expect(bool(field._stream_ready), "field stream ready")
	failed += _expect(not field._chunks.is_empty(), "chunks exist after rebuild")
	var painted := _chunk_has_pixels(field)
	failed += _expect(painted, "painted A2 cell is visible on chunk")
	field.free()
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)


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
		if used.size.x > 0 and used.size.y > 0:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1
