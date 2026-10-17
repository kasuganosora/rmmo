extends "res://tools/test_building_entry_gpu.gd"
## Real production entry, with no forced building flag. Hold navigation work,
## never fake a ready signal; release it and observe actual publication.
const OUT="D:/code/rmmo_runtime/review_artifacts/staged_far_20261017/"
var evidence:Dictionary={"checks":[],"states":[]}
var held_navigation:Array[Node]=[]
var hold_initial:=true
func check(ok:bool,label_:String)->void:
	super.check(ok,label_);evidence.checks.append({"ok":ok,"label":label_})
func run()->void:
	create_timer(300).timeout.connect(func():print("AUTOMATIC_ENTRY_TIMEOUT");quit(2))
	check(not WorldScript.building_readiness_enabled and WorldScript.automatic_staged_entry_enabled,"production defaults select the protocol automatically")
	preload("res://tools/world3d_test_character.gd").ensure(self)
	directory=Paths.cache_directory("automatic_entry_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var a:=directory.path_join("a.gltf");var b:=directory.path_join("b.gltf");var unknown:=directory.path_join("unknown.gltf")
	check(make_building_map(a) and make_building_map(b) and make_building_map(unknown,true),"save real complete and unsupported cross-chunk building maps")
	var hashes:Array=[FileAccess.get_sha256(a),FileAccess.get_sha256(b),FileAccess.get_sha256(unknown)]
	var callback:=func(node:Node):
		if hold_initial and node.get_script()==NavigationScript:
			node.process_mode=Node.PROCESS_MODE_DISABLED;held_navigation.append(node)
	node_added.connect(callback)
	var session:=root.get_node("GameSession");session.world3d_map_path=a;session.world3d_spawn=indoor
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"};session.go_world_3d()
	var deadline:=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_meta("entry_loading_error"):check(false,str(current_scene.get_meta("entry_loading_error")));quit(1);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	world=current_scene
	if world==null or not world.has_method("preparation_state"):check(false,"production entry did not complete");quit(1);return
	world._preparation_sample_at=0;world._update_preparation_hint()
	var state:Dictionary=world.preparation_state();evidence.states.append(state)
	check(state.policy.mode=="staged" and state.playable and not state.navigation.ready,"complete building becomes playable while real navigation is held")
	check(world._building_entry.report().state=="active" and world._building_entry.report().building_members.size()==member_count,"complete members, physics and real first frame still authorize entry")
	check(world._preparation_hint.visible and world._preparation_hint.text.contains("点击寻路准备中"),"UI describes keyboard movement and pending click navigation")
	check(world._manual_traversal_receipt(AABB(indoor-Vector3(.4,.9,.4),Vector3(.8,1.8,.8)),weakref(world._map_root)).ok,"manual movement retains actual physical and building traversal proof")
	check(not world._navigation.find_foreground_path(indoor,indoor+Vector3(2,0,0)).get("ok",false),"unready click navigation never pretends to have a route")
	hold_initial=false;node_added.disconnect(callback)
	for nav:Node in held_navigation:nav.process_mode=Node.PROCESS_MODE_INHERIT
	held_navigation.clear();deadline=Time.get_ticks_msec()+60000
	while not world._navigation.ready_for_queries and Time.get_ticks_msec()<deadline:await process_frame
	world._preparation_sample_at=0;world._update_preparation_hint();state=world.preparation_state();evidence.states.append(state)
	check(state.navigation.ready and world._building_entry.report().capabilities.navigation.state=="ready","background completion publishes real ready state to shared contract")
	var before:Vector3=world._player.global_position
	check(not await world.transfer_map(unknown,Vector3(0,40,4)),"unsupported target with no support fails under complete waiting policy")
	check(world._entry_policy.mode=="staged" and world._building_entry.report().state=="active" and not world._player.input_locked and before.distance_to(world._player.global_position)<.15,"failed fallback restores source policy and fresh authority evidence")
	check(await world.transfer_map(unknown,Vector3(0,.8,4)),"unsupported catalogue can use the complete legacy wait at a valid outdoor destination")
	state=world.preparation_state();evidence.states.append(state)
	check(state.policy.mode=="full" and state.policy.reason=="incomplete_building_semantics" and world._building_entry==null and state.navigation.ready,"missing semantics keep full wait and release previous building ticket")
	check(await world.transfer_map(b,indoor) and world._entry_policy.mode=="staged" and world._building_entry.report().state=="active","full-wait map can hand off back into automatically verified building")
	for i in 20:
		var cancelled:Dictionary={"done":false,"ok":false};var latest:Dictionary={"done":false,"ok":false}
		execute(b,Vector3(0,.8,4),cancelled,Callable());execute(b,indoor,latest,Callable())
		while not latest.done:await process_frame
		check(cancelled.done and not cancelled.ok and latest.ok and world._building_transfer==null and world._local_transfer.is_empty(),"round %d latest request cancels and leaves no transaction owner"%i)
	check(hashes==[FileAccess.get_sha256(a),FileAccess.get_sha256(b),FileAccess.get_sha256(unknown)],"staged/fallback/cancel/revisit never edits authored maps")
	await cleanup_world()
	evidence.failures=failures;evidence.fixture=directory
	FileAccess.open(OUT+"automatic_entry.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "))
	print("AUTOMATIC_STAGED_ENTRY failures=",failures," checks=",evidence.checks.size());quit(1 if failures else 0)
