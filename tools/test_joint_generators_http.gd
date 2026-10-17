extends "res://tools/test_joint_candidate_http.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")

func run()->void:
	output="D:/code/rmmo_runtime/review_artifacts/joint_candidate_20261017/generators.json"
	rpc_timeout_ms=120000;Engine.max_fps=60
	create_timer(700).timeout.connect(func():check(false,"timeout");finish())
	directory=Paths.external_root().path_join("__joint_generators_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":directory.get_file(),"name":"Temporary joint generator regression"}))
	map_path=directory.path_join("maps/test/map.gltf")
	var doc:=Doc.new();var river_ground:=doc.add_box("ground",Vector3(-50,-.25,0),Vector3(80,.5,80))
	doc.add_box("ground",Vector3(0,-.25,70),Vector3(70,.5,50));doc.add_box("grass",Vector3(65,-.25,65),Vector3(40,.5,40))
	var model:=Node3D.new();var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.position.y=.5;model.add_child(mesh)
	var gltf:=GLTFDocument.new();var state:=GLTFState.new();var path:=directory.path_join("test_only.glb")
	check(gltf.append_from_scene(model,state)==OK and gltf.write_to_filesystem(state,path)==OK,"temporary logical scatter fixture exported");model.free()
	var library:=Library.new(directory.path_join("assets"));var imported:=library.import_file(path);check(imported.ok,"temporary asset imported natively")
	check(doc.save(map_path)==OK,"independent generator fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job.active:await process_frame
	editor._safety.enabled=false;editor._shared_assets=[library]
	var probe:=TCPServer.new();port=32500
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"private generator HTTP starts")
	var created:=await call_tool("create_terrain",{"center":[60,0,0],"width":32.,"depth":32.,"cell_size":1.})
	if not created.ok:await finish();return
	var terrain:String=created.id
	var high:=await call_tool("create_terrain",{"center":[110,8.175,0],"width":20.,"depth":20.,"cell_size":1.})
	if not high.ok:await finish();return
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var request:={"steps":[
		{"id":"grade","apply_terrain_layout":{"strokes":[{"id":terrain,"mode":"flatten","shape":"rectangle","points":[[60.,0.]],"plot_width":8.,"plot_depth":8.,"target_height":.15,"strength":1.,"blend_margin":2.}]}},
		{"id":"ramp","apply_terrain_ramp":{"id":terrain,"start":[56.,.15,-3.],"end":[64.,.15,-3.],"width":2.,"blend_margin":1.}},
		{"id":"river","generate_waterway":{"id":"river","ground_ids":[river_ground],"points":[[-50,-25],[-50,25]],"bridges":[{"id":"crossing","segment":0,"t":.5,"width":5.,"approach":3.,"rail_height":1.1,"prefab_id":"legacy_flat"}]}},
		{"id":"connect","connect_waterway_bridge":{"waterway_id":"river","bridge_id":"crossing"}},
		{"id":"arch","generate_bridge":{"id":"arch","prefab_id":"stone_segmental","start":[106,8.2,0],"end":[114,8.2,0],"width":6.2,"depth":1.5,"camber":0.,"arches":1,"wing_length":0.,"auto_clearance":false,"clearance_mode":"stream"}},
		{"id":"wall","generate_fortification":{"id":"wall","points":[[-20,70],[20,70]],"closed":false,"corner_towers":false,"wall_access":false,"style":"plain"}},
		{"id":"grove","generate_vegetation_scatter":{"id":"grove","polygon":[[50,50],[80,50],[80,80],[50,80]],"asset_ids":[imported.entry.asset_path],"count":4,"seed":5}}
	]};evidence.request=request
	var conflict:Array=request.steps.slice(0,2).duplicate(true)
	var later:Dictionary=request.steps[0].duplicate(true);later.id="later_grade";later.apply_terrain_layout.strokes[0].target_height=.6;conflict.append(later)
	var rejected:=await call_tool("preview_joint_candidate",{"steps":conflict},false)
	check(rejected.get("stage")=="joint_final" and equivalent(before,editor._doc.recovery_snapshot()),"later grading cannot invalidate earlier endpoint-height ramp")
	var plan:=await call_tool("preview_joint_candidate",request)
	if not plan.ok:evidence.last_failure=plan;await finish();return
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"seven native generators remain private during preview")
	check(plan.step_count==7 and plan.terrain_operation_count==2 and plan.steps.back().result.count==4,"terrain, ramps, river, both bridge types, walls and scatter share one candidate")
	var bytes:=FileAccess.get_file_as_bytes(imported.entry.asset_path)
	FileAccess.open(imported.entry.asset_path,FileAccess.WRITE).store_buffer(bytes+PackedByteArray([0]))
	await atomic_reject("apply_joint_candidate",{"plan_token":plan.plan_token})
	FileAccess.open(imported.entry.asset_path,FileAccess.WRITE).store_buffer(bytes)
	editor._doc._find(river_ground).editor_locked=true
	await atomic_reject("preview_joint_candidate",request);editor._doc._find(river_ground).erase("editor_locked")
	plan=await call_tool("preview_joint_candidate",request)
	if not plan.ok:evidence.last_failure=plan;await finish();return
	var applied:=await call_tool("apply_joint_candidate",{"plan_token":plan.plan_token})
	if not applied.ok:evidence.last_failure=applied;await finish();return
	check(editor._doc._undo.size()==history+1,"all seven generators commit once")
	var after:Dictionary=editor._doc.recovery_snapshot()
	var zone:={"id":"late_no_plants","purpose":"no_vegetation","polygon":[[50,50],[80,50],[80,80],[50,80]],"min_y":-1.,"max_y":10.}
	rejected=await call_tool("preview_joint_candidate",{"steps":[{"id":"late_zone","update_planning_zones":zone_request({"zones":[zone]})}]},false)
	check(rejected.get("stage")=="joint_final" and equivalent(after,editor._doc.recovery_snapshot()),"later no-vegetation zone cannot strand an earlier scatter result")
	check(City.resolve(editor._doc.map_meta).waterways.size()==1 and City.resolve(editor._doc.map_meta).fortifications.size()==1,"native ownership manifests preserved")
	await call_tool("undo");check(equivalent(before.records,editor._doc.records) and equivalent(before.map_meta,editor._doc.map_meta),"one undo restores every generator")
	await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"one redo restores stable generated identities")
	await call_tool("save_world")
	while editor.saving():await process_frame
	var reopened=Doc.open_file(map_path);check(reopened!=null and equivalent(reopened.records,editor._doc.records) and equivalent(reopened.map_meta,editor._doc.map_meta),"multi-generator native save round trip")
	evidence.plan=plan
	await finish()
