extends RefCounted
## Diagnostic-only read observer. No admission calls which can preempt workers,
## no estimate/texture-plan cache mutation, no ownership of job resources.
const DependencyIndex=preload("res://scripts/world3d/map_dependency_index.gd")
const CollisionProducts=preload("res://scripts/world3d/collision_product_cache.gd")
var _event_cursor:=0
var _ledger:Dictionary={}
var _cursor_work:Dictionary={}
var _candidate_cursor:=0
var candidate_limit:=4

func _identity(path:String,generation:int)->String:
	return JSON.stringify([path,generation])

func _ingest(events:Array)->void:
	while _event_cursor<events.size():
		var event:Dictionary=events[_event_cursor];_event_cursor+=1
		if not event.has("generation") or not event.has("path"):continue
		var identity:=_identity(str(event.path),int(event.generation))
		if not _ledger.has(identity):_ledger[identity]={"committed":{},"private_finished":{},"events":0,"sampled_private_work_us":0,"cursor_counter_resets":0}
		var data:Dictionary=_ledger[identity];var details:Dictionary=event.get("details",{})
		data.events+=1
		var uuid:String=str(details.get("uuid",event.get("uuid","")))
		if event.get("event")=="committed" and not uuid.is_empty():data.committed[uuid]=true
		if event.get("event")=="private_finished" and not uuid.is_empty():data.private_finished[uuid]=true

func _native_estimate(queue:Node,item:Dictionary,requests:Array)->Dictionary:
	# Mirrors ONLY the native-reference branch with provably empty image plan.
	# Sources with any potential texture plan retain an explicit unknown status.
	if not item.get("native_reference",false):return {"estimate_verified":false,"unknown_reason":"non_native_route"}
	var rows:Array=queue._reference_index.get("rows",[])
	var positions:Array=[];var reference_bytes:=0;var collision_workspace:=0
	var wants_textures:bool=queue.prefab_texture_preparation_enabled or queue._targeted_bridge_textures(item)
	for request:Dictionary in requests:
		reference_bytes+=int(request.get("memory_bytes",65536))
		if not request.has("record_index"):continue
		var at:int=int(request.record_index)
		if at<0 or at>=rows.size():return {"estimate_verified":false,"unknown_reason":"request_index_unavailable"}
		positions.append(at)
		if wants_textures and not rows[at].get("prefab_textures",{}).is_empty():return {"estimate_verified":false,"unknown_reason":"texture_plan_not_proven_empty"}
		if CollisionProducts.enabled and rows[at].get("prefab_locked",false):collision_workspace=CollisionProducts.WORKSPACE_BYTES
	for row:Dictionary in DependencyIndex.terrain_context_rows(queue._reference_index,positions):reference_bytes+=int(row.memory_bytes)
	return {"estimate_verified":true,"estimated_bytes":maxi(65536,reference_bytes)+collision_workspace,"exclusive":false,"estimate_source":"native_empty_texture_plan_readonly","reference_bytes":reference_bytes,"collision_workspace_bytes":collision_workspace,"request_count":requests.size()}

func _candidate(queue:Node,path:String)->Dictionary:
	var item:Dictionary=queue._path_first.get(path,{})
	var result:Dictionary={"path":path,"eligible":not item.is_empty() and not queue.path_errors.has(path) and not queue._jobs.has(path),"estimate_verified":false}
	if item.is_empty():result.eligible=false;result.unknown_reason="missing_first_item";return result
	if queue.instance_errors.has(str(item.get("record",{}).get("uuid",""))):result.eligible=false;return result
	# This estimate applies to normal post-entry native demand dispatch only.
	if queue._cancelled or not queue.error.is_empty() or not queue._entry_prefetch.is_empty():result.eligible=false;result.unknown_reason="inactive_or_prefetch_route";return result
	var requests:Array=queue._reference_requests(path)
	var estimate:=_native_estimate(queue,item,requests)
	if path.begins_with("reference:road_batch:") and requests.size()>1 and estimate.get("estimate_verified",false) and int(estimate.estimated_bytes)>queue._admission.byte_limit:
		estimate=_native_estimate(queue,item,[requests[0]])
		estimate.road_batch_solo=true
	result.merge(estimate,true)
	return result

func sample(queue:Node,at_us:int,phase:String,events:Array)->Dictionary:
	var began:=Time.get_ticks_usec()
	_ingest(events)
	var active_workers:=0;var exclusive_count:=0
	for entry:Dictionary in queue._admission._entries.values():
		if entry.get("occupies_worker",true):active_workers+=int(entry.get("worker_slots",1))
		if entry.get("exclusive",false):exclusive_count+=1
	var unstarted:Array[String]=[]
	for path:String in queue._demanded_by_path:
		if not queue._jobs.has(path) and not queue.path_errors.has(path):unstarted.append(path)
	var candidates:Array=[]
	var count:=mini(candidate_limit,unstarted.size())
	for i:int in range(count):
		var at:=(_candidate_cursor+i)%unstarted.size()
		candidates.append(_candidate(queue,unstarted[at]))
	if not unstarted.is_empty():_candidate_cursor=(_candidate_cursor+count)%unstarted.size()
	var jobs:Array=[];var live:=0
	for path:String in queue._jobs:
		var job:Dictionary=queue._jobs[path]
		var generation:int=job.token.get_instance_id()
		var identity:=_identity(path,generation)
		if not _ledger.has(identity):_ledger[identity]={"committed":{},"private_finished":{},"events":0,"sampled_private_work_us":0,"cursor_counter_resets":0}
		var ledger:Dictionary=_ledger[identity]
		var state:="accepted" if job.get("accepted",false) else "ready" if job.has("result") else "other"
		if job.has("worker"):
			state="live" if job.worker.is_alive() else "finished"
			if state=="live":live+=1
		var instance:Dictionary=job.get("instance_preparation",{})
		if instance.has("cursor"):
			var cursor_key:=identity+":"+str(instance.cursor.get_instance_id())
			var elapsed:int=int(instance.cursor.profile.get("elapsed_us",0))
			var previous:int=int(_cursor_work.get(cursor_key,0))
			if elapsed>=previous:ledger.sampled_private_work_us+=elapsed-previous
			else:ledger.cursor_counter_resets+=1
			_cursor_work[cursor_key]=elapsed
		for packet:Dictionary in job.get("publication_packets",{}).values():
			if not packet.has("index_preparation"):continue
			var index_key:=identity+":index:"+str(packet.index_preparation.get_instance_id())
			var elapsed:int=int(packet.index_preparation.profile.get("elapsed_us",0))
			var previous:int=int(_cursor_work.get(index_key,0))
			if elapsed>=previous:ledger.sampled_private_work_us+=elapsed-previous
			else:ledger.cursor_counter_resets+=1
			_cursor_work[index_key]=elapsed
		var reasons:Dictionary={};var pending_supports:=0;var pending_collisions:=0;var remaining:=0;var private_unfinished:=0
		for uuid:String in job.get("publication_ids",[]):
			var item:Dictionary=queue._demanded_by_id.get(uuid,{})
			if item.is_empty() or item.get("published",false) or queue.instance_errors.has(uuid) or queue.path_errors.has(path):continue
			remaining+=1
			if not ledger.private_finished.has(uuid):private_unfinished+=1
			var support_count:=0
			for support_id:String in queue._runtime_building_supports.get(uuid,{}):
				var support:Dictionary=queue._pending_by_record_id.get(support_id,{})
				if not support.is_empty() and not support.get("published",false):support_count+=1
			var status:Dictionary=queue._collision_publication_status(uuid)
			var collision_waiting:bool=status.get("owned",false) and status.get("pending",false)
			pending_supports+=support_count
			if collision_waiting:pending_collisions+=1
			var reason:="support" if support_count>0 else "collision" if collision_waiting else "eligible"
			reasons[reason]=int(reasons.get(reason,0))+1
		var lease:Dictionary=queue._admission._entries.get(path,{})
		var private_pending:bool=not instance.is_empty() or private_unfinished>0
		var block:Dictionary={"stage":"private_prepare" if private_pending else "commit","reason":"unknown","evidence":{}}
		# Commit dependency is not evidence that private preparation must wait.
		# Only classify all remaining items blocked; mixed ready items stay unknown.
		if not private_pending and remaining>0 and int(reasons.get("support",0))==remaining:block={"stage":"commit","reason":"support","evidence":{"pending_support_count":pending_supports}}
		elif not private_pending and remaining>0 and int(reasons.get("collision",0))==remaining:block={"stage":"commit","reason":"collision","evidence":{"pending_collision_count":pending_collisions}}
		jobs.append({"path":path,"generation":generation,"state":state,"private_work_us":ledger.sampled_private_work_us,"private_prepared_count":ledger.private_finished.size(),"committed_count":ledger.committed.size(),"cursor_counter_resets":ledger.cursor_counter_resets,"private_pending":private_pending,"remaining_count":remaining,"instance_uuid":instance.get("uuid",""),"instance_phase":instance.get("phase",""),"commit_block_reasons":reasons,"block":block,"consumed_is_not_commit":queue._job_consumed(job),"lease_present":not lease.is_empty(),"lease_stage":lease.get("stage",""),"lease_bytes":lease.get("bytes",0),"lease_occupies_worker":lease.get("occupies_worker",false),"cancelled":job.token.is_cancelled()})
	return {"at_us":at_us,"phase":phase,"capacity":{"jobs":queue._jobs.size(),"job_limit":queue._job_limit(),"live_workers":live,"worker_limit":queue._admission.worker_limit,"charged_workers":active_workers,"byte_limit":queue._admission.byte_limit,"reserved_bytes":queue._admission.reserved_bytes,"exclusive_count":exclusive_count,"entry_count":queue._admission._entries.size(),"unstarted_paths":unstarted.size(),"dispatch_fence":queue._dispatch_fence},"unstarted_candidates":candidates,"candidates_complete":count==unstarted.size(),"jobs":jobs,"observer_us":Time.get_ticks_usec()-began,"progress_scope":"Per-generation monotonic sampled cursor-work lower bound plus authoritative event counts. No missing interval is inferred CPU work."}
