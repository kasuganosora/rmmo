extends SceneTree
## Object-free decoded metadata shares author definitions with mixed runtime
## specs. It must outlive MAIN owners and retire on the existing CPU lane.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
class Journal extends RefCounted:
	var freed:=0
	var off_main:=0
class MeshOwner extends BoxMesh:
	var journal:Journal
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			journal.freed+=1
			if not Thread.is_main_thread():journal.off_main+=1
var failures:Array[String]=[]
var checks:=0
var count:=128
var raw:=PackedByteArray()
var baseline:=false
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func fixture(journal:Journal,marked:bool)->Node3D:
	var records:Array=[];var specs:Dictionary={}
	for i in count:
		# Production package decoder, with Objects disabled. Every definition
		# has independent decoded storage, not a synthetic shallow duplicate.
		var record:Dictionary=bytes_to_var(raw)
		record.uuid="pavement_test_%d"%i
		record.position=[0.,0.,0.];record.rotation=[0.,0.,0.];record.size=[16.,.2,16.]
		var owner:=MeshOwner.new();owner.journal=journal
		specs[record.uuid]={"uuid":record.uuid,"ground_batch_record":record,"mesh":owner}
		records.append(record)
	var map:=Node3D.new()
	map.set_meta("extras",{"rmmo_records":records,"environment":{"preset":"day"}})
	map.set_meta("stream_by_id",specs);map.set_meta("stream_library",specs.values())
	map.set_meta("stream_prop_index",{})
	if marked:map.set_meta("runtime_record_metadata_cpu_only",true)
	return map
func cpu_only(value:Variant)->bool:
	if value is Object or value is Callable or value is RID:return false
	if value is Array:
		for item:Variant in value:
			if not cpu_only(item):return false
	elif value is Dictionary:
		for key:Variant in value:
			if not cpu_only(key) or not cpu_only(value[key]):return false
	return true
func drain(service:Node)->Dictionary:
	var max_main:=0;var main_sum:=0;var slices:=0
	var started:=Time.get_ticks_usec();var deadline:=Time.get_ticks_msec()+15000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:
		var began:=Time.get_ticks_usec()
		# Positive budget is the running-game path. Zero requests a shutdown
		# drain and joins live CPU workers, which would invalidate this measure.
		if service._advance(service.pending[0],1000):service._finish_front()
		var elapsed:=Time.get_ticks_usec()-began
		main_sum+=elapsed;max_main=maxi(max_main,elapsed);slices+=1
		service.set_process(false)
		await process_frame
	check(service.pending.is_empty() and service.known.is_empty(),"all mixed and decoded owners drain")
	return {"max_main_us":max_main,"main_sum_us":main_sum,"slices":slices,"wall_us":Time.get_ticks_usec()-started}
func case_(marked:bool,background:bool)->Dictionary:
	Retirement.background_decoded_release_enabled=background
	var service:=Retirement._service();service.set_process(false)
	var journal:=Journal.new();var map:=fixture(journal,marked);root.add_child(map)
	var borrowed:Dictionary=map.get_meta("extras").rmmo_records[0]
	var digest:=var_to_bytes(borrowed)
	var seen:Array=[]
	map.tree_exiting.connect(func():seen.append(map.get_meta("extras").rmmo_records.size()))
	root.remove_child(map);root.add_child(map);seen.clear()
	check(service.pending.is_empty(),"temporary tree handoff does not enqueue retirement")
	var began:=Time.get_ticks_usec();Stream.prepare_map_disposal(map,self);var prepare_us:=Time.get_ticks_usec()-began
	service.set_process(false)
	var ticket_count:int=service.pending.size()
	Stream.prepare_map_disposal(map,self);service.set_process(false)
	check(service.pending.size()==ticket_count,"permanent preparation remains idempotent")
	var want_cpu:bool=marked and background and Stream.cpu_record_metadata_retirement_enabled
	var last:Dictionary=service.pending.back()
	check((last.kind=="cpu_geometry")==want_cpu,"decoded metadata uses CPU only with producer proof and available lane")
	if want_cpu:
		check(last.kind=="cpu_geometry" and is_same(last.values[0],map.get_meta("extras")),"one final CPU ticket owns original metadata without deep copies")
		if last.kind=="cpu_geometry":check(cpu_only(last.values),"CPU ticket has no Object RID or Callable anywhere")
		check(service.pending[0].kind=="private_array","MAIN owners precede final decoded metadata release")
	var watch:WeakRef=weakref(map)
	began=Time.get_ticks_usec();map.free();map=null;var destroy_us:=Time.get_ticks_usec()-began
	check(watch.get_ref()==null and seen==[count],"map dies immediately after exit observers read intact records")
	var before:int=service.profile.private_values
	var batches_before:int=int(service.profile.get("geometry_batches",0))
	var timing:Dictionary=await drain(service)
	check(journal.freed==count and journal.off_main==0,"all Resource leaves release exactly once on main")
	check(var_to_bytes(borrowed)==digest,"external decoded record borrower remains intact")
	if want_cpu:check(int(service.profile.get("geometry_batches",0))==batches_before+1 and int(service.profile.get("geometry_last_thread_id",0))!=OS.get_thread_caller_id(),"one decoded batch actually runs off main")
	var result:={"marked":marked,"background":background,"entries":count,"prepare_us":prepare_us,"destroy_us":destroy_us,"retirement":timing,"private_units":service.profile.private_values-before,"cpu_batches":int(service.profile.get("geometry_batches",0))-batches_before,"cpu_worker_us":int(service.profile.get("geometry_worker_us",0))}
	borrowed={};service.free()
	return result
func load_input()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--baseline":baseline=true
		if arg.begins_with("--entries="):count=int(arg.trim_prefix("--entries="))
		if arg.begins_with("--record-file="):
			var bytes:=FileAccess.get_file_as_bytes(arg.trim_prefix("--record-file="))
			assert(bytes.slice(0,8).get_string_from_ascii()=="RMMORES1")
			raw=bytes.slice(16).decompress(bytes.decode_u64(8),FileAccess.COMPRESSION_ZSTD)
	if raw.is_empty():
		var points:Array=[]
		for i in 1024:points.append([float(i),float(i%17),0.])
		raw=var_to_bytes({"road_mesh":{"points":points},"surface_paint":[{"id":"stone"}]})
func run()->void:
	load_input()
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	Stream.cpu_record_metadata_retirement_enabled=not baseline
	var measured:Dictionary=await case_(true,true)
	var saved:=count;count=4
	await case_(false,true)
	await case_(true,false)
	count=saved
	var report:={"checks":checks,"failures":failures,"baseline":baseline,"decoded_bytes_each":raw.size(),"measured":measured,"scope":"headless lifetime component; no map/FPS claim"}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MAP_DECODED_RECORD_RETIREMENT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
