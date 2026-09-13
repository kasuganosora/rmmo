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
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var pack = ContentPack.new()
	pack.new_blank("unit_autotile_vis", "at", 16, 16)
	var d2 = pack.get_map("Map001")
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
	failed += _expect(_chunk_has_pixels(field), "autotile patch is visible")
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
		if used.size.x > 8 and used.size.y > 8:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1
