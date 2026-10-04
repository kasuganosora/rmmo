extends SceneTree
var MAP="D:/code/rmmo_runtime/maps/medieval_house_showcase/map.gltf"
var observations: Array=[]
class LoadingFixture extends Control:
	var progress_history: Array=[]
	func transition_visual() -> Control:
		var screen=load("res://scenes/loading.tscn").instantiate()
		var visual: Control=screen.transition_visual(); screen.free(); return visual
func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	var session=root.get_node_or_null("GameSession")
	if session!=null:
		var cover=session.get_node_or_null("WorldTransition")
		if cover!=null and cover.get_child_count()>0:
			var label=cover.get_child(0).get_node_or_null("Center/VBox/Status")
			if label!=null and (observations.is_empty() or observations.back()!=label.text): observations.append(label.text)
	return false
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):MAP=arg.trim_prefix("--map=")
	if "--cold-cache" in OS.get_cmdline_user_args():
		DirAccess.remove_absolute(preload("res://scripts/world3d/map_metadata_cache.gd").cache_path(MAP))
	if "--cold-runtime-cache" in OS.get_cmdline_user_args():
		var context:Dictionary={}
		preload("res://scripts/world3d/map_metadata_cache.gd").read(MAP,FileAccess.get_sha256(MAP),context)
		for source:Array in context.get("textures",[]):
			DirAccess.remove_absolute(preload("res://scripts/world3d/runtime_texture_cache.gd").cache_path(source[0],source[1]))
		DirAccess.remove_absolute(preload("res://scripts/world3d/map_metadata_cache.gd").cache_path(MAP))
		DirAccess.remove_absolute(preload("res://scripts/world3d/runtime_mesh_cache.gd").cache_path(MAP))
	Engine.max_fps=60; root.size=Vector2i(1280,800)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	create_timer(180).timeout.connect(func():quit(2))
	var started:=Time.get_ticks_msec()
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession"); session.world3d_loading=true; session.world3d_map_path=MAP
	session.prepare_world_resources()
	var loader=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(MAP)
	session.prepare_world_actor()
	var loaded: Array=await loader.finished
	if loaded[0]==null: push_error(loaded[2]); quit(1); return
	if "--cold-runtime-cache" in OS.get_cmdline_user_args():loaded[0].remove_meta("runtime_geometry_key")
	print("ENTRY_MAP_READY ",Time.get_ticks_msec()-started," profile=",loaded[0].get_meta("load_profile",{}))
	session.prepared_world3d=loaded[0]
	var previous:=LoadingFixture.new(); root.add_child(previous); current_scene=previous
	await session.go_world()
	await process_frame # queue_free of the transition cover completes at frame end.
	var world:=current_scene
	var passed: bool=world!=null and world.is_world_ready() and world._player!=null and not world._player.input_locked and session.get_node_or_null("WorldTransition")==null
	passed=passed and not is_instance_valid(session._prepared_world_actor) and not is_instance_valid(session._world_render_warmup)
	print("WORLD_STATE ready=",world.is_world_ready()," player=",world._player!=null," locked=",world._player.input_locked," cover=",session.get_node_or_null("WorldTransition"))
	var stages_ok:=observations.any(func(s):return "附近物件与碰撞" in s) and observations.any(func(s):return "准备通行导航" in s)
	print("HOUSE_WORLD_READY passed=",passed," progress=",stages_ok," elapsed_ms=",Time.get_ticks_msec()-started)
	print("ENTRY_PHASES started=",started," session=",session.last_loading_profile," world=",world.loading_profile)
	print("ENTRY_NAVIGATION ",world._navigation.loading_profile)
	var load_ms:=Time.get_ticks_msec()-started
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/code/rmmo_runtime/review_artifacts/entry_loading/ready.png")
	if "--diagnose" in OS.get_cmdline_user_args():await diagnose(world)
	var out:="D:/code/rmmo_runtime/review_artifacts/house_playground/world_loading.json"
	if "--walk" in OS.get_cmdline_user_args():passed=await measure_stairs(world) and passed
	var file:=FileAccess.open(out,FileAccess.WRITE); file.store_string(JSON.stringify({"ready":passed,"progress":stages_ok,"elapsed_ms":load_ms,"stages":observations,"map_profile":world._map_root.get_meta("load_profile",{}),"session_profile":session.last_loading_profile,"world_profile":world.loading_profile},"\t")); file.close()
	quit(0 if passed and stages_ok else 1)

func diagnose(world:Node)->void:
	for stage in ["normal","model_off","world_off","batches_off","radar_off"]:
		if stage=="model_off":world._player._model.set_process(false)
		if stage=="world_off":world.set_process(false)
		if stage=="batches_off":world._map_root.get_node("GroundRenderBatches").set_process(false)
		if stage=="radar_off":world._hud.hide()
		var times:Array=[];var previous:=Time.get_ticks_usec()
		for i in 40:
			await process_frame;var now:=Time.get_ticks_usec();times.append((now-previous)/1000.0);previous=now
		times.sort();print("HOUSE_FRAME_DIAG ",stage," median=",times[20]," max=",times.back())

	var probes={"all":func():world._process(1.0/60),"resize":func():world._navigation.resize_agent(float(world._player.get_meta("standing_height",1.9)),world._map_root.get_meta("stream_library",[]),world._player.position),"facial":func():world.apply_actions(preload("res://scripts/net/net.gd").server().facial_expressions.drain()),"residency":func():world._apply_residency(12),"camera":func():world._camera.follow(world._player.global_position,1.0/60),"actors":func():world._apply_actor_view(),"warp":func():world._poll_warp(),"furniture":func():world.furniture.tick()}
	for key in probes:
		var total:=0
		for i in 20:
			await process_frame
			var began:=Time.get_ticks_usec();probes[key].call();total+=Time.get_ticks_usec()-began
		print("HOUSE_COMPONENT ",key," ms=",total/20000.0)
	# Diagnostics temporarily disable components; restore the real workload
	# before an optional walking benchmark in the same run.
	world._player._model.set_process(true);world.set_process(true)
	world._map_root.get_node("GroundRenderBatches").set_process(true);world._hud.show()

func measure_stairs(world:Node)->bool:
	var Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
	var extra:Dictionary=preload("res://scripts/world3d/world_document.gd").authoritative_extras(MAP).extras
	var fixture:Dictionary={}
	for value in extra.building_instances.values():
		if value.parameters.compound=="rear_workshop":fixture=value;break
	var plan:Dictionary=Blueprint.generate(fixture.parameters)
	var route:Array=plan.stairs[0].waypoints;var origin:=Blueprint.vec(fixture.position)
	var player:Node3D=world._player
	var authority=preload("res://scripts/net/net.gd").server().world3d_authority
	authority.release();player.position=origin+Blueprint.vec(route[0])+Vector3(0,.9,0)
	authority.mount(player,world._navigation,world._map_ref())
	world._camera.yaw=PI
	print("MAP_SHAPES ",world._map_data.shapes.size())
	var results:Array=[];var okay:=true
	for pass_ in 4:
		var points:Array=route.duplicate(true)
		if pass_%2==1:points.reverse()
		var samples:Array=[];var queries:Array=[];var timing:Array=[];var begin:=Time.get_ticks_usec();var previous:=begin
		for point in points.slice(1):
			var target:=origin+Blueprint.vec(point)
			var query_start:=Time.get_ticks_usec();player.set_click_target(target,"ground")
			queries.append((Time.get_ticks_usec()-query_start)/1000.0);previous=Time.get_ticks_usec()
			var deadline:=Time.get_ticks_msec()+20000
			while Time.get_ticks_msec()<deadline:
				await process_frame
				var now:=Time.get_ticks_usec();samples.append((now-previous)/1000.0);previous=now
				timing.append([RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),Performance.get_monitor(Performance.TIME_PROCESS)*1000,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000])
				if (player.position-Vector3(0,.9,0)-target).length()<.4:break
			var arrived:bool=(player.position-Vector3(0,.9,0)-target).length()<.5
			okay=okay and arrived
			if not arrived:print("STAIR_WALK_MISSED ",point," actual=",player.position-origin);break
		samples.sort();results.append({"pass":pass_,"frames":samples.size(),"median_ms":samples[samples.size()/2],"p95_ms":samples[int(samples.size()*.95)],"max_ms":samples.back(),"path_queries_ms":queries,"timing_gpu_process_physics":timing,"arrived":okay})
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/code/rmmo_runtime/review_artifacts/house_revision/stair_play_%d.png"%pass_)
	var file:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/house_revision/stair_frames.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"\t"));file.close()
	print("STAIR_FRAME_RESULTS ",JSON.stringify(results.map(func(row):var brief:Dictionary=row.duplicate();brief.erase("timing_gpu_process_physics");return brief)));return okay
