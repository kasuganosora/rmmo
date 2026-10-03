extends SceneTree
const Doc = preload("res://scripts/world3d/world_document.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
var failed := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failed += 1
func frames(count: int = 6) -> void:
	for i in count: await process_frame
func run() -> void:
	root.size = Vector2i(1280, 800); root.content_scale_size = root.size
	var directory := Paths.external_root().path_join("__material_picker_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(directory)
	var doc := Doc.new()
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(20, 0.2, 20))
	var wall := doc.add_box("block", Vector3(0, 1.5, 0), Vector3(4, 3, 0.4))
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = directory.path_join("map.gltf"); session.world3d_editor_doc = doc
	var editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false
	editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor)
	editor._dock_tabs.current_tab = 3
	await frames(30)
	var panel = editor._material_panel
	for i in 600:
		if panel._catalog_thread == null: break
		await process_frame
	check(not panel._entries.is_empty(), "background material catalog becomes available")
	var before: Array = doc.records.duplicate(true)
	var chosen: String = editor._material_tool.material_id
	panel.search.text = "no_such_material_999"
	panel.search.text_changed.emit(panel.search.text)
	check(panel.picker.item_count == 0 and editor._material_tool.material_id == chosen, "empty search preserves brush material")
	check(panel.current_label.text.contains("棋盘格"), "current material remains visible with zero results")
	panel.find_child("ResetSurfaceFilter", true, false).pressed.emit()
	check(panel.search.text.is_empty() and panel.picker.item_count > 0, "reset filters recovers empty results")
	panel.category_picker.select(1); panel.category_picker.item_selected.emit(1)
	check(editor._material_tool.material_id == chosen, "category browsing does not select another material")
	panel.category_picker.select(0); panel.category_picker.item_selected.emit(0)
	await frames()
	var click_at: Vector2 = panel.picker.global_position + panel.picker.get_item_rect(0).get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = click_at; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		Input.parse_input_event(event)
		await frames()
	check(editor._material_tool.material_id == "builtin:white" and panel.preview.texture != null, "click selects material and shows solid-color swatch")
	check(doc.records == before, "browsing and choosing never paint the map")
	check(not panel._drawer.visible, "advanced options initially collapsed")
	check(panel.find_child("ApplySurfacePaint", true, false).disabled, "apply disabled until a face is selected")
	var brush: Button = panel.find_child("BeginSurfacePaint", true, false)
	brush.pressed.emit(); await frames()
	check(editor._material_tool.active and brush.button_pressed and brush.text == "结束刷面", "brush mode has visible active state")
	brush.pressed.emit(); await frames()
	check(not editor._material_tool.active and not brush.button_pressed, "same button exits brush mode")
	panel.find_child("CustomizeSurfaceMaterial", true, false).pressed.emit()
	await frames()
	check(panel._drawer.visible and panel._drawer.global_position.x >= editor._dock_tabs.get_global_rect().end.x, "customize opens a drawer to the right of the dock")
	panel.mapping.select(2)
	panel.fields.scale_u.value = 3
	panel.fields.scale_v.value = 4
	panel.fields.rotation.value = 45
	panel.fields.offset_u.value = 0.2
	panel.fields.offset_v.value = -0.3
	panel.find_child("CloseSurfaceDrawer", true, false).pressed.emit()
	check(not panel._drawer.visible and editor._material_tool.options.rotation == 45 and editor._material_tool.options.mapping == "meters", "closing commits and retains all settings")
	panel.find_child("CustomizeSurfaceMaterial", true, false).pressed.emit()
	check(panel.fields.scale_u.value == 3, "reopening preserves custom values")
	brush.pressed.emit(); await frames()
	var reset: Button = panel.find_child("ResetSurfaceDefaults", true, false)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = reset.get_global_rect().get_center(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		Input.parse_input_event(event); await frames()
	check(panel.mapping.selected == 0 and panel.fields.scale_u.value == 1 and panel.fields.scale_v.value == 1 and panel.fields.rotation.value == 0 and panel.fields.offset_u.value == 0 and panel.fields.offset_v.value == 0, "restore defaults resets mapping and all five numeric parameters")
	check(doc.records == before and not editor._material_tool.pointer_down, "drawer click cannot paint through to the scene with brush active")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	Input.parse_input_event(escape); await frames()
	check(not panel._drawer.visible and editor._material_tool.active, "Escape closes drawer before affecting scene tools")
	editor._material_tool.cancel()
	var faces: Dictionary = editor._material_tool.list_faces(wall)
	editor._material_tool.selected = {"ok": true, "id": wall, "target": faces.faces[0].target}
	editor._material_tool.target_changed.emit(); await frames()
	panel.find_child("ApplySurfacePaint", true, false).pressed.emit()
	check(doc._find(wall).get("surface_paint", []).size() == 1, "apply still uses shared paint transaction")
	editor._undo()
	check(doc.records == before, "UI application remains undoable")
	panel.search.text = ""; panel.search.text_changed.emit("")
	await frames(180)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("material_picker/1280.png"))
	root.size = Vector2i(1024, 720); root.content_scale_size = root.size
	await frames(20); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("material_picker/1024.png"))
	check(panel.size.x <= editor._dock_tabs.size.x and editor._canvas.size.x > 600, "panel fits 1024px without squeezing viewport")
	panel.find_child("CustomizeSurfaceMaterial", true, false).pressed.emit()
	await frames(10); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("material_picker/drawer_1024.png"))
	check(panel._drawer.get_global_rect().end.x <= root.size.x and panel._drawer.get_global_rect().end.y <= root.size.y, "drawer stays inside the small window")
	editor._dock_tabs.current_tab = 0; await frames()
	check(not panel._drawer.visible, "leaving materials closes the floating drawer")
	await review_workspace(editor)
	editor.queue_free(); await frames()
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(directory)
	print("test_material_picker_ui: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)

func review_workspace(_editor: Node3D) -> void:
	pass
