extends "res://tools/apply_medieval_town_terrain.gd"
const Cultivation=preload("res://tools/medieval_town_cultivation.gd")
const Furrows=preload("res://scripts/world3d/terrain_furrows.gd")
func run() -> void:
	OUTPUT="D:/code/rmmo_runtime/review_artifacts/terrain_furrows/town"
	CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_furrows/map.gltf"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	if "--publish" in OS.get_cmdline_user_args():
		var runtime: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("runtime_result.json")))
		check(runtime is Dictionary and runtime.get("failures",1)==0 and runtime.get("candidate_sha256")==FileAccess.get_sha256(CANDIDATE),"candidate runtime verified")
		var review: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("performance.json")))
		check(review is Dictionary and review.get("failures",1)==0 and review.get("candidate_sha256")==FileAccess.get_sha256(CANDIDATE),"candidate visual/batching review verified")
		if failed: quit(1); return
		publish(); return
	progress=FileAccess.open(OUTPUT.path_join("progress.log"),FileAccess.WRITE)
	create_timer(1600).timeout.connect(func():quit(2)); Engine.max_fps=60
	var doc=Doc.open_file(SOURCE); check(doc!=null,"open current town")
	if doc==null: quit(1); return
	var source_hash:=FileAccess.get_sha256(SOURCE); var original: Array=doc.records.duplicate(true)
	root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=CANDIDATE; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false; await batches()
	var probe:=TCPServer.new(); port=31060
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"town real HTTP MCP")
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	var overview:={"projection":"top","center":[0,0,0],"span":1480}
	var close:={"projection":"perspective","center":[-380,0,-15],"distance":9,"pitch":-45,"yaw":20}
	await capture("grass_before",close)
	await capture("overview_before",overview); var before_stats:=await measure()
	var materials:=await call_tool("list_surface_materials",{"category":"地表／草地","limit":50})
	check(materials.materials.any(func(m):return m.material_id==Cultivation.GRASS),"2K Mossy Grass available through 3D catalog")
	for record in original:
		if record.has("terrain_mesh"):
			var result:=await call_tool("set_terrain_material",{"id":record.uuid,"material_id":Cultivation.GRASS,"saturation":1.})
			if not result.ok: quit(1); return
	for args in Cultivation.field_regions(editor._doc):
		var result:=await call_tool("paint_terrain_region",args)
		if not result.ok: quit(1); return
	var requests:=Cultivation.requests(editor._doc.records)
	for args in requests:
		var result:=await call_tool("set_terrain_furrows",args)
		if not result.ok: quit(1); return
	await batches(); var expected: Array=editor._doc.records.duplicate(true)
	var before_geometry:=original.duplicate(true); var after_geometry:=expected.duplicate(true)
	for rows in [before_geometry,after_geometry]:
		for r in rows:
			for key in ["terrain_material","terrain_saturation","terrain_regions"]: r.erase(key)
	check(equivalent(before_geometry,after_geometry),"all base heights, river, road, identity and collision settings retained")
	check(Paint.missing(expected).is_empty(),"all PBR dependencies present")
	await call_tool("undo"); await call_tool("redo"); check(equivalent(expected,editor._doc.records),"town last farm undo/redo exact")
	await call_tool("recall_view_bookmark",{"id":"whole_town"}); await call_tool("save_world"); await call_tool("open_world",{"path":CANDIDATE}); await batches()
	check(equivalent(expected,editor._doc.records),"full town native save/reopen")
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	await capture("overview",overview); var after_stats:=await measure(); var batching: Dictionary=editor._ground_batches.stats()
	await capture("grass_after",close)
	await capture("farm",{"projection":"perspective","center":[-205,0,-670],"distance":100,"pitch":-48,"yaw":15})
	await capture("farm_close",{"projection":"perspective","center":[-210,0,-670],"distance":10,"pitch":-40,"yaw":12})
	await capture("river_seam",{"projection":"perspective","center":[357,-1,-100],"distance":70,"pitch":-52,"yaw":30})
	var triangles:=0
	for r in expected:
		if r.has("terrain_mesh"): triangles+=Furrows.generate(r).triangles
	check(source_hash==FileAccess.get_sha256(SOURCE),"source unchanged during validation")
	var report:={"failures":failed,"source":SOURCE,"source_sha256":source_hash,"candidate":CANDIDATE,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"grass_material":Cultivation.GRASS,"grass_saturation":1.,"farms":requests.size(),"furrow_triangles":triangles,"before":before_stats,"after":after_stats,"ground_batching":batching}
	var f:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)
