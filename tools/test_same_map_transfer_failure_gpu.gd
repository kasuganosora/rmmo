extends "res://tools/test_transfer_loading_gpu.gd"
## Run with the private-desktop runner. Only disposable fixture assets mutate.
func store_bytes(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()

func pending_path(deferred:Node,x:float)->String:
	for item:Dictionary in deferred.pending:
		if absf(item.bounds.get_center().x-x)<2:return str(item.path)
	return ""

func wait_optional_navigation(label_:String)->void:
	if not world._navigation_async(world._map_root):return
	check(physical_destination_ready() and not world._player.input_locked,label_+" has physical support and gameplay before optional navigation")
	var deadline:=Time.get_ticks_msec()+30000
	while not world._navigation.ready_for_queries and world._navigation.geometry_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(world._navigation.ready_for_queries,label_+" optional navigation completes within bounded time")

func run()->void:
	create_timer(300).timeout.connect(func():print("SAME_MAP_TRANSFER_FAILURE_TIMEOUT");quit(2))
	preload("res://tools/world3d_test_character.gd").ensure(self)
	directory=Paths.cache_directory("same_map_failure_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var b_asset:=directory.path_join("b.glb");var c_asset:=directory.path_join("c.glb")
	check(ordinary_fixture(b_asset)==OK and ordinary_fixture(c_asset)==OK,"create independent B and C source models")
	var c_bytes:=FileAccess.get_file_as_bytes(c_asset)
	var json_length:=c_bytes.decode_u32(12)
	var json_bytes:=c_bytes.slice(20,20+json_length).get_string_from_utf8().replace("Crate","Cargo").to_utf8_buffer()
	for i in json_bytes.size():c_bytes[20+i]=json_bytes[i]
	store_bytes(c_asset,c_bytes)
	var doc:=Doc.new();doc.map_meta={"spawn":[0,.9,4],"map_ref":"isolated_transfer_failure"}
	for x:float in [0.,300.,600.]:doc.add_box("ground",Vector3(x,-.1,0),Vector3(24,.2,24))
	doc.add_asset({"label":"B prop","asset_path":b_asset,"bounds_position":[-.5,-.5,-.5]},Vector3(304,.5,4))
	doc.add_asset({"label":"C prop","asset_path":c_asset,"bounds_position":[-.5,-.5,-.5]},Vector3(604,.5,4))
	var path:=directory.path_join("three_regions.gltf")
	check(doc.save(path)==OK,"save three separated disposable regions")
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
	var original_map:int=world._map_root.get_instance_id()
	var original_navigation:int=world._navigation.get_instance_id()
	var deferred:Node=world._map_root.get_node_or_null("DeferredAssets")
	check(deferred!=null,"map retains its demand-loaded model service")
	if deferred==null:await cleanup_world();quit(1);return
	var interactive_workers:int=deferred._admission.worker_limit
	var admission_bytes:int=deferred._admission.byte_limit
	var actual_b:=pending_path(deferred,304);var actual_c:=pending_path(deferred,604)
	check(not actual_b.is_empty() and not actual_c.is_empty() and actual_b!=actual_c,"B and C are distinct unpublished source dependencies")
	if actual_b.is_empty() or actual_c.is_empty() or actual_b==actual_c:await cleanup_world();quit(1);return
	# Map admission has already captured the valid header. Corrupt only this
	# fixture's GLB magic before the first demanded import, changing full SHA.
	var original_bytes:=FileAccess.get_file_as_bytes(actual_b)
	var original_sha:=FileAccess.get_sha256(actual_b)
	var corrupt:=original_bytes.duplicate();corrupt[0]^=1;store_bytes(actual_b,corrupt)
	check(FileAccess.get_sha256(actual_b)!=original_sha,"B source changed after admission")
	var gate:=func()->bool:callbacks+=1;return true
	await fail_case(path,Vector3(300,.9,4),gate,"corrupt B dependency")
	check(deferred._admission.worker_limit==interactive_workers and deferred._admission.byte_limit==admission_bytes,"failed covered transfer restores interactive worker capacity without changing memory quota")
	var b_clip:=AABB(Vector3(220,-100000,-76),Vector3(160,200000,160))
	var c_clip:=AABB(Vector3(520,-100000,-76),Vector3(160,200000,160))
	check(world._navigation.get_instance_id()==original_navigation and world._navigation.geometry_error.is_empty() and deferred.error.is_empty(),"B failure preserves original navigation and service health")
	check(not deferred.error_for_clip(b_clip).is_empty() and deferred.error_for_clip(c_clip).is_empty(),"B error is limited to regions depending on B")
	check(not world._player.input_locked and world._navigation.find_path(Vector3(1,.05,4),Vector3(3,.05,4)).ok and Stream.nearby_collision_ready(world._map_root,world._player.global_position),"A remains playable with actual navigation and collision after rollback")
	check(not pending_path(deferred,604).is_empty(),"C remains genuinely unpublished after B fails")
	var to_c:=await transfer(path,Vector3(600,.9,4),gate)
	if to_c.ok:await wait_optional_navigation("independent C")
	check(to_c.ok and world._navigation.geometry_error.is_empty() and world._navigation.find_path(Vector3(598,.05,4),Vector3(602,.05,4)).ok,"independent C still loads and supports navigation despite B failure")
	check(not deferred.error_for_clip(b_clip).is_empty(),"successful C transaction does not erase unresolved B error")
	store_bytes(actual_b,original_bytes)
	check(FileAccess.get_sha256(actual_b)==original_sha,"restore exact B source identity")
	var to_b:=await transfer(path,Vector3(300,.9,4),gate)
	check(to_b.ok and deferred.error_for_clip(b_clip).is_empty() and world._navigation.geometry_error.is_empty(),"retry of repaired B clears its scoped error and commits")
	if to_b.ok:await wait_optional_navigation("repaired B")
	check(world._navigation.find_path(Vector3(298,.05,4),Vector3(302,.05,4)).ok,"repaired B has usable navigation")
	check(deferred._admission.worker_limit==interactive_workers and deferred._admission.byte_limit==admission_bytes,"successful retry restores the same interactive worker capacity and memory quota")
	check(world._map_root.get_instance_id()==original_map and world._transfer_loader==null and world._map_root.get_meta("stream_sources",{}).is_empty(),"failure, independent transfer and retry retain one map with no leaked pins")
	check(callbacks==2 and FileAccess.get_sha256(path)==source_sha,"only successful destinations call commit gate and source map is unchanged")
	await cleanup_world()
	print("SAME_MAP_TRANSFER_FAILURE_GPU_FINISHED failures=",failures," fixture=",directory)
	quit(1 if failures else 0)
