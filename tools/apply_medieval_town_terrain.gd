extends "res://tools/apply_medieval_town_materials.gd"
## Author and review a temporary candidate through the live 3D HTTP tools.
const Recipe=preload("res://tools/medieval_town_river_materials.gd")
var progress: FileAccess
func check(ok: bool,label_: String) -> void:
	super.check(ok,label_)
	if progress: progress.store_line(("PASS " if ok else "FAIL ")+label_); progress.flush()
func batches() -> void:
	while editor._ground_batches.stats().pending_groups>0: await process_frame
	await settle()
func reject(name_: String,args: Dictionary) -> void:
	var records: Array=editor._doc.records.duplicate(true); var history: int=editor._doc._undo.size()
	await call_tool(name_,args,false)
	check(equivalent(records,editor._doc.records) and history==editor._doc._undo.size(),"invalid "+name_+" has no partial edits or undo entry")
func geometry(records: Array) -> Array:
	var result:=records.duplicate(true)
	for r in result: r.erase("terrain_material"); r.erase("terrain_depth_blend")
	return result
func measure() -> Dictionary:
	var viewport: Viewport=editor._camera.get_viewport()
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	for i in 45: await process_frame
	var samples: Array=[]
	for i in 80:
		await process_frame; samples.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
	samples.sort()
	return {"gpu_median_ms":samples[40],"gpu_p95_ms":samples[76],"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}
func run() -> void:
	OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_terrain"
	CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_terrain/map.gltf"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	progress=FileAccess.open(OUTPUT.path_join("progress.log"),FileAccess.WRITE)
	create_timer(1200).timeout.connect(func():quit(2)); Engine.max_fps=60
	if "--publish" in OS.get_cmdline_user_args():
		var geometry_report: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("geometry_result.json")))
		check(geometry_report is Dictionary and geometry_report.get("failures",1)==0 and geometry_report.get("candidate_sha256")==FileAccess.get_sha256(CANDIDATE),"reviewed candidate passed shore and terrain seam geometry audit")
		var runtime: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("runtime_result.json")))
		check(runtime is Dictionary and runtime.get("failures",1)==0 and runtime.get("scope")=="full" and runtime.get("candidate_sha256")==FileAccess.get_sha256(CANDIDATE),"reviewed candidate passed full walking/bridge runtime verification")
		if failed: quit(1); return
		publish(); return
	var doc=Doc.open_file(SOURCE); check(doc!=null,"open actual 1.4 km town")
	if doc==null: quit(1); return
	var source_hash:=FileAccess.get_sha256(SOURCE); var original: Array=doc.records.duplicate(true)
	check(source_hash=="afd94beb232c0a0b6cf95022c9387d217e2cfed94c5ad111949b1b7be3383bbc","expected authored base; do not overwrite subsequent user sculpting")
	if failed: quit(1); return
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/medieval_town_layout.json"))
	var curve=preload("res://tools/medieval_town_river_curves.gd").new(); curve.setup(spec)
	var previous=preload("res://tools/medieval_town_river_curves.gd").new(); previous.setup(spec.merged(spec.river_previous_trace,true).merged({"river_dry_bank_width":10.},true))
	var revised: Dictionary=curve.apply(doc,previous)
	check(revised.ok,"reference shoreline revision: "+JSON.stringify(revised))
	var ground:=preload("res://tools/medieval_town_ground_materials.gd").apply(doc)
	check(ground.ok and ground.dirt_chunks>0,"rural dirt paths separated from urban stone paving: "+str(ground.get("dirt_chunks",0)))
	if failed: quit(1); return
	var revised_geometry:=geometry(doc.records)
	var old_roads: Array=original.filter(func(r):return r.has("road_mesh")).duplicate(true)
	var new_roads: Array=doc.records.filter(func(r):return r.has("road_mesh")).duplicate(true)
	for records in [old_roads,new_roads]:
		for r in records: r.erase("surface_paint")
	check(equivalent(old_roads,new_roads),"all road and bridge geometry, identities and collision preserved")
	# Work in memory until the single native save below; the editor's target is
	# always the temporary candidate, never the source map.
	root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=CANDIDATE; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false; await batches()
	var probe:=TCPServer.new(); port=30970
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"full town HTTP MCP")
	var defs: Array=(await rpc("tools/list")).result.tools
	check(defs.any(func(d):return d.name=="set_terrain_material") and defs.any(func(d):return d.name=="set_river_materials") and defs.all(func(d):return d.name!="paint_tile"),"3D material tools discovered, old 2D disabled")
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	var close_camera:={"projection":"perspective","center":[338,-1.5,-125],"distance":34,"pitch":-38,"yaw":30}
	# The source-only before views are retained from the first audit; this scene
	# already has the corrected shoreline geometry and is not a before image.
	var terrain_ids: Array=[]
	for r in original:
		if r.has("terrain_mesh"): terrain_ids.append(r.uuid)
	check(terrain_ids.size()==49,"49 editable terrain patches")
	await reject("set_terrain_material",{"id":terrain_ids[0],"material_id":"pack:default:missing/grass"})
	for id in terrain_ids: await call_tool("set_terrain_material",{"id":id,"material_id":Recipe.GROUND_MATERIAL})
	await batches()
	var before_river: Array=editor._doc.records.duplicate(true); var args:=Recipe.parameters(editor._doc)
	await reject("set_river_materials",args.merged({"shore_end":.01},true))
	var history: int=editor._doc._undo.size()
	await call_tool("set_river_materials",args); await batches()
	check(editor._doc._undo.size()==mini(history+1,32),"river configuration is one undo transaction (32-entry history cap)")
	var after: Array=editor._doc.records.duplicate(true)
	await call_tool("undo"); await batches(); check(equivalent(before_river,editor._doc.records),"undo restores previous river while keeping grass")
	await call_tool("redo"); await batches(); check(equivalent(after,editor._doc.records),"redo restores natural bank coverage")
	# River water settings are intentionally retuned below; its geometry is fixed.
	var material_geometry:=geometry(after)
	for records in [revised_geometry,material_geometry]:
		for r in records: r.erase("water_depth_effect")
	check(equivalent(revised_geometry,material_geometry),"material edits preserve corrected heights, holes, geometry, IDs and collision")
	check(Paint.missing(after).is_empty(),"all 2K PBR dependencies present")
	check(after.filter(func(r):return r.has("terrain_material") and r.terrain_material.has("normal_path")).size()==49,"all terrain carries grass normals")
	await call_tool("save_world"); await call_tool("open_world",{"path":CANDIDATE}); await batches()
	check(equivalent(after,editor._doc.records),"HTTP save/reopen retains material records")
	var catalog:=await call_tool("list_terrains")
	check(catalog.terrains.filter(func(r):return r.depth_blend.get("bank_profile")=="natural").size()==args.terrain_ids.size(),"HTTP reports all corrected natural river patches")
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	await capture("overview",{"projection":"top","center":[0,0,0],"span":1480})
	var merged:=await measure(); var stats: Dictionary=editor._ground_batches.stats()
	# Same material/lighting/camera: measure only the batching effect, not flat-colour vs PBR.
	editor._ground_batches.clear(); await settle(); var separate:=await measure()
	check(merged.draw_calls<separate.draw_calls*.6 and merged.buffer_bytes<separate.buffer_bytes,"natural PBR terrain retains draw-call and GPU-buffer savings")
	editor._sync_ground_batches(); await batches()
	await capture("river_close",close_camera)
	await capture("river_bridge",{"projection":"perspective","center":[338,-1,-154],"distance":150,"pitch":-48,"yaw":-18})
	await capture("south_bank",{"projection":"perspective","center":[215,-1,350],"distance":200,"pitch":-55,"yaw":0})
	await capture("grass_close",{"projection":"perspective","center":[-80,0,30],"distance":9,"pitch":-40,"yaw":22})
	await capture("patch_crossing",{"projection":"perspective","center":[357,-1,-100],"distance":70,"pitch":-52,"yaw":30})
	await call_tool("recall_view_bookmark",{"id":"whole_town"})
	check(source_hash==FileAccess.get_sha256(SOURCE),"user map remains unchanged during candidate tests")
	var report:={"failures":failed,"source":SOURCE,"source_sha256":source_hash,"candidate":CANDIDATE,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"shoreline":revised,"ground_materials":ground,"parameters":args,"grass_material":Recipe.GROUND_MATERIAL,"merged":merged,"unmerged":separate,"ground_batching":stats,"gpu":RenderingServer.get_video_adapter_name()}
	var f:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)
