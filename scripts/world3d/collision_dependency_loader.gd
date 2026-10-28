extends Node
## Opt-in map-owned collision dependency coordinator. Source IO is worker-only;
## accepted instances still require Residency's physics synchronization proof.
const Adapter=preload("res://scripts/world3d/collision_instance_preparation.gd")
const NoCollision=preload("res://scripts/world3d/collision_not_required_preparation.gd")
const Residency=preload("res://scripts/world3d/collision_instance_residency.gd")
const Proof=preload("res://scripts/world3d/dependency_index_proof.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const FrameBudget=preload("res://scripts/world3d/frame_work_budget.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const MAX_PENDING:=4
const MAX_WORKERS:=2
const PLAN_BYTES:=16*1024*1024
const PREPARE_BYTES:=256*1024*1024
const MAX_COMPACT_BYTES:=1024*1024
const MAX_REQUESTS:=4096
const MAX_NONE_PROOF_BYTES:=8*1024*1024
static var no_collision_proof_enabled:=false
static var dispatch_before_installation:=false
static var dispatch_profile_enabled:=false

class Lease extends RefCounted:
	var planning:RefCounted
	var preparing:RefCounted
	var key:=""
	func release()->void:
		planning.release(key);preparing.release(key)

var error:=""
var profile:Dictionary={"plan_jobs":0,"prepare_jobs":0,"fallbacks":0,"fallback_reason_totals":{},"fallback_samples":[],"accepted":0,"cancelled":0,"max_pending":0,"peak_workers":0,"plan_us":0,"prepare_us":0,"max_main_us":0,"shared_source_jobs":0}
var _index:Dictionary={}
var _proof:Proof
var _path:=""
var _root:=""
var _epoch:=-1
var _map:WeakRef
var _owner:WeakRef
var _tree:WeakRef
var _phase:="unconfigured"
var _last_prefetch_frame:=-1
var _store:Node
var _drainer:Node
var _planning:=Admission.new()
var _preparing:=Admission.new()
var _work:Dictionary={}
var _states:Dictionary={}
var _tickets:Dictionary={}
var _source_counts:Dictionary={}
var _negative_candidates:Dictionary={}
var _serial:=0
var _cancelled:=false
var _waiting_capacity:=false
var _allow_none:=false
var _none_proof_bytes:=0
var _dispatch_first:=false
var _dispatch_profile:=false

func _init()->void:
	name="CollisionDependencyLoader";set_meta("stream_instance",true);set_process(false)
	_planning.worker_limit=MAX_WORKERS;_planning.byte_limit=MAX_PENDING*PLAN_BYTES
	_preparing.worker_limit=MAX_WORKERS;_preparing.byte_limit=PREPARE_BYTES

static func _failure(reason:String)->Dictionary:return {"ok":false,"error":reason,"reason":reason}

func configure(index:Dictionary,path:String,root:String,proof:Proof,map:Node,epoch:int)->Dictionary:
	if _phase!="unconfigured":return _failure("already_configured")
	if not map is Node3D or epoch<0:return _failure("invalid_context")
	var started:=begin_prefetch(map,index,path,root,proof)
	if not started.ok:return started
	return adopt(map,epoch)

func begin_prefetch(owner:Node,index:Dictionary,path:String,root:String,proof:Proof)->Dictionary:
	if _phase!="unconfigured":return _failure("already_configured")
	if not is_inside_tree() or not is_instance_valid(owner) or owner.is_queued_for_deletion() or get_parent()!=owner or proof==null or path.is_empty() or root.is_empty() or not Index.validate_index_ownership(index,root,proof,path):
		error="invalid_context";return _failure(error)
	_index=index;_proof=proof;_path=path;_root=root;_owner=weakref(owner);_tree=weakref(get_tree())
	_allow_none=no_collision_proof_enabled
	_dispatch_first=dispatch_before_installation;_dispatch_profile=dispatch_profile_enabled
	_negative_candidates.clear()
	_drainer=Drainer.for_tree(get_tree());_phase="prefetch";set_process(false)
	profile.prefetch_started_us=Time.get_ticks_usec()
	return {"ok":true,"error":"","reason":""}

func matches_context(index:Dictionary,path:String,root:String,proof:Proof)->bool:
	return not _cancelled and error.is_empty() and _phase!="unconfigured" and path==_path and root==_root and is_same(proof,_proof) and is_same(index,_index) and Index.validate_index_ownership(index,root,proof,path)

func _map_identity(map:Node,epoch:int,require_source:bool)->bool:
	if not map is Node3D or map.is_queued_for_deletion() or epoch<0 or not Index.validate_index_ownership(_index,_root,_proof,_path):return false
	if require_source and not map.has_meta("source_map_sha256"):return false
	if map.has_meta("source_map_sha256") and map.get_meta("source_map_sha256")!=_index.source_sha256:return false
	if _map!=null and (not is_same(_map.get_ref(),map) or _epoch!=epoch):return false
	return true

func handoff(map:Node,epoch:int)->Dictionary:
	# Explicit ownership transfer permits an off-tree result to wait safely for
	# its preparation viewport. A bare remove_child still cancels the operation.
	if _phase=="handoff" and _map_identity(map,epoch,true) and get_parent()==map:return {"ok":true,"error":"","reason":""}
	if _phase!="prefetch" or not _context() or not _map_identity(map,epoch,true):return _failure("handoff_identity")
	if map.is_inside_tree() and not is_same(map.get_tree(),_tree.get_ref()):return _failure("handoff_tree")
	if map.get_node_or_null("CollisionDependencyLoader")!=null or map.get_node_or_null("CollisionInstanceResidency")!=null:return _failure("existing_collision_owner")
	_map=weakref(map);_epoch=epoch;_owner=weakref(map);_phase="handoff";set_process(false)
	profile.handoff_us=Time.get_ticks_usec();profile.prefetch_ready_at_handoff=_ready_count()
	reparent(map)
	return {"ok":true,"error":"","reason":""}

func adopt(map:Node,epoch:int)->Dictionary:
	if _phase=="adopted":
		return {"ok":true,"error":"","reason":""} if _context() and _map_identity(map,epoch,false) else _failure("adoption_identity")
	if _phase not in ["prefetch","handoff"] or _cancelled or not error.is_empty() or not is_inside_tree() or not _map_identity(map,epoch,_phase=="handoff") or get_parent()!=map or not is_same(get_tree(),_tree.get_ref()):return _failure("adoption_identity")
	if map.get_node_or_null("CollisionInstanceResidency")!=null:
		error="existing_residency_owner";return _failure(error)
	var store:=Residency.new();map.add_child(store)
	var configured:Dictionary=store.configure(map,_path,str(_index.source_sha256),epoch)
	if not configured.ok:store.free();error=str(configured.error);return _failure(error)
	_epoch=epoch;_map=weakref(map);_owner=weakref(map);_store=store;_phase="adopted"
	profile.adopted_us=Time.get_ticks_usec();profile.prefetch_ready_at_adopt=_ready_count();set_process(true)
	return {"ok":true,"error":"","reason":""}

func _context()->bool:
	if _cancelled or not error.is_empty() or _owner==null or not is_instance_valid(_owner.get_ref()) or _owner.get_ref().is_queued_for_deletion() or get_parent()!=_owner.get_ref() or not is_inside_tree() or _tree==null or not is_same(get_tree(),_tree.get_ref()):return false
	return _phase=="prefetch" or (_phase=="adopted" and is_instance_valid(_store))

func _ready_count()->int:
	var count:=0
	for job:Dictionary in _work.values():
		if job.stage=="ready":count+=1
	return count

func pump_prefetch(budget_usec:int=1500)->void:
	if _phase!="prefetch" or not _context() or budget_usec<=0:return
	var frame:=Engine.get_process_frames()
	if frame==_last_prefetch_frame:return
	_last_prefetch_frame=frame
	_advance_queue(budget_usec,false)

func _entry_matches(entry:Variant)->bool:
	if not entry is Dictionary or not entry.get("record_index") is int:return false
	var at:int=entry.record_index
	if at<0 or at>=_index.rows.size():return false
	var row:Dictionary=_index.rows[at]
	var bounds:AABB=_index.groups[row.group_id].bounds if not row.group_id.is_empty() else row.bounds
	return entry.get("compact_record")==_index.extras.rmmo_records[at] and entry.get("bounds")==bounds and entry.get("group_id","")==row.group_id and entry.get("asset_path","")==row.asset_path

func _entry_snapshot(at:int)->Dictionary:
	var row:Dictionary=_index.rows[at]
	return {"record_index":at,"compact_record":_index.extras.rmmo_records[at],"bounds":_index.groups[row.group_id].bounds if not row.group_id.is_empty() else row.bounds,"group_id":row.group_id,"asset_path":row.asset_path}

func request(entries:Array,priority:int=0,ticket_id:String="default")->Dictionary:
	if not _context():return _failure("inactive_context")
	if ticket_id.is_empty() or entries.size()>MAX_REQUESTS:return _failure("request_limit")
	var wanted:Dictionary={}
	for entry:Variant in entries:
		if not _entry_matches(entry):return _failure("entry_identity")
		var uuid:String=entry.compact_record.uuid
		if wanted.has(uuid):return _failure("duplicate_request")
		# Borrow only immutable reader-owned source containers, never a caller's
		# mutable request dictionary while a worker is using its pose or identity.
		wanted[uuid]=_entry_snapshot(int(entry.record_index))
	var previous:Dictionary=_tickets.get(ticket_id,{})
	if previous.get("priority") == priority and previous.get("entries",{}).keys()==wanted.keys() and previous.get("entries")==wanted:
		return _request_result(wanted)
	_tickets[ticket_id]={"entries":wanted,"priority":priority}
	_reconcile_requests()
	set_process(_phase=="adopted")
	return _request_result(wanted)

func _request_result(wanted:Dictionary)->Dictionary:
	var accepted:Array=[];var deferred:Array=[];var fallback:Array=[]
	for uuid:String in wanted:
		var state:Dictionary=_states.get(uuid,{})
		if state.get("state","")=="fallback":fallback.append(uuid)
		elif state.is_empty():deferred.append(uuid)
		else:accepted.append(uuid)
	return {"ok":true,"error":"","accepted":accepted,"deferred_capacity":deferred,"fallback":fallback}

func release_request(ticket_id:String)->void:
	_tickets.erase(ticket_id);_reconcile_requests()
func cancel_request(ticket_id:String)->void:release_request(ticket_id)

func _wanted()->Dictionary:
	var result:Dictionary={};var order:=0
	for ticket:Dictionary in _tickets.values():
		for uuid:String in ticket.entries:
			if not result.has(uuid) or ticket.priority<result[uuid].priority:result[uuid]={"entry":ticket.entries[uuid],"priority":ticket.priority,"order":order}
			order+=1
	return result

func _pending_count()->int:
	# Detached cancelled workers remain real pending work until Drainer joins.
	# Their planning lease remains present for both stages of a transaction.
	var result:=_planning.count()
	for job:Dictionary in _work.values():
		if job.stage=="queued":result+=1
	return result

func _yield_lower(priority:int)->void:
	var victim:="";var lowest:=priority
	for uuid:String in _work:
		if int(_work[uuid].priority)>lowest:lowest=int(_work[uuid].priority);victim=uuid
	if victim.is_empty():return
	_cancel_job(victim)

func _erase_state(uuid:String)->void:
	var value:Dictionary=_states.get(uuid,{})
	if Trace.enabled and value.get("state","")=="not_required":Trace.instant("collision.none.retire",{"uuid":uuid,"epoch":_epoch,"bytes":int(value.get("proof_bytes",0))})
	_none_proof_bytes-=int(value.get("proof_bytes",0))
	_states.erase(uuid)

func _cancel_job(id:String)->void:
	if not _work.has(id):return
	var ids:Array=_work[id].ids
	_discard(id)
	for uuid:String in ids:
		if _states.get(uuid,{}).get("job_id","")==id:_erase_state(uuid)
	profile.cancelled+=1

func _ordinary(entry:Dictionary)->bool:
	var row:Dictionary=_index.rows[entry.record_index]
	return row.reason=="model_accessor_bounds" and row.group_id.is_empty() and row.bounds_known and row.owner_keys.is_empty()

func _reconcile_requests()->void:
	var wanted:=_wanted()
	profile.request_reconciliations=int(profile.get("request_reconciliations",0))+1
	_waiting_capacity=false
	var retire:Array=[]
	for uuid:String in _states.keys():
		if wanted.has(uuid):continue
		var id:String=_states.get(uuid,{}).get("job_id","")
		if _work.has(id):
			var retained:=false
			for member:String in _work[id].ids:
				if wanted.has(member) and _states.get(member,{}).get("job_id","")==id:retained=true;break
			# Visual publication retires members one at a time. Keep a shared
			# absence proof in flight for its other consumers instead of hashing
			# the same large source again after every published grass instance.
			if not retained:_cancel_job(id)
		_erase_state(uuid);retire.append(uuid)
	if not retire.is_empty() and is_instance_valid(_store):_store.discard_instances(retire)
	var ordered:Array=wanted.keys()
	ordered.sort_custom(func(a,b):return wanted[a].priority<wanted[b].priority if wanted[a].priority!=wanted[b].priority else wanted[a].order<wanted[b].order)
	# A shared job follows its most urgent remaining consumer. Updating from
	# every member in turn would let the last (least urgent) one win.
	for job_id:String in _work:
		var job:Dictionary=_work[job_id]
		var best:Dictionary={}
		for member:String in job.ids:
			if not wanted.has(member) or _states.get(member,{}).get("job_id","")!=job_id:continue
			var candidate:Dictionary=wanted[member]
			if best.is_empty() or candidate.priority<best.priority or (candidate.priority==best.priority and candidate.order<best.order):best=candidate
		if not best.is_empty():job.priority=best.priority;job.order=best.order
	for uuid:String in ordered:
		if _states.has(uuid):continue
		var entry:Dictionary=wanted[uuid].entry;var row:Dictionary=_index.rows[entry.record_index]
		if not _ordinary(entry):
			_states[uuid]={"state":"fallback","reason":"unsupported_record","entry":entry};_note_fallback(uuid,"unsupported_record");continue
		if not _allow_none and _negative_candidates.has(row.asset_path):
			_states[uuid]={"state":"fallback","reason":"collision_asset_missing","entry":entry}
			_note_negative_hit(uuid);continue
		if _pending_count()>=MAX_PENDING:
			_yield_lower(int(wanted[uuid].priority))
			if _pending_count()>=MAX_PENDING:_waiting_capacity=true;continue
		_serial+=1
		var key:="collision:"+str(_serial)
		var id:String=key if _allow_none else uuid
		var entries:Array=[entry];var ids:Array=[uuid]
		if _allow_none:
			for sibling:String in ordered:
				if entries.size()>=32:break
				if sibling==uuid or _states.has(sibling):continue
				var other:Dictionary=wanted[sibling].entry
				if other.asset_path==entry.asset_path and _ordinary(other):entries.append(other);ids.append(sibling)
		_work[id]={"key":key,"entry":entry,"entries":entries,"ids":ids,"priority":wanted[uuid].priority,"order":wanted[uuid].order,"stage":"queued"}
		for member:String in ids:_states[member]={"state":"pending","reason":"planning","entry":wanted[member].entry,"job_id":id}
	profile.max_pending=maxi(int(profile.max_pending),_pending_count())

func instance_readiness(uuid:String)->Dictionary:
	if not _context():return {"ok":false,"state":"cancelled","reason":"inactive_context"}
	var value:Dictionary=_states.get(uuid,{})
	if value.is_empty():return {"ok":false,"state":"unrequested","reason":"not_requested"}
	if value.state=="not_required":
		var receipt:NoCollision.Receipt=value.get("proof")
		var map:Node=_map.get_ref() if _map!=null else null
		if _phase=="adopted" and _map_identity(map,_epoch,false) and receipt!=null and receipt.matches_entry(value.entry) and receipt.matches_context(_index,_path,_root,_proof):
			return {"ok":true,"state":"not_required","reason":"collision_not_required"}
		return {"ok":false,"state":"fallback","reason":"none_proof_identity"}
	if value.state=="installing":
		var ready:Dictionary=_store.instance_readiness(uuid,_epoch)
		if ready.state=="promoted":return {"ok":false,"state":"fallback","reason":"render_promoted"}
		if ready.state=="failed":
			_store.discard_instances([uuid]);value.state="fallback";value.reason=ready.reason;_note_fallback(uuid,str(ready.reason))
		else:return ready
	return {"ok":false,"state":value.state,"reason":value.reason}
func status(uuid:String)->Dictionary:return instance_readiness(uuid)

func coverage(entries:Array)->Dictionary:
	var result:Dictionary={"ok":false,"reason":"","pending":[],"fallback":[],"ready":[]}
	if not _context():result.reason="inactive_context";return result
	var seen:Dictionary={}
	for entry:Variant in entries:
		if not _entry_matches(entry):result.reason="entry_identity";return result
		var uuid:String=entry.compact_record.uuid
		if seen.has(uuid):result.reason="duplicate_request";return result
		seen[uuid]=true
		var state:=instance_readiness(uuid)
		if state.ok:result.ready.append(uuid)
		elif state.state=="fallback":result.fallback.append(uuid)
		else:result.pending.append(uuid)
	result.ok=result.pending.is_empty() and result.fallback.is_empty()
	result.reason="" if result.ok else "render_fallback" if not result.fallback.is_empty() else "collision_pending"
	return result

static func _bounded(value:Variant,left:Array,depth:int=0)->bool:
	left[0]-=64
	if left[0]<0 or depth>32:return false
	if value is String:left[0]-=value.length()*4;return left[0]>=0
	if value is Dictionary:
		for key:Variant in value:
			if not _bounded(key,left,depth+1) or not _bounded(value[key],left,depth+1):return false
	elif value is Array:
		for child:Variant in value:
			if not _bounded(child,left,depth+1):return false
	return true

static func _plan_task(index:Dictionary,entries:Array,path:String,root:String,proof:Proof,token:RefCounted,allow_none:bool,known_missing:bool)->Dictionary:
	var began:=Time.get_ticks_usec()
	if token.is_cancelled():return {"ok":false,"reason":"cancelled","cancelled":true}
	var left:Array=[MAX_COMPACT_BYTES]
	for entry:Dictionary in entries:
		if not _bounded(entry.compact_record,left):return {"ok":false,"reason":"planning_metadata_limit"}
	# Coalesce only absence proofs. Geometry keeps the established per-instance
	# priority and publication budget, so a nearby instance does not drag every
	# same-source camera neighbour into its physics installation transaction.
	var result:Dictionary={"ok":false,"reason":"collision_asset_missing"} if known_missing else Adapter.plan(index,[entries[0]],path,root,proof)
	var missing:bool=not result.ok and result.get("reason","")=="collision_asset_missing"
	var none:bool=allow_none and missing
	# Missing/unsafe offline absence metadata is an ordinary full-native render
	# fallback. Neither the coordinator nor its worker retries an authoring GLB.
	if none:result=NoCollision.plan(index,entries,path,root,proof)
	if token.is_cancelled():result.clear();return {"ok":false,"reason":"cancelled","cancelled":true}
	return {"ok":result.ok,"reason":str(result.get("reason","")),"plan":result,"no_collision":none,"sidecar_missing":missing,"elapsed_us":Time.get_ticks_usec()-began}

static func _prepare_task(plan:Dictionary,token:RefCounted,none:bool)->Dictionary:
	var began:=Time.get_ticks_usec()
	var result:Dictionary=NoCollision.prepare(plan,int(plan.estimated_bytes),token) if none else Adapter.prepare(plan,int(plan.estimated_bytes),token)
	result.elapsed_us=Time.get_ticks_usec()-began
	return result

func _start_worker(worker:Thread,task:Callable)->int:return worker.start(task)

func _launch(uuid:String,stage:String)->bool:
	var job:Dictionary=_work[uuid];var key:String=job.key
	# A sibling may have observed absence after this record was queued. Already
	# running workers finish normally; no cancellation or synchronous join here.
	if stage=="plan" and not _allow_none and _negative_candidates.has(job.entry.asset_path):
		_note_negative_hit(uuid,false);_fallback(uuid,"collision_asset_missing");return false
	if _planning.active_workers()+_preparing.active_workers()>=MAX_WORKERS:return false
	var ledger:RefCounted=_planning if stage=="plan" else _preparing
	var bytes:int=PLAN_BYTES if stage=="plan" else int(job.plan.estimated_bytes)
	# Admission never grants an oversized exclusive exception in this service.
	if bytes>ledger.byte_limit:_fallback(uuid,"preparation_capacity");return false
	if not ledger.reserve(key,{"estimated_bytes":bytes,"exclusive":false,"stage":stage}):return false
	var lease:=Lease.new();lease.planning=_planning;lease.preparing=_preparing;lease.key=key
	var token:=Drainer.CancelToken.new();token.set_meta("admission_owner",lease);token.set_meta("admission_release",lease.release)
	var worker:=Thread.new()
	var task:Callable=_plan_task.bind(_index,job.entries,_path,_root,_proof,token,_allow_none,_negative_candidates.has(job.entry.asset_path)) if stage=="plan" else _prepare_task.bind(job.plan,token,job.get("no_collision",false))
	_drainer.watch(worker,token)
	if _start_worker(worker,task)!=OK:
		_drainer.forget(worker);lease.release();_fallback(uuid,"thread_start");return false
	job.worker=worker;job.token=token;job.stage=stage
	if Trace.enabled:Trace.instant("collision.job.dispatch",{"job":key,"stage":stage,"path":job.entry.asset_path,"records":job.ids.size(),"none":job.get("no_collision",false),"bytes":bytes,"phase":_phase})
	if _phase=="prefetch" and not profile.has("prefetch_first_dispatch_us"):profile.prefetch_first_dispatch_us=Time.get_ticks_usec()
	profile["plan_jobs" if stage=="plan" else "prepare_jobs"]+=1
	if stage=="prepare":
		var source:String=job.entry.asset_path
		if _source_counts.has(source):profile.shared_source_jobs+=1
		_source_counts[source]=int(_source_counts.get(source,0))+1
	profile.peak_workers=maxi(int(profile.peak_workers),_planning.active_workers()+_preparing.active_workers())
	return true

func _poll()->void:
	for uuid:String in _work.keys():
		var job:Dictionary=_work[uuid]
		if not job.has("worker") or job.worker.is_alive():continue
		var worker:Thread=job.worker;var result:Dictionary=worker.wait_to_finish();_drainer.forget(worker)
		if Trace.enabled:Trace.instant("collision.job.finished",{"job":job.key,"stage":job.stage,"path":job.entry.asset_path,"records":job.ids.size(),"none":job.get("no_collision",false),"ok":result.get("ok",false),"reason":result.get("reason",""),"worker_us":result.get("elapsed_us",0),"phase":_phase})
		job.erase("worker");job.erase("token")
		if job.stage=="plan":_planning.park(job.key);profile.plan_us+=int(result.get("elapsed_us",0))
		else:_preparing.park(job.key);profile.prepare_us+=int(result.get("elapsed_us",0))
		if job.stage=="plan" and result.get("sidecar_missing",false):_negative_candidates[job.entry.asset_path]=true
		if not result.get("ok",false):
			var reason:String=str(result.get("reason","preparation_failed"))
			# Only the bounded candidate probe's absence result is shared. Source
			# changes, corrupt payloads, instance semantics and prepare failures are
			# never converted into a source-wide negative. This lasts one map/proof
			# attempt; a repaired sidecar is probed by the next Loader. The current
			# attempt continues through ordinary validated render fallback.
			if job.stage=="plan" and reason=="collision_asset_missing":_negative_candidates[job.entry.asset_path]=true
			result.clear();_fallback(uuid,reason);continue
		if job.stage=="plan":
			job.plan=result.plan;job.no_collision=result.get("no_collision",false);result.clear();job.stage="planned"
			if not job.no_collision and job.ids.size()>1:
				for member:String in job.ids.slice(1):
					if _states.get(member,{}).get("job_id","")==uuid:_erase_state(member)
				job.ids=[job.ids[0]];job.entries=[job.entry];_waiting_capacity=true
			if not job.no_collision and int(job.plan.retained_upper_bytes)>Residency.MAX_RETAINED_BYTES:_fallback(uuid,"store_capacity")
		else:
			if job.get("no_collision",false):
				var measured:Dictionary=result.get("profile",{})
				for counter:String in ["source_sha_calls","native_identity_reads","map_sha_calls","records","proofs","fallbacks"]:
					var field:="none_"+counter
					profile[field]=int(profile.get(field,0))+int(measured.get(counter,0))
			job.erase("plan");job.result=result;job.stage="ready"
			if _phase=="prefetch":
				profile.prefetch_ready_count=int(profile.get("prefetch_ready_count",0))+1
				if not profile.has("prefetch_first_ready_us"):profile.prefetch_first_ready_us=Time.get_ticks_usec()

func _enqueue_ready()->void:
	for uuid:String in _work.keys():
		var job:Dictionary=_work[uuid]
		if job.stage!="ready":continue
		if job.get("no_collision",false):
			_accept_none(uuid,job)
			continue
		var intact:=true
		for member:String in job.ids:
			if _states.get(member,{}).get("job_id","")!=uuid:intact=false;break
		if not intact:
			# A sealed geometry Batch cannot be filtered. Replan live members;
			# never install a body for a consumer whose request was withdrawn.
			_cancel_job(uuid);_waiting_capacity=true;continue
		var accepted:Dictionary=_store.enqueue(job.result.batch,_epoch)
		if not accepted.ok:
			if accepted.error=="queue_capacity":continue
			_fallback(uuid,str(accepted.error));continue
		# The store now owns and charges Batch + native shape storage. Drop every
		# queue result alias before releasing its completed worker reservation.
		job.result.clear();job.erase("result");_planning.release(job.key);_preparing.release(job.key)
		_work.erase(uuid)
		for member:String in job.ids:
			if _states.get(member,{}).get("job_id","")!=uuid:continue
			_states[member].state="installing";_states[member].reason="physics_pending";profile.accepted+=1

func _accept_none(id:String,job:Dictionary)->void:
	var proofs:Dictionary=job.result.get("proofs",{})
	var fallbacks:Dictionary=job.result.get("fallbacks",{})
	for uuid:String in job.ids:
		var state:Dictionary=_states.get(uuid,{})
		if state.get("job_id","")!=id:continue
		var receipt:NoCollision.Receipt=proofs.get(uuid) as NoCollision.Receipt
		var reason:String=str(fallbacks.get(uuid,"none_proof_identity"))
		if receipt!=null and receipt.matches_entry(state.entry) and receipt.matches_context(_index,_path,_root,_proof):
			var bytes:int=receipt.retained_bytes()
			if bytes>0 and _none_proof_bytes+bytes<=MAX_NONE_PROOF_BYTES:
				state.proof=receipt;state.proof_bytes=bytes;state.state="not_required";state.reason="collision_not_required"
				_none_proof_bytes+=bytes
				profile.none_accepted=int(profile.get("none_accepted",0))+1
				profile.none_peak_bytes=maxi(int(profile.get("none_peak_bytes",0)),_none_proof_bytes)
				if Trace.enabled:Trace.instant("collision.none.accept",{"uuid":uuid,"job":job.key,"path":receipt.asset_path(),"record_index":receipt.record_index(),"epoch":_epoch,"bytes":bytes})
				continue
			reason="none_proof_capacity"
		state.state="fallback";state.reason=reason;_note_fallback(uuid,reason)
	# Individual typed receipts now have independent retained charges. Drop
	# every result alias before returning the shared preparation reservation.
	proofs={};fallbacks={};job.result.clear();job.erase("result")
	_planning.release(job.key);_preparing.release(job.key);_work.erase(id)

func _fallback(uuid:String,reason:String)->void:
	var ids:Array=_work[uuid].ids.duplicate() if _work.has(uuid) else [uuid]
	_discard(uuid)
	for member:String in ids:
		if _states.get(member,{}).get("job_id","")!=uuid:continue
		_states[member].state="fallback";_states[member].reason=reason
		_note_fallback(member,reason)

func _note_fallback(uuid:String,reason:String)->void:
	# Retiring a request must not erase the reason an attempted transaction
	# fell back before visual publication won the race. Keep only bounded IDs.
	profile.fallbacks+=1
	profile.fallback_reason_totals[reason]=int(profile.fallback_reason_totals.get(reason,0))+1
	if profile.fallback_samples.size()<16:profile.fallback_samples.append({"uuid":uuid,"reason":reason})

func _note_negative_hit(uuid:String,note_fallback:bool=true)->void:
	profile.negative_candidate_hits=int(profile.get("negative_candidate_hits",0))+1
	if note_fallback:_note_fallback(uuid,"collision_asset_missing")

func _discard(uuid:String)->void:
	if not _work.has(uuid):return
	var job:Dictionary=_work[uuid]
	if job.has("worker"):
		# The token owns both ledgers until the independent tree drainer joins.
		job.token.cancel();_drainer.abandon(job.worker)
	else:
		if job.get("result") is Dictionary:job.result.clear()
		job.erase("plan");_planning.release(job.key);_preparing.release(job.key)
	_work.erase(uuid)

func _process(_delta:float)->void:
	if _phase!="adopted" or not _context():return
	_advance_queue(1500,true)

func _advance_queue(budget_usec:int,install:bool)->void:
	var allowance:=FrameBudget.allowance("collision",budget_usec,not install)
	if allowance<=0:return
	var began:=Time.get_ticks_usec()
	_poll()
	if install:_enqueue_ready()
	if _waiting_capacity and _pending_count()<MAX_PENDING:_reconcile_requests()
	# Dispatch is CPU-only and still subject to both worker/byte ledgers. Let it
	# overlap the existing main-thread shape slices instead of waiting until a
	# slice has consumed the entire local frame allowance.
	if _dispatch_first:_dispatch_work(allowance,began)
	var remaining:int=allowance-(Time.get_ticks_usec()-began)
	if install and remaining>0:_store.step(remaining)
	if not _dispatch_first:_dispatch_work(allowance,began)
	profile.max_main_us=maxi(int(profile.max_main_us),Time.get_ticks_usec()-began)
	FrameBudget.charge("collision",began)
	if install and _work.is_empty() and not _waiting_capacity and int(_store.debug_snapshot().pending)==0:set_process(false)

func _dispatch_work(allowance:int,began:int)->void:
	var ordered:Array=_work.keys()
	ordered.sort_custom(func(a,b):return _work[a].priority<_work[b].priority if _work[a].priority!=_work[b].priority else _work[a].order<_work[b].order)
	for uuid:String in ordered:
		if Time.get_ticks_usec()-began>=allowance:
			if _dispatch_profile:_note_dispatch_budget_delay(began,allowance)
			break
		if _work[uuid].stage=="planned":_launch(uuid,"prepare")
		elif _work[uuid].stage=="queued":_launch(uuid,"plan")

func _note_dispatch_budget_delay(began:int,allowance:int)->void:
	var active:=_planning.active_workers()+_preparing.active_workers()
	if active>=MAX_WORKERS:return
	for job:Dictionary in _work.values():
		if job.stage not in ["queued","planned"]:continue
		var ledger:RefCounted=_planning if job.stage=="queued" else _preparing
		var bytes:int=PLAN_BYTES if job.stage=="queued" else int(job.plan.estimated_bytes)
		if bytes>ledger.byte_limit or not ledger.can_admit(job.key,{"estimated_bytes":bytes,"exclusive":false}):continue
		profile.dispatch_budget_eligible_frames=int(profile.get("dispatch_budget_eligible_frames",0))+1
		if active==0:profile.dispatch_budget_idle_frames=int(profile.get("dispatch_budget_idle_frames",0))+1
		if Trace.enabled:Trace.instant("collision.dispatch.frame_budget",{"job":job.key,"active_workers":active,"elapsed_us":Time.get_ticks_usec()-began,"allowance_us":allowance,"dispatch_first":_dispatch_first,"store_pending":_store.debug_snapshot().pending if is_instance_valid(_store) else 0})
		return

func snapshot()->Dictionary:
	var result:=profile.duplicate(true);result.pending=_pending_count();result.planning=_planning.snapshot();result.preparing=_preparing.snapshot()
	result.phase=_phase;result.ready_count=_ready_count()
	result.negative_candidate_sources=_negative_candidates.size()
	result.no_collision_proof_enabled=_allow_none;result.none_proof_bytes=_none_proof_bytes
	result.dispatch_before_installation=_dispatch_first;result.dispatch_profile_enabled=_dispatch_profile
	result.states={};result.fallback_reasons={}
	for value:Dictionary in _states.values():
		result.states[value.state]=int(result.states.get(value.state,0))+1
		if value.state=="fallback":result.fallback_reasons[value.reason]=int(result.fallback_reasons.get(value.reason,0))+1
	result.store=_store.debug_snapshot() if is_instance_valid(_store) else {}
	return result

func cancel(reason:String="cancelled")->void:
	if _cancelled:return
	_cancelled=true;_phase="cancelled";set_process(false);_tickets.clear()
	for uuid:String in _work.keys():_discard(uuid);profile.cancelled+=1
	_states.clear();_none_proof_bytes=0
	if is_instance_valid(_store):_store.cancel(reason)

func _enter_tree()->void:
	if _phase=="adopted" and _context():set_process(true)
func _exit_tree()->void:call_deferred("_dispose_if_detached")
func _dispose_if_detached()->void:
	if _phase=="handoff" and _map!=null and is_instance_valid(_map.get_ref()) and not _map.get_ref().is_queued_for_deletion() and get_parent()==_map.get_ref():return
	if not _context():cancel("loader_detached")
func _notification(what:int)->void:
	if what==NOTIFICATION_PREDELETE:cancel("loader_freed")
