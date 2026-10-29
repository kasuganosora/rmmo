extends "res://tools/test_building_entry_gpu.gd"
## Same fixture/character/viewport, real native entry and first drawn frame.
## No held services and no detailed per-frame instrumentation while timing.
const OUT="D:/code/rmmo_runtime/review_artifacts/staged_far_20261017/"
func run()->void:
	create_timer(100).timeout.connect(func():print("STAGED_ENTRY_BENCH_TIMEOUT");quit(2))
	var control:bool="--control" in OS.get_cmdline_user_args();var label_:="control" if control else "staged"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):label_=arg.trim_prefix("--label=")
	WorldScript.automatic_staged_entry_enabled=not control;WorldScript.navigation_background_enabled=not control;WorldScript.wind_background_enabled=false
	preload("res://tools/world3d_test_character.gd").ensure(self);root.size=Vector2i(1280,800);root.content_scale_size=root.size;Engine.max_fps=60
	directory=Paths.cache_directory("staged_entry_benchmark");DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	if not make_building_map(path):quit(1);return
	var session:=root.get_node("GameSession");session.world3d_map_path=path;session.world3d_spawn=indoor
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	var started:=Time.get_ticks_usec();session.go_world_3d()
	while true:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_meta("entry_loading_error"):check(false,str(current_scene.get_meta("entry_loading_error")));quit(1);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	world=current_scene
	var elapsed:float=(Time.get_ticks_usec()-started)/1000.;var ready:Dictionary=world.preparation_state()
	check(not world._player.input_locked and world._player.is_physics_processing(),"real initial first frame releases playable input")
	check(ready.policy.mode==("full" if control else "staged"),"measurement uses requested policy")
	var result:Dictionary={"label":label_,"control":control,"entry_ms":elapsed,"map_sha256":FileAccess.get_sha256(path),"fixture":path,"profile":world.loading_profile.duplicate(true),"state":ready,"failures":failures}
	FileAccess.open(OUT+"entry_"+label_+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	await cleanup_world();print("STAGED_ENTRY_BENCH label=",label_," elapsed_ms=",elapsed," failures=",failures);quit(1 if failures else 0)
