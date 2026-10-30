extends SceneTree
## Reproduce nested source ownership retained until the retired navigation dies.
## The flat list contains GPU-capable Resource owners: only pure geometry may
## move to a CPU worker; source records must retire on budgeted main slices.
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
class Journal extends RefCounted:
	var released:=0
	var off_main:=0
class Owner extends Resource:
	var journal:Journal
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			journal.released+=1
			if not Thread.is_main_thread():journal.off_main+=1
var checks:=0
var failures:Array=[]
var output:=""
var timings:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func populate(nav:Node,journal:Journal,count:int)->Array:
	var retained:Array=[]
	for i in count:
		var owner:=Owner.new();owner.journal=journal
		var heights:Array=[]
		for j in 512:heights.append(float(i+j))
		var record:={"uuid":"part_%d"%i,"owner":owner,"extras":{"terrain_mesh":{"heights":heights}}}
		nav._spec_snapshot.append(record);nav._spec_ids[record.uuid]=record
		if i%32==0:nav._doors.append(record)
		if i==0:retained.append(record)
	return retained
func asynchronous_owners(service:Node)->void:
	var journal:=Journal.new();var nav:=Navigation.new();nav.streaming_geometry=true;root.add_child(nav)
	var shared:Array=populate(nav,journal,3)
	var borrowed_snapshot:Array=nav._spec_snapshot
	# Reproduce a stale lazy snapshot and a later append absent from that snapshot.
	nav._spec_ids.erase("part_2");nav._spec_snapshot_dirty=true
	var later:=Owner.new();later.journal=journal
	nav._spec_ids.later={"uuid":"later","owner":later};later=null
	var door:=Owner.new();door.journal=journal
	nav._doors.append({"uuid":"door_only","owner":door});door=null
	var gate:=Semaphore.new();nav._face_worker=Thread.new()
	check(nav._face_worker.start(func():gate.wait();return PackedVector3Array())==OK,"start an unfinished source worker")
	check(nav.retire_background("worker_pending"),"retirement accepts an active worker without joining")
	nav.set_process(false);nav._process(0.)
	check(not nav.is_queued_for_deletion() and journal.released==0 and service.pending.is_empty(),"worker consumers keep all source owners until completion")
	gate.post()
	while nav._face_worker.is_alive():await process_frame
	nav._process(0.);nav=null;service.set_process(false)
	await process_frame;await process_frame
	check(borrowed_snapshot.size()==3 and shared[0].extras.terrain_mesh.heights.size()==512,"retirement does not pop a shared source snapshot")
	var deadline:=Time.get_ticks_msec()+10000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:
		service._process(0.);await process_frame
	check(service.pending.is_empty() and journal.released==2,"catalogue-only and door-only owners drain despite stale snapshot")
	borrowed_snapshot=[];shared=[]
	check(journal.released==5 and journal.off_main==0,"all stale/current/shared owners release exactly once on main")
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	Budget.enabled=false
	var service:Node=Retirement._service();service.set_process(false)
	var journal:=Journal.new();var nav:=Navigation.new();nav.streaming_geometry=true;root.add_child(nav)
	var borrowed:Array=populate(nav,journal,1536);var watch:WeakRef=weakref(nav)
	var started:=Time.get_ticks_usec()
	check(nav.retire_background("test"),"normal retired navigation accepts ownership handoff")
	check(not nav.ready_for_queries and not nav.fully_ready,"navigation queries are revoked immediately")
	nav._process(0.);nav=null;service.set_process(false)
	await process_frame;await process_frame
	timings.retire_wall_us=Time.get_ticks_usec()-started
	check(watch.get_ref()==null,"navigation Node disappears without retaining a fake live map")
	check(journal.released==0 and not service.pending.is_empty(),"nested source owners survive Node deletion in explicit bounded retirement")
	check(not service.pending.is_empty() and service.pending[0].values.size()==1536+48,"current snapshot does not enqueue every catalogue record twice")
	check(borrowed[0].extras.terrain_mesh.heights.size()==512,"surviving borrower is never recursively cleared")
	var drained:=Time.get_ticks_usec();var slices:=0;var max_slice:=0
	while not service.pending.is_empty() and Time.get_ticks_usec()-drained<10000000:
		var before:=Time.get_ticks_usec();service._process(0.);max_slice=maxi(max_slice,Time.get_ticks_usec()-before);slices+=1
		await process_frame
	timings.drain_us=Time.get_ticks_usec()-drained;timings.slices=slices;timings.max_slice_us=max_slice
	check(service.pending.is_empty(),"every transferred owner eventually drains")
	check(journal.released==1535,"external borrower keeps exactly its one resource")
	check(slices>1,"source owner finalizers are distributed over multiple budget slices")
	check(journal.off_main==0,"GPU-capable source owners are never finalized on a worker")
	borrowed.clear()
	check(journal.released==1536,"last external borrower releases normally")
	await asynchronous_owners(service)
	print(JSON.stringify({"checks":checks,"failures":failures,"timings":timings}))
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"timings":timings},"\t"))
	quit(0 if failures.is_empty() else 1)
