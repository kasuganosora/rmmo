extends SceneTree
## The production append-index producer creates scalar bookkeeping; mesh/spec
## owners beside it must remain on main. Only temporary test maps are used.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var failures:Array=[]
var checks:=0
var rows:Array=[]
class Journal extends RefCounted:
	var freed:=0
	var off_main:=0
class Owner extends Resource:
	var journal:Journal
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			journal.freed+=1
			if not Thread.is_main_thread():journal.off_main+=1
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func pure(value:Variant)->bool:
	if value is Object or value is RID or value is Callable or value is Signal:return false
	if value is Dictionary:
		for key:Variant in value:
			if not pure(key) or not pure(value[key]):return false
	elif value is Array:
		for child:Variant in value:
			if not pure(child):return false
	return true
func make_map(count:int,journal:Journal)->Node3D:
	var specs:Array=[];var known:Dictionary={};var spatial:Dictionary={}
	for i in count:
		var id:="model%d__part%d"%[i/16,i%16];var cell:=Vector2i(i/32,i%32)
		specs.append({"uuid":id,"chunk_min":cell,"chunk_max":cell+Vector2i.ONE})
		known[id]=true;spatial[cell]=[id]
	var state:=Index._append_state(specs,{},[])
	var map:=Node3D.new();map.set_meta("stream_append_state",state)
	map.set_meta("stream_known",known);map.set_meta("stream_index",spatial)
	var owner:=Owner.new();owner.journal=journal
	map.set_meta("stream_by_id",{"retained_mesh_owner":owner})
	return map
func drain(service:Node)->void:
	var deadline:=Time.get_ticks_msec()+10000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:
		service._process(0.);await process_frame
	check(service.pending.is_empty() and service.known.is_empty(),"scalar-index retirement completes within its ordinary queue")
func trial(enabled:bool)->void:
	Retirement.background_decoded_release_enabled=enabled
	var journal:=Journal.new();var map:=make_map(32768,journal);root.add_child(map)
	check(pure(map.get_meta("stream_append_state")) and pure(map.get_meta("stream_known")) and pure(map.get_meta("stream_index")),"actual index producer emits no Object/RID/Callable owners in the selected scalar fields")
	var service:=Retirement._service();service.set_process(false)
	var observed:Array=[]
	map.tree_exiting.connect(func():observed.append(map.get_meta("stream_known").size()))
	var before_batches:int=service.profile.get("geometry_batches",0)
	var before_worker:int=service.profile.get("geometry_worker_us",0)
	var began:=Time.get_ticks_usec();Stream.prepare_map_disposal(map,self);service.set_process(false)
	var prepared:=Time.get_ticks_usec()
	check(service.pending.size()==(1 if enabled else 0),"permanent disposal hands all three scalar index roots to one existing CPU ticket")
	Stream.prepare_map_disposal(map,self)
	check(service.pending.size()==(1 if enabled else 0),"repeated disposal does not enqueue the same index twice")
	map.free();map=null
	var destroyed:=Time.get_ticks_usec()
	check(observed==[32768],"exit callbacks still read the exact complete index")
	check(journal.freed==1 and journal.off_main==0,"mixed spec/resource metadata keeps its main-thread destructor")
	await drain(service)
	var batches:int=int(service.profile.get("geometry_batches",0))-before_batches
	check(batches==(1 if enabled else 0),"no extra task per cell or namespace is introduced")
	if enabled:check(batches==1 and int(service.profile.get("geometry_last_thread_id",-1))!=OS.get_main_thread_id(),"final scalar-container release runs on an actual background worker")
	rows.append({"enabled":enabled,"entries":32768,"prepare_us":prepared-began,"destroy_us":destroyed-prepared,"main_total_us":destroyed-began,"worker_us":int(service.profile.get("geometry_worker_us",0))-before_worker,"batches":batches})
func borrower_case()->void:
	Retirement.background_decoded_release_enabled=true
	var journal:=Journal.new();var map:=make_map(64,journal);root.add_child(map)
	var state:Dictionary=map.get_meta("stream_append_state");var expected:=var_to_bytes(state)
	var service:=Retirement._service();service.set_process(false)
	Stream.prepare_map_disposal(map,self);service.set_process(false);map.free();map=null
	await drain(service)
	check(var_to_bytes(state)==expected,"retirement only drops its reference and never clears a surviving borrowed index")
func run()->void:
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	var previous:=Retirement.background_decoded_release_enabled
	for enabled:bool in [false,true,true,false]:await trial(enabled)
	await borrower_case();Retirement.background_decoded_release_enabled=previous
	var report:={"checks":checks,"failures":failures,"trials":rows,"contract":"ABBA scalar-container release fixture, not a full-map loading or FPS benchmark; mixed resources remain on main."}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MAP_INDEX_RETIREMENT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
