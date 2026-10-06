extends "res://tools/apply_medieval_town_finishing.gd"
const PREVIOUS="D:/code/rmmo_runtime/cache/world3d/medieval_town_finishing/map.gltf"
func run() -> void:
	OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_ribbon"
	CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_ribbon/map.gltf"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	create_timer(1200).timeout.connect(func():quit(2)); Engine.max_fps=60
	if "--publish" in OS.get_cmdline_user_args():
		for name_ in ["geometry_result.json","runtime_result.json"]:
			var report: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join(name_)))
			check(report is Dictionary and report.get("failures",1)==0 and report.get("candidate_sha256")==FileAccess.get_sha256(CANDIDATE),"candidate verification "+name_)
			if name_=="runtime_result.json": check(report is Dictionary and report.get("scope")=="full","full bridge and walking coverage required")
		if failed: quit(1); return
		publish(); return
	progress=FileAccess.open(OUTPUT.path_join("progress.log"),FileAccess.WRITE)
	var prior: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/medieval_town_finishing/result.json"))
	check(prior.failures==0 and FileAccess.get_sha256(PREVIOUS)==prior.candidate_sha256 and FileAccess.get_sha256(SOURCE)==prior.source_sha256,"reviewed materials and original formal map unchanged")
	if failed: quit(1); return
	var doc=Doc.open_file(PREVIOUS); check(doc!=null,"open approved wet-bank candidate")
	if doc==null: quit(1); return
	var original: Array=doc.records.duplicate(true)
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/medieval_town_layout.json"))
	var old_spec:=spec.duplicate(true); old_spec.erase("river_centerline")
	var old=preload("res://tools/medieval_town_river_curves.gd").new(); old.setup(old_spec)
	var curve=preload("res://tools/medieval_town_river_curves.gd").new(); curve.setup(spec)
	var revised: Dictionary=curve.apply(doc,old)
	check(revised.ok,"rebuild banks, bed, water and reserved corridor: "+JSON.stringify(revised))
	if not revised.ok: quit(1); return
	var before: Array=original.filter(func(r):return not r.has("channel_mesh")).duplicate(true)
	var after: Array=doc.records.filter(func(r):return not r.has("channel_mesh")).duplicate(true)
	for records in [before,after]:
		for record in records:
			if record.has("terrain_mesh"): record.terrain_mesh.erase("heights")
	check(equivalent(before,after),"all road geometry, farms, verges, identities and collision settings retained")
	root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=CANDIDATE; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false; await batches()
	var probe:=TCPServer.new(); port=31330
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real 3D MCP on regenerated river")
	await call_tool("set_river_materials",Recipe.parameters(editor._doc)); await batches()
	var expected: Array=editor._doc.records.duplicate(true)
	var id: String=expected.filter(func(r):return r.has("terrain_mesh"))[0].uuid
	var terrain: Dictionary=editor._doc._find(id)
	await call_tool("sculpt_terrain",{"id":id,"mode":"raise","points":[[terrain.position[0],terrain.position[2]]],"radius":4,"strength":.05})
	await call_tool("undo"); check(equivalent(expected,editor._doc.records),"regenerated map remains editable through HTTP, undo exact")
	check(Paint.missing(expected).is_empty(),"all approved 2K PBR dependencies retained")
	await call_tool("recall_view_bookmark",{"id":"whole_town"}); await call_tool("save_world")
	await call_tool("open_world",{"path":CANDIDATE}); await batches()
	check(equivalent(expected,editor._doc.records),"regenerated river native save/reopen exact")
	for label in VIEWS: await capture(label,VIEWS[label])
	await call_tool("set_editor_camera",VIEWS.overview); var stats:=await measure()
	check(FileAccess.get_sha256(SOURCE)==prior.source_sha256,"formal map unchanged while reviewing the new shape")
	var report:={"failures":failed,"source":SOURCE,"source_sha256":prior.source_sha256,"candidate":CANDIDATE,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"shoreline":revised,"centerline":spec.river_centerline,"performance":stats,"ground_batching":editor._ground_batches.stats(),"previous_candidate":PREVIOUS,"previous_sha256":prior.candidate_sha256}
	var f:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)
