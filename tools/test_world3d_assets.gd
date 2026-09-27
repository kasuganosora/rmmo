extends SceneTree
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const Library = preload("res://scripts/world_editor/asset_library.gd")
const Doc = preload("res://scripts/world3d/world_document.gd")
var failed := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failed += 1
func run() -> void:
	var dir := preload("res://scripts/world3d/map_paths.gd").cache_directory("assets_%d" % Time.get_ticks_usec())
	var source := Node3D.new()
	var visual := MeshInstance3D.new()
	visual.mesh = BoxMesh.new()
	visual.position = Vector3(0, 1, 0)
	source.add_child(visual)
	var source_path := dir.path_join("whitebox.gltf")
	check(Io.save_scene(source, source_path) == OK, "create glTF whitebox and external buffer")
	source.free()
	var library := Library.new(dir.path_join("library"))
	var result := library.import_file(source_path)
	check(result.ok, "import packages glTF dependencies into library GLB")
	check(library.import_file(source_path).ok and library.entries.size() == 1, "identical import is deduplicated")
	var doc := Doc.new()
	var id: String = doc.add_asset(result.entry, Vector3(2.125, 0, 3.25))
	doc._find(id).rotation[1] = 35.0
	doc._find(id).size = [1.5, 2.0, 0.5]
	var second: String = doc.add_asset(result.entry, Vector3(-3, 0, 2))
	var map_path := dir.path_join("map.gltf")
	check(doc.save(map_path) == OK, "save repeated asset with decimal transform")
	DirAccess.remove_absolute(source_path)
	DirAccess.remove_absolute(dir.path_join("whitebox.bin"))
	var reopened = Doc.open_file(map_path)
	check(reopened != null and Vector3(reopened._find(id).position[0], reopened._find(id).position[1], reopened._find(id).position[2]).is_equal_approx(Vector3(2.125, 0, 3.25)) and is_equal_approx(float(reopened._find(id).size[1]), 2.0), "asset transforms roundtrip after original source is removed")
	var host := Node3D.new()
	root.add_child(host)
	var loader := preload("res://scripts/world3d/map_loader.gd").new()
	root.add_child(loader)
	loader.start(map_path)
	var loaded: Array = await loader.finished
	check(loaded[0] != null, "runtime record loader instantiates imported assets")
	if loaded[0] != null:
		host.add_child(loaded[0])
		preload("res://scripts/world3d/world_stream.gd").sync(loaded[0], host, Vector3.ZERO)
		var specs: Array = loaded[0].get_meta("stream_library", [])
		check(specs.size() == 2 and specs[0].uuid != specs[1].uuid, "repeated model instances have distinct stream identities")
		check(loaded[0].get_meta("stream_bodies", {}).size() == 2, "both model instances produce independent collision")
	host.free()
	check(Library.new(library.directory).entries.size() == 1, "asset catalog reloads")
	doc.checkpoint()
	doc.remove(second)
	check(doc.undo() and doc.has_uuid(second), "asset removal supports undo")
	var session = root.get_node("GameSession")
	session.world3d_editor_doc = reopened
	session.world3d_editor_path = map_path
	var editor = load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(editor)
	editor._assets = library
	editor._pick = preload("res://scripts/world3d/world_modules.gd").search("").size()
	editor._refresh_palette()
	editor._inspector.select(id)
	editor._focus_selected()
	await process_frame
	check(editor._preview.visible and editor._preview.scene != null and editor._preview.viewport_.own_world_3d, "editor previews selected asset in an isolated viewport")
	check(editor._inspector.rows["size"][0].text == "缩放倍率", "asset inspector distinguishes model scale from box dimensions")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("rmmo-asset-editor.png"))
	editor.free()
	session.world3d_editor_doc = null
	session.world3d_editor_path = ""
	DirAccess.remove_absolute(result.entry.asset_path)
	check(doc.missing_assets().size() == 2 and doc.save(map_path) == ERR_FILE_NOT_FOUND, "missing model blocks overwrite and reports all affected records")
	check(Doc.open_file(map_path) != null, "missing reference does not destroy editable document")
	loader = preload("res://scripts/world3d/map_loader.gd").new()
	root.add_child(loader)
	loader.start(map_path)
	loaded = await loader.finished
	check(loaded[0] == null and not str(loaded[2]).is_empty(), "runtime reports missing asset rather than silently spawning a box")
	Io._remove_tree(dir)
	Library._scenes.clear()
	print("test_world3d_assets: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
