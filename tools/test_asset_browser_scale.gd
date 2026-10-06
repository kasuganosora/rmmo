extends SceneTree
const Library = preload("res://scripts/world_editor/asset_library.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
var failed := 0
var import_done := false
var import_error := -1

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failed += 1

func settle(frames: int = 12) -> void:
	for i in frames: await process_frame

func run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	var directory: String = preload("res://scripts/world3d/map_paths.gd").cache_directory("asset_scale_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata := FileAccess.open(directory.path_join("metadata.json"), FileAccess.WRITE)
	metadata.store_string('{"id":"scale_test","name":"缩略图压力测试"}')
	metadata.close()
	var source := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	source.add_child(mesh)
	var path := directory.path_join("source.glb")
	check(Io.save_scene(source, path) == OK, "create model import fixture")
	source.free()
	var session = root.get_node("GameSession")
	session.world3d_editor_doc = preload("res://scripts/world3d/world_document.gd").new()
	var editor = load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(editor)
	await settle()
	var initial_scene_cache: int = Library._scenes.size()
	editor._thumbnails.import_finished.connect(func(_key, _path, error): import_done = true; import_error = error)
	editor._import_asset_into_pack(directory, false)
	for child in editor.get_children():
		if child is FileDialog:
			child.hide()
			child.file_selected.emit(path)
	for i in 120:
		if import_done: break
		await process_frame
	check(import_done and import_error == OK, "import workflow generates and saves thumbnail")
	var imported: Dictionary = editor._assets.entries[0]
	check(FileAccess.file_exists(imported.thumbnail_path) and str(imported.thumbnail_path).begins_with(directory + "/assets/thumbnails/"), "thumbnail stored inside owning resource pack")
	check(Library.new(editor._assets.directory).entries[0].thumbnail_path == imported.thumbnail_path, "thumbnail link survives library reload")
	var moved := directory.path_join("moved/assets")
	DirAccess.make_dir_recursive_absolute(moved.path_join("thumbnails"))
	DirAccess.copy_absolute(editor._assets.directory.path_join("library.json"), moved.path_join("library.json"))
	DirAccess.copy_absolute(imported.asset_path, moved.path_join(str(imported.asset_path).get_file()))
	DirAccess.copy_absolute(imported.thumbnail_path, moved.path_join("thumbnails").path_join(str(imported.thumbnail_path).get_file()))
	var moved_entry: Dictionary = Library.new(moved).entries[0]
	check(str(moved_entry.thumbnail_path).begins_with(moved) and FileAccess.file_exists(moved_entry.thumbnail_path) and FileAccess.file_exists(moved_entry.asset_path), "copying resource pack preserves relative model and thumbnail links")
	check(Library._scenes.size() == initial_scene_cache, "import/thumbnail preview does not retain packed 3D scenes")
	var loads_before: int = editor._thumbnails.model_load_count
	var samples: Array = []
	for i in 10000:
		samples.append({"label": "物件 %05d" % i, "category": "测试", "asset_path": "fixture_%d.glb" % i, "thumbnail_path": imported.thumbnail_path})
	editor._assets.entries = samples
	var start := Time.get_ticks_usec()
	editor._refresh_palette()
	var elapsed := Time.get_ticks_usec() - start
	await settle(40)
	var shared_count := 0
	for shared in editor._shared_assets: shared_count += shared.entries.size()
	check(editor._palette.item_count == 10000 + preload("res://scripts/world3d/world_modules.gd").all().size() + shared_count, "10,000 assets remain searchable without creating 10,000 UI nodes")
	check(editor._palette._pool.size() <= 36, "virtual grid bounds live controls to viewport and buffer rows")
	print("METRIC 10000 metadata refresh_ms=", elapsed / 1000.0, " live_tiles=", editor._palette._pool.size())
	var peak := 0
	for step in 12:
		editor._palette.scroll_vertical = step * 21000
		await settle(4)
		editor._update_visible_thumbnails()
		await settle(28)
		peak = maxi(peak, editor._thumbnails.cache.size())
		check(editor._palette._pool.size() <= 36 and editor._thumbnails._pending.size() <= 36, "scroll step %d bounds nodes and pending IO" % step)
	check(peak <= editor._thumbnails.MAX_CACHE and editor._thumbnails.disk_load_count > 96, "scrolling beyond cache capacity evicts old thumbnail textures")
	check(editor._thumbnails.model_load_count == loads_before, "browsing 10,000 assets performs zero model loads")
	check(not editor._thumbnails.cache.has("fixture_0.glb"), "offscreen oldest thumbnail is released from cache")
	var visible_index: int = editor._palette._active.keys()[0]
	editor._palette._active[visible_index].pressed.emit()
	check(editor._pick == visible_index and editor._selected().asset_path == editor._palette_items[visible_index].asset_path, "recycled tile selects the correct global asset after scrolling")
	editor._palette.scroll_vertical = 0
	await settle(40)
	check(editor._palette.get_item_icon(preload("res://scripts/world3d/world_modules.gd").all().size()) != editor._thumbnails.placeholder, "scrolling back reloads thumbnail from pack PNG")
	start = Time.get_ticks_usec()
	for i in 10000: editor._selected()
	print("METRIC 10000 selected lookups_ms=", (Time.get_ticks_usec() - start) / 1000.0)
	editor._on_search("物件 09999")
	await settle(20)
	check(editor._palette.item_count == 1 and editor._palette._pool.size() == 1, "search releases old rows and preserves global item selection")
	editor._on_search("不存在")
	await settle()
	check(editor._palette._pool.is_empty() and editor._thumbnails._pending.is_empty(), "empty results release tiles and cancel stale requests")
	editor._on_search("")
	await settle(40)
	editor._dock_tabs.current_tab = 1
	await settle(20)
	check(editor._palette._active.is_empty() and editor._thumbnails._pending.is_empty(), "hidden library releases visible texture references and stops work")
	editor.free()
	session.world3d_editor_doc = null
	Io._remove_tree(directory)
	print("test_asset_browser_scale: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
