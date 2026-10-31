extends "res://tools/test_deferred_backpressure.gd"
## Real producer Threads and atomic publication with a fixed four-result cap.
## Service-unit bounds avoid hardware timing assertions and queue enlargement.
const Order=preload("res://scripts/world3d/publication_order.gd")
class GatedQueue extends Queue:
	var gate_path:=""
	var gate:=Semaphore.new()
	func _make_prepare_task(path:String,digest:String,token:RefCounted,row:Dictionary,faces:bool,source_root:String,requests:Array,native:bool,need_model:bool)->Callable:
		var prepare:=super._make_prepare_task(path,digest,token,row,faces,source_root,requests,native,need_model)
		return gated_work.bind(gate,prepare) if path==gate_path else prepare
	static func gated_work(signal_gate:Semaphore,prepare:Callable)->Dictionary:
		signal_gate.wait()
		return prepare.call()

class GraphDocument extends Document:
	func _mesh(record:Dictionary,_effects:bool=true,_timings:Variant=null)->Node3D:
		calls[record.uuid]=int(calls.get(record.uuid,0))+1
		var holder:=Node3D.new()
		for i:int in 4:holder.add_child(Node3D.new())
		return holder

func fixture(rows:Array)->Dictionary:
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",[])
	var index:=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	map.set_meta("extras",{"rmmo_records":[]})
	var queue:=GatedQueue.new();var document:=GraphDocument.new()
	queue._doc=document;queue.pending=rows;queue._reference_root="D:/code/rmmo"
	map.add_child(queue);queue.activate(map);queue._admission.byte_limit=100000
	return {"map":map,"queue":queue,"document":document}

func source_fixture(sizes:Array,delayed:bool=false)->Dictionary:
	var rows:Array=[];var compact:Array=[];var groups:Dictionary={}
	for number:int in sizes.size():
		var group:="building:service%d"%number;var members:Array=[]
		for part:int in sizes[number]:
			var row:=item("service%d_part%d"%[number,part],number*100.+part*.01,10,"reference:"+group)
			row.group_id=group;members.append(compact.size());compact.append(row.record);rows.append(row)
		groups[group]={"members":members}
	var f:=fixture(rows);var queue:GatedQueue=f.queue;f.groups=groups;f.sizes=sizes
	if delayed:queue.gate_path="reference:building:service1"
	queue._reference_index={"groups":groups,"extras":{"rmmo_records":compact}}
	queue.set_demand("background",AABB(Vector3(-1000,-1,-1),Vector3(2000,3,3)),10)
	queue.set_process(false);queue._admission.worker_limit=2;queue.ready_job_limit=4;queue.paused=true
	return f

func measure(sizes:Array,delayed:bool=false)->Dictionary:
	var f:=source_fixture(sizes,delayed);var queue:GatedQueue=f.queue;var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		var accepted:=0
		for job:Dictionary in queue._jobs.values():
			if job.get("accepted",false):accepted+=1
		if queue._jobs.size()==mini(4,sizes.size()) and accepted==mini(4,sizes.size())-int(delayed) and queue._admission.active_workers()==int(delayed):break
	if delayed:
		check(queue.started.size()==4 and queue._admission.active_workers()==1,"one gated worker does not stop its peer preparing three real results")
		queue.paused=false
		for i in 8:await tick(queue)
		check(int(queue.profile.get("publication_units",0))==8 and not queue.group_is_published("building:service0"),"large ready owner makes private progress while another worker is held")
		queue.paused=true;queue.gate.post() # Always release before any cleanup, including failed assertions.
		deadline=Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<deadline:
			await tick(queue)
			if queue._admission.active_workers()==0 and queue._jobs.values().all(func(job):return job.get("accepted",false)):break
	check(queue._jobs.size()==mini(4,sizes.size()) and queue._admission.active_workers()==0,"all initial results joined and accepted with no live worker")
	if sizes.size()>4:
		check(queue._jobs.size()==4 and queue._job_limit()==4 and queue._admission.reserved_bytes==40 and not queue.started.has("reference:building:service4"),"four real completed owners hold the unchanged cap; fifth source remains unstarted")
		if Order.completed_owner_drain_enabled:
			check(queue._completed_owner_pressure(),"real waiting dispatcher enables completion service while worker capacity is spare")
			queue._demand_revision+=1
			check(not queue._completed_owner_pressure(),"stale demand cannot activate completion reordering")
			queue._demand_revision-=1
			var waiter:String=queue._job_cap_waiter;queue._job_cap_waiter=""
			check(not queue._completed_owner_pressure(),"a full result cap without a waiting source is not completion pressure")
			queue._job_cap_waiter=waiter;queue.path_errors[waiter]="fixture error"
			check(not queue._completed_owner_pressure(),"failed waiting source cannot activate completion reordering")
			queue.path_errors.erase(waiter)
	var generations:Dictionary={}
	for path:String in queue._jobs:generations[path]=queue._jobs[path].token.get_instance_id()
	var origin:=int(queue.profile.get("publication_units",0));var first_release:=-1;var next_start:=-1
	var first_path:="";var atomic:=true;var bounded:=true;var legitimate_release:=true
	queue.paused=false;deadline=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		var units:=int(queue.profile.get("publication_units",0))-origin
		if first_release<0:
			for path:String in generations:
				if not queue._jobs.has(path) or queue._jobs[path].token.get_instance_id()!=generations[path]:
					first_release=units;first_path=path;legitimate_release=queue.group_is_published(path.trim_prefix("reference:"));break
		if next_start<0 and queue.started.has("reference:building:service4"):next_start=units
		for number:int in sizes.size():
			var group:="building:service%d"%number;var remaining:=0
			for row:Dictionary in queue.pending:
				if row.get("group_id","")==group:remaining+=1
			if remaining not in [0,int(sizes[number])]:atomic=false
		bounded=bounded and queue._jobs.size()<=4 and queue._admission.reserved_bytes<=queue._admission.byte_limit
		if queue.is_complete():break
	check(first_release>0 and legitimate_release,"first source releases only after its complete atomic publication")
	check(atomic and queue.is_complete() and f.groups.keys().all(func(group):return queue.group_is_published(group)),"all source groups remain atomic and publish completely")
	var starts:Dictionary={};var members:=0
	for path:String in queue.started:starts[path]=int(starts.get(path,0))+1
	for size:int in sizes:members+=size
	check(f.document.calls.size()==members and f.document.calls.values().all(func(n):return n==1) and starts.size()==sizes.size() and starts.values().all(func(n):return n==1),"every source prepares once and every member constructs once")
	check(bounded and int(queue.profile.max_total_jobs)<=4 and queue._admission.peak_workers<=2 and queue._jobs.is_empty() and queue._admission.reserved_bytes==0,"two workers and four-result/byte caps remain unchanged; all leases release")
	var result:={"members":sizes,"delayed":delayed,"first_release_units":first_release,"first_path":first_path,"next_start_units":next_start,"total_units":int(queue.profile.get("publication_units",0)),"units_before_arrival":origin}
	print("COMPLETED_RESULT_SERVICE ",JSON.stringify(result))
	await queue.quiesce();f.map.free();return result

func cancel_return_case()->void:
	var f:=source_fixture([16,1,16,16,1]);var queue:GatedQueue=f.queue
	var commits:Array=[0]
	queue.published.connect(func(_specs):commits[0]+=1)
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		if queue._jobs.size()==4 and queue._admission.active_workers()==0 and queue._jobs.values().all(func(job):return job.get("accepted",false)):break
	queue.paused=false
	for i in 6:await tick(queue)
	check(commits[0]==0 and f.document.calls.size()==1,"cancellation fixture has one private instance but no visible partial building")
	var old_tokens:Dictionary={}
	for path:String in queue._jobs:old_tokens[path]=queue._jobs[path].token.get_instance_id()
	queue.release_demand("background")
	deadline=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		if queue._jobs.is_empty():break
	check(queue._jobs.is_empty() and queue._admission.reserved_bytes==0 and queue.pending_count()==50 and commits[0]==0,"lost demand discards every private result and lease while preserving unpublished membership")
	check(int(queue.profile.get("instance_work_cancelled_stages",0))==1,"private cursor is disposed once on cancellation")
	queue.set_demand("background",AABB(Vector3(-1000,-1,-1),Vector3(2000,3,3)),10)
	deadline=Time.get_ticks_msec()+15000;var fresh:=true
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		for path:String in queue._jobs:
			fresh=fresh and queue._jobs[path].token.get_instance_id()!=int(old_tokens.get(path,0))
		if queue.is_complete():break
	check(fresh and queue.is_complete() and commits[0]==5 and int(queue.profile.instances)==50,"return uses fresh generations and commits all five complete groups exactly once")
	var constructions:=0
	for count:int in f.document.calls.values():constructions+=count
	check(constructions==51 and f.document.calls.size()==50,"return rebuilds only the cancelled private instance; no published member duplicates")
	check(queue._admission.reserved_bytes==0 and int(queue.profile.max_total_jobs)<=4,"return preserves result cap and releases every replacement lease")
	await queue.quiesce();f.map.free()

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var trace_enabled:bool="--trace-queue-latency" in OS.get_cmdline_user_args()
	if trace_enabled:Deferred.CompletedTrace.start()
	var selector:Script=Order;var candidate:Variant=selector.get("completed_owner_drain_enabled")
	if candidate!=null:selector.set("completed_owner_drain_enabled",not "--baseline" in OS.get_cmdline_user_args())
	var single:=await measure([1]);var full:=await measure([16,1,16,16,1])
	var bound:int=int(single.first_release_units)+Order.MAX_BURST
	check(full.first_path=="reference:building:service1","under real capacity pressure the already completed short source commits before the large predecessor")
	check(int(full.first_release_units)<=bound and int(full.next_start_units)>0 and int(full.next_start_units)<=bound+1,"fifth producer starts within one short source's real work plus a bounded service allowance")
	var arrival:=await measure([16,1,16,16,1],true)
	check(arrival.first_path=="reference:building:service1" and int(arrival.first_release_units)<=bound and int(arrival.next_start_units)<=bound+1,"later short completion overtakes an unfinished large cursor and releases a real producer slot")
	check(arrival.total_units==full.total_units,"out-of-order arrival does not increase total publication work")
	await cancel_return_case()
	if trace_enabled:
		var units:Array=Deferred.CompletedTrace.events.filter(func(event):return event.event=="main_unit")
		var workers:Array=Deferred.CompletedTrace.events.filter(func(event):return event.event=="worker_finished")
		check(not units.is_empty() and units.all(func(event):return event.details.duration_us>=0 and event.at_us>=event.details.start_us and event.generation!=0),"each processing unit records task identity and monotonic wall clocks")
		check(not workers.is_empty() and workers.all(func(event):return event.at_us>=event.details.started_us),"actual worker start/end clocks survive join and cancellation")
		check(Deferred.CompletedTrace.dropped==0,"queue clock journal retains every event in the fixture")
		for arg:String in OS.get_cmdline_user_args():
			if arg.begins_with("--output="):
				var file:=FileAccess.open(arg.substr(9),FileAccess.WRITE)
				file.store_string(JSON.stringify({"completed_job_trace":Deferred.CompletedTrace.snapshot(0)}));file.close()
		Deferred.CompletedTrace.enabled=false
	if candidate!=null:selector.set("completed_owner_drain_enabled",candidate)
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("COMPLETED_RESULT_SERVICE passed=",passed," failures=",failed);quit(1 if failed else 0)
