extends SceneTree
## Real GameSession entry, real streamed guild, real player physics/camera orbit.
## --map=<fresh fixture/map.gltf> --out=<fresh external review directory>
const Paths=preload("res://scripts/world3d/map_paths.gd")
var game:Node
var output:=""
var map_path:=""
var report:Dictionary={"checks":[],"samples":[],"images":[],"failures":0}
var deadline_us:=0

func _initialize()->void:run.call_deferred()

func check(value:bool,label:String)->void:
	report.checks.append({"ok":value,"label":label})
	if not value:report.failures+=1;push_error(label)

func save()->void:
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()

func finish(status:String)->void:
	report.status=status;report.passed=report.failures==0 and status=="complete"
	report.finished_us=Time.get_ticks_usec();save()
	print("GUILD_NIGHT_CAMERA_GAME ",JSON.stringify({"status":status,"passed":report.passed,"failures":report.failures,"out":output}))
	quit(0 if report.passed else 1)

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
		if arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	if DisplayServer.get_name()=="headless" or not Paths.allowed(map_path,Paths.external_root().path_join("cache/world3d")) or not FileAccess.file_exists(map_path) or not Paths.allowed(output,Paths.external_root().path_join("review_artifacts")) or DirAccess.dir_exists_absolute(output):
		push_error("Requires GPU, an external temporary map, and a fresh external review output directory");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps=60;root.size=Vector2i(1280,900)
	report.engine=Engine.get_version_info();report.map_path=map_path;report.map_sha256=FileAccess.get_sha256(map_path)
	report.runtime_identity={}
	for path:String in ["scripts/world3d/streetlamp_lights.gd","scripts/world3d/weather_controller.gd","scripts/world3d/world_3d.gd","scripts/world3d/third_person_camera.gd","scripts/world3d/occlusion_outline.gd"]:
		report.runtime_identity[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session:Node=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_map_path=map_path
	report.entry_started_us=Time.get_ticks_usec();deadline_us=Time.get_ticks_usec()+240000000
	session.go_world_3d()
	while Time.get_ticks_usec()<deadline_us:
		await process_frame
		if is_instance_valid(current_scene) and (current_scene.has_node("FailActions") or current_scene.has_meta("entry_loading_error")):
			check(false,"normal game entry succeeds");finish("entry_failed");return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	if Time.get_ticks_usec()>=deadline_us:check(false,"entry deadline");finish("entry_timeout");return
	game=current_scene;report.playable_us=Time.get_ticks_usec()
	var lights:Node=game._weather.streetlamps
	while lights.fixtures.size()!=16 and Time.get_ticks_usec()<deadline_us:await process_frame
	check(lights.fixtures.size()==16,"real guild publishes all 16 authored sockets")
	if lights.fixtures.size()!=16:finish("socket_timeout");return
	await create_timer(2.0).timeout
	check(lights.observer==game._player,"game lighting observer is the actual player")
	check(not game._player.geometry_blocked and not game._player.input_locked,"real player physics is ready and unlocked")
	game._camera.yaw=0.0
	await create_timer(.6).timeout
	var fixed:Vector3=game._player.global_position
	var initial:Dictionary=capture("orbit_start")
	var signature:String=initial.selection
	var max_drift:=0.0;var min_arm:=INF;var max_arm:=0.0;var blocked_samples:=0;var outlines:=0;var unchanged:=true
	for i:int in 36:
		game._camera.yaw=float(i)*TAU/36.0
		await create_timer(.27).timeout
		var sample:Dictionary=capture("orbit_%02d"%i)
		unchanged=unchanged and sample.selection==signature
		max_drift=maxf(max_drift,game._player.global_position.distance_to(fixed))
		min_arm=minf(min_arm,float(sample.arm_length));max_arm=maxf(max_arm,float(sample.arm_length))
		if not sample.blocked_light_rays.is_empty():blocked_samples+=1
		if sample.outline_occluded:outlines+=1
		if i%9==0:await photograph("orbit_%02d"%i)
	report.orbit={"selection_unchanged":unchanged,"max_player_drift_m":max_drift,"minimum_arm_m":min_arm,"maximum_arm_m":max_arm,"blocked_light_samples":blocked_samples,"outline_samples":outlines}
	check(max_drift<.05,"orbit keeps the actual player stationary")
	check(unchanged,"full camera orbit preserves all light and shadow selections")
	check(blocked_samples>0,"real geometry obscures camera-to-light rays during orbit")
	check(min_arm<max_arm-.15,"real camera collision sweep shortens its arm")
	# Drive the regular player input/authority/physics path; no body teleport and
	# no manual controller refresh are allowed to manufacture a passing result.
	game._camera.yaw=0.0;await create_timer(.4).timeout
	var before_move:Vector3=game._player.global_position
	var before_selection:String=str(capture("before_walk").selection)
	var key:=InputEventKey.new();key.keycode=KEY_D;key.pressed=true;Input.parse_input_event(key)
	var move_started:=Time.get_ticks_usec();var changed:=false
	while Time.get_ticks_usec()-move_started<1800000:
		await create_timer(.15).timeout
		var sample:Dictionary=capture("walk_right")
		changed=changed or sample.selection!=before_selection
	key=InputEventKey.new();key.keycode=KEY_D;key.pressed=false;Input.parse_input_event(key)
	await create_timer(.6).timeout
	var after_move:Dictionary=capture("walk_end")
	changed=changed or after_move.selection!=before_selection
	report.walk={"distance_m":game._player.global_position.distance_to(before_move),"selection_changed":changed}
	check(float(report.walk.distance_m)>.5,"regular input moves the player through real guild collision")
	check(changed,"real player movement updates the light selection")
	await photograph("after_walk")
	check(FileAccess.get_sha256(map_path)==report.map_sha256,"test does not modify its map")
	finish("complete")

func vector(value:Vector3)->Array:return [value.x,value.y,value.z]

func capture(label:String)->Dictionary:
	var lights:Node=game._weather.streetlamps
	var camera:Camera3D=game._camera.camera
	var rows:Array=[];var selected:Array[String]=[];var blocked:Array=[]
	for id:Variant in lights.fixtures:
		var fixture:Dictionary=lights.fixtures[id]
		var source:Node=fixture.node.get_ref()
		var light:OmniLight3D=fixture.light
		var name_:String=str(source.name) if is_instance_valid(source) else "released"
		rows.append({"source":name_,"position":vector(light.global_position),"visible":light.visible,"shadow":light.shadow_enabled,"energy":light.light_energy,"range":light.omni_range})
		if light.visible:
			selected.append(name_+":"+str(light.shadow_enabled))
			var query:=PhysicsRayQueryParameters3D.create(camera.global_position,light.global_position)
			query.exclude=[game._player.get_rid()];query.collide_with_areas=false
			var hit:Dictionary=game._player.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():blocked.append({"light":name_,"position":vector(hit.position),"uuid":preload("res://scripts/world3d/fortification_collision_batcher.gd").hit_uuid(hit)})
	selected.sort();rows.sort_custom(func(a,b):return a.source<b.source)
	var outline:Node=game._outline
	var sample:Dictionary={"label":label,"ticks_us":Time.get_ticks_usec(),"frame":Engine.get_process_frames(),"player":vector(game._player.global_position),"player_rotation":vector(game._player.global_rotation),"camera":vector(camera.global_position),"camera_rotation":vector(camera.global_rotation),"camera_yaw":game._camera.yaw,"camera_desired":vector(game._camera.last_desired),"arm_length":game._camera._arm_length,"outline_occluded":outline.occluded if is_instance_valid(outline) else false,"outline_update_mode":outline.mask.render_target_update_mode if is_instance_valid(outline) else -1,"lights":rows,"selection":"|".join(selected),"blocked_light_rays":blocked}
	report.samples.append(sample);save();return sample

func photograph(label:String)->void:
	var model:Node3D=game._player._model
	var visible_:bool=model.visible;model.visible=false
	await process_frame;await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var path:String=output.path_join(label+"_q90.webp")
	var error:int=image.save_webp(path,false,.9)
	model.visible=visible_
	report.images.append({"path":path,"lossy":true,"quality":90,"width":image.get_width(),"height":image.get_height(),"save_error":error,"sha256":FileAccess.get_sha256(path) if error==OK else ""})
	check(error==OK,"lossy quality-90 screenshot "+label);save()
