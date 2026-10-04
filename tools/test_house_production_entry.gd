extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	Engine.max_fps=60;root.size=Vector2i(1280,800)
	create_timer(120).timeout.connect(func():quit(2))
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession")
	var axis_actor:bool="--axis-actor" in OS.get_cmdline_user_args()
	if axis_actor:session.selected_character={"id":-101,"name":"女性角色切换回归","gender":"female","customization":{"body_model":"female_base_v2"}}
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_requested=true;session.loading_mode="world3d_preview"
	session.world3d_map_path="D:/code/rmmo_runtime/maps/medieval_house_showcase_v8/map.gltf"
	var started:=Time.get_ticks_msec()
	if change_scene_to_file("res://scenes/loading.tscn")!=OK:quit(1);return
	var world:Node
	while true:
		await process_frame
		world=current_scene
		if world!=null and world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active:break
	var okay:bool=world._player!=null and not world._player.input_locked and not is_instance_valid(session._prepared_world_actor) and not is_instance_valid(session._world_render_warmup) and world._navigation.ready_for_queries
	print("PRODUCTION_LOADING_SCREEN passed=",okay," elapsed_ms=",Time.get_ticks_msec()-started," profile=",session.last_loading_profile," map=",world._map_root.get_meta("load_profile",{})," navigation=",world._navigation.loading_profile)
	if axis_actor:
		var bodies:Array=[]
		_collect_bodies(world,bodies)
		assert(not bodies.is_empty(),"Production entry did not create the requested axis actor")
		for body in bodies:
			assert(body.gpu!=null and body.gpu_display!=null,"World handoff released live GPU resources")
			for pose in ["stand","step","elbow"]:
				body.set_test_pose(pose)
				await process_frame
			assert(not body._solving)
		print("PASS axis actor production handoff and three subsequent poses")
	world._camera.yaw=PI
	for i in 30:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/code/rmmo_runtime/review_artifacts/entry_loading/production_ready.png")
	quit(0 if okay else 1)

func _collect_bodies(node:Node,result:Array)->void:
	if node.get_script()==preload("res://scripts/char/female_axis_body.gd"):result.append(node)
	for child in node.get_children():_collect_bodies(child,result)
