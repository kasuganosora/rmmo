extends SceneTree
## Real queue/admission/Thread/Drainer lifecycle, synthetic CPU model results.
## No resource import, production map, mesh, texture or GPU scene is required.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const CLIP=AABB(Vector3(-10,-10,-10),Vector3(40,20,40))
const PREFIX="user://entry_prefetch_probe_"
class Gate extends RefCounted:
	var semaphore:=Semaphore.new()
	var scene_id:=0
	var cancelled:=false
	var failure:=""
	var cooperative:=false
	func work(token:RefCounted)->Dictionary:
		if cooperative:
			while not token.is_cancelled():OS.delay_usec(100)
		else:semaphore.wait()
		cancelled=token.is_cancelled()
		var scene:=Node3D.new();scene_id=scene.get_instance_id()
		return {"error":failure,"scene":scene,"source_digest":"a".repeat(64),"elapsed_us":1,"records":[],"dependencies":{}}
class Probe extends Deferred:
	var calls:Array=[]
	var gates:Dictionary={}
	var accept_calls:=0
	var publication_calls:=0
	func _make_prepare_task(path:String,_digest:String,token:RefCounted,_item:Dictionary,_faces:bool,_root:String,_requests:Array,_native:bool,_need_model:bool)->Callable:
		calls.append(path)
		return gates[path].work.bind(token)
	func _accept_prepared_records(result:Dictionary)->void:
		accept_calls+=1;super(result)
	func _publish_ready(_began:int,_budget:int=INTERACTIVE_BUDGET_US)->Dictionary:
		publication_calls+=1
		for job:Dictionary in _jobs.values():
			if not job.get("accepted",false):continue
			for uuid:String in job.publication_ids:
				if _demanded_by_id.has(uuid):_demanded_by_id[uuid].published=true
		return {"units":0,"unit_us":0,"max_unit_us":0,"scan_us":0}
class Host extends Node3D:
	var _ready_for_play:=false
class QuietCover extends Deferred.TransferLoading:
	func _ready()->void:set_process(false)
	func _process(_delta:float)->void:pass
var failures:=0
var passed:=0
var cache_paths:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if ok:passed+=1
	else:failures+=1
func item(id:String,x:float,path:String="",native:bool=false)->Dictionary:
	if path.is_empty():path=PREFIX+id+".glb"
	if not cache_paths.has(path):cache_paths.append(path)
	return {"record":{"uuid":id,"collision":"none"},"path":path,"bounds":AABB(Vector3(x,0,0),Vector3.ONE),"digest":"","native_reference":native,"memory":{"estimated_bytes":64,"exclusive":false,"known":true}}
func queue(rows:Array)->Probe:
	var result:=Probe.new();result.pending=rows;result.loading_worker_limit=2
	result._admission.byte_limit=128
	for row:Dictionary in rows:result.gates[row.path]=Gate.new()
	return result
func start_prefetch(service:Probe,paths:Dictionary={})->bool:
	var ok:=service.begin_entry_prefetch(self,CLIP,paths)
	if ok:service._admission.byte_limit=128
	return ok
func wait_ready(service:Probe,count_:int)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while int(service.profile.get("entry_prefetch_ready_jobs",0))<count_ and Time.get_ticks_msec()<deadline:
		service.pump_entry_prefetch();await process_frame
	check(int(service.profile.get("entry_prefetch_ready_jobs",0))==count_,"CPU worker results reached ready state")
func wait_dispatched(service:Probe,count_:int)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while service.calls.size()<count_ and Time.get_ticks_msec()<deadline:
		service.pump_entry_prefetch();await process_frame
	check(service.calls.size()==count_,"deadline-bounded prefetch dispatch reached the requested worker count")
func quiesce(queue_:Node,state:Dictionary)->void:
	await queue_.quiesce();state.done=true
func run()->void:
	Deferred.native_entry_prefetch_enabled=false # Preserve the legacy model-only lifecycle comparison.
	var path_a:=PREFIX+"a.glb";var path_b:=PREFIX+"b.glb";var path_core:=PREFIX+"core.glb"
	var service:=queue([item("native",0,"reference:native",true),item("core",1,path_core),item("a",8,path_a),item("a_second",10,path_a),item("b",9,path_b),item("later",-9),item("far",500)])
	service.set_demand("original",AABB(Vector3(490,-1,-1),Vector3(20,2,2)))
	service.set_demand_scope(["original"])
	var paths:Dictionary={};paths[path_core]=true
	check(not service.begin_entry_prefetch(self,AABB(),paths),"invalid prefetch clip has no effect")
	check(start_prefetch(service,paths),"off-tree queue enters explicit prepare-only phase")
	var physical:=int(OS.get_memory_info().get("physical",16*1024*1024*1024))
	check(service.profile.entry_prefetch_budget_bytes==clampi(physical/4,512*1024*1024,8*1024*1024*1024),"prefetch uses the same physical-RAM budget as ordinary activation")
	paths.clear()
	check(not start_prefetch(service),"second begin cannot replace a live prefetch transaction")
	service.activate(null)
	check(not service._active and not service.begin_entry_loading(null,CLIP),"active prefetch cannot be bypassed by ordinary activation or entry loading")
	service.pump_entry_prefetch()
	# Dispatch is now deadline/cursor bounded; a cold first decision may use the
	# first slice without forcing the second worker to start in that same frame.
	var dispatch_deadline:=Time.get_ticks_msec()+5000
	while service.calls.size()<2 and Time.get_ticks_msec()<dispatch_deadline:
		await process_frame;service.pump_entry_prefetch()
	check(service.calls.size()==2 and service.calls.has(path_a) and service.calls.has(path_b),"dispatch selects new safety models, deduplicates path and excludes native/core/far rows")
	check(service._jobs.size()==2 and service._admission.reserved_bytes==128,"same real admission ledger charges both in-flight tasks")
	var first_job:Dictionary=service._jobs[path_a];var first_token:RefCounted=first_job.token
	service.gates[path_a].semaphore.post();service.gates[path_b].semaphore.post()
	await wait_ready(service,2)
	for i in 3:service.pump_entry_prefetch()
	check(service.calls.size()==2 and service._admission.count()==2 and service._admission.reserved_bytes==128,"ready results retain slots and bytes instead of growing an unbounded prefetch backlog")
	check(not service.is_inside_tree() and not service._active and not service.is_processing(),"prepare-only phase never activates a scene node")
	check(service.accept_calls==0 and service.publication_calls==0 and service._prepared_paths.is_empty() and service.profile.models==0,"prefetch never accepts records or publishes geometry")
	check(not Deferred.Assets._scenes.has(path_a) and not Deferred.Assets._scenes.has(path_b),"prefetch does not alter the shared model cache")
	check(service._jobs[path_a].result.scene.get_parent()==null and service._jobs[path_b].result.scene.get_parent()==null,"prepared models remain private and outside every SceneTree")
	service.finish_entry_prefetch();service.pump_entry_prefetch()
	check(service.get_demand_scope()==["original"] and service._demands.has("entry_safety"),"handoff restores real scope while retaining the required safety ticket")
	check(is_same(service._jobs[path_a],first_job) and service._jobs[path_a].token==first_token and not first_token.is_cancelled(),"handoff preserves exact job/token ownership without scope-driven cancellation")
	check(service.calls.size()==2 and service._admission.reserved_bytes==128,"handoff stops pumping without repeating preparation or releasing reservations")
	var host:=Host.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map);map.set_meta("extras",{"rmmo_records":[]})
	map.set_meta("entry_plan",{"core_resources_ready_us":1,"safety_clip":CLIP})
	map.add_child(service)
	var cover:=QuietCover.new();host.add_child(cover);cover.drawn_frame=0
	check(not start_prefetch(service),"attached queues cannot start a second off-tree prefetch")
	check(service.begin_entry_loading(host,CLIP,cover),"normal entry takes ownership after core readiness")
	service.set_process(false);service._admission.worker_limit=0
	service._process(0)
	check(service.accept_calls==2 and service.publication_calls==1 and service.calls.size()==2,"existing ready jobs pass through normal acceptance without reparse")
	check(Deferred.Assets.has_cached_scene(path_a,"a".repeat(64)) and Deferred.Assets.has_cached_scene(path_b,"a".repeat(64)),"only normal entry stamps and publishes verified model templates")
	check(service._jobs.is_empty() and service._admission.reserved_bytes==0 and service._admission.byte_limit==128,"consumption retires original reservations and preserves handoff byte allowance")
	service.end_entry_loading();service.set_process(false)
	check(service.get_demand_scope()==["original"] and not service._demands.has("entry_safety"),"entry completion cannot strand the queue in a removed temporary ticket")
	service._refresh_demanded()
	check(service._demanded.any(func(row):return row.record.uuid=="far"),"previous ordinary demand is usable again after entry")
	host.free()
	await cancellation_cases()
	await failure_case()
	await shutdown_cases()
	for path:String in cache_paths:Deferred.Assets.evict_cached_scene(path)
	print("DEFERRED_ENTRY_PREFETCH passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
func cancellation_cases()->void:
	var live:=item("cancel_live",0);var ready:=item("cancel_ready",1)
	var service:=queue([live,ready]);start_prefetch(service);service.pump_entry_prefetch()
	await wait_dispatched(service,2)
	var worker:Thread=service._jobs[live.path].worker
	var live_gate:Gate=service.gates[live.path]
	service.gates[ready.path].semaphore.post();await wait_ready(service,1)
	var ready_id:int=service.gates[ready.path].scene_id
	var state:={"done":false};quiesce(service,state)
	check(not state.done and service._admission.reserved_bytes==64 and service._jobs[live.path].token.is_cancelled(),"off-tree quiesce cancels live work while retaining its charge until join")
	check(not is_instance_id_valid(ready_id),"already joined unpublished scene is safely disposed")
	await process_frame
	check(not state.done and worker.is_alive(),"off-tree quiesce yields main frames instead of blocking on a live worker")
	live_gate.semaphore.post()
	var deadline:=Time.get_ticks_msec()+5000
	while not state.done and Time.get_ticks_msec()<deadline:await process_frame
	check(state.done and not worker.is_started() and live_gate.cancelled,"late result observes cancellation and joins before owner resumes")
	check(not is_instance_id_valid(live_gate.scene_id) and service._jobs.is_empty() and service._admission.count()==0,"cancelled late result and all reservations are gone before free")
	check(service._drainer.jobs.is_empty() and service.get_demand_scope().is_empty() and service._entry_prefetch.is_empty(),"drainer ownership and temporary scope are fully released")
	check(service.accept_calls==0 and service.publication_calls==0,"cancellation cannot publish or accept prefetch output")
	service.free()
	# Cancellation after finish but before first tree attachment still owns a tree.
	var row:=item("handoff_cancel",0);service=queue([row]);start_prefetch(service);service.pump_entry_prefetch()
	await wait_dispatched(service,1)
	service.finish_entry_prefetch();service.gates[row.path].semaphore.post();await service.quiesce()
	check(service._jobs.is_empty() and service._admission.reserved_bytes==0 and service._drainer.jobs.is_empty(),"off-tree cancellation remains valid after successful finish handoff")
	service.free()
func failure_case()->void:
	var row:=item("broken",0);var service:=queue([row]);service.gates[row.path].failure="injected verified-source failure"
	start_prefetch(service);service.pump_entry_prefetch();service.gates[row.path].semaphore.post()
	var deadline:=Time.get_ticks_msec()+5000
	while not service.path_errors.has(row.path) and Time.get_ticks_msec()<deadline:
		service.pump_entry_prefetch();await process_frame
	check(service.path_errors.get(row.path)=="injected verified-source failure" and service._jobs.is_empty(),"worker validation failure follows existing per-path isolation")
	check(not Deferred.Assets._scenes.has(row.path) and service._admission.reserved_bytes==0 and service.accept_calls==0,"failure returns its reservation without publishing invalid content")
	check(not is_instance_id_valid(service.gates[row.path].scene_id),"failed private model is destroyed")
	await service.quiesce();service.free()
func shutdown_cases()->void:
	var row:=item("shutdown",0);var service:=queue([row]);var gate:Gate=service.gates[row.path];gate.cooperative=true
	start_prefetch(service);await wait_dispatched(service,1);service.shutdown()
	check(gate.cancelled and not is_instance_id_valid(gate.scene_id) and service._jobs.is_empty() and service._admission.reserved_bytes==0,"explicit shutdown safely drains a never-attached queue")
	check(service._drainer.jobs.is_empty() and not start_prefetch(service),"shutdown is permanent and releases drainer ownership")
	service.shutdown();service.free()
	row=item("forced_free",0);service=queue([row]);gate=service.gates[row.path];gate.cooperative=true
	start_prefetch(service);await wait_dispatched(service,1)
	var admission:RefCounted=service._admission;var drainer:Node=service._drainer
	service.free()
	check(gate.cancelled and not is_instance_id_valid(gate.scene_id) and admission.reserved_bytes==0 and drainer.jobs.is_empty(),"forced off-tree free has a last-resort lifetime drain without _exit_tree")
