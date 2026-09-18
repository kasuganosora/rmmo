extends SceneTree
## Minimap thumbnail + small-px render_preview.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var MapMinimap = load("res://scripts/editor/interface/map_minimap.gd")
	var TileId = load("res://scripts/map/tile_id.gd")
	var pack = ContentPack.new()
	pack.new_blank("mini_pack", "缩略图", 24, 16)
	failed += _expect(pack.save_dir(), "save pack")
	var doc = pack.get_map("Map001")
	var dirt: int = TileId.TILE_ID_A1 + 24 * 48
	for y in range(4, 12):
		for x in range(6, 14):
			doc.set_tile(x, y, 0, dirt, false)
	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.rebuild()
	var img: Image = field.render_preview(0, 0, int(doc.width), int(doc.height), 2)
	failed += _expect(img != null, "preview image")
	failed += _expect(img.get_width() == 48, "2px * 24 = 48")
	failed += _expect(img.get_height() == 32, "2px * 16 = 32")
	failed += _expect(_has_color(img), "thumbnail has color")

	var mini: Control = MapMinimap.new()
	root.add_child(mini)
	mini.size = Vector2(220, 176)
	if mini._host:
		mini._host.size = Vector2(214, 170)
	mini.rebuild(field, doc)
	failed += _expect(mini._tex != null, "minimap texture")
	failed += _expect(int(mini.map_w) == 24, "minimap map_w")
	failed += _expect(int(mini.cell_px) >= 1, "cell_px")
	var jumped := [Vector2.ZERO]
	mini.jump_to_world.connect(func(p): jumped[0] = p)
	var r: Rect2 = mini.map_draw_rect()
	failed += _expect(r.size.x > 8.0 and r.size.y > 8.0, "draw rect")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = r.position + r.size * 0.5
	mini._on_input(ev)
	failed += _expect(jumped[0].x > 0.0 and jumped[0].y > 0.0, "click jumps")
	var half_w := float(doc.width * doc.tile_size) * 0.5
	failed += _expect(absf(jumped[0].x - half_w) < float(doc.tile_size) * 2.0, "jump near center x")
	mini.set_view_world(Rect2(Vector2(48, 48), Vector2(200, 120)))
	failed += _expect(mini.view_world.size.x == 200.0, "view rect stored")

	field.free()
	mini.free()
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED %d" % failed)
		quit(1)


func _has_color(img: Image) -> bool:
	if img == null:
		return false
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.g > 0.08 or c.r > 0.08 or c.b > 0.08:
				return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS %s" % label)
		return 0
	print("FAIL %s" % label)
	return 1
