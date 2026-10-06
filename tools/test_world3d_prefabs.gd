extends SceneTree
const Doc = preload("res://scripts/world3d/world_document.gd")
const Library = preload("res://scripts/world_editor/asset_library.gd")
const Prefabs = preload("res://scripts/world_editor/prefab_library.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
var failed := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failed += 1

func run() -> void:
	var directory: String = preload("res://scripts/world3d/map_paths.gd").cache_directory("prefab_test_%d" % Time.get_ticks_usec())
	var library = Library.new(directory.path_join("assets"))
	var source := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.position = Vector3(0.4, 0.8, -0.3)
	source.add_child(mesh)
	var source_path := directory.path_join("source/model.glb")
	check(Io.save_scene(source, source_path) == OK, "create actual glTF dependency")
	source.free()
	var imported := Library.new(directory.path_join("source_assets")).import_file(source_path)
	check(imported.ok, "import model for prefab fixture")
	var doc = Doc.new()
	var a: String = doc.add_box("block", Vector3(-2, 1, 0), Vector3(2, 2, 2), Vector3(0, 35, 0))
	var b: String = doc.add_asset(imported.entry, Vector3(2, 0, 0))
	doc._find(a).editor_group = "original_group"
	doc._find(a).editor_group_name = "测试小屋"
	doc._find(a).event = {"pages": [{"commands": [{"op": "move_route", "target": b}]}]}
	doc._find(b).editor_locked = true
	var cell: String = doc.add_box_silent("ground", Vector3.ZERO, Vector3.ONE)
	Rules.configure(doc._find(cell), Vector2i(0, 1), "road", 2.0, 0.0)
	Rules.refresh_all(doc.records)
	var before: Array = doc.records.duplicate(true)
	var saved := Prefabs.capture(doc.records, library, "测试房屋")
	check(saved.ok and doc.records == before, "capture leaves source transforms, group, locks and auto rules unchanged")
	if not saved.ok: print(saved); quit(1); return
	var loaded := Prefabs.read(saved.entry)
	check(loaded.ok and loaded.records.size() == 3, "prefab stores editable component records")
	check(is_zero_approx(Geometry.bounds(loaded.records).position.y), "prefab origin sits on its lowest surface")
	check(not loaded.records[1].has("editor_locked") and not loaded.records[0].has("editor_group") and not Rules.attached(loaded.records[2]), "prefab has independent editor state and frozen automatic shape")
	check(str(loaded.records[1].asset_path).begins_with(library.directory + "/"), "model dependency is copied into destination resource pack")
	# Deleting the fixture's original source does not break the saved prefab.
	Io._remove_tree(directory.path_join("source_assets"))
	Io._remove_tree(directory.path_join("source"))
	check(Prefabs.read(saved.entry).ok, "prefab survives removal of original model source")
	var reloaded := Library.new(library.directory)
	check(reloaded.search("测试房屋").size() == 1 and reloaded.search("预制件").size() == 1, "library reload resolves relative prefab paths and search")
	var destination = Doc.new()
	destination.add_box("ground", Vector3(0, -0.1, 0), Vector3(30, 0.2, 30))
	var placed := Prefabs.place(destination, saved.entry, Vector3(4, 2, -3))
	var placed_again := Prefabs.place(destination, saved.entry, Vector3(-5, 0, 4))
	check(placed.ok and placed_again.ok and destination.records.size() == 7, "one prefab places three independent editable objects")
	var distinct := true
	var ids := {}
	for record in destination.records:
		if ids.has(record.uuid): distinct = false
		ids[record.uuid] = true
	check(distinct and destination._find(placed.ids[0]).editor_group != destination._find(placed_again.ids[0]).editor_group, "each placement gets fresh object and group identities")
	check(destination._find(placed.ids[0]).event.pages[0].commands[0].target == placed.ids[1], "internal event target follows duplicated object identity")
	check(Geometry.bounds(placed.ids.map(func(id): return destination._find(id))).position.y == 2.0, "placement aligns prefab base to the support height")
	check(destination.undo() and destination.records.size() == 4 and destination.redo() and destination.records.size() == 7, "each whole placement is one undo and redo operation")
	var hidden: Dictionary = destination._find(placed.ids[0])
	hidden.editor_hidden = true
	hidden.editor_locked = true
	var path := directory.path_join("maps/test/map.gltf")
	check(destination.save(path) == OK, "save grouped map with packaged models")
	var reopened = Doc.open_file(path)
	check(reopened != null and reopened._find(placed.ids[0]).editor_group == hidden.editor_group and reopened._find(placed.ids[0]).editor_locked and reopened._find(placed.ids[0]).editor_hidden, "reopen preserves grouping and editor flags")
	var view: Node3D = reopened.build()
	check(view.get_node(NodePath(placed.ids[0])).visible, "editor-only hiding does not remove runtime geometry")
	view.free()
	var loader := preload("res://scripts/world3d/map_loader.gd").new()
	root.add_child(loader)
	loader.start(path)
	var result: Array = await loader.finished
	var host := Node3D.new()
	root.add_child(host)
	if result[0] != null:
		host.add_child(result[0])
		preload("res://scripts/world3d/world_stream.gd").sync(result[0], host, Vector3.ZERO)
	check(result[0] != null and result[0].get_meta("stream_library", []).size() == 7, "runtime loads all grouped prefab components including imported meshes")
	host.free()
	loader.queue_free()
	# Move an entire resource library: nested model paths must still resolve.
	var moved := directory.path_join("moved_assets")
	check(DirAccess.rename_absolute(library.directory, moved) == OK, "move test resource library")
	var moved_library := Library.new(moved)
	var moved_entry: Dictionary = moved_library.search("测试房屋")[0]
	check(Prefabs.read(moved_entry).ok, "relocated prefab resolves packaged models relative to library")
	var broken := moved.path_join("prefabs/broken.json")
	var file := FileAccess.open(broken, FileAccess.WRITE)
	file.store_string('{"format":"rmmo_prefab","version":1,"records":[{}]}')
	file.close()
	var count: int = destination.records.size()
	var undo_count: int = destination._undo.size()
	check(not Prefabs.place(destination, {"prefab_path": broken}, Vector3.ZERO).ok and destination.records.size() == count and destination._undo.size() == undo_count, "malformed prefab is rejected without changing map or history")
	var packed := Prefabs.read(moved_entry)
	DirAccess.remove_absolute(str(packed.records[1].asset_path))
	check(not Prefabs.place(destination, moved_entry, Vector3.ZERO).ok and destination.records.size() == count, "missing prefab dependency fails before placement")
	# Stale library saves must not overwrite another window's published edits.
	var stale := Library.new(moved)
	moved_library.entries[0].label = "changed"
	check(moved_library.save() == OK and stale.save() == ERR_BUSY, "concurrent library edits are protected")
	Io._remove_tree(directory)
	print("test_world3d_prefabs: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
