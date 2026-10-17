extends "res://tools/test_residential_relocation_http.gd"

func run()->void:
	create_timer(900).timeout.connect(func():push_error("Block HTTP timeout");quit(2));rpc_timeout_ms=120000;Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	report_path="D:/code/rmmo_runtime/review_artifacts/joint_candidate_20261017/residential.json"
	var source_report:="review_artifacts/residential_curves_20261017/http.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		if arg.begins_with("--source-report="):source_report=arg.trim_prefix("--source-report=")
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_report))
	check(source.failures==0 and FileAccess.get_sha256(source.fixture)==source.map_sha256,"verified frozen source map remains read-only")
	if failed:await finish();return
	directory=Paths.external_root().path_join("__joint_residential_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":"residential_block_%d"%OS.get_process_id(),"name":"临时街区联合候选回归"}))
	map_path=directory.path_join("maps/test/map.gltf");var doc=Doc.open_file(source.fixture)
	var dependency:=isolate_dependency(doc.records.filter(func(r):return r.get("building",{}).get("id")==source.plan.building_id))
	for record:Dictionary in doc.records:
		if record.get("building",{}).get("id")==source.plan.building_id:
			if record.get("fixture",{}).get("kind")=="window":record.fixture.open=.35
			preload("res://scripts/world3d/house_prefab.gd").retarget_materials(record)
	var road_settings:Dictionary=doc.map_meta.editor_layout.road_surface.settings.duplicate(true)
	doc.records=doc.records.filter(func(r):return not r.has("road_source"));doc.map_meta.editor_layout.erase("road_surface")
	doc.map_meta.editor_layout.roads=source.source_graph.duplicate(true)
	check(doc.save(map_path)==OK,"private mixed-house baseline saved")
	if failed:await finish();return
	Net.session().world3d_editor_path=map_path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);await settle();editor._safety.enabled=false
	while editor._load_job!=null and editor._load_job.active:await process_frame
	editor._material_tool.library.include_shared=true;editor._shared_assets=[Library.new(source.source_path.get_base_dir().get_base_dir())]
	var probe:=TCPServer.new();port=33910
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"private 3D loopback server starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.filter(func(d):return str(d.name).ends_with("residential_block")).size()==3 and not definitions.any(func(d):return d.name=="paint_tile"),"current 3D discovers all block tools without retired 2D")
	var made:=await call_tool("generate_road_surface",road_settings)
	if not made.get("ok",false):manifest.last_failure=made;await finish();return
	var id:String=source.plan.building_id;var original:Dictionary=editor._doc.recovery_snapshot()
	var args:Dictionary={"homes":[{"id":"home_1","residential":Placement.defaults().merged({"building_id":id,"position":[-8.,.12,1.],"road_edge_id":"main_lane","setback_min":2.5},true)},{"id":"home_2","residential":Placement.defaults().merged({"asset_id":source.asset_id,"position":[8.,.12,1.],"road_edge_id":"main_lane","setback_min":2.5},true)}],"terrain":{"strokes":[{"id":"residential_ground","mode":"flatten","shape":"rectangle","points":[[0.,1.]],"plot_width":30.,"plot_depth":19.,"plot_yaw":0.,"plot_grade":[0.,0.],"target_height":.12,"strength":1.,"blend_margin":2.,"cross_tiles":true}]}}
	var steps:Array=[{"id":"homes","preview_residential_block":args},{"id":"paving","generate_road_surface":road_settings}]
	var request:Dictionary={"steps":steps};manifest.request=request
	var before:=snapshot();var plan:=await call_tool("preview_joint_candidate",request)
	if not plan.ok:manifest.last_failure=plan;await finish();return
	same_snapshot(before,"general queue stages grading, migration, new home and paving privately")
	check(plan.steps[0].result.homes.size()==2 and plan.terrain_operation_count==1,"joint queue preserves residential composite receipt and grading")
	var staged:Dictionary=editor._joint_candidate._candidate.after
	check(staged.map_meta.building_instances[id].parts==original.map_meta.building_instances[id].parts,"existing house retains exact component identities in generic candidate")
	var bytes:=FileAccess.get_file_as_bytes(dependency);FileAccess.open(dependency,FileAccess.WRITE).store_buffer(bytes+PackedByteArray([0]))
	await reject("apply_joint_candidate",{"plan_token":plan.plan_token},"source_changed")
	FileAccess.open(dependency,FileAccess.WRITE).store_buffer(bytes)
	for flag:String in ["editor_locked","editor_hidden"]:
		editor._doc._find(source.plan.house_ids[0])[flag]=true
		var denied:=await reject("preview_joint_candidate",request,"protected_scope")
		check(denied.get("step_id")=="homes","protected member reports composite step")
		restore(original)
	plan=await call_tool("preview_joint_candidate",request)
	if not plan.ok:manifest.last_failure=plan;await finish();return
	var count:int=editor._doc._undo.size();var applied:=await call_tool("apply_joint_candidate",{"plan_token":plan.plan_token})
	check(applied.ok and editor._doc._undo.size()==count+1,"grading, migration, new house and paving publish one transaction")
	var after:Dictionary=editor._doc.recovery_snapshot()
	for record:Dictionary in original.records:
		if record.has("building") or record.has("road_source") or record.uuid in plan.changes.terrain_ids:continue
		check(Placement._same(record,editor._doc._find(record.uuid)),"unrelated author record remains exact: "+record.uuid)
	# The second operation must not invalidate an existing guaranteed entrance.
	var home:Dictionary=plan.steps[0].result.homes[0];var value:Dictionary=editor._buildings.instances()[home.building_id]
	var members:Array=editor._doc.records.filter(func(r):return r.uuid in home.house_ids)
	var entry:=Placement.Access.entrance(members,value.yaw)
	var receipt:Dictionary=value.residential_access
	var road_token:String=City.token(City.resolve(editor._doc.map_meta).roads)
	var denied:=await reject("preview_joint_candidate",{"steps":[{"id":"late_road_removal","update_road_graph":{"expected_token":road_token,"remove_edges":[receipt.edge.id]}}]})
	check(denied.get("stage")=="joint_final","final proof protects saved residential connection from a later tool")

	await call_tool("undo");check(Placement._same(original.records,editor._doc.records) and Placement._same(original.map_meta,editor._doc.map_meta),"one undo restores all residential and terrain content")
	await call_tool("redo");check(Placement._same(after,editor._doc.recovery_snapshot()),"one redo restores generic final candidate exactly")
	await settle()
	for house:Dictionary in plan.steps[0].result.homes:
		check(house.house_ids.any(func(uuid):return not editor._bodies_by_uuid.get(uuid,[]).is_empty()),"joint house keeps native independent picking and physics")
	await call_tool("save_world")
	while editor.saving():await process_frame
	var reopened=Doc.open_file(map_path);check(reopened!=null and equivalent(reopened.records,editor._doc.records) and equivalent(reopened.map_meta,editor._doc.map_meta),"generic mixed residential candidate saves and reopens native records")
	manifest.joint_plan=plan;manifest.plan=plan.steps[0].result;manifest.source_graph=source.source_graph;manifest.fixture=map_path
	await finish()
