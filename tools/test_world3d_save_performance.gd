extends "res://tools/test_world3d_roads.gd"
const SaveIo = preload("res://scripts/world3d/gltf_map_io.gd")
func run() -> void:
	create_timer(240).timeout.connect(func(): quit(2))
	directory = Paths.cache_directory("save_perf_http_%d" % Time.get_ticks_usec())
	map_path = directory.path_join("map.gltf")
	var doc := Doc.new()
	check(doc.save(map_path) == OK, "temporary map")
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = map_path; session.world3d_editor_doc = doc
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false; editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled = false
	var probe := TCPServer.new(); port = 31540
	while probe.listen(port, "127.0.0.1") != OK: port += 1
	probe.stop(); check(editor.start_mcp(port).ok, "real HTTP save server")
	var definitions: Array = (await rpc("tools/list")).result.tools
	check(definitions.size() == 114 and definitions.any(func(d): return d.name == "save_world") and definitions.all(func(d): return d.name != "paint_tile"), "current 3D save tool, no legacy 2D registration")
	var ids := []
	for x in [8,24]:
		var made := await call_tool("create_terrain", {"center":[x,0,8],"width":16,"depth":16,"cell_size":2})
		ids.append(made.id)
	var first := await call_tool("save_world")
	check(first.timings.export.streamed_meshes == 2 and first.timings.geometry_cache_misses == 2, "HTTP reports streamed geometry and first-save timings")
	var second := await call_tool("save_world")
	check(second.timings.geometry_cache_hits == 2 and second.timings.geometry_cache_bytes <= 100663296, "unchanged geometry reused in bounded CPU cache")
	check(editor._status.text.begins_with("已保存（"), "UI reports actual shared-operation time")
	var initial: Array = doc.records.duplicate(true)
	await call_tool("sculpt_terrain", {"id":ids[0],"mode":"raise","points":[[14,8]],"radius":1.5,"strength":0.1})
	var expected: Array = doc.records.duplicate(true)
	var edited := await call_tool("save_world")
	check(edited.timings.geometry_cache_misses == 2, "sculpt invalidates own mesh and neighbor shared normals")
	var fresh := Doc.new(); fresh.records = doc.records.duplicate(true); fresh.map_meta = doc.map_meta.duplicate(true)
	var fresh_view: Node3D = fresh.build(false); var cached_view: Node3D = doc.build(false)
	var equal_meshes := true
	for i in fresh_view.get_child_count():
		var a: Mesh = fresh_view.get_child(i).mesh; var b: Mesh = cached_view.get_child(i).mesh
		if a.get_surface_count() != b.get_surface_count(): equal_meshes = false; continue
		for slot in a.get_surface_count():
			var aa := a.surface_get_arrays(slot); var bb := b.surface_get_arrays(slot)
			if var_to_bytes(aa) != var_to_bytes(bb):
				equal_meshes = false
				for channel in Mesh.ARRAY_MAX:
					if var_to_bytes(aa[channel]) == var_to_bytes(bb[channel]): continue
					print("CACHE_DIFFERENCE mesh=",i," slot=",slot," channel=",channel," before=",str(aa[channel]).left(180)," after=",str(bb[channel]).left(180))
	check(equal_meshes, "cached mesh arrays equal independently rebuilt edited terrain")
	fresh_view.free(); cached_view.free()
	await call_tool("undo"); check(equivalent(initial,doc.records), "undo survives save")
	await call_tool("redo"); check(equivalent(expected,doc.records), "redo survives save")
	await call_tool("save_world")
	await call_tool("open_world", {"path":map_path})
	check(equivalent(expected,editor._doc.records), "HTTP save/reopen keeps authored geometry")
	var signature := FileAccess.get_sha256(map_path)
	await call_tool("save_world", {"path":"C:/rmmo_outside.gltf"}, false)
	check(FileAccess.get_sha256(map_path) == signature, "invalid path has no side effects")
	var external = Doc.open_file(map_path)
	external.map_meta["save_test_revision"] = 2
	check(external.save(map_path) == OK, "external writer")
	signature = FileAccess.get_sha256(map_path)
	await call_tool("save_world", {}, false)
	check(FileAccess.get_sha256(map_path) == signature, "stale HTTP save preserves external revision")
	await call_tool("open_world", {"path":map_path,"discard_changes":true})
	await call_tool("sculpt_terrain", {"id":ids[0],"mode":"raise","points":[[8,8]],"radius":1.5,"strength":0.1})
	SaveIo.save_fault = func(stage): return stage == "before_publish"
	await call_tool("save_world", {}, false)
	SaveIo.save_fault = Callable()
	check(editor._dirty and FileAccess.get_sha256(map_path) == signature, "interrupted save preserves live map and dirty state")
	await call_tool("save_world")
	check(not editor._dirty, "retry publishes intact geometry")
	var report := {"failures":failed,"first":first.timings,"cached":second.timings,"edited":edited.timings}
	var file := FileAccess.open(preload("res://scripts/asset/art_paths.gd").review_path("save_performance/http.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	editor._mcp.stop(); editor.queue_free(); await settle()
	SaveIo._remove_tree(directory)
	print("SAVE_PERFORMANCE_HTTP failures=",failed)
	quit(0 if failed == 0 else 1)
