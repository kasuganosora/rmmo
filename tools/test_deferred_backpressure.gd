extends SceneTree
## CPU-only real Thread/admission/publication scheduler regression. No GLTF,
## texture upload or authored map. Timing limits assert work counts/cursors,
## never machine-specific performance numbers.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
class Document extends RefCounted:
	var calls:Dictionary={}
	var terrain_neighbors=preload("res://scripts/world3d/terrain_neighbors.gd").new()
	func _mesh(record:Dictionary,_effects:bool=true,_timings:Variant=null)->Node3D:
		calls[record.uuid]=int(calls.get(record.uuid,0))+1
		return Node3D.new()
class Queue extends Deferred:
	var paused:=false
	var requests:=0
	var started:Array=[]
	var estimate_delay:=0
	func _reference_requests(_path:String)->Array:requests+=1;return []
	func _estimate_job(item:Dictionary,_requests:Array,_need_model:bool=true)->Dictionary:
		if estimate_delay>0:OS.delay_usec(estimate_delay)
		return item.memory
	func _make_prepare_task(path:String,_digest:String,token:RefCounted,_item:Dictionary,_faces:bool,_root:String,_requests:Array,_native:bool,_need_model:bool)->Callable:
		started.append(path)
		var records:Array=[]
		for item:Dictionary in _demanded_by_path[path]:records.append(item.record.duplicate(true))
		return work.bind(token,records)
	static func work(token:RefCounted,records:Array)->Dictionary:
		return {"error":"cancelled" if token.is_cancelled() else "","records":records,"elapsed_us":1}
	func _publish_ready(_began:int,_budget:int=INTERACTIVE_BUDGET_US)->Dictionary:
		if paused:return {"units":0,"unit_us":0,"max_unit_us":0}
		return super._publish_ready(Time.get_ticks_usec()-1000000,1)
var passed:=0
var failed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failed+=1
func item(id:String,x:float,bytes:int=1,path:String="")->Dictionary:
	return {"record":{"uuid":id},"path":"reference:"+id if path.is_empty() else path,"bounds":AABB(Vector3(x,0,0),Vector3.ONE),"digest":"","native_reference":true,"memory":{"estimated_bytes":bytes,"exclusive":false}}
func fixture(rows:Array)->Dictionary:
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",[])
	var index:=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	map.set_meta("extras",{"rmmo_records":[]})
	var queue:=Queue.new();var document:=Document.new();queue._doc=document;queue.pending=rows;queue._reference_root="D:/code/rmmo"
	map.add_child(queue);queue.activate(map);queue._admission.byte_limit=100000;queue._admission.worker_limit=2
	queue.set_demand("background",AABB(Vector3(-1,-1,-1),Vector3(20000,3,3)),10)
	queue.set_process(false);queue._refresh_demanded()
	return {"map":map,"queue":queue,"document":document}
func tick(queue:Queue)->void:
	queue.set_process(false);queue._process(0);await process_frame
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var old_yield:=Deferred.ready_worker_yield_enabled;Deferred.ready_worker_yield_enabled=true
	await backlog_test();await cursor_test();await partial_retry_test();await retry_head_test();await demoted_path_group_test()
	Deferred.ready_worker_yield_enabled=old_yield
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEFERRED_BACKPRESSURE passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
func backlog_test()->void:
	var rows:Array=[]
	for i in 60:rows.append(item("n%d"%i,float(i*2)))
	var f:=fixture(rows);var queue:Queue=f.queue;queue.paused=true
	for i in 24:await tick(queue)
	check(queue._jobs.size()==4 and queue.started.size()==4,"ready outputs backpressure at four whole closures without lowering the two-worker limit")
	check(queue._admission.active_workers()==0 and queue._admission.reserved_bytes==4,"parked ready outputs retain bytes while publication is deliberately paused")
	check(queue._admission.worker_limit==2 and int(queue.profile.max_total_jobs)==4,"total-job peak is recorded independently of execution capacity")
	queue.set_demand("critical",AABB(Vector3(99,-1,-1),Vector3(4,3,3)),-2);queue.set_process(false)
	for i in 12:
		await tick(queue)
		if queue._jobs.has("reference:n50"):break
	check(queue._jobs.has("reference:n50") and queue._jobs.size()<=4,"new critical closure replaces a lower-priority ready output at a full backlog")
	check(int(queue.profile.get("priority_retirements",0))>0,"priority replacement is observable")
	queue.paused=false
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		if queue.is_complete():break
	check(queue.is_complete() and queue._admission.reserved_bytes==0,"bounded queue sustainably refills slots until all requested closures publish")
	check(f.document.calls.size()==60 and f.document.calls.values().all(func(n):return n==1),"critical replacement never loses or duplicates pending publication")
	check(int(queue.profile.max_total_jobs)<=4,"total ready plus running closures never grow with the sixty-job demand")
	f.map.free()
func cursor_test()->void:
	var rows:Array=[item("held",0)]
	for i in 600:rows.append(item("blocked%d"%i,float(i+1),50))
	var f:=fixture(rows);var queue:Queue=f.queue;queue.paused=true;queue.estimate_delay=100
	# Hold the metadata generation constant before testing unchanged byte
	# pressure. The first empty header request initializes this context and
	# legitimately restarts admission once; it performs no source I/O.
	check(queue._texture_headers_ready(rows[0],[],self),"empty texture header context is ready before the byte-pressure trial")
	queue._admission.byte_limit=100;queue._admission.reserve("reference:held",{"estimated_bytes":90,"exclusive":false});queue._admission.park("reference:held")
	queue._jobs["reference:held"]={"accepted":true,"result":{},"token":Deferred.Drainer.CancelToken.new(),"publication_ids":["held"]}
	queue._dispatch_jobs(self)
	check(queue.requests>0 and queue.requests<64 and queue._dispatch_cursor<queue._dispatch_paths.size(),"dispatch deadline yields with a saved path cursor instead of scanning six hundred failed estimates")
	var until:=Time.get_ticks_msec()+5000
	while queue._dispatch_cursor<queue._dispatch_paths.size() and Time.get_ticks_msec()<until:queue._dispatch_jobs(self)
	var calls:=queue.requests
	for i in 20:queue._dispatch_jobs(self)
	check(calls==600 and queue.requests==calls,"unchanged byte-pressure failures are examined once, not re-estimated every frame")
	queue._dispatch_deadline=Time.get_ticks_usec()-1;queue._scheduler_epoch+=1;queue._dispatch_jobs(self);queue._dispatch_deadline=0
	check(queue.requests==calls,"an expired caller deadline starts no new preparation decision")
	queue._discard_job("reference:held");queue._dispatch_jobs(self)
	check(not queue._jobs.is_empty(),"released capacity reopens admission from the highest live priority")
	await queue.quiesce();f.map.free()
func partial_retry_test()->void:
	var a:=item("a",0,1,"reference:shared");var b:=item("b",1,1,"reference:shared")
	for row:Dictionary in [a,b]:
		row.record.rmmo_ref={"uri":row.record.uuid+".rmres","sha256":"a".repeat(64)}
		row.reference_entry={"compact_record":row.record.duplicate(true)}
	var f:=fixture([a,b,item("target",100)]);var queue:Queue=f.queue;queue.ready_job_limit=1
	queue.set_demand("first",AABB(Vector3(-1,-1,-1),Vector3(3,3,3)),0);queue.set_process(false)
	for i in 20:
		await tick(queue)
		# Instance construction now spans private slices before publication.
		if not queue.runtime_record("a").is_empty():break
	check(f.document.calls.get("a",0)==1 and not f.document.calls.has("b"),"one closure may be partially published while retaining its second instance")
	var retained:Dictionary=f.map.get_meta("extras").rmmo_records[0]
	queue.paused=true;queue.set_demand("critical",AABB(Vector3(99,-1,-1),Vector3(3,3,3)),-2);queue.set_process(false)
	for i in 12:
		await tick(queue)
		if queue._jobs.has("reference:target"):break
	check(queue._jobs.has("reference:target") and retained.uuid=="a" and retained.has("rmmo_ref"),"critical replacement leaves the already-published author record intact")
	queue.paused=false
	for i in 40:
		await tick(queue)
		if queue.is_complete():break
	check(queue.is_complete() and f.document.calls.get("a",0)==1 and f.document.calls.get("b",0)==1,"cap-one retry publishes only the unpublished sibling and cannot deadlock its whole closure")
	check(f.map.get_meta("extras").rmmo_records.size()==2,"published author metadata is neither cleared nor duplicated on retry")
	f.map.free()
func retry_head_test()->void:
	var a:=item("bad",0,1,"reference:both");var b:=item("good",1,1,"reference:both")
	for row:Dictionary in [a,b]:
		row.record.rmmo_ref={"uri":row.record.uuid+".rmres","sha256":"a".repeat(64)}
		row.reference_entry={"compact_record":row.record.duplicate(true)}
	var f:=fixture([a,b]);var queue:Queue=f.queue
	queue._instance_failed("bad","fixture failure");queue._demand_revision+=1;queue._refresh_demanded()
	check(queue._path_first["reference:both"].record.uuid=="good","a demand refresh skips a failed first instance when choosing a healthy same-path job")
	for i in 20:
		await tick(queue)
		if f.document.calls.has("good"):break
	check(f.document.calls.get("good",0)==1 and not f.document.calls.has("bad"),"a failed head cannot prevent healthy same-model publication")
	queue.retry_failed(AABB(Vector3(-1,-1,-1),Vector3(4,3,3)));queue.set_process(false)
	for i in 20:
		await tick(queue)
		if queue.is_complete():break
	check(queue.is_complete() and f.document.calls.get("bad",0)==1,"repair invalidates exhausted dispatch cursors and re-admits the repaired instance")
	f.map.free()

func demoted_path_group_test()->void:
	# Four shared-model paths each start with a near critical instance and retain
	# a distant background sibling. Publishing those heads must move their paths
	# behind three complete building groups without a demand revision.
	var rows:Array=[];var groups:Dictionary={};var compact:Array=[]
	for i in 4:
		rows.append(item("near%d"%i,float(i),1,"reference:model%d"%i))
		rows.append(item("far%d"%i,float(1000+i),1,"reference:model%d"%i))
	for group_number in 3:
		var key:="building:priority%d"%group_number;var members:Array=[]
		for i in 5:
			var row:=item("group%d_part%d"%[group_number,i],float(100+group_number*10+i),1,"reference:"+key)
			row.group_id=key;members.append(compact.size());compact.append(row.record);rows.append(row)
		groups[key]={"members":members}
	var f:=fixture(rows);var queue:Queue=f.queue;queue.ready_job_limit=4
	queue._reference_index={"groups":groups,"extras":{"rmmo_records":compact}}
	queue.set_demand("near",AABB(Vector3(-1,-1,-1),Vector3(6,3,3)),-2)
	queue.set_demand("groups",AABB(Vector3(99,-1,-1),Vector3(30,3,3)),-1)
	queue.set_process(false);queue._refresh_demanded()
	var revision:=queue._demand_revision;var atomic:=true;var saw_stage:=false
	for i in 100:
		await tick(queue)
		for key:String in groups:
			var remaining:=0
			for row:Dictionary in queue.pending:
				if row.get("group_id","")==key:remaining+=1
			if remaining!=0 and remaining!=5:atomic=false
		for job:Dictionary in queue._jobs.values():
			if not job.get("staged",{}).is_empty():saw_stage=true
		if queue.is_complete():break
	check(queue.is_complete() and queue._demand_revision==revision,"live head demotion admits critical whole groups without needing a new demand revision")
	check(saw_stage and atomic and groups.keys().all(func(key):return queue.group_is_published(key)),"five-part groups really stage across frames and publish their complete membership atomically")
	var starts:Dictionary={}
	for path:String in queue.started:starts[path]=int(starts.get(path,0))+1
	check(queue.started.size()<=11 and int(queue.profile.get("priority_retirements",0))<=4,"demoted shared paths cannot repeatedly refill and cancel ahead of required groups")
	check(f.document.calls.size()==23 and f.document.calls.values().all(func(n):return n==1),"multi-path group pressure publishes every component and distant sibling exactly once")
	check(int(queue.profile.max_total_jobs)<=4 and queue._admission.reserved_bytes==0,"group progress preserves the total-job cap and releases all finished reservations")
	await queue.quiesce();f.map.free()
