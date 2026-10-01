extends SceneTree
const Doc = preload("res://scripts/world3d/world_document.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
var editor: Node3D
var failed := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failed += 1

func settle() -> void:
	for i in 4: await process_frame
	await physics_frame
	await process_frame

func mouse(point: Vector2, pressed: bool, shift: bool = false, global: bool = false, ctrl: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point if global else editor._canvas.global_position + point
	event.pressed = pressed
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	Input.parse_input_event(event)
	await settle()

func click(point: Vector2, shift: bool = false) -> void:
	await mouse(point, true, shift)
	await mouse(point, false, shift)

func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = editor._canvas.global_position + point
	Input.parse_input_event(event)
	await settle()

func key(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	Input.parse_input_event(event)
	await settle()

func project(point: Vector3) -> Vector2: return editor._camera.unproject_position(point)

func position(id: String) -> Vector3: return Geometry.vector(editor._doc._find(id), "position")

func list_click(id: String, column: int, ctrl: bool = false) -> void:
	var item: TreeItem = editor._object_list._items[id]
	var rect: Rect2 = editor._object_list.tree.get_item_area_rect(item, column)
	var point: Vector2 = editor._object_list.tree.global_position + rect.get_center()
	await mouse(point, true, false, true, ctrl)
	await mouse(point, false, false, true, ctrl)

func capture(name_: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	var path: String = preload("res://scripts/asset/art_paths.gd").review_path("editor_groups/" + name_ + ".png")
	root.get_texture().get_image().save_png(path)
	print("capture=" + path)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var pack: String = preload("res://scripts/world3d/map_paths.gd").external_root().path_join("__editor_groups_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(pack)
	var metadata := FileAccess.open(pack.path_join("metadata.json"), FileAccess.WRITE)
	metadata.store_string('{"id":"editor_groups_test","name":"组合测试包"}')
	metadata.close()
	var doc = Doc.new()
	var ground: String = doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(26, 0.2, 26))
	doc._find(ground).editor_locked = true
	doc._find(ground).editor_name = "地面（锁定）"
	doc._find(ground).color = [0.28, 0.36, 0.34]
	var a: String = doc.add_box("block", Vector3(-2, 1, 0), Vector3(1.5, 2, 1.5))
	doc._find(a).editor_name = "石柱 A"
	doc._find(a).color = [0.6, 0.73, 0.8]
	var b: String = doc.add_box("block", Vector3(2, 1, 0), Vector3(1.5, 2, 1.5), Vector3(0, 30, 0))
	doc._find(b).editor_name = "石柱 B"
	doc._find(b).color = [0.7, 0.65, 0.45]
	var c: String = doc.add_box("block", Vector3(6, 0.5, -4), Vector3.ONE)
	doc._find(c).editor_name = "独立物件"
	var session = root.get_node("GameSession")
	session.world3d_editor_doc = doc
	session.world3d_editor_path = pack.path_join("maps/test/map.gltf")
	editor = load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(editor)
	await settle()
	if editor._canvas == null: quit(1); return
	editor._camera.position = Vector3(8, 7, 12)
	editor._camera.look_at(Vector3(0, 1, 0))
	editor._orbit_center = Vector3(0, 1, 0)
	await key(KEY_W)
	await click(project(position(a)))
	await click(project(position(b)), true)
	check(editor._selection_tools.ids.size() == 2, "Shift click adds objects without starting a transform")
	await click(project(position(a)), true)
	check(editor._selection_tools.ids == [b], "Shift click toggles selected object off")
	await click(project(position(a)), true)
	var center: Vector3 = editor._selection_tools.pivot()
	var anchor: Vector3 = center + Vector3.RIGHT * editor._gizmo.world_length() * 0.8
	var start_a := position(a)
	var start_b := position(b)
	var history: int = doc._undo.size()
	var view: Node = editor._view
	var untouched: Node = editor._view.get_node(NodePath(c))
	await mouse(project(anchor), true)
	await motion(project(anchor + Vector3(1, 0, 0)))
	check(position(a).is_equal_approx(start_a + Vector3.RIGHT) and position(b).is_equal_approx(start_b + Vector3.RIGHT), "XYZ drag moves every selected object by the same displacement")
	check(doc._undo.size() == history and editor._view == view and editor._view.get_node(NodePath(c)) == untouched, "live group drag preserves scene nodes and undo history")
	await mouse(Vector2(-100, 220), false)
	check(doc._undo.size() == history + 1, "release over sidebar commits whole group once")
	await key(KEY_Z, true)
	check(position(a).is_equal_approx(start_a) and position(b).is_equal_approx(start_b), "undo restores all selected transforms")
	await key(KEY_Y, true)
	check(position(a).is_equal_approx(start_a + Vector3.RIGHT), "redo restores whole group")
	await key(KEY_Z, true)
	await mouse(project(anchor), true)
	await motion(project(anchor + Vector3.RIGHT * 2))
	await key(KEY_ESCAPE)
	check(position(a).is_equal_approx(start_a) and position(b).is_equal_approx(start_b) and doc._redo.size() == 1, "Escape cancels whole group without losing redo")
	await mouse(project(anchor), false)
	await key(KEY_G, true)
	var original_group: String = doc._find(a).editor_group
	check(doc._find(b).editor_group == original_group, "Ctrl+G creates one persistent group")
	editor._inspector.select("")
	await click(project(position(b)))
	check(editor._selection_tools.ids.size() == 2, "viewport click selects all members of a group")
	await key(KEY_D, true)
	var copies: Array = editor._selection_tools.ids.duplicate()
	check(copies.size() == 2 and doc._find(copies[0]).editor_group != original_group and doc._find(copies[0]).editor_group == doc._find(copies[1]).editor_group, "Ctrl+D duplicates the group with independent identities")
	await key(KEY_DELETE)
	check(doc.records.size() == 4, "Delete removes every selected member")
	await key(KEY_Z, true)
	check(doc.records.size() == 6, "undo restores the deleted group")
	await key(KEY_Z, true)
	editor._selection_tools.set_ids([a, b])
	await key(KEY_R)
	center = editor._selection_tools.pivot()
	var ring: PackedVector2Array = editor._gizmo.ring_points(1)
	var ring_index := -1
	for i in range(0, 64):
		if editor._gizmo.hit_test(ring[i]) == 1: ring_index = i; break
	check(ring_index >= 0, "group rotation ring can be picked")
	if ring_index >= 0:
		var angle := TAU * ring_index / 64.0
		var offset: Vector3 = (Vector3.BACK * cos(angle) + Vector3.RIGHT * sin(angle)) * editor._gizmo.world_length() * 0.85
		await mouse(project(center + offset), true)
		await motion(project(center + Basis(Vector3.UP, PI / 2) * offset))
		await mouse(project(center + offset), false)
		check(position(a).is_equal_approx(center + Basis(Vector3.UP, PI / 2) * (start_a - center)) and position(b).is_equal_approx(center + Basis(Vector3.UP, PI / 2) * (start_b - center)), "rotation moves component positions around the common center")
		await key(KEY_Z, true)
	await key(KEY_T)
	center = editor._selection_tools.pivot()
	var screen := project(center)
	await mouse(screen, true)
	await motion(screen + Vector2(60, -60))
	await mouse(screen + Vector2(60, -60), false)
	check(position(a).is_equal_approx(center + (start_a - center) * 2) and Geometry.vector(doc._find(b), "size").is_equal_approx(Vector3(3, 4, 3)), "uniform group scale changes both spacing and object dimensions")
	check(Geometry.vector(doc._find(b), "rotation").is_equal_approx(Vector3(0, 30, 0)), "uniform group scale preserves individual model orientation")
	await key(KEY_Z, true)
	editor._inspector.multi_scale.value = 1.5
	check(Geometry.vector(doc._find(a), "size").is_equal_approx(Vector3(2.25, 3, 2.25)), "numeric multi-selection scale applies uniformly")
	editor._undo()
	await key(KEY_G, true, true)
	check(not doc._find(a).has("editor_group") and not doc._find(b).has("editor_group"), "Ctrl+Shift+G ungroups without changing transforms")
	await key(KEY_B)
	editor._inspector.select("")
	var rectangle := Rect2(project(position(a)), Vector2.ZERO)
	for record in [doc._find(a), doc._find(b)]:
		for point in Geometry.corners(record): rectangle = rectangle.expand(project(point))
	rectangle = rectangle.grow(6)
	await mouse(rectangle.position, true)
	await motion(rectangle.end)
	await mouse(rectangle.end, false)
	check(editor._selection_tools.ids.size() == 2 and editor._selection_tools.ids.has(a) and editor._selection_tools.ids.has(b), "marquee selects enclosed objects and ignores locked ground")
	await mouse(Vector2(5, 5), true)
	await motion(Vector2(30, 30))
	await key(KEY_ESCAPE)
	check(editor._selection_tools.ids.size() == 2 and not editor._selection_tools.marquee, "Escape cancels rectangle without clearing selection")
	await mouse(Vector2(30, 30), false)
	await key(KEY_W)
	await key(KEY_G, true)
	editor._dock_tabs.current_tab = 2
	await settle()
	await list_click(a, 0)
	check(editor._selection_tools.ids == [a] and editor._dock_tabs.current_tab == 2, "object-list child can be edited independently while list stays open")
	await list_click(b, 0, true)
	check(editor._selection_tools.ids.size() == 2, "Ctrl click in object list adds another component")
	await list_click(a, 0, true)
	check(editor._selection_tools.ids == [b], "Ctrl click in object list removes a component")
	await list_click(c, 2)
	check(doc._find(c).get("editor_locked", false), "list checkbox locks object")
	editor._inspector.select(c)
	await key(KEY_DELETE)
	check(doc.has_uuid(c) and editor._selection_tools.ids.is_empty(), "locked object cannot be selected or deleted")
	await list_click(c, 2)
	await list_click(c, 1)
	check(doc._find(c).get("editor_hidden", false) and not editor._view.get_node(NodePath(c)).visible and not editor._bodies_by_uuid.has(c), "hidden object loses editor rendering and picking only")
	editor._undo()
	check(not doc._find(c).get("editor_hidden", false) and editor._bodies_by_uuid.has(c), "visibility change can be undone")
	editor._selection_tools.set_ids([a, b])
	await capture("objects_and_groups")
	editor._save_prefab_dialog()
	await settle()
	var dialog: ConfirmationDialog
	for child in editor.get_children():
		if child is ConfirmationDialog: dialog = child
	check(dialog != null and dialog.visible, "save prefab dialog exposes name and destination pack")
	if dialog != null:
		var name_edit := dialog.find_children("*", "LineEdit", true, false)[0] as LineEdit
		name_edit.text = "双柱门廊"
		var ok: Vector2 = Vector2(dialog.position) + dialog.get_ok_button().get_global_rect().get_center()
		await mouse(ok, true, false, true)
		await mouse(ok, false, false, true)
	var matches: Array = editor._assets.search("双柱门廊")
	check(matches.size() == 1, "confirmed dialog writes prefab into selected resource pack")
	if not matches.is_empty():
		var entry: Dictionary = matches[0]
		editor._on_palette_selected(editor._palette_items.find(entry))
		await settle()
		check(editor._preview.visible and editor._preview.scene != null, "prefab palette selection previews the composed object")
		var count: int = doc.records.size()
		await click(project(Vector3(-3, 0, 5)))
		check(doc.records.size() == count + 2 and editor._selection_tools.ids.size() == 2, "palette prefab places a grouped editable copy with one click")
		await click(project(Vector3(4, 0, 5)))
		check(doc.records.size() == count + 4, "same prefab can be placed repeatedly")
		await key(KEY_W)
		editor._dock_tabs.current_tab = 2
		await capture("prefab_instances")
	check(editor._save(), "save complete map after group and prefab operations")
	var reopened = Doc.open_file(editor._path)
	check(reopened != null and reopened.records.size() == doc.records.size() and reopened.records.filter(func(r): return r.has("editor_group")).size() == 6, "reopen retains source group and both prefab instances")
	root.size = Vector2i(1024, 720)
	root.content_scale_size = root.size
	await settle()
	check(editor._canvas.size.x > 600 and editor._status.get_global_rect().end.y <= 720, "object list and toolbar fit 1024 pixel workspace")
	await capture("groups_1024")
	editor.free()
	session.world3d_editor_doc = null
	session.world3d_editor_path = ""
	await settle()
	Io._remove_tree(pack)
	print("test_world3d_groups_ui: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
