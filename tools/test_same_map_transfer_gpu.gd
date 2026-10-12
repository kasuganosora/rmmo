extends "res://tools/test_transfer_loading_gpu.gd"
## Parent runs this via run_godot_background.py; never launch a foreground test.
func run()->void:
	create_timer(300).timeout.connect(func():print("SAME_MAP_TRANSFER_TIMEOUT");quit(2))
	preload("res://tools/world3d_test_character.gd").ensure(self)
	directory=Paths.cache_directory("same_map_transfer_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var asset:=directory.path_join("prop.glb")
	check(ordinary_fixture(asset)==OK,"create ordinary deferred fixture")
	var path:=directory.path_join("large.gltf")
	if not make_map(path,asset,true):quit(1);return
	var source_sha:=FileAccess.get_sha256(path)
	var session:=root.get_node("GameSession");session.world3d_map_path=path;session.world3d_spawn=Vector3(0,.9,4)
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.go_world_3d()
	while true:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_node("FailActions"):
			check(false,"real loading entry: "+str(current_scene.status_label.text));quit(1);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	world=current_scene
	var map_id:int=world._map_root.get_instance_id();var combat_id:int=world._combat.get_instance_id();var hud_id:int=world._hud.get_instance_id()
	var deferred:Node=world._map_root.get_node_or_null("DeferredAssets")
	var original_listeners:Dictionary=listener_snapshot(deferred)
	var residency:Node=world._map_root.get_node_or_null("AssetResidency")
	var residency_listener:=Callable(residency,"observe")
	check(residency!=null and deferred.published.is_connected(residency_listener),"indexed fixture has its explicit persistent asset-residency observer")
	check(deferred!=null and not deferred.ensure_geometry(AABB(Vector3(292,-100,0),Vector3(20,200,12)),"test_setup"),"destination starts with unprepared external geometry")
	deferred.release_demand("test_setup")
	world._combat.set_physics_process(false)
	world._combat.summons.spawn("audit_summon","Transfer audit",Vector3(2,0,4))
	var actor:Node=world._combat.actors.audit_summon
	var actor_id:int=actor.get_instance_id()
	var server:=root.get_node("MockServer");server.combat_stats.npcs.audit_summon.hp=19
	world._combat.defeated.audit_marker=true
	actor.global_position=Vector3(300,.9,4)
	await physics_frame;await process_frame
	var gate:=func()->bool:callbacks+=1;return true
	await fail_case(path,Vector3(300,.9,4),gate,"live moved actor occupancy")
	check(actor.get_instance_id()==actor_id and server.combat_stats.npcs.audit_summon.hp==19,"rejected transfer preserves actor identity and HP")
	actor.global_position=Vector3(302,.9,8)
	await physics_frame;await process_frame
	var moved:=await transfer(path,Vector3(300,.9,4),gate)
	check(moved.ok and world._map_root.get_instance_id()==map_id and world._combat.get_instance_id()==combat_id and world._hud.get_instance_id()==hud_id,"same-map success preserves map, combat and HUD objects")
	check(world._combat.actors.audit_summon.get_instance_id()==actor_id and server.combat_stats.npcs.audit_summon.hp==19 and world._combat.defeated.audit_marker,"same-map success preserves live actor and defeated state")
	check(actor.authority._navigation.get_ref()==world._navigation,"preserved actor authority binds the committed navigation")
	check(world.get_meta("transfer_loading_profile").map_reused and world._transfer_loader==null,"same-map handoff reports reuse without creating a map loader")
	check(world._map_root.get_meta("stream_sources",{}).is_empty(),"successful transaction releases both residency pins")
	var rejected:=func()->bool:callbacks+=1;return false
	await fail_case(path,Vector3(306,.9,4),rejected,"same-map commit condition rejection",1)
	var original_pose:Transform3D=world._player.global_transform
	var cancelled:Dictionary={"done":false,"ok":false};var latest:Dictionary={"done":false,"ok":false}
	var gate_calls:=callbacks
	execute(path,Vector3(0,.9,4),cancelled,gate)
	# Submit while the first cover is awaiting its initial frame. The old
	# transaction owns all cleanup before the latest request starts preparing.
	execute(path,Vector3(306,.9,4),latest,gate)
	var saw_rollback:=false;var reused:=true
	while not latest.done:
		if cancelled.done and world._player.global_transform==original_pose:saw_rollback=true
		reused=reused and world._map_root.get_instance_id()==map_id and world._transfer_loader==null
		await process_frame
	check(cancelled.done and not cancelled.ok and latest.ok and callbacks==gate_calls+1,"newest same-map request cancels predecessor before its commit gate")
	check(saw_rollback and reused,"cancelled handoff restores original pose before latest request while reusing map")
	check(world._player.global_position.distance_to(Vector3(306,.9,4))<.1 and Stream.nearby_collision_ready(world._map_root,world._player.global_position),"latest request enters only after destination collision is ready")
	check(world._local_transfer.is_empty() and world._map_root.get_meta("stream_sources",{}).is_empty(),"consecutive transfer cleanup leaves no transaction or residency pins")
	var no_transfer_demands:=true
	var current_navigation_demand:="navigation:%d"%world._navigation.get_instance_id()
	for id:String in deferred._demands:
		if id.begins_with("transfer:") or (id.begins_with("navigation:") and id!=current_navigation_demand):no_transfer_demands=false
	var final_listeners:Dictionary=listener_snapshot(deferred)
	var listeners_valid:bool=final_listeners.published.size()==2 and final_listeners.completed.size()==1 and final_listeners.failed.size()==1 and final_listeners.published.count(residency_listener)==1
	for signal_name:String in final_listeners:
		for callback:Callable in final_listeners[signal_name]:
			if callback==residency_listener:continue
			# The one current navigation bridge is a World3D lambda. Retired
			# navigation callbacks must be disconnected, not merely inert.
			listeners_valid=listeners_valid and callback.is_valid() and callback.get_object()==world and not original_listeners[signal_name].has(callback)
	check(no_transfer_demands and listeners_valid,"consecutive transfers retain only current navigation callbacks and the exact residency observer")
	print("TRANSFER_LISTENERS ",{"published":final_listeners.published.size(),"completed":final_listeners.completed.size(),"failed":final_listeners.failed.size(),"demands":deferred._demands.keys()})
	check(FileAccess.get_sha256(path)==source_sha,"all transfers preserve the authored source map")
	await cleanup_world()
	print("SAME_MAP_TRANSFER_GPU_FINISHED failures=",failures," fixture=",directory)
	quit(1 if failures else 0)
