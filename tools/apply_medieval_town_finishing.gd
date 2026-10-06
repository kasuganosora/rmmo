extends "res://tools/apply_medieval_town_terrain.gd"
const Finish=preload("res://tools/medieval_town_finishing.gd")
const RegionTool=preload("res://scripts/world_editor/terrain_region_tools.gd")
const VIEWS={
	"overview":{"projection":"top","center":[0,0,0],"span":1480},
	"river":{"projection":"perspective","center":[357,-1,-100],"distance":70,"pitch":-52,"yaw":30},
	"river_close":{"projection":"perspective","center":[362,-1.3,-122],"distance":12,"pitch":-38,"yaw":40},
	"rural_junction":{"projection":"perspective","center":[-460,0,-310],"distance":95,"pitch":-60,"yaw":0},
	"farm":{"projection":"perspective","center":[-350,0,-675],"distance":95,"pitch":-52,"yaw":15}}

func capture(label: String,camera: Dictionary) -> void:
	await call_tool("set_editor_camera",camera)
	for i in 30: await process_frame
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	await RenderingServer.frame_post_draw
	check(editor._camera.get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(label+".png"))==OK,"render "+label)

func run() -> void:
	OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_finishing"
	CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_finishing/map.gltf"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	create_timer(1200).timeout.connect(func():quit(2)); Engine.max_fps=60
	if "--publish" in OS.get_cmdline_user_args():
		var runtime: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("runtime_result.json")))
		check(runtime is Dictionary and runtime.get("failures",1)==0 and runtime.get("scope")=="full" and runtime.get("candidate_sha256")==FileAccess.get_sha256(CANDIDATE),"full candidate walking/bridge verification")
		if failed: quit(1); return
		publish(); return
	progress=FileAccess.open(OUTPUT.path_join("progress.log"),FileAccess.WRITE)
	var doc=Doc.open_file(SOURCE); check(doc!=null,"open current formal town")
	if doc==null:
		var raw:=Doc.authoritative_extras(SOURCE)
		print("READ_DIAGNOSTIC ",raw.get("error","extras read"))
		for r in raw.get("extras",{}).get("rmmo_records",[]):
			if not Paint.valid(r): print("INVALID_MATERIAL ",r.uuid," river=",preload("res://scripts/world3d/river_material_data.gd").valid(r)); break
		quit(1); return
	var source_hash:=FileAccess.get_sha256(SOURCE); var original: Array=doc.records.duplicate(true)
	var requests:=Finish.requests(doc)
	check(requests.ok,"derive road faces and continuous soil verges")
	if not requests.ok: print(requests); quit(1); return
	# Preflight every mask against the real per-patch budgets before live edits.
	var staging: Array=original.duplicate(true); var library:=Library.new()
	for args in requests.regions:
		var result:=RegionTool.prepare(staging,args,library,func(r):return not r.get("editor_hidden",false) and not r.get("editor_locked",false))
		if not result.ok: check(false,"region preflight "+JSON.stringify([args,result])); quit(1); return
		for replacement in result.records:
			for i in staging.size():
				if staging[i].uuid==replacement.uuid: staging[i]=replacement; break
	check(true,"all verge masks fit existing layer/vertex/work budgets")
	print("FINISH_REQUESTS regions=",requests.regions.size()," faces=",requests.paints.size())
	if "--preflight" in OS.get_cmdline_user_args(): quit(1 if failed else 0); return
	root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=CANDIDATE; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false; await batches()
	var probe:=TCPServer.new(); port=31300
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real HTTP MCP for town finishing")
	var definitions: Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(d):return d.name=="set_river_materials" and d.inputSchema.properties.has("wet_darkening")),"3D MCP discovers wet riverbank parameter")
	for label in VIEWS: await capture(label+"_before",VIEWS[label])
	await call_tool("set_editor_camera",VIEWS.overview); var before:=await measure()
	var args:=Recipe.parameters(editor._doc)
	await reject("set_river_materials",args.merged({"wet_darkening":1.1},true))
	await call_tool("set_river_materials",args); await batches()
	var river_expected: Array=editor._doc.records.duplicate(true)
	await call_tool("undo"); check(equivalent(original,editor._doc.records),"wetness undo restores exact source records")
	await call_tool("redo"); check(equivalent(river_expected,editor._doc.records),"wetness redo exact")
	for request in requests.paints:
		var result:=await call_tool("paint_surface",request)
		if not result.ok: quit(1); return
	for request in requests.regions:
		var result:=await call_tool("paint_terrain_region",request)
		if not result.ok: quit(1); return
	await batches()
	var expected: Array=editor._doc.records.duplicate(true)
	var old_geometry:=original.duplicate(true); var new_geometry:=expected.duplicate(true)
	for rows in [old_geometry,new_geometry]:
		for r in rows:
			for field in ["terrain_depth_blend","water_depth_effect","surface_paint"]: r.erase(field)
			if r.has("terrain_regions"): r.terrain_regions.regions=r.terrain_regions.regions.filter(func(region):return not str(region.id).begins_with("verge_"))
			if r.get("terrain_regions",{}).get("regions",[]).is_empty(): r.erase("terrain_regions")
			elif r.has("terrain_regions"): preload("res://scripts/world3d/terrain_regions.gd").compact(r.terrain_regions)
	check(equivalent(old_geometry,new_geometry),"all terrain heights, holes, 12 farms, roads, IDs and collision settings preserved")
	check(Paint.missing(expected).is_empty(),"complete PBR dependencies")
	await call_tool("undo"); await call_tool("redo"); check(equivalent(expected,editor._doc.records),"verge undo/redo exact")
	await call_tool("recall_view_bookmark",{"id":"whole_town"})
	await call_tool("save_world"); await call_tool("open_world",{"path":CANDIDATE}); await batches()
	check(equivalent(expected,editor._doc.records),"native save/reopen retains finished terrain")
	for label in VIEWS: await capture(label,VIEWS[label])
	await call_tool("set_editor_camera",VIEWS.overview); var after:=await measure()
	var batching: Dictionary=editor._ground_batches.stats()
	# Same rendered material with/without batching; verify world wetness doesn't
	# restart at a batch boundary and record its actual cost.
	await capture("bank_merged",VIEWS.river)
	var image_a: Image=editor._camera.get_viewport().get_texture().get_image()
	editor._ground_batches.clear(); await capture("bank_unmerged",VIEWS.river)
	var image_b: Image=editor._camera.get_viewport().get_texture().get_image(); var difference:=0.; var count:=0
	for z in range(0,image_a.get_height(),3):
		for x in range(0,image_a.get_width(),3):
			var a:=image_a.get_pixel(x,z); var b:=image_b.get_pixel(x,z)
			difference+=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b); count+=3
	difference/=float(count)
	check(difference<.001,"wet riverbank merged/unmerged visual agreement")
	check(after.draw_calls<=before.draw_calls+40,"verges and wetness retain spatial ground batching")
	check(FileAccess.get_sha256(SOURCE)==source_hash,"formal map unchanged during validation")
	var report:={"failures":failed,"source":SOURCE,"source_sha256":source_hash,"candidate":CANDIDATE,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"road_faces":requests.paints.size(),"changed_roads":requests.changed_roads,"verge_requests":requests.regions.size(),"river_parameters":args,"before":before,"after":after,"ground_batching":batching,"bank_batch_image_difference":difference}
	var f:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)
