extends RefCounted
## Coordinator runs on the caller's loading worker, never the scene thread.
## cancel() is the only method intended for concurrent calls. run() always joins
## every started worker before returning, including failure and cancellation.
## Injected parsers must own their resources and must not touch nodes or caches.
## Cancellation is sticky: create a new preparation for a new load transaction.
## Native products are read independently. Raw GLTF fallback uses one global
## import mutex shared with live streaming, including across loading queues.
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const MemoryEstimate=preload("res://scripts/world3d/asset_memory_estimate.gd")
const Embedded=preload("res://scripts/world3d/embedded_glb.gd")
# Compiled products own independent resources and never take this lock. Every
# default raw append uses it; Deferred holds it through raw append + generate.
# Injected parsers remain independent CPU probes and do not take this lock.
static var RAW_IMPORT_MUTEX:=Mutex.new()
var inflight_byte_limit:=4*1024*1024*1024
# Optional operation-local CPU probes. Configure before run(), never mid-load.
var memory_estimator:Callable
var cache_reader:Callable
var eligibility_checker:Callable
static var native_footprints_enabled:=true # Probe-only old-budget control.
var candidate_provider:Callable
var candidate_reader:Callable
# An early private compiled read may precede authoritative record validation.
# Raw imports wait on this operation-local gate, including serial fallback.
var fallback_gate:Callable
var _mutex := Mutex.new()
var _cancelled := false
var _running := false

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func is_cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value

func run(paths: Array, parser: Callable = Callable(), worker_limit: int = 2, thread_starter: Callable = Callable(), content_root:String="", verified_sources:Dictionary={}) -> Dictionary:
	_mutex.lock()
	if _running:
		_mutex.unlock()
		return {"error": ERR_BUSY, "cancelled": false, "entries": []}
	_running = true
	_mutex.unlock()
	var started := Time.get_ticks_usec()
	var unique: Array[String] = []
	var seen := {}
	for path in paths:
		if not path is String or path.is_empty():
			return _finish({"error": ERR_INVALID_PARAMETER, "cancelled": is_cancelled(), "entries": []}, started)
		if not seen.has(path):
			seen[path] = true
			unique.append(path)
	var native_route:=not parser.is_valid() or cache_reader.is_valid()
	var parse:=parser if parser.is_valid() else _parse_verified_fallback.bind(content_root,verified_sources)
	var limit := clampi(worker_limit, 1, 4)
	var eligibility_started := Time.get_ticks_usec()
	var eligible:Dictionary={};var estimates:Dictionary={};var candidates:Dictionary={};var native_estimates:Dictionary={};var legacy_estimates:Dictionary={};var native_bounds:Dictionary={};var required_resident:=0
	for path: String in unique:
		if is_cancelled(): break
		if not native_route or (eligibility_checker.call(path) if eligibility_checker.is_valid() else Embedded.can_copy(path)):eligible[path]=true
		var estimate:Variant=memory_estimator.call(path) if memory_estimator.is_valid() else (MemoryEstimate.estimate(path) if native_route else {"estimated_bytes":1,"exclusive":false,"known":true})
		if not estimate is Dictionary or not estimate.get("estimated_bytes") is int or estimate.estimated_bytes<=0 or not estimate.get("exclusive") is bool:
			estimate=MemoryEstimate._unknown("invalid_estimator")
		estimates[path]=estimate.duplicate()
		legacy_estimates[path]=estimate.duplicate()
		if native_route and (candidate_provider.is_valid() or not cache_reader.is_valid()):
			var candidate:Dictionary=candidate_provider.call(path) if candidate_provider.is_valid() else preload("res://scripts/world3d/compiled_asset_footprint.gd").candidate(path,content_root,str(verified_sources.get(path,"")))
			if not candidate.is_empty() and candidate.get("estimated_bytes") is int and candidate.estimated_bytes>0 and candidate.get("exclusive") is bool:
				# Source cleanup can shrink the raw envelope without changing the
				# native pixels or loader working set. A known native bound applies
				# even when it costs MORE; the legacy opt-out can still read native.
				native_bounds[path]=candidate.estimated_bytes
				legacy_estimates[path].estimated_bytes=maxi(estimate.estimated_bytes,candidate.estimated_bytes)
				legacy_estimates[path].exclusive=estimate.exclusive or candidate.exclusive
				if native_footprints_enabled:
					candidates[path]=candidate.duplicate(true)
					native_estimates[path]={"estimated_bytes":candidate.estimated_bytes,"exclusive":candidate.exclusive,"known":true,"reason":"verified_native_footprint"}
		# The synchronous API retains every completed model until its caller can
		# consume the returned array. Charge the full task estimate conservatively;
		# GLTFState may retain source buffers as well as decoded meshes/textures.
		required_resident+=int(native_estimates.get(path,legacy_estimates[path]).estimated_bytes)
	var eligibility_us := Time.get_ticks_usec() - eligibility_started
	var admission=Admission.new();admission.worker_limit=limit;admission.byte_limit=preload("res://scripts/world3d/definition_cache_policy.gd").work_budget(inflight_byte_limit)
	var completed:Dictionary={};var pending:Array=[];var fallbacks:Array=[]
	# Retired native packets must survive even when cancellation or a sibling
	# failure prevents their raw stage from starting. Resident is accounting, not
	# the in-flight admission cap: old native and new raw allocations coexist.
	var quarantine:Dictionary={};var quarantine_bytes:=0
	var saw_error:=false;var fallback_count:=0;var parallel_batches:=0;var next:=0
	var native_hits:=0;var native_misses:=0;var serial_fallbacks:=0;var threads_joined:=0;var threads_started:=0
	var resident:=0;var peak_live:=0
	var queued_at:=Time.get_ticks_usec()
	var admission_profile:={"started_us":queued_at,"blocked_us":0,"blocked_us_by_reason":{},"blocked_polls_by_reason":{},"task_queue_us":0,"max_task_queue_us":0,"stages":{},"tasks":{},
		"policy":"conservative_bytes_held_until_join_then_full_result_charge","timing_scope":"scheduler wall time; task waits and overlapping worker stages are not additive CPU time"}
	for path:String in unique:
		admission_profile.tasks[path]={"enqueued_us":queued_at,"queue_us":0,"blocked_us":0,"blocked_us_by_reason":{},"state":"queued","stages":[],"memory":MemoryEstimate.stage_profile(estimates.get(path,{}))}
		if native_bounds.has(path):
			admission_profile.tasks[path].memory.native_bound_bytes=native_bounds[path]
			admission_profile.tasks[path].memory.compiled_read_reservation_bytes=legacy_estimates[path].estimated_bytes
			admission_profile.tasks[path].memory.policy="legacy_native_or_raw_max_envelope"
		if native_estimates.has(path):
			var memory:Dictionary=admission_profile.tasks[path].memory
			memory.compiled_read_reservation_bytes=native_estimates[path].estimated_bytes
			memory.policy="fixed_native_product_then_separately_admitted_raw"
			memory.native_payload_sha=candidates[path].get("payload_sha","")
	if not candidates.is_empty():admission_profile.policy="source_bound_native_footprint_with_full_raw_fallback"
	var waiting:Dictionary={}
	while next<unique.size() or not fallbacks.is_empty() or not pending.is_empty():
		# A failed/cancelled job now drains ownership, not scheduler capacity.
		# Stop the preceding admission-wait span before any blocking joins.
		_close_admission_wait(waiting,admission_profile)
		var draining:bool=saw_error or is_cancelled()
		var at:=0
		while at<pending.size():
			var item:Dictionary=pending[at]
			if item.has("thread") and item.thread.is_alive() and not draining:at+=1;continue
			var reply:Dictionary=item.thread.wait_to_finish() if item.has("thread") else item.result
			if item.has("thread"):threads_joined+=1
			pending.remove_at(at)
			var path:String=unique[item.index]
			admission.set_stage(path,"joined_result")
			var sample:Dictionary={"stage":item.stage,"dispatched_us":item.dispatched_us,"queue_us":item.queue_us,"joined_us":Time.get_ticks_usec(),"worker_us":int(reply.elapsed_us),
				"worker_started_us":int(reply.get("worker_started_us",item.dispatched_us)),"worker_finished_us":int(reply.get("worker_finished_us",0)),"error":int(reply.error),"reserved_bytes":int(item.reserved_bytes),
				"raw_import_lock_wait_us":int(reply.get("raw_import_wait_us",0)),"compiled_cache_us":int(reply.get("cache_us",0))}
			admission_profile.tasks[path].stages.append(sample)
			var phase:Dictionary=admission_profile.stages[item.stage]
			phase.joined+=1;phase.worker_us+=int(reply.elapsed_us);phase.active_jobs-=1
			phase.active_reserved_bytes-=int(item.reserved_bytes)
			# Ownership transfers from in-flight to the explicitly retained initial
			# result set. Completed resources are not treated as freed RAM.
			admission.release(path)
			var legacy_retry:=is_legacy_source_retry(reply)
			var source_retry:bool=reply.get("native_source_retry",false) or legacy_retry
			if source_retry and (item.stage!="compiled_read" or (not legacy_retry and not candidates.has(path)) or quarantine.has(item.index)):
				reply.erase("native_source_retry");reply.error=ERR_INVALID_DATA;source_retry=false
			if source_retry:
				quarantine[item.index]=reply
				resident+=int(item.reserved_bytes);quarantine_bytes+=int(item.reserved_bytes)
				admission_profile.tasks[path].retired_native_charge_bytes=int(item.reserved_bytes)
				peak_live=maxi(peak_live,resident+admission.reserved_bytes)
				# Schedule with a resource-free control packet. The original packet
				# stays in quarantine until attached to the final main-owned entry.
				reply={"error":OK,"fallback_required":true,"elapsed_us":reply.elapsed_us,"cache_reason":reply.cache_reason}
			if (reply.get("fallback_required",false) or reply.get("serial_required",false)) and reply.error==OK:
				if reply.get("fallback_required",false):native_misses+=1
				else:eligible.erase(path)
				# Native preparation may discover a changed source. Refresh the raw
				# envelope before reserving its separate stage; never reuse the
				# discounted product reservation for a newly imported GLB.
				if native_route and not draining:
					var refreshed:Variant=memory_estimator.call(path) if memory_estimator.is_valid() else MemoryEstimate.estimate(path)
					if not refreshed is Dictionary or not refreshed.get("estimated_bytes") is int or refreshed.estimated_bytes<=0 or not refreshed.get("exclusive") is bool:refreshed=MemoryEstimate._unknown("invalid_fallback_estimate")
					estimates[path]=refreshed.duplicate()
					admission_profile.tasks[path].memory.raw_import_reservation_bytes=refreshed.estimated_bytes
				admission_profile.tasks[path].state="fallback_queued" if not draining else "discarded"
				if not draining:fallbacks.append({"index":item.index,"reason":reply.get("cache_reason",item.get("cache_reason","")),"prepare_us":int(reply.elapsed_us)+int(item.get("prepare_us",0)),"enqueued_us":Time.get_ticks_usec()})
			else:
				if item.has("cache_reason"):reply.cache_reason=item.cache_reason
				reply.elapsed_us+=int(item.get("prepare_us",0))
				completed[item.index]=reply
				resident+=int(item.reserved_bytes)
				admission_profile.tasks[path].state="retained";admission_profile.tasks[path].retained_charge_bytes=int(item.reserved_bytes)
				admission_profile.tasks[path].memory.retained_result_charge_bytes=int(item.reserved_bytes)
				admission_profile.tasks[path].compiled=reply.get("compiled",false);admission_profile.tasks[path].compiled_payload_bytes=int(reply.get("compiled_payload_bytes",0))
				peak_live=maxi(peak_live,resident+admission.reserved_bytes)
				if reply.get("compiled",false) and reply.error==OK:native_hits+=1
				if reply.error!=OK:saw_error=true;draining=true
		if saw_error or is_cancelled():
			if pending.is_empty():break
			continue
		while next<unique.size() or not fallbacks.is_empty():
			if is_cancelled():break
			_close_admission_wait(waiting,admission_profile)
			var route:Dictionary=fallbacks[0] if not fallbacks.is_empty() else {"index":next}
			var index:int=route.index;var path:String=unique[index]
			var fallback_stage:bool=route.has("reason")
			var serial:bool=fallback_stage and not eligible.has(path)
			var estimate:Dictionary=(estimates[path] if fallback_stage else native_estimates.get(path,legacy_estimates[path])).duplicate()
			if serial:estimate.exclusive=true
			var stage:String="compiled_read" if native_route and not fallback_stage else ("raw_import" if native_route else "injected_parse")
			estimate.stage=stage
			if not admission.reserve(path,estimate):
				var reason:String=admission.blocking_reason(path,estimate)
				waiting.merge({"path":path,"reason":reason,"since_us":Time.get_ticks_usec()},true)
				admission_profile.blocked_polls_by_reason[reason]=int(admission_profile.blocked_polls_by_reason.get(reason,0))+1
				break
			if fallback_stage:fallbacks.pop_front()
			else:next+=1
			var task_parser:Callable=_cache_stage.bind(content_root,verified_sources) if native_route and not fallback_stage else parse
			if not fallback_stage and candidates.has(path):task_parser=_candidate_stage.bind(candidates[path],content_root)
			if fallback_stage:task_parser=_guarded_fallback.bind(parse,not serial)
			if not pending.is_empty():parallel_batches+=1
			if serial:serial_fallbacks+=1
			var dispatched_at:=Time.get_ticks_usec();var queue_us:=maxi(0,dispatched_at-int(route.get("enqueued_us",queued_at)))
			admission_profile.task_queue_us+=queue_us;admission_profile.max_task_queue_us=maxi(admission_profile.max_task_queue_us,queue_us)
			admission_profile.tasks[path].queue_us+=queue_us;admission_profile.tasks[path].state=stage
			if not admission_profile.stages.has(stage):admission_profile.stages[stage]={"started":0,"joined":0,"worker_us":0,"active_jobs":0,"peak_jobs":0,"active_reserved_bytes":0,"peak_reserved_bytes":0}
			var phase:Dictionary=admission_profile.stages[stage]
			phase.started+=1;phase.active_jobs+=1;phase.peak_jobs=maxi(phase.peak_jobs,phase.active_jobs)
			phase.active_reserved_bytes+=int(estimate.estimated_bytes);phase.peak_reserved_bytes=maxi(phase.peak_reserved_bytes,phase.active_reserved_bytes)
			preload("res://scripts/world3d/load_trace.gd").elapsed("model.queue",dispatched_at-queue_us,{"path":path,"stage":stage,"estimated_bytes":estimate.estimated_bytes,"exclusive":admission.requires_exclusive(estimate)})
			var worker:=Thread.new();var task:=_invoke.bind(task_parser,path)
			var launch:int=thread_starter.call(worker,task) if thread_starter.is_valid() else worker.start(task)
			peak_live=maxi(peak_live,resident+admission.reserved_bytes)
			var item:={"index":index,"stage":stage,"dispatched_us":dispatched_at,"queue_us":queue_us,"reserved_bytes":int(estimate.estimated_bytes)}
			if fallback_stage:item.cache_reason=route.reason;item.prepare_us=route.get("prepare_us",0)
			if launch==OK:
				threads_started+=1;item.thread=worker;pending.append(item)
			else:
				fallback_count+=1;item.result=task.call();pending.append(item)
				# Inspect synchronous failures before dispatching another request.
				break
		if not pending.is_empty():OS.delay_usec(500)
	_close_admission_wait(waiting,admission_profile)
	admission_profile.finished_us=Time.get_ticks_usec();admission_profile.elapsed_us=admission_profile.finished_us-queued_at
	admission_profile.ledger_at_return=admission.snapshot()
	admission_profile.definition_cache=preload("res://scripts/world3d/definition_cache_policy.gd").snapshot()
	var entries:Array=[];var error:=OK
	for index in unique.size():
		if quarantine.has(index):
			if not completed.has(index):
				completed[index]={"path":unique[index],"error":ERR_SKIP,"elapsed_us":int(quarantine[index].elapsed_us)}
			var retired:Array=completed[index].get("retained_resources",[]).duplicate()
			retired.append(quarantine[index]);completed[index].retained_resources=retired
			admission_profile.tasks[unique[index]].retained_charge_bytes=int(admission_profile.tasks[unique[index]].get("retained_charge_bytes",0))+int(admission_profile.tasks[unique[index]].retired_native_charge_bytes)
			admission_profile.tasks[unique[index]].memory.retained_result_charge_bytes=admission_profile.tasks[unique[index]].retained_charge_bytes
		if not completed.has(index):continue
		var entry:Dictionary=completed[index];entries.append(entry)
		if entry.error!=OK and (error==OK or (error==ERR_SKIP and entry.error!=ERR_SKIP)):error=entry.error
	var cancelled := is_cancelled()
	return _finish({"error": ERR_SKIP if cancelled and error == OK else error, "cancelled": cancelled,
		"entries": entries, "unique_count": unique.size(), "worker_limit": limit,
		"fallback_count": fallback_count, "parallel_eligible_count": eligible.size(),
		"eligibility_us": eligibility_us, "parallel_batches": parallel_batches,"native_cache_hits":native_hits,"native_cache_misses":native_misses,
		"serial_fallbacks":serial_fallbacks,"threads_started":threads_started,"threads_joined":threads_joined,
		"inflight_budget_bytes":admission.byte_limit,"peak_inflight_estimate_bytes":admission.peak_bytes,"peak_inflight_jobs":admission.peak_jobs,
		"initial_required_resident_estimate_bytes":required_resident,"result_resident_estimate_bytes":resident,"peak_live_estimate_bytes":peak_live,"retired_native_estimate_bytes":quarantine_bytes,
		"inflight_reserved_at_return":admission.reserved_bytes,"inflight_jobs_at_return":admission.count(),"resident_estimate_policy":"full_task_estimate_retained_until_caller_consumes","admission_profile":admission_profile}, started)

static func _close_admission_wait(waiting:Dictionary,profile:Dictionary)->void:
	if waiting.is_empty():return
	var elapsed:=maxi(0,Time.get_ticks_usec()-int(waiting.since_us));var reason:String=waiting.reason
	profile.blocked_us+=elapsed;profile.blocked_us_by_reason[reason]=int(profile.blocked_us_by_reason.get(reason,0))+elapsed
	profile.tasks[waiting.path].blocked_us+=elapsed
	var reasons:Dictionary=profile.tasks[waiting.path].blocked_us_by_reason
	reasons[reason]=int(reasons.get(reason,0))+elapsed
	waiting.clear()

func _guarded_fallback(path:String,parse:Callable,require_eligible:bool)->Dictionary:
	if fallback_gate.is_valid() and not fallback_gate.call():return {"error":ERR_SKIP}
	# A source can change while a native candidate is being read. Recheck the
	# conservative GLTF gate on the worker immediately before import; a changed
	# route returns to the coordinator instead of importing unsafely in parallel.
	if require_eligible and not (eligibility_checker.call(path) if eligibility_checker.is_valid() else Embedded.can_copy(path)):
		return {"error":OK,"serial_required":true}
	var result:Variant=parse.call(path)
	return result if result is Dictionary else {"error":ERR_INVALID_DATA}

func _cache_stage(path:String,content_root:String,verified_sources:Dictionary)->Dictionary:
	var compiled:Variant=cache_reader.call(path) if cache_reader.is_valid() else preload("res://scripts/world3d/compiled_asset_cache.gd").read(path,str(verified_sources.get(path,"")),content_root)
	if not compiled is Dictionary or not compiled.get("hit") is bool:return {"error":ERR_INVALID_DATA,"retained_resources":[compiled]}
	if compiled.hit:
		if not compiled.has("packed") or compiled.packed==null:return {"error":ERR_INVALID_DATA,"retained_resources":[compiled]}
		return {"error":OK,"packed":compiled.packed,"compiled":true,"source_digest":compiled.get("source_digest",""),"cache_us":compiled.get("elapsed_us",0),"compiled_payload_bytes":int(compiled.get("bytes",0))}
	if not compiled.get("retained_resources",[]).is_empty():return _owned_cache_miss(compiled)
	return {"error":OK,"fallback_required":true,"cache_reason":compiled.get("reason","")}

static func _owned_cache_miss(compiled:Dictionary)->Dictionary:
	var retry:bool=compiled.get("reason")=="source_changed_during_read"
	var result:Dictionary={"error":ERR_BUSY if retry else ERR_INVALID_DATA,"cache_reason":compiled.get("reason","invalid_product"),"retained_resources":[compiled]}
	if retry:result.legacy_native_retry=true
	return result

static func is_legacy_source_retry(packet:Dictionary)->bool:
	if not packet.get("legacy_native_retry") is bool or not packet.legacy_native_retry or not packet.get("error") is int or packet.error!=ERR_BUSY or packet.get("cache_reason")!="source_changed_during_read":return false
	if packet.has("packed") or packet.has("fallback_required") or packet.has("native_source_retry"):return false
	var retained:Variant=packet.get("retained_resources")
	if not retained is Array or retained.size()!=1 or not retained[0] is Dictionary:return false
	var miss:Dictionary=retained[0]
	if not miss.get("hit") is bool or miss.hit or miss.get("reason")!="source_changed_during_read":return false
	var resources:Variant=miss.get("retained_resources")
	return resources is Array and resources.size()==1 and resources[0] is PackedScene

func _candidate_stage(path:String,candidate:Dictionary,content_root:String)->Dictionary:
	var raw:Variant=candidate_reader.call(path,candidate) if candidate_reader.is_valid() else preload("res://scripts/world3d/compiled_asset_preparation.gd").read(path,candidate,content_root)
	var result:Dictionary=raw if raw is Dictionary else {"error":ERR_INVALID_DATA}
	# Only a validated native product whose SOURCE changed can be retired and
	# retried. Other resource-bearing errors remain fatal and main-owned.
	if result.has("native_source_retry"):
		if not result.native_source_retry is bool or not result.native_source_retry or not result.get("error") is int or result.error!=ERR_BUSY or not result.get("packed") is PackedScene or not result.get("compiled") is bool or not result.compiled or not preload("res://scripts/world3d/compiled_asset_cache.gd")._sha(candidate.get("source_sha")) or not result.get("source_digest") is String or result.source_digest!=candidate.source_sha or not result.get("cache_reason") is String or result.cache_reason!="candidate_source_changed_after_read" or result.has("fallback_required"):
			result.erase("native_source_retry");result.error=ERR_INVALID_DATA
	# A reduced native reservation must never cover raw GLTF or discard a GPU
	# object here. The coordinator alone re-admits the explicit retry above.
	if (result.get("packed")!=null or not result.get("retained_resources",[]).is_empty()) and result.get("fallback_required",false):
		result.erase("fallback_required");result.error=ERR_INVALID_DATA
	return result

static func _parse_verified_fallback(path:String,content_root:String,verified_sources:Dictionary)->Dictionary:
	return _parse_fallback(path,content_root,str(verified_sources.get(path,"")))

static func _parse_fallback(path:String,content_root:String="",verified_digest:String="")->Dictionary:
	return _source_transaction(path,content_root,verified_digest,_append_gltf)

static func _source_transaction(path:String,content_root:String,verified_digest:String,parse:Callable)->Dictionary:
	# The cache miss may wait behind other imports. Bind the geometry returned by
	# the raw parser to the same source version the loader used for its Cook key.
	# This shared guard also permits deterministic replacement-race CPU probes.
	if not FileAccess.file_exists(path):return {"error":ERR_FILE_NOT_FOUND}
	if not verified_digest.is_empty() and (verified_digest.length()!=64 or not verified_digest.is_valid_hex_number(false)):return {"error":ERR_INVALID_PARAMETER}
	var Paths=preload("res://scripts/world3d/map_paths.gd")
	if not content_root.is_empty() and not Paths.allowed(path,content_root):return {"error":ERR_INVALID_PARAMETER}
	var before:=FileAccess.get_sha256(path)
	if before.is_empty():return {"error":ERR_FILE_CANT_READ}
	if not verified_digest.is_empty() and before!=verified_digest:return {"error":ERR_BUSY}
	var raw:Variant=parse.call(path)
	var after:=FileAccess.get_sha256(path)
	if after!=before or (not content_root.is_empty() and not Paths.allowed(path,content_root)):
		# No consumable state/source identity escapes a failed transaction. The
		# private GLTF resources can already own GPU textures, however: retain
		# them for the caller's main-thread quarantine disposal instead of
		# dropping their last references on this parser worker.
		return {"error":ERR_BUSY,"retained_resources":[raw]}
	if not raw is Dictionary or not raw.get("error") is int:return {"error":ERR_INVALID_DATA,"retained_resources":[raw]}
	var result:Dictionary=raw
	if result.error==OK:result.source_digest=before
	return result

static func _append_gltf(path:String)->Dictionary:
	var wait_started:=Time.get_ticks_usec()
	RAW_IMPORT_MUTEX.lock()
	var raw_import_wait_us:=Time.get_ticks_usec()-wait_started
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var error:=document.append_from_file(path,state,0,path.get_base_dir())
	RAW_IMPORT_MUTEX.unlock()
	return {"error":error,"document":document,"state":state,"compiled":false,"raw_import_wait_us":raw_import_wait_us}

func _finish(result: Dictionary, started: int) -> Dictionary:
	result.elapsed_us = Time.get_ticks_usec() - started
	_mutex.lock()
	_running = false
	_mutex.unlock()
	return result

static func _invoke(parser: Callable, path: String) -> Dictionary:
	var started := preload("res://scripts/world3d/load_trace.gd").begin("model.parse")
	var raw: Variant = parser.call(path)
	preload("res://scripts/world3d/load_trace.gd").elapsed("model.parse",started,{"path":path})
	var result: Dictionary = raw if raw is Dictionary else {"error": ERR_INVALID_DATA}
	if not result.get("error") is int: result.error = ERR_INVALID_DATA
	result.path = path
	result.worker_started_us=started;result.worker_finished_us=Time.get_ticks_usec()
	result.elapsed_us = result.worker_finished_us - started
	return result

static func _parse_verified_gltf(path:String,content_root:String,verified_sources:Dictionary)->Dictionary:
	return parse_gltf(path,content_root,str(verified_sources.get(path,"")))

static func parse_gltf(path: String,content_root:String="",verified_digest:String="") -> Dictionary:
	if not FileAccess.file_exists(path): return {"error": ERR_FILE_NOT_FOUND}
	var compiled:=preload("res://scripts/world3d/compiled_asset_cache.gd").read(path,verified_digest,content_root)
	if compiled.hit:return {"error":OK,"packed":compiled.packed,"compiled":true,"source_digest":compiled.source_digest,"cache_us":compiled.elapsed_us}
	if not compiled.get("retained_resources",[]).is_empty():
		# Workers cannot discard a failed native allocation or begin another
		# allocation under its lease. Coordinators quarantine or retire then retry.
		if OS.get_thread_caller_id()!=OS.get_main_thread_id():return _owned_cache_miss(compiled)
		if not preload("res://scripts/world3d/compiled_asset_cache.gd").dispose_miss(compiled):return _owned_cache_miss(compiled)
	var result:=_parse_fallback(path,content_root,verified_digest)
	result.cache_reason=compiled.reason
	return result
