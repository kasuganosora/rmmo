extends SceneTree
## Real StreamIndex graphs: repeated cell buckets, neighborhood candidates and
## nested spec payloads. Only final ownership is delayed; the map exits now.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
class Errors extends Logger:
	var errors:Array[String]=[]
	var mutex:=Mutex.new()
	func _log_error(function:String,_file:String,_line:int,code:String,rationale:String,_editor_notify:bool,_type:int,_backtraces:Array)->void:
		mutex.lock();errors.append(function+": "+code+" "+rationale);mutex.unlock()
class Journal extends RefCounted:
	var freed:=0
	var off_main:=0
class Owner extends BoxMesh:
	var journal:Journal
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			journal.freed+=1
			if not Thread.is_main_thread():journal.off_main+=1
var failures:Array=[]
var checks:=0
var entries:=4096
var baseline:=false
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func fixture(journal:Journal,narrow:bool=true)->Node3D:
	var specs:Array=[]
	for i:int in entries:
		var mesh:=Owner.new();mesh.journal=journal
		var payload:Array=[]
		for j:int in 64:payload.append([i,j,"payload"])
		var position:=Vector3((i%64)*2,0,(i/64)*2)
		var cell:=Stream.chunk_key(position)
		var extra:={"payload":payload}
		if i%16==8:extra.building={"id":"building_%d"%(i/64)}
		var spec:={"uuid":"source_%d"%i,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,position),"chunk_min":cell,"chunk_max":cell+Vector2i.ONE,"extras":extra}
		if i==entries-1:spec.ground_batch_record={"kind":"box","surface_id":"ground","size":[128,1,128]}
		specs.append(spec)
	var data:=Index.build(specs,narrow)
	# Exercise both current narrow neighborhoods and the retained fallback cache.
	var map:=Node3D.new();map.set_meta("stream_library",specs)
	for key:String in data:map.set_meta(key,data[key])
	if narrow:data.stream_collision_neighborhood.candidates(Rect2(-1,-1,6,6))
	Stream._collision_candidates(map,data.stream_collision_index,Vector2i.ZERO,Vector2i.ONE)
	return map
func alive(watch:WeakRef)->bool:return watch.get_ref()!=null
func drain(service:Node)->Dictionary:
	var slices:=0;var maximum:=0;var total:=0;var deadline:=Time.get_ticks_msec()+10000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:
		var began:=Time.get_ticks_usec();service._process(0.);var elapsed:=Time.get_ticks_usec()-began
		service.set_process(false);slices+=1;total+=elapsed;maximum=maxi(maximum,elapsed)
		await process_frame
	check(service.pending.is_empty() and service.known.is_empty(),"all retirement ownership drains")
	return {"slices":slices,"total_us":total,"max_slice_us":maximum}
func borrowed_neighborhood_case(service:Node)->void:
	var original_count:=entries;entries=16
	var journal:=Journal.new();var map:=fixture(journal);root.add_child(map)
	var borrowed:RefCounted=map.get_meta("stream_collision_neighborhood")
	var observed:Dictionary=borrowed.snapshot()
	var candidates:Array=borrowed.candidates(Rect2(-1,-1,6,6))
	var first_id:String=candidates[0].spec.uuid
	Stream.prepare_map_disposal(map,self);service.set_process(false);map.free();map=null
	await drain(service)
	check(journal.freed==0 and borrowed.members.size()==16,"external neighborhood borrower retains all original resources")
	check(borrowed.snapshot().references==observed.references and is_same(candidates,borrowed.candidates(Rect2(-1,-1,6,6))),"borrowed cell and range containers remain unchanged")
	check(candidates[0].spec.uuid==first_id,"borrowed candidate identity and spec remain usable")
	candidates=[];borrowed=null
	check(journal.freed==16 and journal.off_main==0,"external final owner releases each resource normally on main")
	entries=original_count
func coarse_only_case(service:Node)->void:
	var original_count:=entries;entries=16
	var journal:=Journal.new();var map:=fixture(journal,false);root.add_child(map)
	check(not map.has_meta("stream_collision_neighborhood"),"public index fixture has no optional narrow neighborhood")
	Stream.prepare_map_disposal(map,self);service.set_process(false);map.free();map=null
	if not baseline:check(journal.freed==0,"coarse-only indexes also defer their final spec owners")
	await drain(service)
	check(journal.freed==16 and journal.off_main==0,"coarse-only ownership fully drains on main")
	entries=original_count
func run()->void:
	var errors:=Errors.new();OS.add_logger(errors)
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--baseline":baseline=true
		if arg.begins_with("--entries="):entries=int(arg.trim_prefix("--entries="))
	Stream.sliced_index_disposal_enabled=not baseline
	# Isolate mixed index ownership from the independently verified scalar lane.
	Retirement.background_decoded_release_enabled=false
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	var service:=Retirement._service();service.set_process(false)
	var empty:=Node3D.new();root.add_child(empty)
	var empty_index:=Index.build([],true)
	for key:String in empty_index:empty.set_meta(key,empty_index[key])
	Stream.prepare_map_disposal(empty,self);service.set_process(false)
	check(service.pending.is_empty(),"empty spatial indexes add no disposal work")
	empty.free();empty_index={}
	var journal:=Journal.new();var map:=fixture(journal);root.add_child(map)
	var borrowed:Dictionary=map.get_meta("stream_by_id").source_0
	var payload_before:=var_to_bytes(borrowed.extras.payload)
	var map_watch:WeakRef=weakref(map)
	var entry_watch:WeakRef=weakref(map.get_meta("stream_collision_neighborhood").members.source_1)
	var exit_seen:Array=[]
	map.tree_exiting.connect(func():exit_seen.append(map.get_meta("stream_collision_neighborhood").members.size()))
	root.remove_child(map);root.add_child(map);exit_seen.clear()
	check(service.pending.is_empty() and journal.freed==0,"temporary tree handoff starts no retirement")
	var began:=Time.get_ticks_usec();Stream.prepare_map_disposal(map,self);var prepare_us:=Time.get_ticks_usec()-began
	service.set_process(false);var tickets:int=service.pending.size()
	Stream.prepare_map_disposal(map,self);service.set_process(false)
	check(service.pending.size()==tickets,"repeated preparation is idempotent")
	check(journal.freed==0 and map.get_meta("stream_by_id").size()==entries,"preparation preserves live data and resources")
	if not baseline:check(tickets==1,"mixed spatial graph enters one main retirement ticket")
	began=Time.get_ticks_usec();map.free();map=null;var destroy_us:=Time.get_ticks_usec()-began
	var synchronous_releases:=journal.freed
	check(not alive(map_watch) and exit_seen==[entries],"map is destroyed immediately after observers read its complete index")
	if not baseline:
		check(synchronous_releases==0,"map free does not cascade through all indexed resources")
		check(alive(entry_watch),"neighborhood candidates survive until their bounded release phase")
	var before:int=service.profile.private_values
	var release:=await drain(service)
	check(not alive(entry_watch),"unborrowed candidate owners are eventually destroyed")
	check(journal.freed==entries-1 and journal.off_main==0,"every unborrowed mesh releases once on main")
	check(var_to_bytes(borrowed.extras.payload)==payload_before and borrowed.mesh.get_aabb().size==Vector3.ONE,"external spec and nested payload remain usable and unchanged")
	borrowed={}
	check(journal.freed==entries and journal.off_main==0,"last external spec releases its resource normally")
	var units:int=service.profile.private_values-before
	await borrowed_neighborhood_case(service)
	await coarse_only_case(service)
	var original_count:=entries;entries=16
	var shutdown_journal:=Journal.new();var shutdown_map:=fixture(shutdown_journal);root.add_child(shutdown_map)
	Stream.prepare_map_disposal(shutdown_map,self);service.set_process(false);shutdown_map.free();shutdown_map=null
	service.free()
	check(shutdown_journal.freed==16 and shutdown_journal.off_main==0,"shutdown drains the same ownership graph without future frames")
	entries=original_count
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script or engine errors")
	var report:={"checks":checks,"failures":failures,"engine_errors":errors.errors,"baseline":baseline,"entries":entries,"prepare_us":prepare_us,"destroy_us":destroy_us,"synchronous_releases":synchronous_releases,"retirement":release,"retirement_units":units,"contract":"headless component only, not map loading/FPS or renderer cost"}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MAP_SPATIAL_OWNER_RETIREMENT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
