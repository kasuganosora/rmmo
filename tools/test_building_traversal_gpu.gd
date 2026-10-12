extends "res://tools/test_building_entry_gpu.gd"
## Small real doorway fixture; root runs on the private GPU desktop.
var intent_sequence:=1000000

func drive(direction:Vector3)->Dictionary:
	await physics_frame
	intent_sequence+=1
	var result:Dictionary=root.get_node("MockServer").try_move_world(intent_sequence,direction,2.6,false)
	await process_frame
	return result

func run()->void:
	var timeout:=Timer.new();timeout.wait_time=180;timeout.one_shot=true;root.add_child(timeout)
	timeout.timeout.connect(func():print("BUILDING_TRAVERSAL_TIMEOUT");quit(2));timeout.start()
	WorldScript.building_readiness_enabled=true
	# Exercise the building guard even with the legacy navigation gate enabled.
	WorldScript.navigation_background_enabled=false;WorldScript.wind_background_enabled=true
	preload("res://tools/world3d_test_character.gd").ensure(self)
	directory=Paths.cache_directory("building_walk_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("walk.gltf")
	check(make_building_map(path),"temporary full building crosses a chunk boundary")
	var plan:Dictionary=Blueprint.generate({"template":"house","floors":2,"rooms_per_floor":1})
	var start:=Vector3(float(plan.entrance[0])+31,.8,float(plan.entrance[2])-2)
	var boundary:float=-float(plan.parameters.depth)/2
	var session:=root.get_node("GameSession")
	session.world3d_map_path=path;session.world3d_spawn=start
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.go_world_3d()
	while true:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_meta("entry_loading_error"):
			check(false,str(current_scene.get_meta("entry_loading_error")));quit(1);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	world=current_scene;world._player.set_physics_process(false)
	check(world._building_entry.report().membership=="outdoor","real entry begins outside the doorway")
	var footprint:AABB=preload("res://scripts/world3d/physical_traversal.gd").motion_bounds(world._player,Vector3.ZERO,world._player.get_physics_process_delta_time(),false)
	var entrance_clip:AABB=footprint.merge(AABB(footprint.position+Vector3(0,0,boundary+2-start.z),footprint.size))
	var entrance_xz:=Rect2(entrance_clip.position.x,entrance_clip.position.z,entrance_clip.size.x,entrance_clip.size.z)
	var disabled:CollisionObject3D
	var fault_spec:Dictionary={}
	for spec:Dictionary in world._map_root.get_meta("stream_library",[]):
		var info:Dictionary=spec.get("extras",{}).get("building",{})
		if info.get("id")=="home" and float(info.get("floor",-1))==1:
			var bounds:AABB=spec.transform*spec.mesh.get_aabb()
			if bounds.position.z<=boundary+4 or entrance_xz.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z),true):continue
			var body:Variant=world._map_root.get_meta("stream_bodies",{}).get(spec.uuid)
			if is_instance_valid(body) and body is CollisionObject3D:disabled=body;fault_spec=spec;break
	check(disabled!=null,"distant floor collision member exists for incomplete-readiness fault")
	if disabled==null:await cleanup_world();quit(1);return
	var fault_bounds:AABB=fault_spec.transform*fault_spec.mesh.get_aabb()
	check(not entrance_xz.intersects(Rect2(fault_bounds.position.x,fault_bounds.position.z,fault_bounds.size.x,fault_bounds.size.z),true),"fault lies outside the entire doorway sweep's local XZ collision footprint")
	var layer:int=disabled.collision_layer;disabled.collision_layer=0
	var blocked:=false
	var reasons:Dictionary={};var first_rejection:Dictionary={}
	for frame:int in 180:
		var result:Dictionary=await drive(Vector3(0,0,1))
		var reason:String=str(result.get("reason","ok"));reasons[reason]=int(reasons.get(reason,0))+1
		if not result.ok and first_rejection.is_empty():
			var sweep:AABB=preload("res://scripts/world3d/physical_traversal.gd").motion_bounds(world._player,Vector3(0,0,2.6),world._player.get_physics_process_delta_time(),false)
			first_rejection={"result":result,"position":world._player.global_position,"sweep":sweep,"requirements":world._building_authority().traversal_requirements(world._building_entry.issued.ticket,world._player.global_position-Vector3.UP*.9,sweep)}
		if not result.ok and str(result.reason).begins_with("building_"):blocked=true;break
	var resident:Variant=world._map_root.get_meta("stream_bodies",{}).get(fault_spec.uuid)
	print("BUILDING_WALK_FAULT ",JSON.stringify({"start":start,"boundary_z":boundary,"position":world._player.global_position,"reasons":reasons,"first_rejection":first_rejection,"fault_uuid":fault_spec.uuid,"fault_part":fault_spec.extras.building.part,"fault_bounds":fault_spec.transform*fault_spec.mesh.get_aabb(),"fault_id":disabled.get_instance_id(),"resident_id":resident.get_instance_id() if is_instance_valid(resident) else 0,"fault_layer":disabled.collision_layer,"input_locked":world._player.input_locked,"barrier":world._building_traversal.report() if world._building_traversal!=null else {}}))
	check(blocked and world._player.global_position.z<boundary,"sweep blocks before doorway when distant building member is not physical")
	check(not world._player.input_locked and world._building_traversal.attempts.has("home"),"waiting preserves input and owns exact building preparation")
	var held:Vector3=world._player.global_position
	for frame:int in 12:await drive(Vector3(0,0,1))
	check(world._player.global_position.distance_to(held)<.05,"unready building cannot be entered on later movement ticks")
	for frame:int in 45:await drive(Vector3(0,0,-1))
	check(world._player.global_position.z<held.z-1 and world._building_traversal.attempts.is_empty(),"turning away moves normally and retires speculative building lease")
	disabled.collision_layer=layer;disabled.set_meta("stream_physics_published_frame",Engine.get_physics_frames())
	for frame:int in 260:
		await drive(Vector3(0,0,1))
		if world._player.global_position.z>boundary+1:break
	check(world._player.global_position.z>boundary+1,"normal authority movement enters after complete building and rendered-frame readiness")
	check(world._building_traversal.attempts.has("home") and world._building_traversal.attempts.home.phase=="active","walking into building retains its complete residency permit")
	var state:Dictionary=world._building_authority().position_snapshot(world._map_ref(),str(world._map_root.get_meta("source_map_sha256")),world._player.global_position-Vector3.UP*.9)
	check(state.ok and state.snapshot.membership=="indoor","membership changes only after actual physical crossing")
	for frame:int in 180:
		await drive(Vector3(0,0,-1))
		if world._player.global_position.z<boundary-2:break
	check(world._player.global_position.z<boundary-2 and world._building_traversal.attempts.is_empty(),"leaving building releases complete-building permit and pins")
	var clean:=true
	for key:String in world._map_root.get_meta("stream_sources",{}):
		if key.begins_with("building_walk:"):clean=false
	check(clean,"walking does not leak residency source pins")
	var entrance_id:=""
	for row:Dictionary in world.list_building_components("home"):
		if str(row.id).contains("entrance"):entrance_id=str(row.id);break
	check(not entrance_id.is_empty(),"real entrance fixture is available for ordered door-state test")
	if not entrance_id.is_empty():
		check(world.set_building_component_state("home",entrance_id,0,0).ok,"authority closes the entrance after outdoor departure")
		for frame:int in 150:await drive(Vector3(0,0,1))
		check(world._player.global_position.z<boundary and world._building_traversal.attempts.has("home") and world._building_traversal.attempts.home.phase=="active","complete-building permit cannot bypass the actual closed-door collision")
		var opened:Dictionary=world.set_building_component_state("home",entrance_id,1,0)
		check(opened.ok,"authority publishes newer open-door state")
		var waited_new_state:=false
		for frame:int in 220:
			var moved:Dictionary=await drive(Vector3(0,0,1))
			waited_new_state=waited_new_state or (not moved.ok and str(moved.reason)=="building_pending")
			if world._player.global_position.z>boundary+1:break
		check(waited_new_state and world._player.global_position.z>boundary+1,"outside re-entry waits for newer door state and a new rendered frame")
		for frame:int in 180:
			await drive(Vector3(0,0,-1))
			if world._player.global_position.z<boundary-2:break
		check(world._building_traversal.attempts.is_empty(),"repeated door-state attempts release their final building leases")
	timeout.free()
	await cleanup_world();await process_frame;await process_frame
	print("BUILDING_TRAVERSAL_GPU_FINISHED failures=",failures)
	quit(1 if failures else 0)
