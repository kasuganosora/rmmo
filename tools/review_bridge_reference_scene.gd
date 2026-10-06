extends "res://tools/test_medieval_town_houses.gd"
const Author=preload("res://tools/arrange_bridge_reference_scene.gd")
func run()->void:
	create_timer(1100).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1440,900)
	output_directory=Author.SCENE_OUT
	var authored:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output_directory+"/result.json"))
	check(authored.failures==0,"authored candidate checks passed")
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession")
	session.world3d_map_path=Author.SCENE_MAP;session.world3d_spawn=Vector3(310,.9,164)
	var began:=Time.get_ticks_msec()
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(Author.SCENE_MAP)
	var loaded:Array=await loader.finished
	check(loaded[0]!=null,"native asynchronous loader")
	if loaded[0]==null:quit(1);return
	session.prepared_world3d=loaded[0];session.world3d_loading=true
	world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	var entry_ms:=Time.get_ticks_msec()-began
	check(world._navigation.ready_for_queries and not world._player.input_locked,"runtime movement ready")
	for child in world.get_children():
		if child is CanvasLayer:child.hide()
	var extras:Dictionary=Recipe.Doc.authoritative_extras(Author.SCENE_MAP).extras
	var bridge:Dictionary=extras.rmmo_records.filter(func(r):return r.uuid==authored.bridge_id)[0]
	var pose:=Transform3D(Basis(Vector3.UP,deg_to_rad(bridge.rotation[1])),B.vec(bridge.position))
	var forward:=pose.basis.x;var right:=pose.basis.z;var center:=pose.origin
	await teleport(center+forward*30)
	world._request_environment({"time_hours":12.,"time_speed":0.})
	world._player.hide();world._camera.camera.fov=60
	await capture("bridge_day",center+forward*4+right*12+Vector3.UP*5.2,center+forward*53+Vector3.UP*4)
	await capture("street_day",Vector3(307,3.2,160),Vector3(340,3,211))
	await capture("district",Vector3(265,96,235),Vector3(326,0,184))
	if "--images-only" in OS.get_cmdline_user_args():world.free();quit();return
	# Real collision sweep along three bridge lanes and both bridgeheads.
	var body:=CharacterBody3D.new();var cs:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.height=2.1;capsule.radius=.3;cs.shape=capsule;body.add_child(cs);world.add_child(body);body.floor_snap_length=.3
	var bridge_runs:Array=[]
	for lane in [-2.,0.,2.]:
		for direction in [-1,1]:
			var start:=pose*Vector3(-31*direction,1.08,lane);body.position=start;body.velocity=Vector3.ZERO
			Stream.sync(world._map_root,world,start)
			for i in 4:await physics_frame
			for frame in 520:
				await physics_frame;body.velocity=forward*10*direction+Vector3.DOWN*2;body.move_and_slide()
				if (pose.affine_inverse()*body.position).x*direction>31:break
			var passed:bool=(pose.affine_inverse()*body.position).x*direction>31
			check(passed,"bridge and bridgehead lane="+str(lane)+" direction="+str(direction));bridge_runs.append({"lane":lane,"direction":direction,"passed":passed})
	body.free()
	# Route the existing player through the street and all doors; no NPC population.
	var route:Array=[Vector3(310.8,.025,163.8),Vector3(323,.025,178),Vector3(337,.025,195),Vector3(347.2,.025,211.4),Vector3(357,.025,235),Vector3(361,.025,249)]
	await teleport(route[0])
	for i in range(1,route.size()):
		var steps:=ceili(route[i-1].distance_to(route[i])/7.)
		for j in range(1,steps+1):await walk(route[i-1].lerp(route[i],float(j)/steps),"continuous street route "+str(i)+"/"+str(j))
	for h:Dictionary in authored.houses:
		var instance:Dictionary=extras.building_instances[h.id];var plan:Dictionary=B.generate(instance.parameters)
		var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw));var at:=B.vec(h.position)
		var outside:=at+basis*B.vec(plan.entrance);var inside:=outside+basis*Vector3(0,0,2.2);inside.y=at.y+instance.parameters.base_height
		await teleport(outside)
		check(Fixtures.set_runtime(world._map_root,h.id,"f0/north/entrance/door",1,0).ok,"independent entrance "+h.id)
		for i in 3:await physics_frame
		await walk(inside,"enter decorated house "+h.id)
		await walk(outside,"exit decorated house "+h.id)
		Fixtures.set_runtime(world._map_root,h.id,"f0/north/entrance/door",0,0)
		check(not Fixtures.list_runtime(world._map_root,h.id).filter(func(x):return x.kind=="window").is_empty(),"independent windows")
	await teleport(center+forward*40);world._player.hide()
	world._request_environment({"time_hours":12.,"time_speed":0.});world._weather.streetlamps.refresh()
	check(world._weather.streetlamps.fixtures.values().all(func(r):return not r.lit),"daytime lanterns off")
	# Fixed settled view, separate from screenshot readback. Not a whole-city benchmark.
	world.set_process(false);world._camera.set_process(false);world._hud.hide()
	var camera:Camera3D=world._camera.camera;camera.global_position=center+forward*4+right*12+Vector3.UP*5.2;camera.look_at(center+forward*53+Vector3.UP*4)
	for i in 60:await process_frame
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var samples:Array=[];var gpu:Array=[];var previous:=Time.get_ticks_usec()
	for i in 180:
		await process_frame;var now:=Time.get_ticks_usec();samples.append((now-previous)/1000.);previous=now;gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	samples.sort();gpu.sort();Engine.max_fps=60
	var perf:={"frame_median_ms":samples[90],"frame_p95_ms":samples[171],"gpu_median_ms":gpu[90],"visible_draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"resolution":[1440,900],"scope":"settled bridge view, no streaming benchmark"}
	world.set_process(true);world._camera.set_process(true)
	world._request_environment({"time_hours":22.,"time_speed":0.});world._weather.streetlamps.refresh()
	var warm_lit:=0
	for fixture:Dictionary in world._weather.streetlamps.fixtures.values():
		if fixture.get("warm",false) and fixture.lit and fixture.light.visible:warm_lit+=1
	check(warm_lit>=9,"all nine nearby warm lanterns illuminate")
	await capture("bridge_night",center+forward*4+right*12+Vector3.UP*5.2,center+forward*53+Vector3.UP*4)
	FileAccess.open(output_directory+"/runtime_result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"entry_ms":entry_ms,"candidate_sha256":FileAccess.get_sha256(Author.SCENE_MAP),"houses":authored.houses.size(),"bridge_runs":bridge_runs,"warm_lanterns":warm_lit,"performance":perf},"\t"))
	print("BRIDGE_SCENE_RUNTIME failures=",failures);world.free();quit(1 if failures else 0)
