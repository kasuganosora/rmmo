extends SceneTree
## Deterministic service-order regression, not a texture or map timing benchmark.
## Real Deferred gates, staging, atomic append and ownership; no models or GPU.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Order=preload("res://scripts/world3d/publication_order.gd")
const LONG_COUNT:=12
const CHARGE:=64

class Errors extends Logger:
	var errors:Array[String]=[]
	var mutex:=Mutex.new()
	func _log_error(function:String,_file:String,_line:int,code:String,rationale:String,_notify:bool,_type:int,_backtraces:Array)->void:
		mutex.lock();errors.append(function+": "+code+" "+rationale);mutex.unlock()

class Document extends RefCounted:
	var calls:Dictionary={}
	var order:Array[String]=[]
	var holders:Array[WeakRef]=[]
	func _mesh(record:Dictionary,_effects:bool=true,_timings:Variant=null)->Node3D:
		calls[record.uuid]=int(calls.get(record.uuid,0))+1;order.append(record.uuid)
		var holder:=Node3D.new();holders.append(weakref(holder))
		return holder

class Queue extends Deferred:
	var hold_private_cursor:=false
	func _advance_instance_specs(item:Dictionary,job:Dictionary,unit_began:int,_budget_usec:int)->void:
		# Only the cancellation case pauses the real newly allocated cursor.
		if hold_private_cursor:return
		# Same tiny-graph technique as test_deferred_ready_progress. An empty
		# Node3D completes traversal/disposal in one deterministic service unit.
		# Selection, dependency gates, staging and publication remain production.
		super._advance_instance_specs(item,job,unit_began,0)

var passed:=0
var failures:=0
var cases:Array=[]

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failures+=1

func limits(queue:Queue)->Dictionary:
	return {"workers":queue._admission.worker_limit,"bytes":queue._admission.byte_limit,"ready":queue.ready_job_limit,"jobs":queue._job_limit()}

func make_fixture()->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	map.set_meta("stream_library",[]);map.set_meta("extras",{"rmmo_records":[]})
	var index:=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	var queue:=Queue.new();map.add_child(queue)
	var document:=Document.new();queue._doc=document
	queue._reference_index={"groups":{},"extras":{"rmmo_records":[]}}
	var groups:Dictionary={}
	for label:String in ["a","b"]:
		var path:="reference:building:"+label;var group:="building:"+label
		var rows:Array=[];var indices:Array=[]
		var position:=Vector3(0,0,0) if label=="a" else Vector3(100,0,0)
		for member:int in LONG_COUNT if label=="a" else 1:
			var record:={"uuid":label+"_part"+str(member)}
			var item:={"record":record,"path":path,"group_id":group,"native_reference":true,"bounds":AABB(position,Vector3.ONE)}
			indices.append(queue._reference_index.extras.rmmo_records.size())
			queue._reference_index.extras.rmmo_records.append(record)
			rows.append(item);queue.pending.append(item)
		queue._reference_index.groups[group]={"members":indices,"bounds":AABB(position,Vector3.ONE)}
		groups[label]=rows
	queue.activate(map)
	queue.set_demand("background",AABB(Vector3(-110,-1,-1),Vector3(213,3,3)),10)
	queue.set_process(false);queue._refresh_demanded()
	for label:String in groups:
		var path:="reference:building:"+label;var ids:Array=[]
		for item:Dictionary in groups[label]:ids.append(item.record.uuid)
		check(queue._admission.reserve(path,{"estimated_bytes":CHARGE,"exclusive":false}),"fixture reserves original bounded ownership for "+label)
		# These are explicitly already joined/accepted lightweight outputs.
		check(queue._admission.park(path),"fixture parks execution only, retaining result bytes for "+label)
		queue._prepared_paths[path]=true
		queue._jobs[path]={"accepted":true,"native":true,"result":{},"token":Deferred.Drainer.CancelToken.new(),"publication_ids":ids}
	var f:={"map":map,"queue":queue,"document":document,"groups":groups,"limits":limits(queue),"atomic":true,"emissions":0,"commit_order":[],"committed":{},"units":0,"bounded":true}
	queue.published.connect(on_published.bind(f))
	return f

func on_published(_specs:Array,f:Dictionary)->void:
	f.emissions+=1
	for label:String in f.groups:
		var count_:=0
		for item:Dictionary in f.groups[label]:count_+=int(item.get("published",false))
		if count_!=0 and count_!=f.groups[label].size():f.atomic=false
		if count_==f.groups[label].size() and not f.committed.has(label):
			f.committed[label]=true;f.commit_order.append(label)

func unit(f:Dictionary)->int:
	var queue:Queue=f.queue
	# An expired soft slice guarantees one indivisible unit without a hardware
	# timing assertion. The actual production interactive budget is unchanged.
	var result:Dictionary=queue._publish_ready(Time.get_ticks_usec()-1000000,Deferred.INTERACTIVE_BUDGET_US)
	f.units+=int(result.units)
	f.bounded=f.bounded and int(result.units)<=1 and limits(queue)==f.limits and queue._jobs.size()<=2 and queue._admission.reserved_bytes==2*CHARGE
	return int(result.units)

func prove_eligible(f:Dictionary)->void:
	var queue:Queue=f.queue
	check(queue._candidates_revision==queue._demand_revision and queue._demanded_by_id.size()==LONG_COUNT+1,"fresh production demand contains both complete buildings")
	var same_priority:=true;var eligible:=true
	for label:String in f.groups:
		var rows:Array=f.groups[label];var first:Dictionary=rows[0];var job:Dictionary=queue._jobs[first.path]
		same_priority=same_priority and int(queue._demanded_priority[first.record.uuid])==10
		for item:Dictionary in rows:
			var collision:Dictionary=queue._collision_publication_status(item.record.uuid)
			eligible=eligible and not collision.get("owned",false) and queue._runtime_supports_ready(item.record.uuid) and queue._publication_eligible(item,{})
		eligible=eligible and job.accepted and queue._prepared_paths.has(first.path) and queue._publication_workspace_available(job,first.path) and queue._publication_packet_ready(rows)
	check(same_priority and int(queue._demanded_rank.a_part0)<int(queue._demanded_rank.b_part0),"long A and short B have the same visual priority, A initially nearer")
	check(eligible and queue._runtime_building_supports.is_empty(),"both accepted buildings pass real collision, support, workspace and whole-packet gates before scheduling")
	check(queue._admission.active_workers()==0 and queue._admission.reserved_bytes==2*CHARGE and not Order.completed_owner_drain_enabled,"joined results retain byte leases; completion-pressure scheduling stays disabled")

func dispose_fixture(f:Dictionary)->void:
	var queue:Queue=f.queue
	queue.shutdown()
	check(queue._jobs.is_empty() and queue._admission.reserved_bytes==0,"shutdown releases both actual result owners and reservations")
	f.map.free()

func test_selector()->void:
	var order:=Order.new()
	var a:={"path":"a","group_id":"building:a","record":{"uuid":"a"}}
	var b:={"path":"b","group_id":"building:b","record":{"uuid":"b"}}
	var sequence:Array=[]
	for i:int in Order.MAX_BURST+1:sequence.append(order.choose([a,b],{"a":10,"b":10},{"a":0,"b":1},{"a":{},"b":{}}).path)
	check(sequence[0]=="a","nearest equal-priority building starts the first visual burst")
	check(sequence.has("b"),"FAIRNESS selector gives ready building B a first turn within MAX_BURST+1")
	cases.append({"case":"selector","sequence":sequence,"bound":Order.MAX_BURST+1})

func test_real_service()->void:
	var f:=make_fixture();prove_eligible(f)
	var queue:Queue=f.queue;var document:Document=f.document
	var first_b:=-1
	for attempt:int in 4*(LONG_COUNT+1):
		if queue.pending_count()==0:break
		var work:=unit(f)
		if first_b<0 and document.calls.has("b_part0"):first_b=f.units
		if work==0:break
	check(first_b>0 and first_b<=Order.MAX_BURST+1,"FAIRNESS actual qualified B starts within MAX_BURST+1, without waiting for A to finish")
	check(f.units==LONG_COUNT+1 and document.calls.size()==LONG_COUNT+1 and document.calls.values().all(func(n):return n==1),"all thirteen components construct exactly once with unchanged total service work")
	check(f.atomic and f.emissions==2 and queue.pending_count()==0 and int(queue.profile.instances)==LONG_COUNT+1,"both groups publish atomically, once, through the real Deferred commit chain")
	check(f.bounded and queue._jobs.values().all(func(job):return queue._job_consumed(job)),"each service call respects its original slice and retained ownership, with no budget or queue expansion")
	check(document.holders.all(func(value):return value.get_ref()==null),"actual temporary instance nodes are all disposed after successful publication")
	cases.append({"case":"real_service","first_b_unit":first_b,"total_units":f.units,"commit_order":f.commit_order.duplicate(),"calls":document.calls.duplicate(),"limits":f.limits,"ready_building_skips":queue.profile.get("ready_building_skips",0)})
	dispose_fixture(f)

func test_priority_preemption()->void:
	var f:=make_fixture();var queue:Queue=f.queue;var document:Document=f.document
	unit(f)
	check(document.order==["a_part0"] and f.emissions==0,"priority fixture starts inside A's unfinished private burst")
	queue.set_demand("safety",AABB(Vector3(99,-1,-1),Vector3(3,3,3)),-2)
	queue.set_process(false);queue._refresh_demanded()
	check(int(queue._demanded_priority.b_part0)==-2 and int(queue._demanded_priority.a_part1)==10,"real safety demand promotes only B above A")
	unit(f)
	check(document.order.size()==2 and document.order[1]=="b_part0" and f.commit_order==["b"],"negative-priority building immediately interrupts the current visual burst and commits atomically")
	for attempt:int in LONG_COUNT+1:
		if queue.pending_count()==0:break
		if unit(f)==0:break
	check(queue.pending_count()==0 and f.atomic and f.units==LONG_COUNT+1 and document.calls.values().all(func(n):return n==1),"safety interruption resumes the original private group with no repeated components")
	check(f.bounded,"priority interruption preserves the same queue, byte and per-unit budgets")
	cases.append({"case":"negative_priority","order":document.order.duplicate(),"units":f.units})
	dispose_fixture(f)

func test_cancellation()->void:
	var f:=make_fixture();var queue:Queue=f.queue;var document:Document=f.document
	queue.hold_private_cursor=true;unit(f)
	var job:Dictionary=queue._jobs["reference:building:a"]
	check(job.has("instance_preparation") and document.holders.size()==1 and document.holders[0].get_ref()!=null and f.emissions==0,"cancellation holds a real unfinished private cursor and no partially visible group")
	queue.release_demand("background");queue.set_process(false);queue._refresh_demanded()
	queue._poll_jobs(queue._demanded_by_path)
	check(queue._demanded_by_id.is_empty() and queue._jobs.is_empty() and queue._admission.reserved_bytes==0,"real demand cancellation disposes both accepted owners without publication")
	check(document.holders.all(func(value):return value.get_ref()==null) and f.emissions==0 and int(queue.profile.instances)==0,"cancelled private node is released and neither building commits")
	check(document.calls.size()==1 and document.calls.get("a_part0",0)==1 and limits(queue)==f.limits,"cancellation performs no duplicate construction or budget change")
	cases.append({"case":"cancel","calls":document.calls.duplicate(),"cancelled_work_stages":queue.profile.get("instance_work_cancelled_stages",0)})
	dispose_fixture(f)

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var previous_fair:bool=Deferred.fair_publication_enabled
	var previous_drain:bool=Order.completed_owner_drain_enabled
	Deferred.fair_publication_enabled=true;Order.completed_owner_drain_enabled=false
	test_selector();test_real_service();test_priority_preemption();test_cancellation()
	Deferred.fair_publication_enabled=previous_fair;Order.completed_owner_drain_enabled=previous_drain
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine or script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	var report:={"passed":passed,"failures":failures,"errors":logger.errors,"cases":cases,"scope":"Deterministic completed-building service and lifetime; no texture, worker-throughput or real-map timing claim"}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BUILDING_PUBLICATION_FAIRNESS ",JSON.stringify(report));quit(0 if failures==0 else 1)
