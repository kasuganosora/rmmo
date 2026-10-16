extends "res://tools/review_axel_town_fortifications.gd"
## Diagnostic only: continue past the review's 20 unsupported ticks to observe
## native descent/landing. Never grants acceptance or changes player settings.
## Launch GPU only through run_godot_background.py. No screenshots or map writes.
const DIAGNOSTIC_MAP="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
const DIAGNOSTIC_SHA="cbfa6d3b0d5315d934bb679c741976e15d9e3170808dccac8bf74cb857248475"
const MotionDiagnostic=preload("res://scripts/world3d/world_motion.gd")

func controller_configuration()->Dictionary:
	var player:CharacterBody3D=world._player
	var collider:CollisionShape3D=player.get_node("CollisionShape3D")
	var capsule:CapsuleShape3D=collider.shape
	return {"floor_snap_length":player.floor_snap_length,"floor_max_angle":player.floor_max_angle,"floor_stop_on_slope":player.floor_stop_on_slope,"floor_constant_speed":player.floor_constant_speed,"safe_margin":player.safe_margin,"motion_mode":player.motion_mode,"walk_mps":MotionDiagnostic.WALK_MPS,"run_mps":MotionDiagnostic.RUN_MPS,"speed_multiplier":float(preload("res://scripts/net/net.gd").server().player_move_speed_mul()),"physics_ticks_per_second":Engine.physics_ticks_per_second,"capsule_height":capsule.height,"capsule_radius":capsule.radius,"collision_mask":player.collision_mask,"gravity_mps2_from_controller_source":9.8}

func authored_below(point:Vector3,stair:Dictionary)->Dictionary:
	var height:float=stair.size[1]-1.1
	var spec:Dictionary=preload("res://scripts/world3d/fortification_stair_mesh.gd").spec(height,stair.size[0]*.5)
	var basis:=Basis.from_euler(vector(stair.rotation)*PI/180)
	var local:Vector3=basis.inverse()*(point-vector(stair.position))
	var radius:=Vector2(local.x,local.z).length()
	var angle:=fposmod(atan2(local.z,local.x),TAU)
	var inside:bool=radius>=spec.inner+.16 and radius<=spec.outer+.08 and angle<=spec.sweep
	var index:=clampi(int(floor(angle/(spec.sweep/spec.count))),0,int(spec.count)-1)
	var y:float=-stair.size[1]*.5+height*(index+1)/spec.count
	var expected:Vector3=basis*Vector3(local.x,y,local.z)+vector(stair.position)
	return {"in_tread_footprint":inside,"radius_m":radius,"angle":angle,"step_index":index,"step_rise_m":height/spec.count,"step_angle":spec.sweep/spec.count,"expected_top_y":expected.y,"feet_gap_m":point.y-expected.y,"source_part":stair.fortification.part}

func diagnostic_sample(point:Vector3,stair:Dictionary,tick:int,elapsed:float,strict:Dictionary)->Dictionary:
	# This deeper ray is evidence only. It never changes the original support
	# predicate, character state, collision mask, or acceptance threshold.
	var below:=ray_surface(point,.08,12.)
	if below.get("ok",false):
		below.feet_gap_m=point.y-float(below.position[1])
		below.authored_tread=fort_ids.has(below.get("id","")) and TowerWalkSupport.authored_tread(vector(below.position),stair)
	var target:Variant=world._player.click_target
	return {"tick":tick,"elapsed_physics_s":elapsed,"feet":xyz(point),"velocity":xyz(world._player.velocity),"native_on_floor":world._player.is_on_floor(),"floor_normal":xyz(world._player.get_floor_normal()),"original_support_ok":strict.get("ok",false),"original_center_ray":strict.center_ray,"actual_below":below,"authored_below":authored_below(point,stair),"click_target":xyz(target) if target is Vector3 else null,"remaining_route_points":world._player._route.size(),"path_reason":world._player.path_status.get("reason",""),"geometry_blocked":world._player.geometry_blocked,"input_locked":world._player.input_locked}

func finish_air_segment(segment:Dictionary,last:Dictionary,completed:bool)->Dictionary:
	segment.end_tick=last.tick
	segment.end_feet=last.feet
	segment.duration_s=float(last.elapsed_physics_s)-float(segment.start_physics_s)
	segment.max_vertical_drop_m=float(segment.start_feet[1])-float(segment.minimum_y)
	segment.relanded=completed
	segment.end_native_on_floor=last.native_on_floor
	segment.end_actual_below=last.actual_below
	return segment

func probe_descent(route:Dictionary)->void:
	report.phase="diagnostic_tower_%d"%route.tower
	var stair:Dictionary={}
	for record:Dictionary in fitted_plan.records:
		if record.fortification.part=="access_tower_%d_internal_stair"%route.tower:stair=record;break
	if not check(not stair.is_empty(),"diagnostic exact stair source available tower %d"%route.tower):return
	if not await relocate_fortification(vector(route.deck),"diagnostic_tower_%d_deck"%route.tower):return
	if not await set_fixture(route.door_id,1.):return
	var config:=controller_configuration()
	var target:=terrain_point(vector(route.entry))
	var start:=feet()
	var request:Dictionary=world._player.set_click_target(target,"ground")
	var initial_path:Array=[]
	for point:Vector3 in request.get("path",PackedVector3Array()):initial_path.append(xyz(point))
	var samples:Array=[];var air_segments:Array=[];var current_air:Dictionary={}
	var began:=Time.get_ticks_msec();var elapsed:=0.0;var unsupported:=0;var maximum_unsupported:=0
	var airborne_ticks:=0;var maximum_airborne:=0;var min_y:=start.y;var max_y:=start.y
	var max_gap:=0.0;var missing_below:=0;var below_authored:=0;var reason:="45_second_limit"
	var reached:=false;var first_over_limit:Dictionary={};var last:Dictionary={}
	while Time.get_ticks_msec()-began<45000:
		await physics_frame
		var point:=feet();elapsed+=world._player.get_physics_process_delta_time()
		var strict:=tower_stair_support(point,stair)
		last=diagnostic_sample(point,stair,samples.size()+1,elapsed,strict);samples.append(last)
		min_y=minf(min_y,point.y);max_y=maxf(max_y,point.y)
		unsupported=0 if strict.ok else unsupported+1;maximum_unsupported=maxi(maximum_unsupported,unsupported)
		if unsupported>20 and first_over_limit.is_empty():first_over_limit=last.duplicate(true)
		if last.actual_below.get("ok",false):
			max_gap=maxf(max_gap,float(last.actual_below.feet_gap_m))
			if last.actual_below.get("authored_tread",false):below_authored+=1
		else:missing_below+=1
		if not last.native_on_floor:
			airborne_ticks+=1;maximum_airborne=maxi(maximum_airborne,airborne_ticks)
			if current_air.is_empty():current_air={"start_tick":last.tick,"start_physics_s":elapsed,"start_feet":last.feet,"minimum_y":point.y,"maximum_y":point.y,"maximum_actual_gap_m":0.0,"ticks":0,"missing_below_ticks":0,"authored_tread_below_ticks":0}
			current_air.ticks+=1;current_air.minimum_y=minf(current_air.minimum_y,point.y);current_air.maximum_y=maxf(current_air.maximum_y,point.y)
			if last.actual_below.get("ok",false):
				current_air.maximum_actual_gap_m=maxf(current_air.maximum_actual_gap_m,last.actual_below.feet_gap_m)
				if last.actual_below.get("authored_tread",false):current_air.authored_tread_below_ticks+=1
			else:current_air.missing_below_ticks+=1
		else:
			airborne_ticks=0
			if not current_air.is_empty():air_segments.append(finish_air_segment(current_air,last,true));current_air={}
		if point.distance_to(target)<.35 and last.native_on_floor and strict.ok:
			reached=true;reason="actual_target_arrival_and_ground_contact";break
		if not world._player.path_status.get("ok",false) and world._player.path_status.get("reason","")!="pending":reason="native_path_failed";break
	if not current_air.is_empty():air_segments.append(finish_air_segment(current_air,last,false))
	var row:={"tower":route.tower,"diagnostic_only":true,"acceptance_passed":false,"termination":reason,"start_mode":"native same-map transfer to exact authored deck center; actual settled physics","start":xyz(start),"target":xyz(target),"end":xyz(feet()),"actual_target_reached_grounded":reached,"remaining_m":feet().distance_to(target),"elapsed_ms":Time.get_ticks_msec()-began,"physics_elapsed_s":elapsed,"minimum_y":min_y,"maximum_y":max_y,"maximum_actual_below_gap_m":max_gap,"maximum_original_unsupported_ticks":maximum_unsupported,"original_20_tick_bound_exceeded":maximum_unsupported>20,"first_original_bound_exceeded":first_over_limit,"maximum_native_airborne_ticks":maximum_airborne,"actual_below_missing_ticks":missing_below,"authored_tread_below_ticks":below_authored,"controller_before":config,"controller_after":controller_configuration(),"controller_unchanged":config==controller_configuration(),"initial_path":initial_path,"request_reason":request.get("reason",""),"source_stair":stair,"airborne_segments":air_segments,"samples":samples,"final_native_on_floor":world._player.is_on_floor(),"final_velocity":xyz(world._player.velocity),"final_original_support":tower_stair_support(feet(),stair)}
	check(row.controller_unchanged,"diagnostic controller configuration unchanged tower %d"%route.tower)
	report.towers.append(row);stop_route();await restore_fixture(route.door_id);save_report()
	print("TOWER_DESCENT_DIAGNOSTIC tower=",route.tower," arrived=",reached," max_unsupported=",maximum_unsupported," air_segments=",air_segments.size()," max_gap=",max_gap)

func finish(code:int=-1)->void:
	if finished:return
	finished=true
	if is_instance_valid(world) and is_instance_valid(world.get("_player")):
		stop_route();report.final_feet=xyz(feet())
		for id:String in saved_fixture_states:world.set_building_component_state("fortification:"+str(settings.get("id","")),id,saved_fixture_states[id],0.)
		saved_fixture_states.clear()
	report.passed=false;report.acceptance_passed=false
	report.diagnostic_complete=report.get("phase","")=="complete" and failures==0 and code!=2
	report.status="diagnostic_complete_not_acceptance" if report.diagnostic_complete else "diagnostic_incomplete"
	save_report();print("TOWER_DESCENT_DIAGNOSTIC_RESULT ",output.path_join("result.json"))
	quit(code if code>=0 else (0 if report.diagnostic_complete else 1))

func run()->void:
	started_ms=Time.get_ticks_msec();map_path=DIAGNOSTIC_MAP
	output="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016/tower_descent_diagnostic"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=").replace("\\","/").simplify_path()
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=").replace("\\","/").simplify_path()
	report={"phase":"metadata","map_path":map_path,"checks":[],"towers":[],"screenshots":[],"diagnostic_only":true,"acceptance_passed":false,"scope":"Two unchanged production-controller tower descents, up to 45 seconds each; original support failures recorded but not used as early-stop condition","not_tested":["acceptance approval","other towers","screenshots","interiors of houses","performance"]}
	if not Paths.allowed(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:quit(1);return
	create_timer(750).timeout.connect(func():
		if not finished:check(false,"descent diagnostic overall timeout",{"phase":report.phase});finish(2))
	if not check(DisplayServer.get_name()!="headless","diagnostic production GPU required") or not check(Paths.allowed(map_path) and FileAccess.file_exists(map_path),"diagnostic map exists"):finish();return
	report.map_sha256=FileAccess.get_sha256(map_path)
	if not check(report.map_sha256==DIAGNOSTIC_SHA,"diagnostic exact final candidate SHA"):finish();return
	report.source_sha256={}
	for path:String in ["res://tools/probe_axel_tower_descent.gd","res://tools/review_axel_town_fortifications.gd","res://tools/axel_tower_walk_support.gd","res://scripts/world3d/world_player.gd","res://scripts/world3d/world_authority.gd","res://scripts/world3d/world_motion.gd","res://scripts/world3d/fortification_stair_mesh.gd"]:report.source_sha256[path]=FileAccess.get_sha256(path)
	document=Document.open_file(map_path)
	if not check(document!=null,"diagnostic map opened read-only"):finish();return
	layout=City.resolve(document.map_meta)
	for record:Dictionary in document.records:records[record.uuid]=record
	if not derive_coordinates():finish();return
	Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	preload("res://tools/world3d_test_character.gd").ensure(self);var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"};session.world3d_requested=true;session.loading_mode="world3d_preview";session.world3d_map_path=map_path;session.world3d_spawn=Vector3(0,.9,4);session.prepared_world3d=null
	report.phase="native_loading";save_report()
	if not check(change_scene_to_file("res://scenes/loading.tscn")==OK,"diagnostic production LoadingScene"):finish();return
	while not finished:
		await process_frame;world=current_scene
		if world==null:continue
		if world.has_meta("entry_loading_error"):check(false,"diagnostic native loading error",{"error":world.get_meta("entry_loading_error")});finish();return
		if world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active:break
	if finished:return
	if not check(canonical_path(world._map_path)==canonical_path(map_path),"diagnostic runtime map identity"):finish();return
	for index:int in [2,9]:
		var selected:Array=routes.filter(func(route):return int(route.tower)==index)
		if check(selected.size()==1,"diagnostic saved tower route %d"%index):await probe_descent(selected[0])
	check(FileAccess.get_sha256(map_path)==report.map_sha256,"diagnostic map bytes unchanged")
	check(report.towers.size()==2,"two diagnostic descents recorded")
	report.phase="complete";finish()
