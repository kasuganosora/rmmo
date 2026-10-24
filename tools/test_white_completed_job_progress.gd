extends "res://tools/test_deferred_backpressure.gd"
## Real workers/acceptance/publication with six complete-result slots. One
## large atomic building must not monopolise white publication ahead of five
## already prepared small buildings and their not-yet-started successor.
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	var old_white:bool=controls.white_materials;var old_discard:bool=controls.discard_map_textures
	controls.white_materials=true;controls.discard_map_textures=true
	var rows:Array=[];var compact:Array=[];var groups:Dictionary={}
	for number:int in 7:
		var group:="building:owner%d"%number;var members:Array=[]
		for part:int in 64 if number==0 else 1:
			var row:=item("owner%d_part%d"%[number,part],float(part if number==0 else 100+number),10,"reference:"+group)
			row.group_id=group;members.append(compact.size());compact.append(row.record);rows.append(row)
		groups[group]={"members":members}
	var f:=fixture(rows);var queue:Queue=f.queue
	queue._reference_index={"groups":groups,"extras":{"rmmo_records":compact}}
	# Rank by distance from the origin, not fixture()'s broad positive-X box
	# centre (which would load the six small groups before the large one).
	queue.set_demand("background",AABB(Vector3(-1000,-1,-1),Vector3(2000,3,3)),10);queue.set_process(false)
	queue._admission.worker_limit=6;queue.paused=true
	for i:int in 20:await tick(queue)
	check(queue._job_limit()==6 and queue._jobs.size()==6 and queue.started.size()==6,"production default holds exactly six results with the seventh path still waiting")
	check(queue.started[0]=="reference:building:owner0" and not queue.started.has("reference:building:owner6"),"large nearest group is accepted first and the seventh producer has never started")
	check(queue._jobs.values().all(func(job):return job.get("accepted",false)) and queue._admission.active_workers()==0,"all six results are already accepted and no worker is keeping a slot busy")
	queue.paused=false
	for i:int in 12:await tick(queue)
	check(not queue.group_is_published("building:owner0"),"large building still owns an unfinished atomic group")
	check(queue.group_is_published("building:owner1"),"WORK: an already ready small white building receives service before the large group finishes")
	check(queue.started.has("reference:building:owner6"),"WORK: consuming a small result frees an existing slot for the seventh producer without widening the queue")
	var atomic:=true;var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		var remaining:=0
		for row:Dictionary in queue.pending:
			if row.group_id=="building:owner0":remaining+=1
		if remaining not in [0,64]:atomic=false
		if queue.is_complete():break
	check(atomic and queue.is_complete() and groups.keys().all(func(group):return queue.group_is_published(group)),"every building remains atomic and every demanded group completes")
	check(f.document.calls.size()==70 and f.document.calls.values().all(func(n):return n==1) and queue.started.size()==7,"all seventy components publish once and each of seven sources prepares once")
	check(int(queue.profile.max_total_jobs)<=6 and queue._admission.peak_workers<=6 and queue._admission.reserved_bytes==0,"progress preserves six total slots, six workers, and final zero retained bytes")
	await queue.quiesce();f.map.free()
	controls.white_materials=old_white;controls.discard_map_textures=old_discard
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("WHITE_COMPLETED_JOB_PROGRESS passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
