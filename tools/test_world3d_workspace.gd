extends SceneTree
## Checks the retired entry point and renders the real 3D workspace with a fixture.
const Doc = preload("res://scripts/world3d/world_document.gd")
const ArtPaths = preload("res://scripts/asset/art_paths.gd")
var failed := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", description])
	if not ok: failed += 1

func settle() -> void:
	for i in 12: await process_frame

func run() -> void:
	var session = root.get_node("GameSession")
	var doc = Doc.new()
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(20, 0.2, 20))
	doc.add_box("block", Vector3(-3, 1, -3), Vector3(3, 2, 3))
	doc.add_box("block", Vector3(3, 1.5, -3), Vector3(3, 3, 3))
	doc.add_box("bridge_deck", Vector3(0, 1, 0), Vector3(6, 0.25, 2))
	var selected: String = doc.add_npc(Vector3(0, 0.8, 3), "guide", "编辑器布局测试")
	session.world3d_editor_doc = doc
	change_scene_to_file("res://scenes/content_editor.tscn")
	await settle()
	check(current_scene is Node3D and current_scene.get_script().resource_path == "res://scripts/world_editor/world_editor.gd", "legacy scene opens 3D editor")
	session.go_content_editor()
	await settle()
	var editor = current_scene
	check(editor is Node3D and editor.get_script().resource_path == "res://scripts/world_editor/world_editor.gd", "content editor route opens 3D editor")
	check(editor.find_child("ProjectLibrarySplit", true, false) == null, "map tree no longer occupies sidebar")
	editor._mode_buttons[1].pressed.emit()
	editor._inspector.select(selected)
	check(editor._mode == 1 and editor._dock_tabs.current_tab == 1, "select tool opens properties")
	editor._palette.item_selected.emit(0)
	check(editor._mode == 0 and editor._dock_tabs.current_tab == 0 and editor._mode_buttons[0].button_pressed, "palette returns to placement with synchronized toolbar")
	editor._on_search("墙")
	check(editor._palette.item_count == 1, "thumbnail palette keeps search working")
	editor._on_search("")
	await settle()
	if DisplayServer.get_name() != "headless":
		for i in 240:
			if not editor._thumbnails._busy and editor._thumbnails._pending.is_empty(): break
			await process_frame
		check(editor._palette.get_item_icon(0) != null and editor._palette.get_item_icon(0) != editor._thumbnails.placeholder, "library renders visible built-in thumbnails")
	for dimensions in [Vector2i(1024, 720), Vector2i(1280, 800)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		for tab in 2:
			editor._dock_tabs.current_tab = tab
			await settle()
			check(editor._canvas.size.x > 600 and editor._canvas.get_global_rect().end.x <= dimensions.x, "canvas fits %s tab %d" % [dimensions, tab])
			check(editor._status.get_global_rect().end.y <= dimensions.y, "status remains in window")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var output := ArtPaths.review_path("world3d_u2u_%d_tab%d.png" % [dimensions.x, tab])
				root.get_texture().get_image().save_png(output)
				print("capture=" + output)
	# Closing while thumbnails are queued must not resume methods on freed nodes.
	editor.queue_free()
	await settle()
	print("test_world3d_workspace: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
