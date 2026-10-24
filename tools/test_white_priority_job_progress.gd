extends "res://tools/test_deferred_backpressure.gd"
## Real workers, acceptance and publication: prepared priority-10 owners must
## release existing slots while a priority-0 atomic building still has work.
## The bound counts publication units, not wall-clock speed or rendered FPS.
const Order=preload("res://scripts/world3d/publication_order.gd")
const LONG_PARTS:=128
const WAITING_OWNERS:=5
const EMPTY_NODE_STEPS:=4 # visit, advance phase, free, finish the spec cursor.
const PROGRESS_UNITS:=(Order.MAX_BURST+1)*WAITING_OWNERS*EMPTY_NODE_STEPS

func long_group_atomic(queue:Queue)->bool:
	var remaining:=0
	for row:Dictionary in queue.pending:
		if row.group_id=="building:owner0":remaining+=1
	return remaining in [0,LONG_PARTS]

func short_group_published(queue:Queue)->bool:
	for number:int in range(1,WAITING_OWNERS+1):
		if queue.group_is_published("building:owner%d"%number):return true
	return false

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	var old_white:bool=controls.white_materials;var old_discard:bool=controls.discard_map_textures
	controls.white_materials=true;controls.discard_map_textures=true
	var rows:Array=[];var compact:Array=[];var groups:Dictionary={}
	for number:int in 7:
		var group:="building:owner%d"%number;var members:Array=[]
		for part:int in LONG_PARTS if number==0 else 1:
			var row:=item("owner%d_part%d"%[number,part],float(part if number==0 else 1000+number),10,"reference:"+group)
			row.group_id=group;members.append(compact.size());compact.append(row.record);rows.append(row)
		groups[group]={"members":members}
	var f:=fixture(rows);var queue:Queue=f.queue
	queue._reference_index={"groups":groups,"extras":{"rmmo_records":compact}}
	queue.set_demand("background",AABB(Vector3(-2000,-1,-1),Vector3(4000,3,3)),10)
	queue.set_demand("near",AABB(Vector3(-1,-1,-1),Vector3(LONG_PARTS+2,3,3)),0)
	queue.set_process(false);queue._admission.worker_limit=6;queue.paused=true
	for i:int in 20:await tick(queue)
	check(queue.ready_job_limit==0 and queue._job_limit()==6 and queue._jobs.size()==6 and queue.started.size()==6,"production default admits exactly six results without widening capacity")
	check(queue.started[0]=="reference:building:owner0" and not queue.started.has("reference:building:owner6"),"the long nearby owner is admitted first and the seventh producer has not started")
	check(queue._jobs.values().all(func(job):return job.get("accepted",false)) and queue._admission.active_workers()==0,"six finished results occupy the slots with no running producer")
	check(queue._path_priority("reference:building:owner0")==0 and queue._path_priority("reference:building:owner1")==10,"the fixture exercises distinct nearby and distant visual priorities")
	var atomic:=true;var first_short_units:=-1
	var began_units:int=int(queue.profile.get("publication_units",0))
	var deadline:=Time.get_ticks_msec()+30000
	queue.paused=false
	while int(queue.profile.get("publication_units",0))-began_units<=PROGRESS_UNITS and Time.get_ticks_msec()<deadline:
		await tick(queue)
		atomic=atomic and long_group_atomic(queue)
		if first_short_units<0 and short_group_published(queue):first_short_units=int(queue.profile.get("publication_units",0))-began_units
		if queue.started.has("reference:building:owner6"):break
	check(first_short_units>0 and first_short_units<=PROGRESS_UNITS,"WORK: an already accepted distant owner publishes within a bounded number of service units")
	check(not queue.group_is_published("building:owner0") and queue._jobs.has("reference:building:owner0"),"the nearby owner still has unfinished work when the distant owner releases its slot")
	check(queue.started.has("reference:building:owner6"),"WORK: a seventh producer starts through an existing slot while nearby work remains ready")
	deadline=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		atomic=atomic and long_group_atomic(queue)
		if queue.is_complete():break
	check(atomic and queue.is_complete() and groups.keys().all(func(group):return queue.group_is_published(group)),"all seven groups complete and the large building remains atomic throughout")
	var starts:Dictionary={}
	for path:String in queue.started:starts[path]=int(starts.get(path,0))+1
	check(starts.size()==7 and starts.values().all(func(count_):return count_==1),"every source prepares exactly once without cancellation or readmission churn")
	check(f.document.calls.size()==LONG_PARTS+6 and f.document.calls.values().all(func(count_):return count_==1) and int(queue.profile.instances)==LONG_PARTS+6,"all demanded components construct and publish exactly once")
	check(int(queue.profile.max_total_jobs)<=6 and queue._admission.peak_workers<=6 and queue._jobs.is_empty() and queue._admission.active_workers()==0 and queue._admission.reserved_bytes==0,"progress retains six jobs and six workers and finishes with zero owners or retained bytes")
	await queue.quiesce();f.map.free()
	controls.white_materials=old_white;controls.discard_map_textures=old_discard
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("WHITE_PRIORITY_JOB_PROGRESS passed=",passed," failures=",failed," first_short_units=",first_short_units," bound=",PROGRESS_UNITS)
	quit(0 if failed==0 else 1)
