extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Landscape=preload("res://scripts/world3d/stream_landscape.gd")
var OUT="D:/code/rmmo_runtime/review_artifacts/town_entry_movement_20261005"
var world:Node
var failures:=0
var report:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func key(code:Key,pressed:bool)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed;Input.parse_input_event(event)
func photo(label_:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(label_+".png"))
func support_check()->bool:
	var meshes:Dictionary=world._map_root.get_meta("stream_meshes")
	for spec:Dictionary in world._map_root.get_meta("stream_library"):
		if not meshes.has(spec.uuid) or not spec.has("render_building"):continue
		for ground:Dictionary in spec.get("render_supports",[]):
			if not meshes.has(ground.uuid):return false
	return true
func run()->void:
	var entry_only:bool="--entry-only" in OS.get_cmdline_user_args()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):OUT=arg.trim_prefix("--out=")
	create_timer(300).timeout.connect(func():push_error("TOWN_ENTRY_MOVEMENT timeout");quit(2))
	Engine.max_fps=60;root.size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(OUT)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_requested=true;session.loading_mode="world3d_preview"
	session.world3d_map_path="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var began:=Time.get_ticks_msec()
	change_scene_to_file("res://scenes/loading.tscn")
	while true:
		await process_frame;world=current_scene
		if world!=null and world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active:break
	report.entry_ms=Time.get_ticks_msec()-began
	report.map_profile=world._map_root.get_meta("load_profile",{})
	report.world_profile=world.loading_profile
	report.loading=session.last_loading_profile
	report.stream_profile=world._map_root.get_meta("stream_load_profile_us",{})
	var initial_batches:Node=world._map_root.get_node_or_null("GroundRenderBatches")
	if initial_batches!=null:report.initial_batches=initial_batches.stats()
	if entry_only:
		report.navigation=world._navigation.loading_profile
		FileAccess.open(OUT.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("TOWN_ENTRY_ONLY ",JSON.stringify(report));world._leave()
		for i in 120:await process_frame
		quit();return
	check(not world._navigation.fully_ready,"exercise cold local navigation before full town is ready")
	check(absf(world._player.position.x+35)<1,"normal map spawn, no teleport")
	world._camera.yaw=PI*.5
	print("ENTRY_MOVEMENT_START ",world._player.position," ",world._navigation.loading_profile)
	await photo("spawn_ground")
	key(KEY_W,true);key(KEY_SHIFT,true)
	var started:=Time.get_ticks_msec();var previous:Vector3=world._player.position
	var stuck:=0;var max_stuck:=0;var supported:=true
	while Time.get_ticks_msec()-started<65000 and world._player.position.x>-155:
		await physics_frame
		var now:Vector3=world._player.position
		stuck=stuck+1 if now.distance_to(previous)<.005 else 0
		max_stuck=maxi(stuck,max_stuck);previous=now
		supported=supported and support_check()
	key(KEY_W,false);key(KEY_SHIFT,false)
	report.keyboard_position=world._player.position;report.max_stuck_ticks=max_stuck
	check(world._player.position.x<-154,"keyboard crosses reported x=-114.9 boundary and reaches shop street")
	check(max_stuck<30,"no half-second invisible wall during continuous movement: "+str(max_stuck))
	check(supported,"every visible house retains all supporting land while crossing cells")
	await photo("keyboard_street")
	# Send a real screen-space click through picking and the runtime input handler.
	var point:Vector3=world._player.position+Vector3(-14,-.9,0)
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*15,point-Vector3.UP*15)
	var hit:Dictionary=world._player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():point=hit.position
	var screen:Vector2=world._camera.camera.unproject_position(point)
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(screen),"mouse destination is visible on screen")
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.position=screen;click.global_position=screen;click.pressed=true
	Input.parse_input_event(click);await process_frame
	click=click.duplicate();click.pressed=false;Input.parse_input_event(click)
	started=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<12000:
		await physics_frame
		if Vector2(world._player.position.x-point.x,world._player.position.z-point.z).length()<.5:break
	var distance:=Vector2(world._player.position.x-point.x,world._player.position.z-point.z).length()
	check(distance<.5,"real mouse click advances along street, remaining="+str(distance))
	report.mouse_remaining=distance;report.mouse_position=world._player.position
	await photo("mouse_street")
	# Measure the expanded terrain residency in the actual forward street view.
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for i in 30:await process_frame
	var times:Array=[];var gpu:Array=[];var last:=Time.get_ticks_usec()
	for i in 180:
		await process_frame
		var now:=Time.get_ticks_usec();times.append((now-last)/1000.0);last=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	times.sort();gpu.sort()
	report.performance={"frame_median_ms":times[90],"frame_p95_ms":times[171],"gpu_median_ms":gpu[90],"draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	Engine.max_fps=60
	# Return along exactly the same route; catches loss of the previous bubble.
	key(KEY_S,true);key(KEY_SHIFT,true);started=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<45000 and world._player.position.x<-40:await physics_frame
	key(KEY_S,false);key(KEY_SHIFT,false)
	check(world._player.position.x>-41,"continuous keyboard return to spawn street")
	report.navigation=world._navigation.loading_profile;report.final_position=world._player.position
	report.failures=failures
	FileAccess.open(OUT.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TOWN_ENTRY_MOVEMENT ",JSON.stringify(report))
	world._leave()
	for i in 120:await process_frame
	check(current_scene!=world,"leave town safely while background navigation is still baking")
	print("TOWN_ENTRY_MOVEMENT_EXIT failures=",failures);quit(1 if failures else 0)
