extends "res://tools/apply_medieval_town_terrain.gd"
const Ground=preload("res://tools/medieval_town_ground_materials.gd")
func run() -> void:
	if "--publish" in OS.get_cmdline_user_args(): await super.run(); return
	OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_terrain"
	CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_terrain/map.gltf"
	progress=FileAccess.open(OUTPUT.path_join("regions_progress.log"),FileAccess.WRITE)
	create_timer(1600).timeout.connect(func():quit(2)); Engine.max_fps=60
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("result.json")))
	check(report.failures==0 and report.candidate_sha256==FileAccess.get_sha256(CANDIDATE) and report.source_sha256==FileAccess.get_sha256(SOURCE),"continue only verified unchanged candidate")
	if failed: quit(1); return
	var doc=Doc.open_file(CANDIDATE); var original: Array=doc.records.duplicate(true)
	root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=CANDIDATE; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); port=30970
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"town region authoring through real HTTP MCP")
	var definitions: Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(d):return d.name=="paint_terrain_region") and definitions.all(func(d):return d.name!="paint_tile"),"current 3D region tool discovered")
	for r in original:
		if r.has("terrain_mesh"): await call_tool("set_terrain_material",{"id":r.uuid,"material_id":Ground.GRASS,"saturation":.45})
	var requests:=Ground.region_requests(editor._doc); var affected:={}
	if "--grade" in OS.get_cmdline_user_args(): requests=[]
	if not requests.is_empty(): await reject("paint_terrain_region",{"id":"over_budget","terrain_ids":requests[0].terrain_ids,"polygon":[[-700,-700],[700,-700],[700,700],[-700,700]],"material_id":Ground.DIRT,"feather":4.})
	for request in requests:
		var result:=await call_tool("paint_terrain_region",request)
		for id in result.get("changed_ids",[]): affected[id]=true
		check(result.ok,"reference region "+str(request.id))
	await batches()
	var expected: Array=editor._doc.records.duplicate(true)
	var after_geometry:=expected.duplicate(true); var before_geometry:=original.duplicate(true)
	for records in [after_geometry,before_geometry]:
		for r in records: r.erase("terrain_material"); r.erase("terrain_regions"); r.erase("terrain_saturation")
	check(equivalent(after_geometry,before_geometry),"regional PBR preserves all heights, river, road, collision and identity")
	await call_tool("undo"); await call_tool("redo"); check(equivalent(expected,editor._doc.records),"last town region undo/redo exact")
	if failed: editor._mcp.stop(); editor.queue_free(); await settle(); quit(1); return
	await call_tool("save_world"); await call_tool("open_world",{"path":CANDIDATE}); await batches()
	check(equivalent(expected,editor._doc.records),"town ground regions survive native save/reopen")
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	await capture("overview",{"projection":"top","center":[0,0,0],"span":1480})
	var merged:=await measure(); var stats: Dictionary=editor._ground_batches.stats()
	editor._ground_batches.clear(); await settle(); var separate:=await measure()
	check(merged.draw_calls<separate.draw_calls*.6 and merged.buffer_bytes<separate.buffer_bytes,"ground regions retain material batching savings")
	editor._sync_ground_batches(); await batches()
	await capture("river_close",{"projection":"perspective","center":[338,-1.5,-125],"distance":34,"pitch":-38,"yaw":30})
	await capture("river_bridge",{"projection":"perspective","center":[338,-1,-154],"distance":150,"pitch":-48,"yaw":-18})
	await capture("north_fields",{"projection":"perspective","center":[100,0,-560],"distance":240,"pitch":-62,"yaw":0})
	await capture("west_yards",{"projection":"perspective","center":[-400,0,125],"distance":160,"pitch":-55,"yaw":20})
	await capture("ground_close",{"projection":"perspective","center":[-405,0,130],"distance":22,"pitch":-50,"yaw":22})
	await call_tool("recall_view_bookmark",{"id":"whole_town"})
	check(report.source_sha256==FileAccess.get_sha256(SOURCE),"source remains unchanged until publication")
	report.merge({"failures":failed,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"grass_material":Ground.GRASS,"regions":requests.size() if not requests.is_empty() else report.get("regions",0),"region_terrain_patches":affected.size() if not requests.is_empty() else report.get("region_terrain_patches",0),"grass_saturation":.45,"merged":merged,"unmerged":separate,"ground_batching":stats},true)
	var f:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)
