extends "res://tools/test_world3d_mcp.gd"
## Real 3D HTTP import/relink for the shared model-library transaction.
## Run on a private graphics desktop with RMMO_MODEL_IMPORT_TEST_ROOT pointing at
## an existing isolated content root; the formal asset packs are never touched.

const Library = preload("res://scripts/world_editor/asset_library.gd")
const Catalog = preload("res://scripts/world_editor/resource_pack_catalog.gd")
const ModelImport = preload("res://scripts/world_editor/model_import_tools.gd")
const Thumbnails = preload("res://scripts/world_editor/asset_thumbnails.gd")

func write_json(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()

func cube(path: String) -> bool:
	var source := Node3D.new()
	source.name=path.get_file().get_basename()
	var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new()
	source.add_child(mesh)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := Io.save_scene(source, path)
	source.free()
	return saved == OK

func imported(payload: Dictionary) -> Dictionary:
	var entry: Dictionary = payload.get("entry", {})
	return {"asset_id": str(payload.get("asset_id", "")), "asset_path": str(entry.get("asset_path", "")), "label": str(entry.get("label", ""))}

func run() -> void:
	create_timer(240).timeout.connect(func(): quit(2))
	Engine.max_fps = 60
	var isolated := OS.get_environment("RMMO_MODEL_IMPORT_TEST_ROOT")
	var asset_manager := root.get_node_or_null("AssetManager")
	if isolated.is_empty() or not isolated.is_absolute_path() or not DirAccess.dir_exists_absolute(isolated) or asset_manager == null:
		check(false, "runner must provide an existing absolute isolated content root")
		quit(1); return
	asset_manager.content_root_override = isolated
	check(Paths.external_root().replace("\\", "/").simplify_path() == isolated.replace("\\", "/").simplify_path(), "editor fixture uses the isolated content root")
	var directory := Paths.cache_directory("model_import_http_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	# Packs are discovered under the content root's own packs directory.
	var pack_root := Paths.external_root().path_join("packs/model_import_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(pack_root)
	write_json(pack_root.path_join("metadata.json"), {"id": "mcp_import", "name": "MCP 导入测试包"})
	check(Catalog.new().packs().any(func(pack): return str(pack.root) == pack_root), "isolated pack is discoverable by list_resource_packs")
	var first_source := directory.path_join("art_sources/first.glb")
	var second_source := directory.path_join("art_sources/second.glb")
	check(cube(first_source) and cube(second_source), "public exporter writes two real GLB fixtures")
	var map_path := directory.path_join("maps/import.gltf")
	var doc := Doc.new()
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(12, 0.2, 12))
	var path := map_path
	check(doc.save(path) == OK, "create isolated editable map")
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = path
	session.world3d_editor_doc = null
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false
	editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor); editor._safety.enabled = false
	await settle()
	# The window publishes its startup view from the load job; requests arrive
	# only after that load hands over the map.
	var load_deadline := Time.get_ticks_msec() + 120000
	while editor.saving() and Time.get_ticks_msec() < load_deadline: await process_frame
	check(not editor.saving(), "startup load settles before HTTP requests")
	var probe := TCPServer.new()
	while probe.listen(port, "127.0.0.1") != OK: port += 1
	probe.stop()
	check(editor.start_mcp(port).ok, "real 3D HTTP endpoint")
	var discovery:=await rpc("tools/list")
	check(["import_model","relink_model"].all(func(tool_name):return discovery.get("result",{}).get("tools",[]).any(func(tool):return tool.name==tool_name)),"HTTP discovers both model import and relink tools")
	await call_tool("open_world", {"path": path})
	var packs: Dictionary = await call_tool("list_resource_packs", {})
	check(packs.get("packs", []).any(func(pack): return str(pack.root) == pack_root), "HTTP advertises the fixture pack root")
	# Invalid requests must not create library entries or native products.
	var entries_before: int = editor._assets.entries.size()
	await call_tool("import_model", {"path": first_source, "pack_root": pack_root.path_join("missing")}, false)
	await call_tool("import_model", {"path": pack_root.path_join("metadata.json"), "pack_root": pack_root}, false)
	check(editor._assets.entries.size() == entries_before, "invalid pack or non-model source adds no library entry")
	var first: Dictionary = imported(await call_tool("import_model", {"path": first_source, "pack_root": pack_root}))
	var second: Dictionary = imported(await call_tool("import_model", {"path": second_source, "pack_root": pack_root}))
	check(not first.asset_id.is_empty() and not second.asset_id.is_empty() and first.asset_path != second.asset_path, "HTTP import publishes stable asset identities")
	check(Library.native_available(first.asset_path) and Library.native_available(second.asset_path), "imported models have complete native products")
	for source_path:String in [first_source,second_source,first.asset_path,second.asset_path]:
		check(DirAccess.remove_absolute(source_path)==OK,"remove fixture GLB before native-only editing")
	var listed: Dictionary = await call_tool("list_assets", {"query": "first"})
	var rows: Array = listed.get("assets", [])
	check(rows.any(func(row): return str(row.get("asset_id", "")) == first.asset_id), "list_assets exposes the imported model")
	# The authored record is created through the public placement path, which is
	# also the only entry that publishes a prepared model into the live view.
	var placed_result: Dictionary = await call_tool("place_asset", {"asset_id": first.asset_id, "position": [0, 0, 0]})
	var id: String = str(placed_result.get("ids", [""])[0])
	check(not id.is_empty(), "HTTP places the imported model")
	var placed: Dictionary = editor._doc._find(id).duplicate(true)
	await call_tool("select_objects",{"ids":[id]})
	await call_tool("duplicate_selection")
	await settle()
	var duplicates:Array=editor._doc.records.filter(func(row):return row.get("kind")=="asset" and row.uuid!=id)
	check(duplicates.size()==1,"duplicate creates one independent authored model")
	if duplicates.size()==1:
		var duplicate_view:Node=editor._view.get_node_or_null(NodePath(str(duplicates[0].uuid)))
		check(duplicate_view!=null and not duplicate_view.get_meta("missing_asset",false) and duplicate_view.get_child_count()>0,"duplicate immediately publishes a complete native visual without GLB")
	await call_tool("undo")
	check(editor._doc.records.filter(func(row):return row.get("kind")=="asset").size()==1,"duplicate undo restores one model")
	editor._dirty = false
	await settle()
	var undo_before: int = editor._doc._undo.size()
	var relinked: Dictionary = await call_tool("relink_model", {"id": id, "asset_id": second.asset_id})
	var record: Dictionary = editor._doc._find(id)
	check(relinked.get("ok", false) and record.get("asset_path") == second.asset_path, "relink points the record at the chosen native model")
	check(record.get("position") == placed.get("position") and record.get("uuid") == id, "relink keeps instance identity and transform")
	check(editor._doc._undo.size() == undo_before + 1, "relink is one undo step")
	await call_tool("undo")
	check(editor._doc._find(id).get("asset_path") == first.asset_path, "undo restores the previous model link")
	await call_tool("redo")
	check(editor._doc._find(id).get("asset_path") == second.asset_path, "redo restores the new model link")
	await call_tool("set_object_properties", {"ids": [id], "locked": true})
	var locked: Array = editor._doc.records.duplicate(true)
	var locked_undo: int = editor._doc._undo.size()
	await call_tool("relink_model", {"id": id, "asset_id": first.asset_id}, false)
	check(equivalent(editor._doc.records, locked) and editor._doc._undo.size() == locked_undo, "locked record rejects relink without document or history changes")
	await call_tool("relink_model", {"id": id, "asset_id": "missing"}, false)
	check(equivalent(editor._doc.records, locked) and editor._doc._undo.size() == locked_undo, "unknown asset id rejects relink without side effects")
	await call_tool("set_object_properties", {"ids": [id], "locked": false})
	await call_tool("save_world")
	var saved: Array = editor._doc.records.duplicate(true)
	await call_tool("open_world", {"path": path})
	check(equivalent(editor._doc.records, saved) and editor._doc._find(id).get("asset_path") == second.asset_path, "save and cold reopen preserve the relinked model")
	check(not FileAccess.file_exists(second.asset_path), "save and reopen never recreate or require the source GLB")
	if editor._mcp != null: editor._mcp.stop()
	Io._remove_tree(directory)
	Io._remove_tree(pack_root)
	print("MODEL_IMPORT_MCP failed=", failed)
	quit(0 if failed == 0 else 1)
