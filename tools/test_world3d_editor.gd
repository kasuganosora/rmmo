extends SceneTree
var failed := 0
const Document = preload("res://scripts/world3d/world_document.gd")

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failed += 1

func run() -> void:
	var session = root.get_node("GameSession")
	var dir := preload("res://scripts/world3d/map_paths.gd").cache_directory("editor_test_%d" % Time.get_ticks_usec())
	var path := dir.path_join("map.gltf")
	var doc = Document.new()
	var id: String = doc.add_npc(Vector3(1.234567, 0.8, -2.765432), "guide", "原对话")
	session.world3d_editor_doc = doc
	session.world3d_editor_path = path
	var editor = load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor._inspector.select(id)
	check(absf(float(doc.records[0]["position"][0]) - 1.234567) < 0.000001, "inspector display does not quantize stored position")
	editor._inspector.fields["position_0"].value = 2.125
	check(absf(float(doc.records[0]["position"][0]) - 2.125) < 0.000001, "numeric inspector edits decimal position")
	check(doc.undo() and absf(float(doc.records[0]["position"][0]) - 1.234567) < 0.000001, "numeric edit is undoable")
	editor._inspector.fields["hostile"].button_pressed = true
	editor._inspector.fields["skills"].text_submitted.emit("fireball, fireball， frostbolt")
	check(doc.records[0].skills == ["fireball", "frostbolt"], "NPC skill list accepts separators and removes duplicates")
	editor._inspector.fields["ally"].button_pressed = true
	check(bool(doc.records[0].get("ally", false)) and not bool(doc.records[0].get("hostile", false)), "companion and hostile toggles are mutually exclusive")
	editor._inspector.fields["line"].text_submitted.emit("新的对话内容")
	check(editor._save(), "editor saves full document")
	editor.free()
	session.world3d_editor_doc = null
	editor = load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	check(editor._doc.records.size() == 1 and editor._doc.records[0]["line"] == "新的对话内容", "editor reopens NPC configuration from disk")
	var other = Document.new()
	other.add_gather(Vector3.ZERO, "herb")
	var other_path := dir.path_join("other.gltf")
	check(other.save(other_path) == OK and editor.open_document(other_path), "open another saved map")
	check(session.world3d_editor_path == other_path and editor._doc.records[0]["kind"] == "gather", "editor remembers selected map independently of playtest")
	editor._inspector.select(editor._doc.records[0]["uuid"])
	check(editor._inspector.fields["item_id"].visible and not editor._inspector.fields["target_path"].visible and not editor._inspector.fields["line"].visible, "inspector shows only selected object properties")
	editor._snap = 0.25
	check(editor.snap_position(Vector3(0.36, 1.237, -0.36)).is_equal_approx(Vector3(0.25, 1.237, -0.25)), "snap rounds XZ and preserves exact support height")
	editor._snap = 0.0
	check(editor.snap_position(Vector3(0.12345, 1.237, -0.12345)).is_equal_approx(Vector3(0.12345, 1.237, -0.12345)), "snap can be disabled")
	editor._snap = 0.25
	var original_id: String = editor._inspector.selection
	editor._duplicate_selected()
	check(editor._doc.records.size() == 2 and editor._inspector.selection != original_id, "duplicate assigns a new stable identity")
	editor._nudge_selected(Vector3.UP)
	editor._rotate_selected(1)
	var copy: Dictionary = editor._doc._find(editor._inspector.selection)
	check(is_equal_approx(float(copy.position[1]), 0.25) and is_equal_approx(float(copy.rotation[1]), 15.0), "nudge and rotate use chosen increments")
	editor._doc.undo()
	check(is_zero_approx(float(editor._doc._find(editor._inspector.selection).rotation[1])), "rotation can be undone")
	editor._inspector.select(original_id)
	editor._focus_selected()
	await process_frame
	await physics_frame
	await process_frame
	# Dummy rendering has no live camera projection/input surface.
	if DisplayServer.get_name() != "headless":
		editor._mode = 1
		editor._inspector.select("")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = editor._canvas.global_position + editor._camera.unproject_position(Vector3.ZERO)
		Input.parse_input_event(click)
		await process_frame
		check(editor._inspector.selection == original_id, "real viewport click selects object after dock coordinate conversion")
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = editor._canvas.global_position + editor._camera.unproject_position(Vector3(1.12, 0, 0))
		Input.parse_input_event(motion)
		await process_frame
		check(is_equal_approx(float(editor._doc._find(original_id).position[0]), 1.0), "mouse drag uses grid snapping in the viewport")
		click = click.duplicate()
		click.pressed = false
		Input.parse_input_event(click)
		await process_frame
		editor._doc.undo()
		check(is_zero_approx(float(editor._doc._find(original_id).position[0])), "entire drag is a single undo operation")
		editor._rebuild()
		editor._inspector.select(original_id)
	else:
		print("SKIP: viewport input requires graphical renderer; run without --headless")
	check(editor._canvas.size.x > 600, "1280 px layout retains a large central canvas")
	if OS.get_cmdline_user_args().has("--capture"):
		editor._inspector.select(editor._doc.records[0]["uuid"])
		await RenderingServer.frame_post_draw
		var screenshot := preload("res://scripts/asset/art_paths.gd").review_path("world3d_editor.png")
		root.get_texture().get_image().save_png(screenshot)
		print("capture=" + screenshot)
	editor.free()
	session.world3d_editor_doc = null
	session.world3d_editor_path = ""
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(dir)
	print("test_world3d_editor: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
