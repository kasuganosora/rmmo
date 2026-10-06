extends SceneTree
const Doc = preload("res://scripts/world3d/world_document.gd")
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
const Stroke = preload("res://scripts/world_editor/auto_tile_stroke.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
var editor: Node3D
var failed := 0


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failed += 1


func settle() -> void:
	for i in 3: await process_frame
	await physics_frame
	await process_frame


func point(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * 4, editor._auto_height, (cell.y + 0.5) * 4)


func screen(cell: Vector2i) -> Vector2:
	return editor._camera.unproject_position(point(cell)) + editor._canvas.global_position


func mouse(cell: Vector2i, pressed: bool, shift: bool = false, outside: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.shift_pressed = shift
	event.position = Vector2(160, 300) if outside else screen(cell)
	Input.parse_input_event(event)
	await settle()


func motion(cell: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = screen(cell)
	Input.parse_input_event(event)
	await settle()


func choose(family: String) -> void:
	for i in editor._palette_items.size():
		if editor._palette_items[i].get("auto_family") == family:
			editor._palette.select(i)
			editor._on_palette_selected(i)
			return
	check(false, "missing palette family " + family)


func record(cell: Vector2i, family: String, elevation: float = 0) -> Dictionary:
	return Rules.index_records(editor._doc.records).get(Rules.key(cell, family, 4, elevation), {})


func line(doc, family: String, from: Vector2i, to: Vector2i, elevation: float = 0) -> void:
	var stroke := Stroke.new()
	stroke.begin(doc, family, 4, elevation, false)
	stroke.paint(Vector3(from.x * 4 + 2, elevation, from.y * 4 + 2))
	stroke.paint(Vector3(to.x * 4 + 2, elevation, to.y * 4 + 2))
	stroke.finish()


func capture(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	var path := preload("res://scripts/asset/art_paths.gd").review_path("editor_transform/" + name + ".png")
	root.get_texture().get_image().save_png(path)
	print("capture=" + path)


func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	var doc = Doc.new()
	doc.add_box("ground", Vector3(0, -0.4, 0), Vector3(48, 0.2, 40))
	doc.records.back().color = [0.26, 0.29, 0.31]
	for z in range(-2, 3): line(doc, "grass", Vector2i(-3, z), Vector2i(3, z))
	for z in range(-2, 1): line(doc, "water", Vector2i(1, z), Vector2i(3, z))
	line(doc, "water", Vector2i(0, -1), Vector2i(0, -1))
	for z in range(-1, 2): line(doc, "dirt", Vector2i(-3, z), Vector2i(-2, z))
	line(doc, "wall", Vector2i(-3, -2), Vector2i(-1, -2))
	line(doc, "wall", Vector2i(-3, -2), Vector2i(-3, 0))
	var directory: String = preload("res://scripts/world3d/map_paths.gd").cache_directory("autotile_ui_%d" % Time.get_ticks_usec())
	var session = root.get_node("GameSession")
	session.world3d_editor_doc = doc
	session.world3d_editor_path = directory.path_join("map.gltf")
	editor = load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(editor)
	await settle()
	editor._camera.position = Vector3(17, 20, 24)
	editor._camera.look_at(Vector3(0, 0, 1))
	editor._orbit_center = Vector3(0, 0, 1)
	choose("road")
	await settle()
	check(editor._auto_toolbar.visible, "choosing auto module reveals grid elevation and erase controls")
	var ground: Node = editor._view.get_child(0)
	var undo_count: int = doc._undo.size()
	await mouse(Vector2i(-2, 1), true)
	await motion(Vector2i(1, 1))
	await motion(Vector2i(1, 3))
	await mouse(Vector2i(1, 3), false, false, true)
	check(not editor._auto_stroke.active and doc._undo.size() == undo_count + 1, "real drag commits whole automatic path after release over dock")
	check(ground == editor._view.get_child(0), "automatic painting retains unrelated ground node")
	var corner := record(Vector2i(1, 1), "road")
	check(not corner.is_empty() and Rules.shape_name(int(corner.tile3d.mask)) == "转角", "mouse path chooses the corner mesh automatically")
	check(not record(Vector2i(0, 1), "road").is_empty(), "fast mouse motion fills intermediate cells")
	undo_count = doc._undo.size()
	await mouse(Vector2i(-2, 1), true)
	await motion(Vector2i(1, 1))
	await mouse(Vector2i(1, 1), false)
	check(doc._undo.size() == undo_count, "repainting through UI is a no-op")
	await mouse(Vector2i(1, 1), true, true)
	await mouse(Vector2i(1, 1), false)
	check(record(Vector2i(1, 1), "road").is_empty() and Rules.shape_name(int(record(Vector2i(0, 1), "road").tile3d.mask)) == "端头", "Shift eraser removes corner and rebuilds adjacent endpoint")
	editor._undo()
	check(Rules.shape_name(int(record(Vector2i(1, 1), "road").tile3d.mask)) == "转角", "undo restores path connectivity")
	var before: Array = doc.records.duplicate(true)
	await mouse(Vector2i(2, 3), true)
	await motion(Vector2i(3, 3))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await settle()
	await mouse(Vector2i(3, 3), false)
	check(doc.records == before, "Esc from real input cancels painted cells and neighbor updates")
	# Branch into the road to show an actual T-junction.
	await mouse(Vector2i(-1, -1), true)
	await motion(Vector2i(-1, 1))
	await mouse(Vector2i(-1, 1), false)
	check(Rules.shape_name(int(record(Vector2i(-1, 1), "road").tile3d.mask)) == "T 形", "new branch turns an existing straight into a T-junction")
	choose("grass")
	editor._grid.visible = false
	await capture("autotile_terrain_roads")
	# Editing an auto tile as an ordinary object must not snap back on the next brush.
	var selected := record(Vector2i(-2, 1), "road")
	var selected_id: String = selected.uuid
	editor._inspector.select(selected_id)
	editor._set_transform_mode(0)
	editor._inspector.fields.position_0.value += 0.25
	check(not Rules.attached(doc._find(selected_id)) and record(Vector2i(-2, 1), "road").is_empty(), "manual transform explicitly detaches tile from grid membership")
	editor._undo()
	check(Rules.attached(doc._find(selected_id)), "undo manual transform restores attached tile and neighboring variants")
	# An L-shaped wall must leave its inside corner pickable as the terrain below.
	var wall := record(Vector2i(-3, -2), "wall")
	var empty_corner := Vector3(-9, 0, -5)
	var query := PhysicsRayQueryParameters3D.create(empty_corner + Vector3.UP * 5, empty_corner - Vector3.UP)
	await settle()
	var hit := editor.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider.get_meta("uuid", "") != wall.uuid and hit.position.y < 0.01, "wall inside corner uses actual mesh collision instead of a filled bounding box")
	choose("wall")
	editor._auto_height = 3
	await settle()
	await mouse(Vector2i(0, -2), true)
	await motion(Vector2i(2, -2))
	await mouse(Vector2i(2, -2), false)
	check(not record(Vector2i(0, -2), "wall", 3).is_empty() and record(Vector2i(0, -2), "wall", 0).is_empty(), "explicit elevation paints a separate upper layer")
	editor._undo()
	editor._auto_height = 0
	check(editor._save() and editor.open_document(editor._path), "editor saves and reopens automatic tile document")
	check(Rules.shape_name(int(record(Vector2i(-1, 1), "road").tile3d.mask)) == "T 形", "reopened document keeps editable connection variants")
	choose("water")
	root.size = Vector2i(1024, 720)
	root.content_scale_size = root.size
	await capture("autotile_1024")
	check(editor._canvas.size.x > 600 and editor._auto_toolbar.get_global_rect().end.x <= 1024, "auto painting controls fit the 1024 px layout")
	editor.free()
	session.world3d_editor_doc = null
	session.world3d_editor_path = ""
	Io._remove_tree(directory)
	print("test_world3d_autotile_ui: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
