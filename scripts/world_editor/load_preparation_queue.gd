extends Node
## Operation-local lookahead. Publication stays with LoadJob in document order.
## Finished packets keep their byte leases until their main-thread owner releases
## them. No live worker is joined during ordinary cancellation or editor exit.
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const FrameBudget=preload("res://scripts/world3d/frame_work_budget.gd")
const LANES:=["model","texture","neutral"]
const LANE_SHARE:=2
const MAX_DIAGNOSTIC_TASKS:=128
const MAX_DIAGNOSTIC_EVENTS:=512
var worker_limit:=2
var byte_limit:=4*1024*1024*1024
var ready_limit:=4
var lanes_enabled:=false # Controlled comparison; total worker/byte/window limits do not change.
var resident_enabled:=false # Separate count window only: retained bytes/exclusivity never shrink.
var resident_limit:=8
var resident_eligible:Callable # Main-thread owner proves this joined packet may remain private.
var diagnostics_enabled:=false # Enable identically in both comparison arms before enqueue.
var thread_starter:Callable # CPU fixture injection only.
var ledger=Admission.new()
# An editor can share the same admission ledger between independent operations.
# Each queue still owns and cancels only its own keys and retained packets.
var shared_ledger_enabled:=false

func _ledger_key(key:String)->String:
	return "editor_queue:%d:%s"%[get_instance_id(),key] if shared_ledger_enabled else key

func _local_key(key:String)->String:
	if not shared_ledger_enabled:return key
	var prefix:="editor_queue:%d:"%get_instance_id()
	return key.trim_prefix(prefix) if key.begins_with(prefix) else ""
var rows:Dictionary={}
var order:Array[String]=[]
var cancelled:=false
var demand_key:=""
var _drainer:Node
var _task_timings:Dictionary={}
var _events:Array[Dictionary]=[]
var _event_next:=0
var _event_dropped:=0
var _task_dropped:=0
var metrics:={"queued":0,"started":0,"joined":0,"consumed":0,"start_failures":0,"ready_on_consume":0,"peak_unconsumed":0,"peak_inflight":0,"peak_resident":0,"peak_private_bytes":0,"resident_entered":0,"resident_exited":0,"preempted":0,"preempted_by_lane":{},"preempted_worker_elapsed_us":0,"blocked":{},"worker_elapsed_us":0,"raw_retries":0,"native_retired_bytes":0}

func enqueue(key:String,task:Callable,estimate:Dictionary,lane:String="")->bool:
	if cancelled or key.is_empty() or rows.has(key) or not task.is_valid():return false
	if not estimate.get("estimated_bytes") is int or estimate.estimated_bytes<=0 or not estimate.get("exclusive") is bool:return false
	if lane.is_empty():lane="neutral"
	if lane not in LANES:return false
	rows[key]={"task":task,"estimate":estimate.duplicate(),"state":"pending","packet":{},"lane":lane}
	order.append(key);metrics.queued+=1
	if diagnostics_enabled:
		if _task_timings.size()<MAX_DIAGNOSTIC_TASKS:
			_task_timings[key]={"lane":lane,"enqueued_us":Time.get_ticks_usec(),"first_start_us":0,"last_start_us":0,"last_join_us":0,"last_acquire_us":0,"last_release_us":0,"attempts":0,"blocked_observations":0,"blocked_intervals":0,"blocked_observed_us":0,"blocked_since_us":0,"blocked_reason":""}
		else:_task_dropped+=1
	_event("enqueue",key)
	return true

func has(key:String)->bool:return rows.has(key)

## A main-thread factory waits for bounded metadata, then supplies one atomic
## workspace/shared-output bundle. It must not allocate renderer resources.
func enqueue_prepared(key:String,factory:Callable,lane:String="model")->bool:
	if not factory.is_valid() or not enqueue(key,func()->Dictionary:return {},{"estimated_bytes":1,"exclusive":false},lane):return false
	rows[key].prepare=factory
	return true

func _prepare_pending(key:String)->bool:
	var row:Dictionary=rows[key]
	if not row.has("prepare"):return true
	var plan:Dictionary=row.prepare.call()
	# Metadata can itself be blocked by a joined speculative model. Demand
	# preemption must be reachable before metadata exists, without assigning
	# metadata a ready-result slot or evicting owners for worker-only pressure.
	if plan.get("pending",false) and key==demand_key and plan.get("dependency_estimate") is Dictionary:
		row.estimate=plan.dependency_estimate
		if not ledger.blocking_reason(_ledger_key(key),row.estimate).is_empty():
			for other:String in _demand_retirements(key,true):_preempt_ready(other)
			plan=row.prepare.call()
	if plan.get("pending",false):return false
	if plan.has("failure"):
		row.packet=plan.failure;row.state="ready";return false
	if not plan.get("task") is Callable or not plan.get("estimate") is Dictionary or not plan.get("retained") is Dictionary:return false
	row.task=plan.task;row.contract=plan
	row.estimate=plan.estimate.duplicate()
	for bytes_:int in plan.retained.values():row.estimate.estimated_bytes+=bytes_
	return true

func demand(key:String)->void:
	if not cancelled and rows.has(key) and rows[key].state in ["pending","running","ready","resident"]:demand_key=key

func is_ready(key:String)->bool:return rows.has(key) and rows[key].state in ["ready","resident"]

func acquire(key:String)->Dictionary:
	if cancelled or not is_ready(key):return {}
	rows[key].held_origin=rows[key].state
	rows[key].state="held"
	if demand_key==key:demand_key=""
	_event("acquire",key)
	return rows[key].packet

func release(key:String)->void:
	if not rows.has(key) or rows[key].state not in ["ready","resident","held"]:return
	# Clearing the actual packet also removes aliases held by the consumer.
	_dispose(rows[key])
	_resident_exit(key,"consumed")
	ledger.release(_ledger_key(key));rows[key].state="done";rows[key].task=Callable()
	rows[key].erase("held_origin")
	metrics.consumed+=1
	_event("release",key)

func forget_terminal(key:String)->bool:
	# Long-lived coordinators may retire completed bookkeeping, but cannot
	# forget a detached worker whose admission lease still belongs to drainer.
	if not rows.has(key) or rows[key].state not in ["done","cancelled"] or ledger._entries.has(_ledger_key(key)):return false
	if demand_key==key:demand_key=""
	rows.erase(key);order.erase(key);_task_timings.erase(key)
	return true

func retry_as_raw(key:String,task:Callable,estimate:Dictionary)->bool:
	# Only a joined fixed-native attempt or explicit legacy source-change result
	# can change route. Its old renderer
	# resources and every packet alias must be disposed on main before returning
	# any byte credit; a raw GLTF must never run inside the smaller native lease.
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or cancelled or not rows.has(key) or not task.is_valid():return false
	var row:Dictionary=rows[key]
	if row.state not in ["ready","resident","held"] or row.has("worker"):return false
	var legacy_retry:bool=row.estimate.get("stage")=="legacy_model" and preload("res://scripts/world3d/model_parse_preparation.gd").is_legacy_source_retry(row.packet)
	if row.estimate.get("stage")!="compiled_read" and not legacy_retry:return false
	if not estimate.get("estimated_bytes") is int or estimate.estimated_bytes<=0 or not estimate.get("exclusive") is bool:return false
	if estimate.get("cpu_only",false):return false
	var demanded:bool=demand_key==key or row.state=="held"
	var retired:int=row.estimate.estimated_bytes
	Drainer.dispose_result(row.packet)
	_resident_exit(key,"native_retry")
	ledger.release(_ledger_key(key))
	_event("release",key,"native_retry")
	row.task=task;row.estimate=estimate.duplicate();row.estimate.stage="raw_import"
	row.state="pending";row.packet={};row.erase("held_origin")
	if demanded:demand_key=key
	metrics.raw_retries+=1;metrics.native_retired_bytes+=retired
	return true

func retry_cached_model(key:String,task:Callable,estimate:Dictionary)->bool:
	# A cache freshness check owns only a bounded CPU hash buffer. A mismatch
	# must acquire a real model lease before it can allocate native/GLTF objects.
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or cancelled or not rows.has(key) or not task.is_valid():return false
	var row:Dictionary=rows[key]
	if row.state not in ["ready","held"] or row.has("worker") or row.estimate.get("stage")!="cache_check" or row.estimate.get("cpu_only")!=true:return false
	var packet:Dictionary=row.packet
	if not packet.get("cache_checked") is bool or not packet.cache_checked or not packet.get("error") is int or packet.error!=OK:return false
	for field:Variant in packet:
		if field not in ["error","cache_checked","source_digest","cache_closed","elapsed_us"]:return false
	if not packet.get("cache_closed") is bool:return false
	if not preload("res://scripts/world3d/compiled_asset_cache.gd")._sha(packet.get("source_digest")):return false
	if not estimate.get("estimated_bytes") is int or estimate.estimated_bytes<=0 or not estimate.get("exclusive") is bool or estimate.get("cpu_only",false):return false
	if estimate.get("stage") not in ["compiled_read","legacy_model"]:return false
	var demanded:bool=demand_key==key or row.state=="held"
	_dispose(row);ledger.release(_ledger_key(key));_event("release",key,"cache_changed")
	row.task=task;row.estimate=estimate.duplicate();row.state="pending";row.packet={};row.erase("held_origin")
	if demanded:demand_key=key
	metrics.cache_retries=int(metrics.get("cache_retries",0))+1
	return true

func _process(_dt:float)->void:pump()

func pump()->void:
	if cancelled or not is_inside_tree():return
	var budget:=FrameBudget.allowance("publication",1500,true)
	if budget<=0:return
	var began:=Time.get_ticks_usec()
	_pump(began+budget)
	FrameBudget.charge("publication",began)

func _pump(deadline:int)->void:
	if not shared_ledger_enabled:
		ledger.worker_limit=worker_limit;ledger.byte_limit=byte_limit
	if not is_instance_valid(_drainer):_drainer=Drainer.for_tree(get_tree())
	# A consumed resident slot can accept a previously joined ready result.
	# This is an ownership label change, not publication or resource disposal.
	if resident_enabled:
		for key:String in order:
			if _resident_count()>=resident_limit:break
			_promote_resident(key)
	for key:String in order:
		var row:Dictionary=rows[key]
		if row.state!="running" or row.worker.is_alive():continue
		row.packet=row.worker.wait_to_finish();_drainer.forget(row.worker)
		row.erase("worker");row.erase("token");row.state="ready"
		ledger.park(_ledger_key(key));ledger.set_stage(_ledger_key(key),"ready")
		if row.get("contract",{}).has("joined") and not row.contract.joined.call(row.packet):row.state="waiting"
		metrics.joined+=1;metrics.worker_elapsed_us+=int(row.packet.get("elapsed_us",0))
		_event("join",key)
		_promote_resident(key)
		if Time.get_ticks_usec()>=deadline:return
	# A waiting dependency keeps its byte lease, but neither a worker nor a
	# producer slot. Resume that same lease before admitting new allocations.
	for key:String in order:
		var row:Dictionary=rows[key]
		if row.state!="waiting":continue
		var task:Callable=row.contract.resume.call(row.packet)
		if not task.is_valid() or not ledger.resume_worker(_ledger_key(key)):continue
		row.task=task
		_start_reserved(key,true)
		if Time.get_ticks_usec()>=deadline:return
	if lanes_enabled or resident_enabled:
		_pump_lanes(deadline);return
	_pump_fifo(deadline)

func _pump_fifo(deadline:int)->void:
	# Preserve the original ordering/preemption policy for the disabled control.
	var pending:Array[String]=[]
	if not demand_key.is_empty() and rows[demand_key].state=="pending":pending.append(demand_key)
	for key:String in order:
		if rows[key].state=="pending" and key!=demand_key:pending.append(key)
	for key:String in pending:
		var row:Dictionary=rows[key]
		if not _prepare_pending(key):continue
		var reason:String=ledger.blocking_reason(_ledger_key(key),row.estimate)
		if reason.is_empty() and _owned_count()>=ready_limit:reason="ready_limit"
		if not reason.is_empty() and key==demand_key:
			# A repaired/missed texture can be demanded before already-prefetched
			# later records. Retire only JOINED, unconsumed later packets so an
			# exclusive demand cannot deadlock behind its own lookahead.
			for later:String in order:
				if later==key or rows[later].state!="ready":continue
				_preempt_ready(later)
				reason=ledger.blocking_reason(_ledger_key(key),row.estimate)
				if reason.is_empty() and _owned_count()>=ready_limit:reason="ready_limit"
				if reason.is_empty() or Time.get_ticks_usec()>=deadline:break
		if not reason.is_empty() or _owned_count()>=ready_limit:
			if reason.is_empty():reason="ready_limit"
			_observe_blocked(key,reason)
			break # First-use ordering also prevents retained-result starvation.
		if not _launch(key):break
		if Time.get_ticks_usec()>=deadline:break

func _pump_lanes(deadline:int)->void:
	while Time.get_ticks_usec()<deadline:
		# Actual consumption always outranks a speculative exclusive lane head.
		# A blocked demand fences new speculation while its live owners drain.
		if not demand_key.is_empty() and rows[demand_key].state=="pending":
			var key:=demand_key
			if not _prepare_pending(key):return
			var reason:=_global_reason(key)
			if not reason.is_empty():
				var retire:=_demand_retirements(key)
				for other:String in retire:
					_preempt_ready(other)
					if Time.get_ticks_usec()>=deadline:return
				reason=_global_reason(key)
			if not reason.is_empty():_observe_blocked(key,reason);return
			# Demand may borrow an idle share directly. Only REAL global capacity
			# pressure justifies discarding an otherwise useful ready result.
			if not _launch(key):return
			continue
		var heads:=_lane_heads()
		for index:int in range(heads.size()-1,-1,-1):
			if not _prepare_pending(heads[index]):heads.remove_at(index)
		if heads.is_empty():return
		var fence:=""
		for key:String in heads:
			if ledger.requires_exclusive(rows[key].estimate):fence=key;break
		if not fence.is_empty():
			# Stop replenishing other lanes so a speculative exclusive eventually
			# sees an empty ledger. Joined results still await real consumption;
			# this fence never evicts them or outranks an actual demand above.
			var reason:=_global_reason(fence)
			if not reason.is_empty():_observe_blocked(fence,"exclusive_fence:"+reason);return
			if not _launch(fence):return
			continue
		var launched:=false
		for key:String in heads:
			var reason:=_global_reason(key)
			if reason.is_empty() and heads.size()>1 and _lane_count(rows[key].lane)>=LANE_SHARE:reason="lane_share"
			if not reason.is_empty():
				_observe_blocked(key,reason)
				continue # Only the OTHER lane head may pass a blocked head.
			if not _launch(key):return
			launched=true;break # Re-evaluate shares after each admission.
		if not launched:return

func _lane_heads()->Array[String]:
	var heads:Array[String]=[];var seen:Dictionary={}
	for key:String in order:
		var row:Dictionary=rows[key]
		if row.state!="pending" or seen.has(row.lane):continue
		seen[row.lane]=true;heads.append(key)
	return heads

func _lane_count(lane:String)->int:
	var count_:=0
	for key:String in order:
		if rows[key].lane==lane and rows[key].state in ["running","ready","held"] and not _is_resident(rows[key]):count_+=1
	return count_

static func _is_resident(row:Dictionary)->bool:
	return row.state=="resident" or (row.state=="held" and row.get("held_origin","")=="resident")

func _resident_count(owner:RefCounted=null)->int:
	if owner==null:owner=ledger
	var count_:=0
	for entry_key:String in owner._entries:
		var key:=_local_key(entry_key)
		if not key.is_empty() and rows.has(key) and _is_resident(rows[key]):count_+=1
	return count_

func _owned_count(owner:RefCounted=null)->int:
	if owner==null:owner=ledger
	var count_:=0
	for entry_key:String in owner._entries:
		var key:=_local_key(entry_key)
		if not key.is_empty() and rows.has(key) and rows[key].state!="waiting":count_+=1
	return count_

func _inflight_count(owner:RefCounted=null)->int:
	if owner==null:owner=ledger
	return _owned_count(owner)-_resident_count(owner) if resident_enabled else _owned_count(owner)

func _update_peaks()->void:
	metrics.peak_unconsumed=maxi(metrics.peak_unconsumed,_owned_count())
	metrics.peak_inflight=maxi(metrics.peak_inflight,_inflight_count())
	metrics.peak_resident=maxi(metrics.peak_resident,_resident_count())
	metrics.peak_private_bytes=maxi(metrics.peak_private_bytes,ledger.reserved_bytes)

func _promote_resident(key:String)->void:
	if not resident_enabled or resident_limit<=0 or not resident_eligible.is_valid() or _resident_count()>=resident_limit:return
	var row:Dictionary=rows[key]
	if row.state!="ready" or row.has("worker") or not ledger._entries.has(_ledger_key(key)):return
	if OS.get_thread_caller_id()!=OS.get_main_thread_id():return
	if not resident_eligible.call(key,row.packet):return
	# Keep exactly the same packet and full lease. No alias is destroyed, no
	# renderer barrier is needed, and exclusivity still fences the entire ledger.
	row.state="resident";ledger.set_stage(_ledger_key(key),"resident")
	metrics.resident_entered+=1;_update_peaks();_event("resident_enter",key)

func _resident_exit(key:String,reason:String)->void:
	if not _is_resident(rows[key]):return
	metrics.resident_exited+=1;_event("resident_exit",key,reason)

func _global_reason(key:String,owner:RefCounted=null,dependency:bool=false)->String:
	if owner==null:owner=ledger
	var reason:String=owner.blocking_reason(_ledger_key(key),rows[key].estimate)
	return "ready_limit" if not dependency and reason.is_empty() and _inflight_count(owner)>=ready_limit else reason

func _demand_retirements(key:String,dependency:bool=false)->Array[String]:
	if resident_enabled:return _resident_demand_retirements(key,dependency)
	# Simulate removals before touching real owners. Worker/held pressure that
	# would survive ALL ready removals must not trigger pointless destruction.
	var ready:Array[String]=[]
	for at in range(order.size()-1,-1,-1):
		var other:String=order[at]
		if other!=key and rows[other].state=="ready":ready.append(other)
	var probe:=Admission.new();probe.worker_limit=ledger.worker_limit;probe.byte_limit=ledger.byte_limit
	probe._entries=ledger._entries.duplicate(true);probe.reserved_bytes=ledger.reserved_bytes
	for other:String in ready:probe.release(_ledger_key(other))
	if not _global_reason(key,probe,dependency).is_empty():return []
	# Global count needs one victim; byte pressure needs the fewest largest
	# victims. Equal sizes retain first-use order by preferring later results.
	if _global_reason(key,null,dependency)=="byte_limit":
		ready.sort_custom(func(a:String,b:String)->bool:
			var left:int=rows[a].estimate.estimated_bytes;var right:int=rows[b].estimate.estimated_bytes
			return order.find(a)>order.find(b) if left==right else left>right)
	probe._entries=ledger._entries.duplicate(true);probe.reserved_bytes=ledger.reserved_bytes
	var retire:Array[String]=[]
	for other:String in ready:
		if _global_reason(key,probe,dependency).is_empty():break
		probe.release(_ledger_key(other));retire.append(other)
	return retire

func _resident_demand_retirements(key:String,dependency:bool=false)->Array[String]:
	# At most ready_limit + resident_limit joined candidates. Simulate the full
	# ledger first: held/running ownership must never be sacrificed speculatively.
	var ready:Array[String]=[]
	for at in range(order.size()-1,-1,-1):
		var other:String=order[at]
		if other!=key and rows[other].state in ["ready","resident"]:ready.append(other)
	var probe:=Admission.new();probe.worker_limit=ledger.worker_limit;probe.byte_limit=ledger.byte_limit
	probe._entries=ledger._entries.duplicate(true);probe.reserved_bytes=ledger.reserved_bytes
	for other:String in ready:probe.release(_ledger_key(other))
	if not _global_reason(key,probe,dependency).is_empty():return []
	ready.sort_custom(func(a:String,b:String)->bool:
		var left:int=rows[a].estimate.estimated_bytes;var right:int=rows[b].estimate.estimated_bytes
		return order.find(a)>order.find(b) if left==right else left>right)
	# If both byte and in-flight limits bind, one in-flight victim is mandatory.
	# Try each such first victim, then the largest remaining byte owners. This
	# yields the smallest count without exponential subset enumeration or
	# wasting a resident eviction that cannot free an in-flight slot.
	var seeds:Array[String]=[""]
	if not dependency and _inflight_count()>=ready_limit:
		seeds.clear()
		for other:String in ready:
			if not _is_resident(rows[other]):seeds.append(other)
	var best:Array[String]=[]
	for seed:String in seeds:
		probe._entries=ledger._entries.duplicate(true);probe.reserved_bytes=ledger.reserved_bytes
		var retire:Array[String]=[]
		if not seed.is_empty():probe.release(_ledger_key(seed));retire.append(seed)
		for other:String in ready:
			if _global_reason(key,probe,dependency).is_empty():break
			if other==seed:continue
			probe.release(_ledger_key(other));retire.append(other)
		if _global_reason(key,probe,dependency).is_empty() and (best.is_empty() or retire.size()<best.size()):best=retire
	return best

func _launch(key:String)->bool:
	# A demanded job may just have retired a ready leader. Recompute the shared
	# offer after that mutation; its old retained/binding set is no longer valid.
	if not _prepare_pending(key):return false
	var row:Dictionary=rows[key]
	var contract:Dictionary=row.get("contract",{})
	if contract.is_empty():
		if not ledger.reserve(_ledger_key(key),row.estimate):return false
	elif not ledger.reserve_bundle(_ledger_key(key),contract.estimate,contract.retained):return false
	_close_blocked(key)
	_start_reserved(key,false)
	return true

func _start_reserved(key:String,continuation:bool)->void:
	var row:Dictionary=rows[key]
	var token:=Drainer.CancelToken.new()
	if row.estimate.get("cpu_only",false):token.set_meta("cpu_metadata_only",true)
	# The detached drainer owns the lease, not this queue's freed Node.
	token.set_meta("admission_owner",ledger)
	token.set_meta("admission_release",ledger.release.bind(_ledger_key(key)))
	if not row.get("contract",{}).is_empty():row.contract.commit.call(token,continuation)
	if continuation:token.set_meta("prefab_continuation_result",row.packet)
	var worker:=Thread.new();var task:=_invoke.bind(row.task,token)
	var err:int=thread_starter.call(worker,task) if thread_starter.is_valid() else worker.start(task,Thread.PRIORITY_LOW)
	if err!=OK:
		# Never move expensive decode onto main after a launch failure.
		token.cancel()
		ledger.park(_ledger_key(key));row.state="ready"
		if not continuation:row.packet={"error":err,"elapsed_us":0,"start_failed":true}
		else:row.packet.error=err;row.packet.start_failed=true
		if token.has_meta("native_texture_scope"):row.packet.native_texture_scope=token.get_meta("native_texture_scope")
		if token.has_meta("prefab_continuation_result"):token.remove_meta("prefab_continuation_result")
		if row.get("contract",{}).has("joined"):row.contract.joined.call(row.packet)
		metrics.start_failures+=1;_event("start_failed",key)
	else:
		row.worker=worker;row.token=token;row.state="running"
		_drainer.watch(worker,token);metrics.started+=1;_event("start",key)
	_update_peaks()

func _preempt_ready(key:String)->void:
	var row:Dictionary=rows[key]
	# Cumulative joined worker wall time discarded, never CPU time or an
	# estimate of extra entry latency. Retries are counted as separate attempts.
	metrics.preempted_worker_elapsed_us+=int(row.packet.get("elapsed_us",0))
	metrics.preempted_by_lane[row.lane]=int(metrics.preempted_by_lane.get(row.lane,0))+1
	_dispose(row);_resident_exit(key,"preempted");ledger.release(_ledger_key(key));row.state="pending";row.erase("held_origin");metrics.preempted+=1
	_event("release",key,"preempted")

static func _invoke(task:Callable,token:RefCounted)->Dictionary:
	var began:=Time.get_ticks_usec()
	if token.is_cancelled():return {"error":ERR_SKIP,"elapsed_us":0,"cancelled":true}
	var raw:Variant=task.call()
	var packet:Dictionary=raw if raw is Dictionary else {"error":ERR_INVALID_DATA,"retained_resources":[raw]}
	packet.elapsed_us=Time.get_ticks_usec()-began
	# Do not destroy an already allocated renderer resource on this worker.
	if token.is_cancelled():packet.cancelled=true
	return packet

func cancel()->void:
	if cancelled:return
	cancelled=true;demand_key="";set_process(false)
	for key:String in order:
		var row:Dictionary=rows[key]
		if row.state=="running":
			if is_instance_valid(_drainer) and _drainer.is_inside_tree():_drainer.abandon(row.worker)
			else:Drainer.drain_shutdown(row.worker,row.token)
			row.erase("worker");row.erase("token")
		elif row.state in ["ready","resident","held","waiting"]:
			_dispose(row);_resident_exit(key,"cancelled");ledger.release(_ledger_key(key))
			_event("release",key,"cancelled")
		_close_blocked(key);_event("cancel",key)
		row.state="cancelled";row.task=Callable();row.erase("contract");row.erase("held_origin")

func snapshot()->Dictionary:
	var result:Dictionary=metrics.duplicate(true)
	result.cancelled=cancelled;result.ledger=ledger.snapshot()
	result.lanes_enabled=lanes_enabled;result.lane_admitted={}
	result.resident_enabled=resident_enabled;result.resident_limit=resident_limit
	result.resident_current=_resident_count();result.inflight_current=_inflight_count()
	for lane:String in LANES:result.lane_admitted[lane]=_lane_count(lane)
	result.states={}
	for key:String in order:result.states[rows[key].state]=int(result.states.get(rows[key].state,0))+1
	result.diagnostics={"enabled":diagnostics_enabled}
	if diagnostics_enabled:
		# Per-task aggregates are bounded; high-volume event history is opt-in via
		# diagnostic_events(), never copied on every UI state/MCP polling call.
		result.diagnostics={"enabled":true,"task_limit":MAX_DIAGNOSTIC_TASKS,"event_limit":MAX_DIAGNOSTIC_EVENTS,"tasks_dropped":_task_dropped,"events_dropped":_event_dropped,"events_retained":_events.size(),"tasks":_task_timings.duplicate(true),"clock":"process monotonic microseconds; start is successful dispatch, not worker entry","blocked_scope":"sampled interval from first blocked observation to different reason/admission/terminal; includes pump gaps, not CPU time; reasons may overlap across tasks"}
		var now:=Time.get_ticks_usec()
		for key:String in result.diagnostics.tasks:
			var timing:Dictionary=result.diagnostics.tasks[key]
			timing.blocked_open_us=maxi(0,now-int(timing.blocked_since_us)) if timing.blocked_since_us>0 else 0
	return result

func _observe_blocked(key:String,reason:String)->void:
	metrics.blocked[reason]=int(metrics.blocked.get(reason,0))+1
	if not diagnostics_enabled or not _task_timings.has(key):return
	var timing:Dictionary=_task_timings[key]
	timing.blocked_observations+=1
	if timing.blocked_reason==reason:return
	_close_blocked(key)
	timing.blocked_reason=reason;timing.blocked_since_us=Time.get_ticks_usec();timing.blocked_intervals+=1
	_event("blocked",key,reason)

func _close_blocked(key:String)->void:
	if not diagnostics_enabled or not _task_timings.has(key):return
	var timing:Dictionary=_task_timings[key]
	if timing.blocked_since_us==0:return
	var elapsed:=maxi(0,Time.get_ticks_usec()-int(timing.blocked_since_us));var reason:String=timing.blocked_reason
	timing.blocked_observed_us+=elapsed;timing.blocked_since_us=0;timing.blocked_reason=""
	_event("blocked_end",key,reason,elapsed)

func _event(kind:String,key:String,reason:String="",elapsed_us:int=0)->void:
	if not diagnostics_enabled:return
	var now:=Time.get_ticks_usec()
	if _task_timings.has(key):
		var timing:Dictionary=_task_timings[key]
		match kind:
			"start":
				if timing.first_start_us==0:timing.first_start_us=now
				timing.last_start_us=now;timing.attempts+=1
			"join":timing.last_join_us=now
			"acquire":timing.last_acquire_us=now
			"release":timing.last_release_us=now
	if kind=="start":
		if not metrics.has("first_start_us"):metrics.first_start_us=now
		if not metrics.has("first_start_by_lane"):metrics.first_start_by_lane={}
		if not metrics.first_start_by_lane.has(rows[key].lane):metrics.first_start_by_lane[rows[key].lane]=now
	var event:Dictionary={"event":kind,"key":key,"lane":rows[key].lane,"time_us":now,"reserved_bytes":ledger.reserved_bytes}
	if not reason.is_empty():event.reason=reason
	if elapsed_us>0:event.elapsed_us=elapsed_us
	if _events.size()<MAX_DIAGNOSTIC_EVENTS:_events.append(event)
	else:
		_events[_event_next]=event;_event_next=(_event_next+1)%MAX_DIAGNOSTIC_EVENTS;_event_dropped+=1

func diagnostic_events()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for offset in _events.size():result.append(_events[(_event_next+offset)%_events.size()].duplicate(true))
	return result

static func _dispose(row:Dictionary)->void:
	# Factories bind immutable offer rows. Clear those aliases before the packet
	# scope returns its table pin, keeping only the scalar retry factory.
	if row.has("prepare"):row.task=Callable()
	row.erase("contract")
	# Image-only packets cannot own rendering commands. Avoid forcing a renderer
	# sync for each terrain/material handoff merely to discard private CPU pixels.
	if row.estimate.get("cpu_only",false):row.packet.clear()
	else:Drainer.dispose_result(row.packet)

func _exit_tree()->void:cancel()
