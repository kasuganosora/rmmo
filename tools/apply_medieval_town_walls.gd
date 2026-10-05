extends "res://tools/apply_medieval_town_finishing.gd"
const Walls=preload("res://tools/medieval_town_walls.gd")
func run() -> void:
	OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_walls"; CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_walls/map.gltf"
	DirAccess.make_dir_recursive_absolute(OUTPUT); DirAccess.make_dir_recursive_absolute(CANDIDATE.get_base_dir()); rpc_timeout_ms=240000
	create_timer(1800).timeout.connect(func():quit(2)); Engine.max_fps=30
	if "--publish" in OS.get_cmdline_user_args():
		var runtime: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("runtime_result.json")))
		check(runtime is Dictionary and runtime.get("failures",1)==0 and runtime.get("candidate_sha256")==FileAccess.get_sha256(CANDIDATE),"reviewed candidate passed actual floor and crossing collision checks")
		var performance: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("batching/performance.json")))
		check(performance is Dictionary and performance.get("failures",1)==0 and performance.get("candidate_sha256")==FileAccess.get_sha256(CANDIDATE) and performance.after.buffer_bytes<=performance.before.buffer_bytes*1.05,"reviewed candidate passed city-defense batching without GPU buffer inflation")
		if failed: quit(1); return
		publish(); return
	progress=FileAccess.open(OUTPUT.path_join("progress.log"),FileAccess.WRITE)
	var export_only: bool="--export-only" in OS.get_cmdline_user_args()
	var doc=Doc.open_file(SOURCE); check(doc!=null,"open formal town")
	if doc==null: quit(1); return
	var source_hash:=FileAccess.get_sha256(SOURCE); var original: Array=doc.records.duplicate(true)
	var roads:=Walls.correct_approaches(doc); check(roads.ok,"local approaches retain graph connectivity")
	if not roads.ok: print(roads); quit(1); return
	var args:=Walls.requests(doc); Walls.water_zones(doc,args)
	var grading:=Walls.grade_foundations(doc,args)
	check(preload("res://scripts/world3d/city_layout.gd").valid(doc.map_meta),"water crossings preserve valid reserved volumes")
	if failed: quit(1); return
	var base: Array=doc.records.duplicate(true)
	root.size=Vector2i(1700,1200); root.content_scale_size=root.size
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=CANDIDATE; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false; await batches()
	var probe:=TCPServer.new(); port=31720
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real HTTP wall authoring")
	var defs: Array=(await rpc("tools/list")).result.tools
	var schema: Dictionary=defs.filter(func(d):return d.name=="generate_fortification")[0].inputSchema
	check(schema.properties.has("tower_indices") and schema.properties.has("terrain_foundation"),"3D discovery exposes traced towers and terrain foundations")
	if "--preflight" not in OS.get_cmdline_user_args() and not export_only:
		await reject("generate_fortification",args.merged({"tower_indices":[999]},true))
		await reject("set_map_reference",{"opacity":2})
		await call_tool("set_map_reference",{"visible":true,"opacity":.38,"meters_per_pixel":1.4,"center":[0,0,0],"yaw":0})
		var ref: Dictionary=editor._doc.map_meta.editor_layout.reference.duplicate(true)
		await call_tool("undo"); await call_tool("redo"); check(equivalent(ref,editor._doc.map_meta.editor_layout.reference),"reference opacity and uniform scale undo/redo")

	var planned: Dictionary={}
	if not export_only:
		planned=await call_tool("preview_fortification",args)
		if not planned.get("ok",false): print("WALL_PREVIEW_ERROR ",JSON.stringify(planned)); quit(1); return
		print("WALL_PLAN count=",planned.count," towers=",planned.tower_count," length=",planned.length)
	if "--preflight" in OS.get_cmdline_user_args(): editor._mcp.stop(); quit(0); return
	var request:=args if export_only else args.merged({"plan_token":planned.plan_token})
	var result:=await call_tool("generate_fortification",request)
	if not result.get("ok",false): print(result); quit(1); return
	if export_only: planned={"count":result.count,"tower_count":args.tower_indices.size()}
	await batches(); var expected: Array=editor._doc.records.duplicate(true)
	check(base.all(func(r):return equivalent(r,editor._doc._find(r.uuid))),"wall generation preserves all staged terrain, road and bridge records")
	check(original.filter(func(r):return r.uuid not in roads.replaced_road_ids and r.uuid not in grading.terrain_ids).all(func(r):return equivalent(r,editor._doc._find(r.uuid))),"terrain outside foundations, water, five bridges and unrelated roads unchanged")
	if not export_only:
		await call_tool("undo"); check(equivalent(base,editor._doc.records),"one undo removes complete wall")
		await call_tool("redo"); check(equivalent(expected,editor._doc.records),"wall redo exact")
	var panel=editor._city.panel.fortification_panel; panel.current=editor._fortifications.regions()[0].settings.duplicate(true); panel.form()
	check(equivalent(panel.request().tower_indices,args.tower_indices) and panel.request().terrain_foundation,"UI restores selected tower nodes and terrain mode")
	await call_tool("set_map_reference",{"visible":false})
	# A whole-city first export can exceed the synchronous HTTP test deadline.
	# Exercise the public background-save contract and wait for its final state.
	var started:=await call_tool("save_world",{"background":true})
	if not started.get("ok",false): quit(1); return
	while editor.saving(): await create_timer(.5).timeout
	var saved_state:=await call_tool("editor_state")
	check(saved_state.save.result.get("saved",false),"background native save completes successfully")
	if not saved_state.save.result.get("saved",false): print(saved_state.save.result); quit(1); return
	var opened:=await call_tool("open_world",{"path":CANDIDATE})
	if not opened.get("ok",false): quit(1); return
	await batches()
	check(equivalent(expected,editor._doc.records),"native save/reopen exact")
	await capture("overview",{"projection":"top","center":[0,0,0],"span":1480})
	await capture("northwest",{"projection":"perspective","center":[-430,2,-403],"distance":260,"pitch":-40,"yaw":25})
	await capture("water_gate",{"projection":"perspective","center":[-55,4,636],"distance":105,"pitch":-25,"yaw":5})
	await capture("east_gate",{"projection":"perspective","center":[591,3,-180],"distance":75,"pitch":-28,"yaw":-70})
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":1480}); var metrics:=await measure()
	check(FileAccess.get_sha256(SOURCE)==source_hash,"formal map unchanged until publication")
	var report:={"failures":failed,"export_only":export_only,"source_sha256":source_hash,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"request":args,"tower_count":planned.tower_count,"wall_records":planned.count,"road_corrections":roads,"foundation_grading":grading,"performance":metrics}
	var file:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	editor._mcp.stop(); editor.queue_free(); await settle(); print("TOWN_WALL_FINISHED failures=",failed); quit(1 if failed else 0)
