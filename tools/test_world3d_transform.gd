extends SceneTree
## Run through run_godot_background.py: live projections, real input, actual GLB.
const Doc = preload("res://scripts/world3d/world_document.gd")
const Gizmo = preload("res://scripts/world_editor/transform_gizmo.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const Paths = preload("res://scripts/asset/art_paths.gd")
var editor: Node3D
var failed := 0
var subject := ""


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failed += 1


func settle() -> void:
	for i in 3: await process_frame
	await physics_frame
	await process_frame


func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = editor._canvas.global_position + point
	Input.parse_input_event(event)
	await settle()


func motion(point: Vector2, alt: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = editor._canvas.global_position + point
	event.alt_pressed = alt
	Input.parse_input_event(event)
	await settle()


func key(code: Key, ctrl: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	Input.parse_input_event(event)
	await settle()


func vector(field: String) -> Vector3:
	return Gizmo.vector(editor._doc._find(subject), field)


func project(point: Vector3) -> Vector2:
	return editor._camera.unproject_position(point)


func capture(label: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	var output := Paths.review_path("editor_transform/" + label + ".png")
	root.get_texture().get_image().save_png(output)
	print("capture=" + output)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Transform input coverage requires a real renderer on the private desktop")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	var directory: String = preload("res://scripts/world3d/map_paths.gd").cache_directory("transform_%d" % Time.get_ticks_usec())
	var doc = Doc.new()
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(16, 0.2, 16))
	doc.records.back().color = [0.3, 0.35, 0.4]
	subject = doc.add_box("block", Vector3(0.13, 1, 0.17), Vector3(1.4, 1.8, 1))
	doc.records.back().color = [0.4, 0.65, 0.76]
	doc.add_box("block", Vector3(3, 0.5, -2), Vector3.ONE)
	var session = root.get_node("GameSession")
	session.world3d_editor_doc = doc
	session.world3d_editor_path = directory.path_join("map.gltf")
	editor = load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(editor)
	await settle()
	editor._camera.position = Vector3(6, 5, 8)
	editor._camera.look_at(Vector3(0, 1, 0))
	editor._orbit_center = Vector3(0, 1, 0)
	editor._inspector.select(subject)
	await key(KEY_W)
	await capture("move_xyz")
	var view: Node = editor._view
	var untouched: Node = view.get_child(2)
	var start_position := vector("position")
	for axis in 3:
		var center := vector("position")
		var direction: Vector3 = Gizmo.AXES[axis]
		var anchor: Vector3 = center + direction * editor._gizmo.world_length() * 0.78
		var undo_count: int = doc._undo.size()
		check(editor._gizmo.hit_test(project(anchor)) == axis, "XYZ handle %d can be picked" % axis)
		await mouse(project(anchor), true)
		await motion(project(anchor + direction * 0.34))
		await motion(project(anchor + direction * 0.73))
		check(vector("position").is_equal_approx(center + direction * 0.75), "axis %d drag snaps and preserves other coordinates" % axis)
		check(doc._undo.size() == undo_count, "live drag does not pollute undo history")
		# Release over the property dock, outside the canvas.
		await mouse(Vector2(-100, 250), false)
		check(not editor._transform_drag.active and doc._undo.size() == undo_count + 1, "outside release commits exactly one change")
		check(editor._view == view and untouched == view.get_child(2), "drag keeps map and unrelated objects alive")
		await key(KEY_Z, true)
		check(vector("position").is_equal_approx(center), "Ctrl+Z restores whole drag")
		await key(KEY_Y, true)
		check(vector("position").is_equal_approx(center + direction * 0.75), "Ctrl+Y reapplies drag")
		editor._undo()
		view = editor._view
		untouched = view.get_child(2)
	var redo_count: int = doc._redo.size()
	var undo_count: int = doc._undo.size()
	var point := project(start_position)
	await mouse(point, true)
	await motion(point + Vector2(1, 1))
	await mouse(point, false)
	check(doc._undo.size() == undo_count and doc._redo.size() == redo_count and vector("position").is_equal_approx(start_position), "click jitter preserves transform undo and redo")
	await mouse(point, true)
	await motion(project(start_position + Vector3(1, 0, 1)))
	await key(KEY_ESCAPE)
	await mouse(point, false)
	check(vector("position").is_equal_approx(start_position) and doc._redo.size() == redo_count, "Esc cancels preview and preserves redo")
	# Local X follows the object's rotation, including off-grid starting coordinates.
	editor._inspector.fields.rotation_1.value = 90.0
	editor._toggle_transform_space()
	var direction: Vector3 = editor._gizmo.axes_basis().x
	var anchor: Vector3 = vector("position") + direction * editor._gizmo.world_length() * 0.78
	await mouse(project(anchor), true)
	await motion(project(anchor + direction * 0.63), true)
	await mouse(project(anchor + direction * 0.63), false)
	check(vector("position").is_equal_approx(start_position + direction * 0.63), "local-axis drag and Alt bypass grid snapping")
	check(doc._redo.is_empty(), "new committed change clears redo branch")
	editor._undo()
	editor._toggle_transform_space()
	editor._inspector.fields.rotation_1.value = 0.0
	await key(KEY_R)
	await capture("rotate_xyz")
	for axis in 3:
		var points: PackedVector2Array = editor._gizmo.ring_points(axis)
		var index := -1
		for i in range(4, 60):
			if editor._gizmo.hit_test(points[i]) == axis:
				index = i
				break
		check(index >= 0, "rotation ring %d has an independent pick target" % axis)
		if index < 0: continue
		var original_basis := Basis.from_euler(vector("rotation") * PI / 180.0)
		var basis: Basis = editor._gizmo.axes_basis()
		var angle := TAU * index / 64.0 + deg_to_rad(43.0)
		var target: Vector3 = vector("position") + (basis[(axis + 1) % 3] * cos(angle) + basis[(axis + 2) % 3] * sin(angle)) * editor._gizmo.world_length() * 0.85
		await mouse(points[index], true)
		await motion(project(target))
		await mouse(project(target), false)
		var expected := Basis(Gizmo.AXES[axis], deg_to_rad(45.0)) * original_basis
		check(Basis.from_euler(vector("rotation") * PI / 180.0).is_equal_approx(expected), "rotation axis %d turns 45 degrees with snapping" % axis)
		editor._undo()
	# Non-commuting rotations: local X must rotate around the already-turned object.
	editor._inspector.fields.rotation_1.value = 35.0
	editor._toggle_transform_space()
	var original_basis := Basis.from_euler(vector("rotation") * PI / 180.0)
	var local_axis: Vector3 = editor._gizmo.axes_basis().x
	var radius: float = editor._gizmo.world_length() * 0.85
	anchor = vector("position") + original_basis.y * radius
	check(editor._transform_drag.begin(editor, project(anchor), 0), "local rotation begins on the object plane")
	var target: Vector3 = vector("position") + Basis(local_axis, deg_to_rad(17.3)) * original_basis.y * radius
	editor._transform_drag.update(project(target), true)
	editor._transform_drag.finish()
	check(Basis.from_euler(vector("rotation") * PI / 180.0).is_equal_approx(original_basis * Basis(Vector3.RIGHT, deg_to_rad(17.3))), "local rotation composes correctly with Alt free angles")
	# Leave this rotated object in the document for the later save/reload assertion.
	await key(KEY_T)
	await capture("scale_xyz")
	var original_size := vector("size")
	for axis in 4:
		var center := project(vector("position"))
		var delta: Vector2 = (editor._gizmo.axis_tip(axis) - center) * 0.5 if axis < 3 else Vector2(60, 0)
		var start: Vector2 = center.lerp(editor._gizmo.axis_tip(axis), 0.78) if axis < 3 else center
		await mouse(start, true)
		await motion(start + delta)
		await mouse(start + delta, false)
		var expected := original_size
		if axis < 3: expected[axis] *= 1.5
		else: expected *= 1.5
		check(vector("size").is_equal_approx(expected), "scale handle %d supports axis / uniform scaling" % axis)
		check((editor._view.get_node(subject).mesh as BoxMesh).size.is_equal_approx(expected), "scaled geometry updates immediately")
		editor._undo()
	editor._scale_snap = 0.25
	point = project(vector("position"))
	await mouse(point, true)
	await motion(point + Vector2(50, 0))
	await mouse(point + Vector2(50, 0), false)
	check(vector("size").is_equal_approx(original_size * 1.5), "uniform scaling honors percentage snapping")
	editor._undo()
	editor._scale_snap = 0.0
	# Scale cannot cross zero and invert colliders.
	point = project(vector("position"))
	await mouse(point, true)
	await motion(point + Vector2(-2000, 0))
	await mouse(point, false)
	check(vector("size").x >= 0.001 and vector("size").y >= 0.001 and vector("size").z >= 0.001, "scaling stays positive even outside viewport")
	editor._undo()
	# A real nested imported model uses local scale; picking bodies follow its mesh.
	var source := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.position = Vector3(0.4, 0.5, 0)
	mesh.rotation_degrees.y = 20
	source.add_child(mesh)
	var asset_path := directory.path_join("fixture.glb")
	check(Io.save_scene(source, asset_path) == OK, "build imported GLB fixture")
	source.free()
	subject = doc.add_asset({"asset_path": asset_path, "bounds_position": [-0.3, 0, -0.7], "bounds_size": [1.4, 1, 1.4]}, Vector3(-2, 1, 0))
	editor._rebuild()
	editor._inspector.select(subject)
	editor._inspector.fields.rotation_1.value = 35.0
	point = project(vector("position"))
	await mouse(point, true)
	await motion(point + Vector2(60, 0))
	await mouse(point + Vector2(60, 0), false)
	check(vector("size").is_equal_approx(Vector3.ONE * 1.5) and editor._view.get_node(subject).scale.is_equal_approx(Vector3.ONE * 1.5), "imported GLB scales in place")
	for child in editor.get_children():
		if child is StaticBody3D and child.get_meta("uuid", "") == subject:
			check(child.transform.is_equal_approx(child.get_meta("visual").global_transform), "nested asset picking body follows transformed mesh")
			var mesh_center: Vector3 = child.get_meta("visual").global_position
			var ray := PhysicsRayQueryParameters3D.create(editor._camera.global_position, mesh_center)
			var hit: Dictionary = editor.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not hit.is_empty() and hit.collider.get_meta("uuid", "") == subject, "physics ray still selects the transformed imported asset")
	var saved: Array = doc.records.duplicate(true)
	check(editor._save(), "save all object transformations")
	var reopened = Doc.open_file(editor._path)
	var roundtrip: bool = reopened != null and saved.size() == reopened.records.size()
	if roundtrip:
		for record in saved:
			var loaded: Dictionary = reopened._find(str(record.uuid))
			for field in ["position", "rotation", "size"]:
				roundtrip = roundtrip and Gizmo.vector(record, field).is_equal_approx(Gizmo.vector(loaded, field))
			roundtrip = roundtrip and record.get("asset_path", "") == loaded.get("asset_path", "") and record.kind == loaded.get("kind")
	check(roundtrip, "GLTF reload preserves positions rotations sizes and model reference")
	# Numeric entry consumes shortcuts instead of rotating/deleting the selected item.
	var input: LineEdit = editor._inspector.fields.position_0.get_line_edit()
	input.grab_focus()
	var current_mode: int = editor._transform_mode
	await key(KEY_W)
	check(editor._transform_mode == current_mode, "typing in numeric input does not change transform tools")
	input.release_focus()
	editor._set_transform_mode(0)
	root.size = Vector2i(1024, 720)
	root.content_scale_size = root.size
	await capture("move_1024")
	check(editor._canvas.size.x > 600 and editor._gizmo.size.is_equal_approx(editor._canvas.size), "gizmo and canvas remain aligned at 1024 pixels")
	editor._dirty = true
	editor._request_exit()
	var protected_exit := false
	for child in editor.get_children():
		if child is ConfirmationDialog and child.visible:
			protected_exit = true
			child.canceled.emit()
	check(protected_exit and is_instance_valid(editor), "return to login offers save or discard and can be canceled")
	editor.free()
	session.world3d_editor_doc = null
	session.world3d_editor_path = ""
	Io._remove_tree(directory)
	print("test_world3d_transform: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
