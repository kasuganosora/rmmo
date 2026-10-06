extends SceneTree
const Recipe=preload("res://tools/place_medieval_town_houses.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
var failures:=0
var world:Node
var output_directory:String=Recipe.OUT
var only_house:=""
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func teleport(point:Vector3)->void:
	var authority=preload("res://scripts/net/net.gd").server().world3d_authority
	authority.release();world._player.position=point+Vector3.UP*.9;world._player.velocity=Vector3.ZERO;world._player.click_target=null;world._player._route.clear()
	Stream.sync(world._map_root,world,point);authority.mount(world._player,world._navigation,world._map_ref())
	for i in 12:await physics_frame
func walk(target:Vector3,label_:String)->void:
	world._player.set_click_target(target,"ground")
	var accepted:bool=world._player.click_target is Vector3
	var began:=Time.get_ticks_msec()
	while accepted and Time.get_ticks_msec()-began<8000:
		await physics_frame
		if Vector2(world._player.position.x-target.x,world._player.position.z-target.z).length()<.4:break
	var distance:float=Vector2(world._player.position.x-target.x,world._player.position.z-target.z).length()
	check(accepted and distance<.5,label_+" distance="+str(snappedf(distance,.01)))
	if not accepted or distance>=.5:
		var foot:Vector3=world._player.position-Vector3.UP*.9
		print("WALK_DIAGNOSTIC ",JSON.stringify({"accepted":accepted,"position":B.arr(world._player.position),"target":B.arr(target),"nearest":B.arr(NavigationServer3D.map_get_closest_point(world._navigation.map,target)),"start_nearest":B.arr(NavigationServer3D.map_get_closest_point(world._navigation.map,foot)),"reason":world._navigation.find_path(foot,target,.65).get("reason","")}))
	world._player.click_target=null;world._player._route.clear()
func capture(label_:String,eye:Vector3,target:Vector3)->void:
	var camera_processing:bool=world._camera.is_processing()
	world.set_process(false);world._camera.set_process(false);world._hud.hide()
	var cam:Camera3D=world._camera.camera;var previous_transform:=cam.transform
	cam.global_position=eye;cam.look_at(target)
	for i in 25:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_directory.path_join(label_+".png"))
	cam.transform=previous_transform
	world._hud.show();world.set_process(true);world._camera.set_process(camera_processing)
func frames()->Dictionary:
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	await teleport(Vector3(-260,0,-40));world._camera.yaw=PI*.5
	for i in 80:await process_frame
	var samples:Array=[];var gpu:Array=[];var previous:=Time.get_ticks_usec()
	for i in 240:
		world._camera.yaw+=.003
		await process_frame
		var now:=Time.get_ticks_usec();samples.append((now-previous)/1000.);previous=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	samples.sort();gpu.sort();Engine.max_fps=60
	return {"frame_median_ms":samples[120],"frame_p95_ms":samples[228],"gpu_median_ms":gpu[120],"draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
func run()->void:
	create_timer(1200).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1280,800)
	var baseline:bool="--baseline" in OS.get_cmdline_user_args();var fast:bool="--entry-only" in OS.get_cmdline_user_args()
	var path:String=Recipe.SOURCE if baseline else Recipe.CANDIDATE
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):path=arg.trim_prefix("--map=")
		if arg.begins_with("--out="):output_directory=arg.trim_prefix("--out=")
		if arg.begins_with("--only-house="):only_house=arg.trim_prefix("--only-house=")
	DirAccess.make_dir_recursive_absolute(output_directory)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"};session.world3d_requested=true;session.loading_mode="world3d_preview";session.world3d_map_path=path
	var began:=Time.get_ticks_msec();check(change_scene_to_file("res://scenes/loading.tscn")==OK,"start real LoadingScene")
	while true:
		await process_frame;world=current_scene
		if world!=null and world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active:break
	var elapsed:=Time.get_ticks_msec()-began
	check(not world._player.input_locked and world._navigation.ready_for_queries,"world ready and player input unlocked")
	var report:={"entry_ms":elapsed,"map_profile":world._map_root.get_meta("load_profile",{}),"navigation":world._navigation.loading_profile,"loading":session.last_loading_profile,"candidate_sha256":FileAccess.get_sha256(path)}
	print("TOWN_ENTRY ",JSON.stringify(report))
	if not baseline and not fast:
		await teleport(Vector3(-260,0,-40))
		await capture("district",Vector3(-265,95,68),Vector3(-265,0,-45))
		await capture("street",Vector3(-320,3,-52),Vector3(-230,5,-28))
	var progress_at:=Time.get_ticks_msec()
	while not world._navigation.fully_ready:
		await process_frame
		if Time.get_ticks_msec()-progress_at>30000:
			progress_at=Time.get_ticks_msec();print("NAVIGATION_PROGRESS ",world._navigation.loading_profile)
	check(world._navigation.mesh.get_polygon_count()>0,"full town navigation contains polygons")
	report.full_navigation_ms=Time.get_ticks_msec()-began
	report.performance=await frames();print("TOWN_PERFORMANCE ",JSON.stringify(report.performance))
	if not baseline and not fast:
		var extras:Dictionary=Recipe.Doc.authoritative_extras(path).extras
		var authored:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output_directory.path_join("result.json")))
		var plans:Dictionary={};var tested:Dictionary={};var window_tested:Dictionary={}
		for row:Dictionary in authored.houses:
			if not only_house.is_empty() and row.id!=only_house:continue
			var instance:Dictionary=extras.building_instances[row.id]
			if not plans.has(row.source):plans[row.source]=B.generate(instance.parameters)
			var plan:Dictionary=plans[row.source];var basis:=Basis(Vector3.UP,deg_to_rad(row.yaw));var origin:=B.vec(row.position)
			var outside:Vector3=origin+basis*B.vec(plan.entrance);var inside:Vector3=outside+basis*Vector3(0,0,2.2)
			inside.y=origin.y+float(instance.parameters.base_height)
			await teleport(outside)
			var window_style:String=instance.parameters.get("window_style","casement")
			if not window_tested.has(window_style):
				window_tested[window_style]=true
				var windows:Array=Fixtures.list_runtime(world._map_root,row.id).filter(func(f):return f.kind=="window")
				check(not windows.is_empty(),"frozen casement identity "+window_style)
				if not windows.is_empty():
					check(Fixtures.set_runtime(world._map_root,row.id,windows[0].id,1,0).ok,"open frozen casement "+window_style)
					await physics_frame
					check(Fixtures.set_runtime(world._map_root,row.id,windows[0].id,0,0).ok,"close frozen casement "+window_style)
			check(Fixtures.set_runtime(world._map_root,row.id,"f0/north/entrance/door",1,0).ok,"open entry "+row.id)
			for i in 3:await physics_frame
			await walk(inside,"enter rotated "+row.use)
			var street:Vector3=B.vec(row.road_point);street.y=.025
			await walk(street,"leave doorstep for street")
			if not tested.has(row.source):
				tested[row.source]=true
				for room:Dictionary in plan.rooms:
					var target:Vector3=origin+basis*(B.vec(room.center)+Vector3(1.1,.018,0))
					await teleport(target-basis*Vector3(2.2,0,0));await walk(target,"indoor click floor "+str(room.floor))
			Fixtures.set_runtime(world._map_root,row.id,"f0/north/entrance/door",0,0)
		await teleport(Vector3(-260,0,-40))
		await capture("district",Vector3(-265,95,68),Vector3(-265,0,-45))
		await capture("street",Vector3(-320,3,-52),Vector3(-230,5,-28))
		await capture("overview",Vector3(0,1200,10),Vector3.ZERO)
		check(world._house_candles.lit_count()==0,"daytime candles are off")
		world._request_environment({"time_hours":23.,"time_speed":0,"weather_transition":0})
		for i in 60:await process_frame
		report.night_performance=await frames()
		check(world._house_candles.lit_count()<=2,"night lights respect nearby light budget")
		report.houses=authored.houses.size()
	report.failures=failures
	var filename:="baseline.json" if baseline else ("entry_cached.json" if fast else "runtime_result.json")
	if not only_house.is_empty():filename="focused_runtime.json";report.only_house=only_house
	var file:=FileAccess.open(output_directory.path_join(filename),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("TOWN_HOUSES_RUNTIME failures=",failures);quit(1 if failures else 0)
