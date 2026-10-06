extends SceneTree
## Actual world/HUD/mocker path on a temporary white-box floor, not a content-map claim.
const Art=preload("res://scripts/asset/art_paths.gd")
const Solver=preload("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd")
const BUDGET_MS:=1000.0/60.0
var world:Node3D
var surface_updates:=0
var output_folder:="character_3d/runtime_performance_06"
var profile:=false
var sample_frames:=120
var actor_count:=1
var companions:Array[Node3D]=[]
func on_surface()->void:surface_updates+=1
func _initialize()->void:call_deferred("run")
func sample(moving:=false)->Dictionary:
	var traveled:=0.0;var retargets:=0
	var last_position:Vector3=world._player.global_position
	var times:Array[float]=[]
	var slow:Array=[];var solve_counts:Array[int]=[];var physics_counts:Array[int]=[]
	for i in sample_frames:
		var start:=Time.get_ticks_usec();var solves_before:=surface_updates;var physics_before:=Engine.get_physics_frames()
		if moving and world._player.click_target==null:
			retargets+=1
			world._player.set_click_target(Vector3(-30,0,-30) if world._player.global_position.x>0 else Vector3(30,0,30),"ground")
		await process_frame;await RenderingServer.frame_post_draw
		traveled+=last_position.distance_to(world._player.global_position);last_position=world._player.global_position
		var ms:float=(Time.get_ticks_usec()-start)/1000.0
		times.append(ms);solve_counts.append(surface_updates-solves_before);physics_counts.append(Engine.get_physics_frames()-physics_before)
		if ms>50:
			var adapter=world._player._model.axis_rig.cloth.entries.Clothing2.adapter
			slow.append({"frame":i,"ms":ms,"surface_solves":surface_updates-solves_before,"physics_steps":Engine.get_physics_frames()-physics_before,"body_last_solve_ms":adapter.body.last_solve_ms,"packet_ms":adapter.last_submit_ms,"dispatch_ms":adapter.last_simulate_ms,"action":world._player._model.action,"gpu_stages_ns":adapter.solver.review_gpu_ticks.duplicate() if profile else {}})
	var chronological:=times.duplicate()
	times.sort()
	return {"distance_m":traveled,"route_retargets":retargets,"frames":sample_frames,"median_ms":times[sample_frames/2],"p95_ms":times[ceili(sample_frames*.95)-1],"p99_ms":times[ceili(sample_frames*.99)-1],"max_ms":times[-1],"over_33ms":times.filter(func(v):return v>33.333).size(),"over_50ms":slow.size(),"frame_times_ms":chronological,"meets_60fps":times[ceili(sample_frames*.95)-1]<=BUDGET_MS,"slow_frames":slow,"surface_solves":solve_counts,"physics_steps":physics_counts}
func run()->void:
	if preload("res://tools/gpu_shader_review_manifest.gd").collect().is_empty():quit(2);return
	var args:=OS.get_cmdline_user_args()
	preload("res://scripts/char/female_axis_body.gd").default_gpu_display="--cpu-display" not in args
	preload("res://scripts/char/garment_candidate_cloth.gd").default_shared_body_points="--shared-body-points" in args
	preload("res://scripts/char/garment_candidate_cloth.gd").default_resident_packet="--readback-packet" not in args
	Solver.default_cooperative_candidates=not "--serial-candidates" in args
	var group_flag:=args.find("--candidate-group-size")
	if group_flag>=0 and group_flag+1<args.size():Solver.default_candidate_group_size=int(args[group_flag+1])
	profile="--profile" in args
	var flag:=args.find("--frames")
	if flag>=0 and flag+1<args.size():sample_frames=maxi(120,int(args[flag+1]))
	flag=args.find("--actors")
	if flag>=0 and flag+1<args.size():actor_count=clampi(int(args[flag+1]),1,16)
	flag=args.find("--stage")
	if flag>=0 and flag+1<args.size():output_folder+="/"+args[flag+1]
	if profile:output_folder+="/profile"
	create_timer(300).timeout.connect(func():push_error("World performance timeout");quit(2))
	DirAccess.make_dir_recursive_absolute(Art.review_path(output_folder))
	var session=root.get_node("GameSession")
	session.selected_character={"id":-402,"name":"Performance probe","gender":"female","customization":{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}}
	session.spawn_data={}
	var folder:String=preload("res://scripts/world3d/map_paths.gd").cache_directory("perf_%d"%Time.get_ticks_usec())
	var doc=preload("res://scripts/world3d/world_document.gd").new()
	doc.add_box("floor",Vector3(0,-.1,0),Vector3(80,.2,80))
	var path:String=folder.path_join("map.gltf")
	if doc.save(path)!=OK:push_error("Cannot save benchmark floor");quit(2);return
	session.world3d_map_path=path;session.world3d_spawn=Vector3(0,.9,0)
	world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	var player=world._player
	player._model.set_equipment({"SurfaceEquipment":{"Clothing2":"maid_separate/item_01"},"SurfaceClothSlots":["Clothing2"]})
	for index in range(1,actor_count):
		var companion=preload("res://scripts/char/character_model_3d.gd").new()
		companion.auto_configure=false;player.add_child(companion)
		companion.position=player._model.position+Vector3(float(index%3-1)*1.5,0,-1.5*ceilf(float(index)/3))
		companion.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}},{"SurfaceEquipment":{"Clothing2":"maid_separate/item_01"},"SurfaceClothSlots":["Clothing2"]})
		companions.append(companion)
	player._model.axis_rig.body.surface_updated.connect(on_surface)
	var cloth=player._model.axis_rig.cloth
	while not cloth.is_ready():
		if not cloth.error.is_empty():push_error(cloth.error);quit(2);return
		await process_frame
	for companion in companions:
		while not companion.axis_rig.cloth.is_ready():
			if not companion.axis_rig.cloth.error.is_empty():push_error(companion.axis_rig.cloth.error);quit(2);return
			await process_frame
	var solver=cloth.entries.Clothing2.adapter.solver
	solver.review_gpu_timing=profile
	for i in 60:await process_frame
	var result:Dictionary={"gpu":RenderingServer.get_video_adapter_name(),"frame_budget_ms":BUDGET_MS,"viewport":str(root.size),"actors":actor_count,"scope":"actual world_3d/HUD/mocker player + synthetic companions sharing world/viewport; native female + hair202 + maid skirt each, 24 iterations/4 substeps; temporary floor, no NPC AI/network crowd"}
	result.idle=await sample();print("World idle ",result.idle)
	result["candidate_group_size"]=solver.candidate_group_size
	result["substep_tree_refit"]=solver.substep_tree_refit
	result["cooperative_candidates"]=solver.cooperative_candidates
	result["gpu_display"]=preload("res://scripts/char/female_axis_body.gd").default_gpu_display
	result["shared_body_points"]=preload("res://scripts/char/garment_candidate_cloth.gd").default_shared_body_points
	result["resident_packet"]=cloth.entries.Clothing2.adapter.indexed_packet.has_method("is_gpu_resident")
	var before:Vector3=player.global_position
	player.set_click_target(Vector3(30,0,30),"ground")
	for companion in companions:companion.play("walk","front",true)
	result.moving=await sample(true)
	result.movement_m=result.moving.distance_m
	if result.resident_packet:
		result["player_body_point_upload_bytes"]=cloth.entries.Clothing2.adapter.indexed_packet.point_upload_bytes
		result["player_body_point_gpu_read_bytes"]=cloth.entries.Clothing2.adapter.indexed_packet.shared_point_read_bytes
	result.net_displacement_m=before.distance_to(player.global_position)
	result.functional_pass=result.movement_m>.25 and cloth.error.is_empty() and cloth.is_ready()
	for companion in companions:result.functional_pass=result.functional_pass and companion.axis_rig.cloth.error.is_empty() and companion.axis_rig.cloth.is_ready()
	result.performance_pass=result.idle.meets_60fps and result.moving.meets_60fps
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(Art.review_path(output_folder+"/world_moving.png"))
	world.free()
	for i in 5:await process_frame
	var file:=FileAccess.open(Art.review_path(output_folder+"/world.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("WORLD PERFORMANCE ","PASS " if result.performance_pass else "FAIL ",JSON.stringify(result))
	quit(0 if result.functional_pass and result.performance_pass else 5)
