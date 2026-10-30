extends SceneTree
## Runtime records may contain resource owners; release them in main-thread
## slices without clearing the metadata seen by exit callbacks or borrowers.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
class Journal extends RefCounted:
	var freed:=0
	var off_main:=0
class Owner extends Resource:
	var journal:Journal
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			journal.freed+=1
			if not Thread.is_main_thread():journal.off_main+=1
var failures:Array=[]
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func make_map(journal:Journal)->Node3D:
	var map:=Node3D.new();var records:Array=[]
	for i in 768:
		var heights:Array=[]
		for j in 1024:heights.append(float(i+j))
		var owner:=Owner.new();owner.journal=journal
		records.append({"uuid":"record_%d"%i,"owner":owner,"terrain":{"heights":heights}})
	map.set_meta("extras",{"rmmo_records":records,"spawn":[0.,.9,0.]})
	return map
func run()->void:
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	var service:Node=Retirement._service();service.set_process(false)
	var journal:=Journal.new();var map:=make_map(journal);root.add_child(map)
	var borrower:Dictionary=map.get_meta("extras").rmmo_records[0]
	var exit_observed:Array=[]
	map.tree_exiting.connect(func():exit_observed.append(map.get_meta("extras").rmmo_records.size()))
	Stream.prepare_map_disposal(map,self);service.set_process(false)
	check(service.pending.size()==1,"permanent disposal hands runtime records to one retirement ticket")
	Stream.prepare_map_disposal(map,self)
	check(service.pending.size()==1,"repeated disposal does not enqueue duplicate records")
	var start:=Time.get_ticks_usec();map.free();map=null
	var destroy_us:=Time.get_ticks_usec()-start
	check(exit_observed==[768],"exit callbacks still see the original metadata")
	check(journal.freed==0,"Node destruction does not synchronously destroy all nested records")
	var slices:=0;var max_slice:=0;var deadline:=Time.get_ticks_msec()+10000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:
		start=Time.get_ticks_usec();service._process(0.);max_slice=maxi(max_slice,Time.get_ticks_usec()-start);slices+=1
		await process_frame
	check(service.pending.is_empty() and service.known.is_empty(),"record retirement drains every ticket")
	check(journal.freed==767 and journal.off_main==0,"resource owners release once on main while shared record survives")
	check(borrower.terrain.heights[1023]==1023.,"shared nested record remains unchanged")
	check(slices>1,"large record set finalizes across multiple slices")
	borrower={}
	check(journal.freed==768 and journal.off_main==0,"the final external borrower releases normally")
	var report:={"checks":checks,"failures":failures,"destroy_us":destroy_us,"slices":slices,"max_slice_us":max_slice}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
