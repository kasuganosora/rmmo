extends "res://tools/test_world3d_mcp.gd"
## Small isolated river fixture for the projection precision/broad-phase fix.
const River = preload("res://scripts/world_editor/terrain_river_tools.gd")


func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	rpc_timeout_ms = 90000
	var directory: String = Paths.cache_directory("terrain_projection_http_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join("map.gltf")
	var doc = Doc.new()
	check(doc.save(path) == OK, "isolated native fixture saved")
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = path
	session.world3d_editor_doc = null
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false
	editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor)
	await settle()
	while editor._load_job != null and editor._load_job.active:
		await process_frame
	var probe := TCPServer.new()
	port = 31790
	while probe.listen(port, "127.0.0.1") != OK:
		port += 1
	probe.stop()
	check(editor.start_mcp(port).ok, "real loopback HTTP MCP started")
	var terrain: Dictionary = await call_tool("create_terrain", {"center": [500.0, 5.0, 500.0], "width": 24.0, "depth": 24.0, "cell_size": 1.0})
	if not terrain.get("ok", false):
		quit(1)
		return
	var args := {"id": "projection_fixture", "terrain_ids": [terrain.id], "points": [[490.0, 500.0], [510.0, 500.0]], "width": 4.0, "bank_width": 1.0, "water_level": 4.0, "depth": 1.0, "curved": false, "natural_materials": false}
	var before: Dictionary = editor._doc.recovery_snapshot()
	var history: int = editor._doc._undo.size()
	var preview: Dictionary = await call_tool("preview_terrain_river", args)
	var shared: Dictionary = River.apply(editor, args, true)
	check(equivalent(preview, shared), "HTTP preview equals the shared UI business operation")
	check(equivalent(before, editor._doc.recovery_snapshot()) and editor._doc._undo.size() == history, "both valid preview entry points leave document and undo untouched")
	await call_tool("sculpt_terrain", {"id": terrain.id, "mode": "hole", "points": [[500.0, 500.0]], "radius": 1.5})
	before = editor._doc.recovery_snapshot()
	history = editor._doc._undo.size()
	await call_tool("preview_terrain_river", args, false)
	await call_tool("generate_terrain_river", args, false)
	check(equivalent(before, editor._doc.recovery_snapshot()) and editor._doc._undo.size() == history, "real hole rejects preview and generation atomically through HTTP")
	await call_tool("undo")
	var base_records: Array = editor._doc.records.duplicate(true)
	var base_meta: Dictionary = editor._doc.map_meta.duplicate(true)
	await call_tool("generate_terrain_river", args)
	var generated_records: Array = editor._doc.records.duplicate(true)
	var generated_meta: Dictionary = editor._doc.map_meta.duplicate(true)
	check(generated_records.size() > base_records.size(), "successful HTTP generation produces native water records")
	await call_tool("undo")
	check(equivalent(base_records, editor._doc.records) and equivalent(base_meta, editor._doc.map_meta), "river undo restores exact terrain and metadata")
	await call_tool("redo")
	check(equivalent(generated_records, editor._doc.records) and equivalent(generated_meta, editor._doc.map_meta), "river redo restores exact generated state")
	await call_tool("save_world")
	await call_tool("open_world", {"path": path})
	check(equivalent(generated_records, editor._doc.records) and equivalent(generated_meta, editor._doc.map_meta), "native save and reopen preserve the projected river")
	await call_tool("remove_terrain_river", {"id": args.id})
	var expected_empty_meta: Dictionary = base_meta.duplicate(true)
	expected_empty_meta.terrain_rivers = [] # Native removal keeps an empty layer list.
	check(equivalent(base_records, editor._doc.records) and equivalent(expected_empty_meta, editor._doc.map_meta), "river removal restores the original native fixture with an empty river list")
	editor._mcp.stop()
	editor.queue_free()
	await settle()
	session.world3d_editor_doc = null
	session.world3d_editor_path = ""
	print("terrain_projection_http_fixture=", directory)
	print("test_terrain_projection_http: failures=%d" % failed)
	quit(0 if failed == 0 else 1)
