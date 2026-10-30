extends "res://tools/profile_axel_hud.gd"
## Full game ownership round trip, using only an external temporary landing map.
## This tests complete map retirement; kilometre building visibility means a
## same-town move alone cannot prove that the guild native graph was released.
var _lifecycle_started:=false
var _lifecycle_done:=false
var _landing_map:=""
var _landing_sha:=""

func _initialize()->void:
	var destination:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):destination=arg.trim_prefix("--output=").replace("\\","/")
	if not destination.begins_with(TEST_ROOT+"/"):quit(2);return
	_landing_map=destination.get_base_dir().path_join("landing/map.gltf")
	DirAccess.make_dir_recursive_absolute(_landing_map.get_base_dir())
	var doc:=preload("res://scripts/world3d/world_document.gd").new()
	doc.add_box("landing",Vector3(0,-.25,0),Vector3(64,.5,64))
	doc.map_meta.spawn=[0.,.9,0.]
	if doc.save(_landing_map)!=OK:printerr("temporary landing save failed");quit(2);return
	_landing_sha=FileAccess.get_sha256(_landing_map)
	super._initialize()

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_native_lifecycle.gd"]=FileAccess.get_sha256("res://tools/profile_axel_native_lifecycle.gd")
	return result

func runtime_observation_finished()->bool:return _lifecycle_done

func _run_ui_schedule(world:Node)->void:
	if _lifecycle_started or (Time.get_ticks_usec()-began)/1000.-float(report.full_ready.at_ms)<5000.:return
	_lifecycle_started=true
	_round_trip.call_deferred(world)

func _settled(world:Node)->bool:
	if not world.is_world_ready() or world._transfer_pending:return false
	var map:Node=world._map_root
	var queue:Node=map.get_node_or_null("DeferredAssets")
	if queue!=null and (not queue._demanded_by_id.is_empty() or not queue._jobs.is_empty()):return false
	if not map.has_meta("stream_chunk") or not map.get_meta("stream_jobs",[]).is_empty() or not map.get_meta("stream_append_pending",[]).is_empty():return false
	var batches:Node=map.get_node_or_null("GroundRenderBatches")
	return batches==null or (batches._preparation.is_empty() and batches.pending.is_empty() and batches._workers.is_empty())

func _wait_settled(world:Node,label:String)->void:
	var start:=Time.get_ticks_msec();var stable:=0
	while Time.get_ticks_msec()-start<180000:
		await process_frame
		stable=stable+1 if _settled(world) else 0
		if stable>=3:break
	check(stable>=3,label+" current demand and publication settle")
	report.lifecycle.append({"label":label,"settled":stable>=3,"wait_ms":Time.get_ticks_msec()-start,"at_ms":(Time.get_ticks_usec()-began)/1000.})

func _transfer(world:Node,path:String,destination:Vector3,label:String)->bool:
	phase=label
	var started:=Time.get_ticks_usec()
	var ok:bool=await world.transfer_map(path,destination)
	report.lifecycle.append({"label":label,"ok":ok,"started_us":started,"finished_us":Time.get_ticks_usec(),"call_ms":(Time.get_ticks_usec()-started)/1000.,"at_ms":(Time.get_ticks_usec()-began)/1000.,"cover":world.get_meta("transfer_loading_profile",{}).duplicate(true)})
	check(ok,label+" ordinary game transfer succeeds")
	if not ok:return false
	for i in 12:await physics_frame
	check(not world._player.input_locked and not world._player.geometry_blocked and world._player.is_on_floor(),label+" avatar remains supported and usable")
	return true

func _round_trip(world:Node)->void:
	report.lifecycle=[]
	report.lifecycle_clock_origin_us=began
	report.actual_scope="Full textured game with ordinary HUD/avatar. Current demand settles, then normal cross-map transfer to a private landing map, complete old-map retirement, and normal return to identical saved town. Does not claim same-map chunk eviction or walking coverage."
	var original:Vector3=world._player.global_position
	var previous_map:WeakRef=weakref(world._map_root)
	var previous_queue:WeakRef=weakref(world._map_root.get_node_or_null("DeferredAssets"))
	if not await _transfer(world,_landing_map,Vector3(0,.9,0),"map_unload"):_lifecycle_done=true;return
	phase="unloaded_settle"
	await _wait_settled(world,"landing")
	await create_timer(12.).timeout
	check(previous_map.get_ref()==null and previous_queue.get_ref()==null,"old town and deferred owner actually freed before return")
	report.old_owners_freed=previous_map.get_ref()==null and previous_queue.get_ref()==null
	if not await _transfer(world,selected_map,original,"map_return"):_lifecycle_done=true;return
	phase="return_loading"
	await _wait_settled(world,"return")
	report.return_map_profile=world._map_root.get_meta("load_profile",{}).duplicate(true)
	phase="return_steady"
	await create_timer(15.).timeout
	check(FileAccess.get_sha256(_landing_map)==_landing_sha,"temporary landing remains unchanged")
	_lifecycle_done=true

func finish(code:int)->void:
	if code==0:check(_lifecycle_done,"native lifecycle completed within observation window")
	await super.finish(code if report.failures.is_empty() else 1)
