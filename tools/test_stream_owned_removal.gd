extends "res://tools/test_stream_child_adoption.gd"
## Exercise the real slow-source yield, not just the child-count helper.
class SlowBatch:
	extends Node3D
	var groups:Dictionary={}
	var _member_groups:Dictionary={}
	var delay_usec:=11000
	func retire_sources(_nodes:Array,_suspended:Dictionary={})->void:
		if delay_usec>0:OS.delay_usec(delay_usec)

const FAR:=Vector3(8192,0,8192)
func unloading_fixture(count:int)->Node3D:
	var map:=fixture(count);tick(map)
	var batch:=SlowBatch.new();batch.name="GroundRenderBatches";batch.set_meta("stream_instance",true);map.add_child(batch)
	var library:Array=map.get_meta("stream_library")
	for i:int in 2:library[i].native_visual=false
	map.remove_meta("stream_chunk");map.set_meta("stream_target",Stream.chunk_key(FAR))
	map.set_meta("stream_jobs",[library[0],library[1]]);map.set_meta("stream_cursor",0)
	map.set_meta("stream_collision_priority_origin",FAR)
	map.set_meta("stream_children",map.get_child_count(true))
	return map

func slow_yield()->Dictionary:
	var map:=unloading_fixture(3500)
	var jobs:Array=map.get_meta("stream_jobs")
	var before:=map.get_child_count(true)
	Stream._sync_work(map,map,FAR,1,0,50000)
	check(map.get_child_count(true)==before-1 and int(map.get_meta("stream_cursor"))==1,"slow removal applies once and yields with its cursor saved")
	check(int(map.get_meta("stream_children"))==map.get_child_count(true),"slow-source yield acknowledges its own removed direct child")
	var began:=Time.get_ticks_usec()
	Stream._sync_work(map,map,FAR,1,Time.get_ticks_usec()+1,3000)
	var elapsed:=Time.get_ticks_usec()-began
	var selected:int=map.get_meta("stream_candidates",[]).size()
	check(not map.has_meta("stream_candidates") and is_same(map.get_meta("stream_jobs"),jobs) and int(map.get_meta("stream_cursor"))==2,"next slice retains the exact pending plan and continues the second removal")
	var result:={"resume_us":elapsed,"selected":selected,"cursor":map.get_meta("stream_cursor")}
	map.free()
	return result

func guard_cases()->void:
	for mode:String in ["external_before","explicit_before","external_callback","explicit_callback","nested","body"]:
		var map:=fixture(3);tick(map)
		var meshes:Dictionary=map.get_meta("stream_meshes")
		var spec:Dictionary=map.get_meta("stream_library")[0];spec.native_visual=false
		var count:=map.get_child_count(true)
		if mode=="external_before":meshes.existing1.free()
		if mode=="explicit_before":map.set_meta("stream_children",-1)
		# Node forbids synchronous sibling removal while its parent is busy.
		if mode=="external_callback":meshes.existing0.tree_exiting.connect(func()->void:meshes.existing1.queue_free())
		if mode=="explicit_callback":meshes.existing0.tree_exiting.connect(func()->void:map.set_meta("stream_children",-1))
		if mode=="nested":
			var holder:=Node3D.new();map.add_child(holder);meshes.existing0.reparent(holder)
			map.set_meta("stream_children",map.get_child_count(true));count=map.get_child_count(true)
		var bodies:Dictionary={}
		if mode=="body":
			spec.native_visual=true
			var body:=StaticBody3D.new();map.add_child(body);bodies.existing0=body
			map.set_meta("stream_children",map.get_child_count(true))
		Stream._apply(map,map,spec,Stream._ring_at(Stream.chunk_key(FAR),1),Stream._ring_at(Stream.chunk_key(FAR),2),meshes,bodies)
		if mode=="external_callback":
			await process_frame
			await process_frame
		if mode.begins_with("external"):
			check(int(map.get_meta("stream_children"))>map.get_child_count(true),mode+" remains a detectable owner loss")
			tick(map);check(map.has_meta("stream_candidates") or not map.has_meta("stream_chunk"),mode+" still schedules residency repair")
		elif mode.begins_with("explicit"):
			check(int(map.get_meta("stream_children"))==-1,mode+" keeps explicit invalidation")
		elif mode=="nested":check(int(map.get_meta("stream_children"))==count and map.get_child_count(true)==count,"nested removal does not decrement direct child membership")
		else:check(bodies.is_empty() and int(map.get_meta("stream_children"))==map.get_child_count(true),"a collision body hosted at map root accounts for its own removal")
		map.free()
	# Bodies normally belong to a separate host, which must not affect map membership.
	var map:=fixture(2);tick(map)
	var host:=Node3D.new();root.add_child(host)
	var body:=StaticBody3D.new();host.add_child(body)
	var spec:Dictionary=map.get_meta("stream_library")[0]
	var bodies:Dictionary={"existing0":body};var count:=map.get_child_count(true)
	Stream._apply(map,host,spec,Stream._ring_at(Stream.chunk_key(FAR),1),Stream._ring_at(Stream.chunk_key(FAR),2),map.get_meta("stream_meshes"),bodies)
	check(bodies.is_empty() and int(map.get_meta("stream_children"))==count,"collision removal from a separate host leaves map membership unchanged")
	host.free();map.free()

func removal_benchmark()->Array:
	var results:Array=[]
	for enabled:bool in [false,true,true,false]:
		Stream.owned_removal_accounting_enabled=enabled
		var map:=fixture(3500);tick(map)
		var meshes:Dictionary=map.get_meta("stream_meshes");var library:Array=map.get_meta("stream_library")
		var sync_us:=0;var selected:=0;var apply_us:=0;var maximum:=0
		for i:int in 20:
			reset_settled(map)
			map.set_meta("stream_target",Stream.chunk_key(FAR));map.set_meta("stream_chunk",Stream.chunk_key(FAR))
			var spec:Dictionary=library[i];spec.native_visual=false
			var began:=Time.get_ticks_usec()
			Stream._apply(map,map,spec,Stream._ring_at(Stream.chunk_key(FAR),1),Stream._ring_at(Stream.chunk_key(FAR),2),meshes,{})
			apply_us+=Time.get_ticks_usec()-began
			began=Time.get_ticks_usec();Stream._sync_work(map,map,FAR,1,Time.get_ticks_usec()+1,3000)
			var elapsed:=Time.get_ticks_usec()-began;sync_us+=elapsed;maximum=maxi(maximum,elapsed)
			selected+=map.get_meta("stream_candidates",[]).size()
		check(selected==0 if enabled else selected>69000,"20 owned removals preserve zero rebuild work only with accounting "+str(enabled))
		check(meshes.size()==3480,"each removal is applied exactly once "+str(enabled))
		var began:=Time.get_ticks_usec();map.free()
		results.append({"accounted":enabled,"removals":20,"apply_us":apply_us,"sync_us":sync_us,"max_sync_us":maximum,"selected":selected,"cleanup_us":Time.get_ticks_usec()-began})
	Stream.owned_removal_accounting_enabled=true
	return results

func run()->void:
	Stream.incremental_adoption_enabled=true
	var report:=slow_yield()
	await guard_cases()
	report.trials=removal_benchmark()
	report.checks=checks;report.failures=failures
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STREAM_OWNED_REMOVAL ",JSON.stringify(report))
	quit(1 if failures else 0)
