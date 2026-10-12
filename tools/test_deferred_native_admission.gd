extends SceneTree
## Real Deferred/Thread/Drainer ownership with CPU-only empty scenes. No GLTF,
## meshes, textures, production files or GPU resource allocation is required.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const UNIT=65536
const OLD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const NEW_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const REASON="candidate_source_changed_after_read"
const CLIP=AABB(Vector3(-10,-10,-10),Vector3(40,20,40))
var passed:int=0
var failures:int=0

class Lifetime extends RefCounted:
	var audit:RefCounted
	var kind:String=""
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE and audit!=null:audit.released(kind)

class Audit extends RefCounted:
	var mutex:=Mutex.new()
	var ledger:WeakRef
	var resources:Array=[]
	var releases:Array=[]
	var starts:Array=[]
	var calls:Array=[]
	func observe(value:Object,kind:String)->void:
		var marker:=Lifetime.new();marker.audit=self;marker.kind=kind
		value.set_meta("deferred_native_test_lifetime",marker)
		mutex.lock();resources.append({"kind":kind,"weak":weakref(value)});mutex.unlock()
	func released(kind:String)->void:
		# All legitimate retirement is on main, so reading this ledger is safe.
		var thread_id:=OS.get_thread_caller_id()
		var owner:RefCounted=ledger.get_ref() if ledger!=null and thread_id==OS.get_main_thread_id() else null
		var charged:int=owner.reserved_bytes if owner!=null else -1
		mutex.lock();releases.append({"kind":kind,"thread":thread_id,"bytes":charged});mutex.unlock()
	func called(path:String,stage:String)->void:
		mutex.lock();calls.append({"path":path,"stage":stage});mutex.unlock()
	func count_calls(stage:String)->int:
		mutex.lock();var count_:int=0
		for row:Dictionary in calls:
			if row.stage==stage:count_+=1
		mutex.unlock();return count_
	func native_alive()->bool:
		mutex.lock();var alive:=false
		for row:Dictionary in resources:
			if row.kind=="native" and row.weak.get_ref()!=null:alive=true
		mutex.unlock();return alive
	func all_released()->bool:
		mutex.lock();var okay:=releases.size()==resources.size()
		for row:Dictionary in resources:okay=okay and row.weak.get_ref()==null
		for row:Dictionary in releases:okay=okay and row.thread==OS.get_main_thread_id()
		mutex.unlock();return okay

class Gate extends RefCounted:
	var audit:Audit
	var mode:String="success"
	var blocked:=false
	var cooperative:=false
	var semaphore:=Semaphore.new()
	var cancelled:=false
	func work(path:String,stage:String,candidate:Dictionary,token:RefCounted)->Dictionary:
		audit.called(path,stage)
		if cooperative:
			while not token.is_cancelled():OS.delay_usec(100)
		elif blocked:semaphore.wait()
		cancelled=token.is_cancelled()
		if stage!="fixed_native":
			var scene:=Node3D.new();audit.observe(scene,"raw_scene")
			return {"error":"raw failure" if mode=="raw_failure" else "","scene":scene,"compiled":false,"source_digest":NEW_SHA,"elapsed_us":1,"records":[],"dependencies":{}}
		if mode=="premiss":
			return {"error":"","native_packet":{"error":OK,"fallback_required":true,"cache_reason":"candidate_missing"},"elapsed_us":1}
		var packed:=PackedScene.new();var empty:=Node.new();var status:=packed.pack(empty);empty.free()
		audit.observe(packed,"native")
		if status!=OK:return {"error":"synthetic pack failed","native_packet":{"error":status,"packed":packed}}
		if mode=="success":
			var scene:=Node3D.new();audit.observe(scene,"native_scene")
			return {"error":"","scene":scene,"compiled":true,"source_digest":candidate.source_sha,"native_packet":{"error":OK,"packed":packed,"compiled":true,"source_digest":candidate.source_sha},"elapsed_us":1,"records":[],"dependencies":{}}
		var packet:Dictionary={"error":ERR_BUSY,"packed":packed,"compiled":true,"source_digest":candidate.source_sha,"native_source_retry":true,"cache_reason":REASON}
		var result:Dictionary={"error":"native source changed","native_packet":packet,"elapsed_us":1}
		match mode:
			"empty_wrapper_error":result.error=""
			"wrong_wrapper_error_type":result.error=ERR_BUSY
			"wrong_digest":packet.source_digest=NEW_SHA
			"wrong_digest_type":packet.source_digest=123
			"wrong_error":packet.error=ERR_INVALID_DATA
			"wrong_error_type":packet.error="busy"
			"wrong_compiled":packet.compiled=false
			"wrong_compiled_type":packet.compiled="true"
			"wrong_reason":packet.cache_reason="other_failure"
			"wrong_reason_type":packet.cache_reason=123
			"wrong_marker_type":packet.native_source_retry="true"
			"false_marker":packet.native_source_retry=false
			"missing_marker":packet.erase("native_source_retry")
			"marker_and_fallback":packet.fallback_required=true
			"marker_and_false_fallback":packet.fallback_required=false
			"wrong_packed_type":
				packet.retained_resources=[packed]
				var other:=RefCounted.new();audit.observe(other,"wrong_resource");packet.packed=other
			"resource_fallback":
				packet.erase("native_source_retry");packet.error=OK;packet.fallback_required=true;result.error=""
			"scene_fallback":
				packet.erase("native_source_retry");packet.error=OK;packet.fallback_required=true;packet.erase("packed")
				packet.retained_resources=[packed]
				var scene:=Node3D.new();audit.observe(scene,"invalid_scene");result.scene=scene;result.error=""
			"retained_fallback":
				packet.erase("native_source_retry");packet.error=OK;packet.fallback_required=true;packet.erase("packed")
				result.retained_resources=[packed];result.error=""
			"top_packed_fallback","private_packet_fallback":
				packet.clear();packet.error=OK;packet.fallback_required=true;packet.cache_reason="candidate_missing"
				if mode=="top_packed_fallback":result.packed=packed
				else:result.private_preparation={"packed":packed}
				result.error=""
			"false_fallback":packet.erase("native_source_retry");packet.error=OK;packet.fallback_required=false;result.error=""
		return result

class Probe extends Deferred:
	var audit:=Audit.new()
	var gates:Dictionary={}
	var mode:String="success"
	var candidates:int=0
	var refreshes:int=0
	var accepts:int=0
	var publications:int=0
	var fail_stage:String=""
	var dispatch_path:String=""
	var dispatch_stage:String=""
	var source_candidate:Dictionary={"estimated_bytes":20*UNIT,"exclusive":false,"source_sha":OLD_SHA,"payload_sha":NEW_SHA,"bytes":1,"generator":"probe","product":"probe.scn","source_path":""}
	func _candidate_for_job(path:String,_root:String,_digest:String)->Dictionary:
		candidates+=1
		var result:=source_candidate.duplicate(true);result.source_path=path;return result
	func _refresh_raw_memory(_path:String)->Dictionary:
		refreshes+=1
		return {"estimated_bytes":60*UNIT,"exclusive":false,"known":true}
	func _reference_requests(path:String)->Array:
		var result:Array=[]
		for row:Dictionary in _demanded_by_path.get(path,[]):result.append({"memory_bytes":5*UNIT,"uuid":row.record.uuid})
		return result
	func _make_prepare_task(path:String,_digest:String,token:RefCounted,_item:Dictionary,_faces:bool,_root:String,_requests:Array,_native:bool,_need_model:bool)->Callable:
		dispatch_path=path;dispatch_stage=str(_jobs[path].get("stage","missing_stage"))
		var candidate:Dictionary=_jobs[path].get("candidate",{}).duplicate(true)
		var key:=path+":"+dispatch_stage
		if not gates.has(key):
			var gate:=Gate.new();gate.audit=audit;gate.mode=mode;gates[key]=gate
		return gates[key].work.bind(path,dispatch_stage,candidate,token)
	func _start_worker(worker:Thread,prepare:Callable)->int:
		audit.starts.append({"path":dispatch_path,"stage":dispatch_stage,"bytes":_admission.reserved_bytes,"workers":_admission.active_workers(),"native_alive":audit.native_alive(),"publication_ids":_jobs[dispatch_path].publication_ids.duplicate()})
		if dispatch_stage==fail_stage:return ERR_CANT_CREATE
		return worker.start(prepare)
	func _accept_prepared_records(_result:Dictionary)->void:accepts+=1
	func _publish_ready(_began:int,_budget:int=INTERACTIVE_BUDGET_US)->Dictionary:
		publications+=1
		return {"units":0,"unit_us":0,"max_unit_us":0}

func _initialize()->void:run.call_deferred()

func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if ok:passed+=1
	else:failures+=1

func row(id:String,path:String,x:float=0.)->Dictionary:
	return {"record":{"uuid":id,"collision":"none"},"path":path,"digest":"","bounds":AABB(Vector3(x,0,0),Vector3.ONE),"memory":{"estimated_bytes":40*UNIT,"exclusive":false,"known":true}}

func fixture(mode:String="success",rows:Array=[])->Probe:
	# Keep the original reduced-budget matrix explicit if production defaults
	# change. Conservative cases switch this off after constructing the fixture.
	Deferred.native_budget_enabled=true
	var service:=Probe.new();service.mode=mode;service.loading_worker_limit=2
	service.audit.ledger=weakref(service._admission)
	service.pending=rows if not rows.is_empty() else [row("a","user://deferred_native_probe.glb"),row("b","user://deferred_native_probe.glb",1.)]
	check(service.begin_entry_prefetch(self,CLIP,{}),mode+": starts off-tree private preparation")
	service._admission.byte_limit=100*UNIT;service._admission.worker_limit=2
	return service

func prepared(service:Probe)->bool:
	for job:Dictionary in service._jobs.values():
		if job.has("result") and not job.has("worker"):return true
	return false

func settled(service:Probe)->bool:
	return not service.error.is_empty() or not service.path_errors.is_empty() or prepared(service)

func drive(service:Probe,predicate:Callable,label_:String)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while not predicate.call(service) and Time.get_ticks_msec()<deadline:
		service.pump_entry_prefetch();await process_frame
	check(predicate.call(service),label_)

func private_only(service:Probe,label_:String)->void:
	check(service.accepts==0 and service.publications==0 and service._prepared_paths.is_empty(),label_+": prefetch performs no acceptance/publication")
	for item:Dictionary in service.pending:check(not Deferred.Assets._scenes.has(item.path),label_+": no shared template cache mutation")

func cleanup(service:Probe,label_:String)->void:
	await service.quiesce()
	check(service._jobs.is_empty() and service._admission.count()==0 and service._admission.reserved_bytes==0,label_+": quiesce retires jobs and every charge")
	check(service._drainer==null or service._drainer.jobs.is_empty(),label_+": drainer has no unjoined worker")
	check(service.audit.all_released(),label_+": all synthetic resources released only on main")
	service.free()

func ledger_cases()->void:
	var ledger:=Admission.new();ledger.worker_limit=1;ledger.byte_limit=100
	check(not ledger.park("missing"),"park rejects a nonexistent reservation")
	check(ledger.reserve("a",{"estimated_bytes":30,"exclusive":false}) and not ledger.has_capacity(),"live reservation occupies the only worker")
	check(ledger.park("a") and ledger.park("a") and ledger.count()==1 and ledger.active_workers()==0 and ledger.reserved_bytes==30,"parking is idempotent and retains the entire result charge")
	check(ledger.has_capacity() and ledger.blocking_reason("b",{"estimated_bytes":71,"exclusive":false})=="byte_limit","parked bytes still reject an oversized sibling")
	check(ledger.reserve("b",{"estimated_bytes":70,"exclusive":false}) and ledger.reserved_bytes==100 and ledger.count()==2,"released worker can admit only the remaining byte allowance")
	check(ledger.park("b") and not ledger.has_capacity(),"all workers parked does not bypass a full byte budget")
	var snap:=ledger.snapshot()
	check(snap.jobs==2 and snap.active_workers==0 and snap.peak_jobs==2 and snap.peak_workers==1,"snapshot separates held jobs from actual worker slots")
	ledger.release("a");ledger.release("b")
	check(ledger.reserve("exclusive",{"estimated_bytes":101,"exclusive":true}) and ledger.park("exclusive"),"an oversize exclusive result can finish and park")
	check(not ledger.has_capacity() and ledger.blocking_reason("next",{"estimated_bytes":1,"exclusive":false})=="active_exclusive","parked exclusive output continues blocking all siblings")
	ledger.release("exclusive");ledger.worker_limit=0
	check(not ledger.has_capacity() and ledger.blocking_reason("disabled",{"estimated_bytes":1,"exclusive":false})=="disabled","disabled dispatch remains disabled after parking")

func successful_native()->void:
	var service:=fixture();service.pump_entry_prefetch()
	check(service.audit.starts.size()==1 and service.audit.starts[0].stage=="fixed_native" and service.audit.starts[0].bytes==30*UNIT,"native candidate plus two reference outputs reserves 20 + 10")
	check(service._admission.active_workers()==1,"unjoined worker remains charged as active")
	service.source_candidate.source_sha=NEW_SHA
	await drive(service,settled,"native result joins individually")
	check(prepared(service) and service._jobs.values()[0].get("candidate",{}).get("source_sha")==OLD_SHA,"dispatch holds a fixed candidate independently of later provider changes")
	check(service._admission.count()==1 and service._admission.active_workers()==0 and service._admission.reserved_bytes==30*UNIT,"joined native result parks its slot but retains resources and bytes")
	private_only(service,"native success");await cleanup(service,"native success")

func parked_refill()->void:
	var service:=fixture("success",[row("first","user://deferred_native_first.glb"),row("second","user://deferred_native_second.glb",1.)])
	service._admission.worker_limit=1
	service.pump_entry_prefetch()
	check(service.audit.starts.size()==1 and service._admission.active_workers()==1,"one-worker queue cannot refill before joining its first result")
	await drive(service,func(queue_:Probe):return queue_._jobs.size()==2 and queue_._admission.active_workers()==0,"parked ready output permits the next bounded worker to finish")
	check(service._admission.reserved_bytes==50*UNIT and service._admission.count()==2 and service._admission.peak_workers==1,"refill retains both native results while peak live workers stays one")
	private_only(service,"parked refill");await cleanup(service,"parked refill")

func retry_case(mode:String,reduced_budget:bool=true)->void:
	var service:=fixture(mode);Deferred.native_budget_enabled=reduced_budget
	var native_charge:int=(30 if reduced_budget else 50)*UNIT
	await drive(service,settled,mode+": retry eventually becomes ready")
	check(service.audit.count_calls("fixed_native")==1 and service.audit.count_calls("raw_import")==1 and service.refreshes>=1,mode+": retry refreshes raw envelope and runs each stage once")
	check(service.audit.starts.size()==2 and service.audit.starts[0].bytes==native_charge and service.audit.starts[1].bytes==70*UNIT,mode+": raw obtains a separate complete 60 + 10 reservation")
	if service.audit.starts.size()>1:check(not service.audit.starts[1].native_alive,mode+": native resource is gone before raw reservation starts")
	check(service._admission.peak_bytes==70*UNIT,mode+": native and raw reservations never coexist")
	if mode!="premiss":
		var releases:Array=service.audit.releases.filter(func(value:Dictionary):return value.kind=="native")
		check(releases.size()==1 and releases[0].thread==OS.get_main_thread_id() and releases[0].bytes==native_charge,mode+": main releases old native while its original budget is still held")
	if mode=="raw_failure":check(not service.path_errors.is_empty() and service._jobs.is_empty(),"raw failure is fatal and cannot retry again")
	else:check(prepared(service) and service._jobs.values()[0].result.get("source_digest")==NEW_SHA,mode+": fresh raw identity remains privately owned")
	private_only(service,mode);await cleanup(service,mode)

func rejected_case(mode:String,verified:bool=false,reduced_budget:bool=true)->void:
	var service:=fixture(mode)
	Deferred.native_budget_enabled=reduced_budget
	if verified:service.source_signatures[service.pending[0].path]=OLD_SHA
	await drive(service,settled,mode+": invalid or forbidden retry terminates")
	check(not service.path_errors.is_empty() or not service.error.is_empty(),mode+": validation failure is visible")
	check(service.audit.count_calls("raw_import")==0 and service._jobs.is_empty(),mode+": failure never obtains raw admission")
	check(service._admission.count()==0 and service.audit.all_released(),mode+": failed resource retired before releasing all charge")
	private_only(service,mode);await cleanup(service,mode)

func conservative_budget_cases()->void:
	var service:=fixture();Deferred.native_budget_enabled=false
	service.pump_entry_prefetch()
	check(service.audit.starts.size()==1 and service.audit.starts[0].stage=="fixed_native" and service.audit.starts[0].bytes==50*UNIT,"conservative native: fixed reader reserves raw model 40 + references 10")
	check(service._admission.active_workers()==1,"conservative native: unjoined worker occupies its slot")
	service.source_candidate.source_sha=NEW_SHA
	await drive(service,settled,"conservative native: fixed result joins individually")
	check(prepared(service) and service._jobs.values()[0].get("candidate",{}).get("source_sha")==OLD_SHA and service._jobs.values()[0].result.get("source_digest")==OLD_SHA,"conservative native: reader keeps the dispatch candidate and source identity")
	check(service.audit.count_calls("fixed_native")==1 and service.audit.count_calls("raw_import")==0,"conservative native: full reservation does not switch the reader to raw")
	check(service._admission.count()==1 and service._admission.active_workers()==0 and service._admission.reserved_bytes==50*UNIT,"conservative native: parking retains all 50 units of its reservation")
	private_only(service,"conservative native");await cleanup(service,"conservative native")
	for mode:String in ["premiss","source_retry"]:await retry_case(mode,false)
	await rejected_case("source_retry",true,false)

func larger_native_bounds()->void:
	for native_units:int in [40,80]:
		for reduced:bool in [true,false]:
			var service:=fixture();service.source_candidate.estimated_bytes=native_units*UNIT
			Deferred.native_budget_enabled=reduced
			service.pump_entry_prefetch()
			var charge:int=(native_units+10)*UNIT
			check(service.audit.starts.size()==1 and service.audit.starts[0].stage=="fixed_native" and service.audit.starts[0].bytes==charge,"equal/larger native bound keeps fixed identity and full credit: "+str(native_units)+" reduced="+str(reduced))
			await drive(service,settled,"equal/larger native result joins")
			check(service._admission.reserved_bytes==charge and service._admission.active_workers()==0,"joined larger native retains all model and reference bytes")
			await cleanup(service,"larger native bound")
	var old_preparation:bool=Deferred.native_preparation_enabled
	var legacy:=fixture();legacy.source_candidate.estimated_bytes=80*UNIT;Deferred.native_preparation_enabled=false
	legacy.pump_entry_prefetch()
	check(legacy.audit.starts.size()==1 and legacy.audit.starts[0].stage=="legacy" and legacy.audit.starts[0].bytes==90*UNIT,"legacy preparation opt-out preserves max(raw,native) plus reference credit")
	await drive(legacy,settled,"legacy max-bound result joins")
	await cleanup(legacy,"legacy max envelope");Deferred.native_preparation_enabled=old_preparation
	# A live or parked lease must drain before an oversized native candidate,
	# even though its raw source estimate would have fit alongside that lease.
	var path:="user://deferred_native_larger_exclusive.glb"
	var exclusive:=fixture("success",[row("exclusive",path)])
	exclusive.source_candidate.estimated_bytes=110*UNIT;exclusive.source_candidate.exclusive=true
	check(exclusive._admission.reserve("held",{"estimated_bytes":10*UNIT,"exclusive":false}) and exclusive._admission.park("held"),"exclusive fixture starts with a real held lease")
	var gate:=gate_for(exclusive,path,"fixed_native");exclusive.pump_entry_prefetch()
	check(exclusive.audit.starts.is_empty() and exclusive._admission.reserved_bytes==10*UNIT,"raw<cap<native waits for the existing held lease")
	exclusive._admission.release("held");exclusive.pump_entry_prefetch()
	check(exclusive.audit.starts.size()==1 and exclusive.audit.starts[0].bytes==115*UNIT and exclusive._admission.snapshot().exclusive_keys.has(path),"oversized native is admitted alone with model plus reference bytes")
	check(not exclusive._admission.can_admit("sibling",{"estimated_bytes":1,"exclusive":false}),"live exclusive native prevents sibling admission")
	gate.semaphore.post();await drive(exclusive,settled,"exclusive native result joins")
	check(exclusive._admission.active_workers()==0 and exclusive._admission.reserved_bytes==115*UNIT and not exclusive._admission.can_admit("sibling",{"estimated_bytes":1,"exclusive":false}),"parked exclusive native retains its fence until actual disposal")
	await cleanup(exclusive,"larger exclusive native")
	for mode:String in ["premiss","source_retry"]:
		var retry:=fixture(mode);retry.source_candidate.estimated_bytes=80*UNIT
		await drive(retry,settled,"larger native retry reaches fresh raw readiness")
		check(retry.audit.starts.size()==2 and retry.audit.starts[0].stage=="fixed_native" and retry.audit.starts[0].bytes==90*UNIT and retry.audit.starts[1].stage=="raw_import" and retry.audit.starts[1].bytes==70*UNIT,"larger native retry refreshes and separately reserves smaller raw model plus references")
		check(not retry.audit.starts[1].native_alive and retry._admission.peak_bytes==90*UNIT and retry.refreshes>=1,"larger native is disposed before raw credit starts without overlapping reservations")
		if mode=="source_retry":
			var releases:Array=retry.audit.releases.filter(func(value:Dictionary):return value.kind=="native")
			check(releases.size()==1 and releases[0].thread==OS.get_main_thread_id() and releases[0].bytes==90*UNIT,"larger native source retry disposal occurs on main while its full old credit is held")
		await cleanup(retry,"larger native retry")

func worker_failure(stage:String)->void:
	var service:=fixture("source_retry");service.fail_stage=stage
	await drive(service,settled,stage+": failed worker start terminates")
	check(not service.error.is_empty() or not service.path_errors.is_empty(),stage+": thread failure is reported")
	check(service._jobs.is_empty() and service._admission.count()==0 and service._admission.reserved_bytes==0,stage+": failed launch returns its reservation")
	private_only(service,stage);await cleanup(service,stage)

func gate_for(service:Probe,path:String,stage:String,cooperative:bool=false)->Gate:
	var gate:=Gate.new();gate.audit=service.audit;gate.mode=service.mode;gate.blocked=true;gate.cooperative=cooperative
	service.gates[path+":"+stage]=gate
	return gate

func scope_cancel()->void:
	var path:="user://deferred_native_scope.glb";var service:=fixture("source_retry",[row("old",path)])
	var gate:=gate_for(service,path,"fixed_native");service.pump_entry_prefetch()
	service.set_demand("other",AABB(Vector3(500,0,0),Vector3.ONE));service.set_demand_scope(["other"])
	check(service._jobs[path].token.is_cancelled() and service._admission.reserved_bytes==25*UNIT,"scope cancellation preserves the live worker's old charge")
	gate.semaphore.post()
	await drive(service,func(queue_:Probe):return queue_._jobs.is_empty(),"scope cancellation joins the late native result")
	check(service.audit.count_calls("raw_import")==0 and service.audit.all_released() and service._admission.reserved_bytes==0,"cancelled retry neither dispatches raw nor leaks its native packet")
	await cleanup(service,"scope cancelled")

func changed_publication_ids()->void:
	var path:="user://deferred_native_ids.glb";var service:=fixture("premiss",[row("old",path),row("new",path,100.)])
	var gate:=gate_for(service,path,"fixed_native");service.pump_entry_prefetch()
	service.set_demand("entry_safety",AABB(Vector3(-10,-10,-10),Vector3(130,20,40)),-3)
	gate.semaphore.post();await drive(service,settled,"changed demand raw retry reaches ready")
	if service.audit.starts.size()>1:
		var ids:Array=service.audit.starts[1].publication_ids
		check(ids.size()==2 and ids.has("old") and ids.has("new") and service.audit.starts[1].bytes==70*UNIT,"raw redispatch refreshes publication IDs and reference-byte estimate")
	else:check(false,"raw redispatch exists for publication identity check")
	private_only(service,"changed demand");await cleanup(service,"changed demand")

func lifetime_cases()->void:
	for kind:String in ["quiesce","shutdown","offtree_free","tree_exit"]:
		var path:="user://deferred_native_"+kind+".glb";var service:=fixture("source_retry",[row(kind,path)])
		var gate:=gate_for(service,path,"fixed_native",true);service.pump_entry_prefetch()
		var audit:Audit=service.audit;var ledger:RefCounted=service._admission;var drainer:Node=service._drainer
		if kind=="quiesce":await service.quiesce();service.free()
		elif kind=="shutdown":service.shutdown();service.free()
		elif kind=="offtree_free":service.free()
		else:
			service.finish_entry_prefetch()
			var map:=Node3D.new();root.add_child(map);map.add_child(service);map.free()
			var deadline:=Time.get_ticks_msec()+5000
			while not drainer.jobs.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check(gate.cancelled and audit.count_calls("raw_import")==0,kind+": cancellation joins native work without a raw retry")
		check(drainer.jobs.is_empty() and ledger.count()==0 and ledger.reserved_bytes==0,kind+": owner or drainer retires every worker and reservation")
		check(audit.all_released(),kind+": late native packet released only on main")

func abandoned_ledger_lifetime()->void:
	var path:="user://deferred_native_weak_ledger.glb"
	var service:=fixture("source_retry",[row("weak_ledger",path)])
	var gate:=gate_for(service,path,"fixed_native")
	service.pump_entry_prefetch()
	var audit:Audit=service.audit
	var ledger_weak:WeakRef=weakref(service._admission)
	var drainer:Node=service._drainer
	service.finish_entry_prefetch()
	var map:=Node3D.new();root.add_child(map);map.add_child(service);map.free()
	check(not drainer.jobs.is_empty() and ledger_weak.get_ref()!=null,"abandoned live worker's token alone retains its admission ledger")
	check(ledger_weak.get_ref().reserved_bytes==25*UNIT and audit.ledger is WeakRef,"test retains no strong ledger alias while abandoned output stays charged")
	gate.semaphore.post()
	var deadline:=Time.get_ticks_msec()+5000
	while not drainer.jobs.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(drainer.jobs.is_empty() and ledger_weak.get_ref()==null,"drain releases the token's ledger owner after disposal and reservation release")
	check(audit.all_released() and audit.releases.size()==1 and audit.releases[0].bytes==25*UNIT,"late native resource releases on main while the sole token-owned ledger still holds its charge")

func run()->void:
	if DisplayServer.get_name()!="headless":print("CPU test requires --headless");quit(2);return
	var old_native_budget:bool=Deferred.native_budget_enabled
	create_timer(45).timeout.connect(func():Deferred.native_budget_enabled=old_native_budget;print("DEFERRED_NATIVE_ADMISSION timeout");quit(2))
	ledger_cases()
	await successful_native()
	await parked_refill()
	for mode:String in ["premiss","source_retry","raw_failure"]:await retry_case(mode)
	for mode:String in ["wrong_digest","wrong_digest_type","wrong_error","wrong_error_type","wrong_compiled","wrong_compiled_type","wrong_reason","wrong_reason_type","wrong_marker_type","false_marker","missing_marker","marker_and_fallback","marker_and_false_fallback","wrong_packed_type","resource_fallback","scene_fallback","retained_fallback","false_fallback","empty_wrapper_error","wrong_wrapper_error_type","top_packed_fallback","private_packet_fallback"]:await rejected_case(mode)
	await rejected_case("source_retry",true)
	await worker_failure("fixed_native");await worker_failure("raw_import")
	await scope_cancel();await changed_publication_ids();await lifetime_cases();await abandoned_ledger_lifetime()
	await conservative_budget_cases()
	await larger_native_bounds()
	Deferred.native_budget_enabled=old_native_budget
	print("DEFERRED_NATIVE_ADMISSION passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
