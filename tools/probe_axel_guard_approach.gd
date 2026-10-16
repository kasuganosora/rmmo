extends "res://tools/review_axel_functional_building_exteriors.gd"
## Run only through run_godot_background.py. No screenshots or content writes.
func json_safe(value:Variant)->Variant:
	if value is Vector3:return xyz(value)
	if value is PackedVector3Array:return Array(value).map(func(v):return xyz(v))
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[str(key)]=json_safe(value[key])
		return result
	if value is Array:return value.map(func(v):return json_safe(v))
	return value
func observe_motion(tick:int)->Dictionary:
	var player=world._player;var contacts:Array=[]
	for i in player.get_slide_collision_count():
		var collision:KinematicCollision3D=player.get_slide_collision(i)
		for j in collision.get_collision_count():contacts.append({"id":object_id(collision.get_collider(j)),"position":xyz(collision.get_position(j)),"normal":xyz(collision.get_normal(j))})
	return {"tick":tick,"physics_frame":Engine.get_physics_frames(),"feet":xyz(feet()),"velocity":xyz(player.velocity),"on_floor":player.is_on_floor(),"geometry_blocked":player.geometry_blocked,"input_locked":player.input_locked,"click_target":xyz(player.click_target) if player.click_target is Vector3 else null,"remaining_route":Array(player._route).map(func(p):return xyz(p)),"path_status":json_safe(player.path_status),"motion_timing":json_safe(player.get_meta("motion_timing",{})),"physics_timing":json_safe(player.get_meta("physics_timing",{})),"contacts":contacts,"navigation_version":world._navigation.version,"navigation_ready":world._navigation.ready_for_queries}
func diagnostic_walk(target:Vector3,label_:String)->Dictionary:
	var start:=feet();var request:Dictionary=world._player.set_click_target(target,"ground")
	var began:=Time.get_ticks_msec();var unsupported:=0;var maximum:=0;var tick:=0;var observations:Array=[]
	while Time.get_ticks_msec()-began<45000:
		await physics_frame;tick+=1
		var support_now:=support(feet(),.6,.3)
		unsupported=0 if support_now.ok else unsupported+1;maximum=maxi(maximum,unsupported)
		if tick<=3 or tick%30==0:observations.append(observe_motion(tick))
		if unsupported>20 or feet().distance_to(target)<.35:break
		if not world._player.path_status.get("ok",false) and world._player.path_status.get("reason","")!="pending":break
	var final:=observe_motion(tick);observations.append(final)
	var result:={"label":label_,"start":xyz(start),"end":xyz(feet()),"target":xyz(target),"remaining_m":feet().distance_to(target),"physics_samples":tick,"elapsed_ms":Time.get_ticks_msec()-began,"unsupported_ticks":maximum,"request":json_safe(request),"observations":observations,"final":final,"passed":feet().distance_to(target)<.45 and maximum<=20}
	check(result.passed,"actual unchanged-controller route "+label_,{"remaining_m":result.remaining_m,"unsupported_ticks":maximum,"final":final})
	stop_route();return result
func run()->void:
	started_ms=Time.get_ticks_msec();map_path="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf";output=FB_OUT+"/guard_approach_diagnostic";build_path=FB_OUT+"/functional_buildings_apply.json"
	expected_map_sha="cbfa6d3b0d5315d934bb679c741976e15d9e3170808dccac8bf74cb857248475";expected_build_sha="8d11d579483330d9239cfd4db40ce3828c8f992d70f43ddec9bdc5ac2d20e3d8"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
		elif arg.begins_with("--expected-map-sha="):expected_map_sha=arg.trim_prefix("--expected-map-sha=")
	report={"phase":"metadata","checks":[],"screenshots":[],"routes":[],"scope":"Only guardhouse's four public-road route segments in production LoadingScene; original controller/speeds/locks/collision and support standard, profile metadata only, no screenshots or authoring","map_path":map_path}
	if not Paths.allowed(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:quit(1);return
	create_timer(900).timeout.connect(func():
		if not finished:check(false,"guard approach diagnostic timeout",{"phase":report.phase});finish(2))
	if not check(DisplayServer.get_name()!="headless","private GPU runtime required"):finish();return
	if not check(Paths.allowed(map_path) and FileAccess.get_sha256(map_path)==expected_map_sha,"exact candidate SHA") or not check(FileAccess.get_sha256(build_path)==expected_build_sha,"exact applied building receipt SHA"):finish();return
	report.map_sha256=expected_map_sha;report.build_sha256=expected_build_sha
	build_receipt=JSON.parse_string(FileAccess.get_file_as_string(build_path));document=Document.open_file(map_path)
	if not check(document!=null,"candidate opens read-only"):finish();return
	for record:Dictionary in document.records:records[record.uuid]=record
	terrain_records=document.records.filter(func(r):return r.has("terrain_mesh"))
	var access:Dictionary=build_receipt.outdoor_access.filter(func(a):return a.key=="guardhouse")[0]
	Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	preload("res://tools/world3d_test_character.gd").ensure(self);var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"};session.world3d_requested=true;session.loading_mode="world3d_preview";session.world3d_map_path=map_path;session.world3d_spawn=Vector3(0,.9,4);session.prepared_world3d=null
	report.phase="native_loading";save_report()
	if not check(change_scene_to_file("res://scenes/loading.tscn")==OK,"production LoadingScene"):finish();return
	while not finished:
		await process_frame;world=current_scene
		if world==null:continue
		if world.has_meta("entry_loading_error"):check(false,"runtime loading failed",{"error":world.get_meta("entry_loading_error")});finish();return
		if world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active:break
	if finished:return
	check(canonical_path(world._map_path)==canonical_path(map_path),"runtime loaded exact candidate")
	world._player.set_meta("profile_frame",true)
	var points:Array=access.access_points_xz;var start:=ground_point(Vector3(points[0][0],0,points[0][1]));var anchor:=layout_view_anchor(start)
	if not check(anchor.ok,"actual public-road start anchor",anchor) or not await relocate(vector(anchor.position)+Vector3.UP*.04,"guardhouse diagnostic existing road"):finish();return
	report.initial_navigation=json_safe(world._navigation.capability_status())
	for i in range(1,points.size()):
		report.phase="guardhouse_public_approach_"+str(i);save_report()
		var at:=ground_point(Vector3(points[i][0],0,points[i][1]));var authored:=saved_pavement_point(at)
		if not check(authored.ok,"saved road destination "+str(i),authored):break
		var row:=await diagnostic_walk(vector(authored.position),"guardhouse public approach "+str(i));row.authored_target=authored;row.target_actual_collision=ray_surface(vector(authored.position),1.,2.)
		report.routes.append(row);save_report()
		if not row.passed:break
	report.final_navigation=json_safe(world._navigation.capability_status())
	check(FileAccess.get_sha256(map_path)==expected_map_sha and FileAccess.get_sha256(build_path)==expected_build_sha,"map and receipt remain unchanged")
	report.phase="complete";finish()
