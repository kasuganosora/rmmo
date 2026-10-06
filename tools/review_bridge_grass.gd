extends "res://tools/test_medieval_town_houses.gd"
const Author=preload("res://tools/arrange_bridge_grass.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var grass_nodes:Array=[]
func performance_sample()->Dictionary:
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for i in 45:await process_frame
	var frames_:Array=[];var gpu:Array=[];var previous:=Time.get_ticks_usec()
	for i in 120:
		await process_frame
		var now:=Time.get_ticks_usec();frames_.append((now-previous)/1000.);previous=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	frames_.sort();gpu.sort();Engine.max_fps=60
	return {"frame_median_ms":frames_[60],"frame_p95_ms":frames_[114],"gpu_median_ms":gpu[60],"draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}
func run()->void:
	create_timer(900).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1440,900)
	output_directory=Author.GRASS_OUT
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output_directory+"/result.json"))
	var baseline:bool="--baseline" in OS.get_cmdline_user_args()
	var path:String=Author.FORMAL if baseline or "--formal" in OS.get_cmdline_user_args() else Author.GRASS_MAP
	if baseline:output_directory+="/baseline";DirAccess.make_dir_recursive_absolute(output_directory);report.placements=[]
	if "--formal" in OS.get_cmdline_user_args():output_directory+="/formal";DirAccess.make_dir_recursive_absolute(output_directory)
	check(report.failures==0,"authored grass candidate")
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession");session.world3d_map_path=path;session.world3d_spawn=Vector3(310,.9,164)
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(path)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"full native grass map load")
	if loaded[0]==null:quit(1);return
	session.prepared_world3d=loaded[0];session.world3d_loading=true;world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	for child in world.get_children():
		if child is CanvasLayer:child.hide()
	var extras:Dictionary=Author.Doc.authoritative_extras(path).extras
	var bridge:Dictionary=extras.rmmo_records.filter(func(r):return r.uuid=="stone_e_0be972769041dbc9")[0]
	var center:=B.vec(bridge.position);var basis:=Basis(Vector3.UP,deg_to_rad(bridge.rotation[1]));var pose:=Transform3D(basis,center)
	await teleport(pose*Vector3(34,0,0));world._player.hide();world._request_environment({"time_hours":12.,"time_speed":0.})
	await capture("bridge_day",pose*Vector3(0,6,19),pose*Vector3(34,0,0))
	await capture("grass_east_close",pose*Vector3(32,1.65,14),pose*Vector3(23,.25,7))
	await capture("grass_reference_close",pose*Vector3(17.5,1.4,19),pose*Vector3(29,.2,5))
	for i in 60:await physics_frame
	await capture("grass_east_wind",pose*Vector3(32,1.65,14),pose*Vector3(23,.25,7))
	await capture("grass_bank_long",pose*Vector3(28,1.55,31),pose*Vector3(26,.2,7))
	await capture("grass_overview",pose*Vector3(28,25,18),pose*Vector3(27,0,17))
	var grass:Array=extras.rmmo_records.filter(func(r):return str(r.uuid).begins_with("bridge_grass_"))
	check(grass.size()==report.placements.size() and grass.all(func(r):return r.collision=="none"),"all placed grass preserved without collision")
	var grass_specs:Array=world._map_root.get_meta("stream_library",[]).filter(func(s):return s.get("extras",{}).get("rmmo_grass",false))
	check(grass_specs.size()==grass.size()*3,"three native LODs per placed grass clump")
	check(grass_specs.all(func(s):return s.extras.get("rmmo_collision","")=="none"),"grass excluded from collision and navigation sources")
	var support_failures:Array=[]
	for end in [1,-1]:
		await teleport(pose*Vector3(31*end,0,0))
		for record:Dictionary in grass:
			var at:=B.vec(record.position)
			if (pose.affine_inverse()*at).x*end<0:continue
			var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*.3,at+Vector3.DOWN*.4))
			if hit.is_empty() or absf(hit.position.y-at.y)>.07:support_failures.append(record.uuid)
		if end<0:await capture("grass_west",pose*Vector3(-32,1.8,-14),pose*Vector3(-23,.2,-7))
	check(support_failures.is_empty(),"every grass root seated on actual collision "+str(support_failures.slice(0,8)))
	await teleport(pose*Vector3(34,0,0))
	await walk(pose*Vector3(29,.05,0),"bridgehead walk")
	var nav_deadline:int=Time.get_ticks_msec()+180000
	while not world._navigation.fully_ready and Time.get_ticks_msec()<nav_deadline:
		await process_frame
	for i in 30:await physics_frame
	check(world._navigation.ready_for_queries,"navigation remains queryable")
	var meshes:Dictionary=world._map_root.get_meta("stream_meshes",{})
	for mesh in meshes.values():
		if is_instance_valid(mesh) and mesh.get_meta("extras",{}).get("rmmo_grass",false):grass_nodes.append(mesh)
	if not baseline:
		check(grass_nodes.size()>0,"grass LOD meshes in native stream")
		check(grass_nodes.any(func(m):return m.has_meta("wind_original")),"grass bound to native wind")
	world.set_process(false);world._camera.set_process(false)
	var cam:Camera3D=world._camera.camera;cam.global_position=pose*Vector3(17.5,1.4,19);cam.look_at(pose*Vector3(29,.2,5))
	var visible_stats:Dictionary=await performance_sample()
	var visibility:Array=[]
	for mesh in grass_nodes:visibility.append(mesh.visible);mesh.hide()
	var hidden_stats:Dictionary=await performance_sample()
	for i in grass_nodes.size():grass_nodes[i].visible=visibility[i]
	world.set_process(true)
	world._request_environment({"time_hours":23.,"time_speed":0.})
	await capture("grass_night",pose*Vector3(17.5,1.4,19),pose*Vector3(29,.2,5))
	var file:=FileAccess.open(output_directory+"/runtime_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"candidate_sha256":FileAccess.get_sha256(path),"grass_count":grass.size(),"stream_grass_lod_meshes":grass_nodes.size(),"support_failures":support_failures,"navigation_fully_ready":world._navigation.fully_ready,"with_grass":visible_stats,"grass_hidden":hidden_stats},"  "));file.close()
	world.free();print("BRIDGE_GRASS_RUNTIME failures=",failures);quit(failures)
