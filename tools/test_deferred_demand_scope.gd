extends SceneTree
## Pure CPU queue/worker lifecycle test: fake holders contain no render resource.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const SHARED:="reference:shared"
class Document extends RefCounted:
	var calls:Array=[]
	func _mesh(record:Dictionary,_effects:bool=true,_timings:Variant=null)->Node3D:
		calls.append(record.uuid);return Node3D.new()
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if ok:passed+=1
	else:failures+=1
func clip(x:float)->AABB:return AABB(Vector3(x-10,-1,-1),Vector3(20,2,2))
func fixture()->Dictionary:
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",[])
	var index:=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	var service:=Deferred.new();map.add_child(service);var document:=Document.new();service._doc=document
	var inputs:Array=[["origin",0.,"reference:origin",""],["target",500.,SHARED,""],["far_shared",1000.,SHARED,""],["far_building",2000.,"reference:building","building:far"],["target_nav",530.,"reference:nav",""]]
	for at in inputs.size():
		var value:Array=inputs[at];var record:Dictionary={"uuid":value[0]}
		var bounds:=AABB(Vector3(value[1],0,0),Vector3.ONE)
		var entry:Dictionary={"record_index":at,"compact_record":record.duplicate(true),"bounds":bounds,"asset_path":value[2],"group_id":"","memory_bytes":32}
		service.pending.append({"record":record,"path":value[2],"bounds":bounds,"native_reference":true,"reference_entry":entry,"reference_prepared":false,"group_id":value[3]})
	service.activate(map);service._admission.worker_limit=0;service.set_process(false)
	service.set_demand("player",clip(0));service.set_demand("navigation:old",clip(1000),-1)
	service.set_demand("building_render",AABB(Vector3(-1,-1,-1),Vector3(3000,2,2)),10,"building")
	service.set_demand("transfer:7",clip(500),-2);service._refresh_demanded();service.set_process(false)
	return {"map":map,"service":service,"document":document}
func add_job(service:Node,path:String,ids:Array,worker:Thread=null)->Dictionary:
	service._admission.worker_limit=2
	service._admission.reserve(path,{"estimated_bytes":32,"exclusive":false})
	service._admission.worker_limit=0
	var job:Dictionary={"accepted":true,"result":{},"publication_ids":ids,"token":Deferred.Drainer.CancelToken.new()}
	if worker!=null:job.worker=worker;job.erase("result");job.accepted=false
	service._jobs[path]=job
	return job
func demanded_ids(service:Node)->Array:
	service._refresh_demanded()
	var ids:Array=service._demanded_by_id.keys();ids.sort();return ids
func run()->void:
	var f:=fixture();var service:Node=f.service
	var original_demands:Dictionary=service._demands.duplicate(true)
	check(demanded_ids(service)==["far_building","far_shared","origin","target"],"unrestricted queue includes origin, distant building, shared-model far instance and target")
	check(service._reference_requests(SHARED).size()==2,"normal mode can prepare both independently demanded instances of one model")
	var old_scope:Array=service.get_demand_scope()
	check(service.set_demand_scope(["transfer:7"]) and demanded_ids(service)==["target"],"transfer scope schedules only the destination ticket")
	check(service._demands==original_demands,"scope preserves every existing ticket and priority for rollback")
	var requests:Array=service._reference_requests(SHARED)
	check(requests.size()==1 and requests[0].compact_record.uuid=="target","shared-model reference read closure excludes a distant instance outside the scope")
	var copy:Array=service.get_demand_scope();copy.append("navigation:old")
	check(service.get_demand_scope()==["transfer:7"],"scope getter cannot mutate scheduler ownership")
	check(not service.set_demand_scope(["transfer:7",42]) and service.get_demand_scope()==["transfer:7"],"invalid scope fails atomically")
	service.ensure_geometry(AABB(Vector3(-1,-1,-1),Vector3(3000,2,2)),"navigation:old")
	check(demanded_ids(service)==["target"],"old navigation updating its ticket cannot widen the transfer scope")
	service.ensure_geometry(clip(530),"navigation:new")
	check(demanded_ids(service)==["target"],"a new ticket alone is insufficient to extend scope")
	check(service.allow_demand_in_scope("navigation:new") and demanded_ids(service)==["target","target_nav"],"explicit authorization adds the staged target navigation demand")
	service.set_demand_scope(old_scope)
	check(demanded_ids(service)==["far_building","far_shared","origin","target","target_nav"],"restoring the previous empty scope re-enables preserved tickets and current navigation demand")
	check(service.allow_demand_in_scope("navigation:later") and service.get_demand_scope().is_empty(),"allow in normal mode does not accidentally restrict all other tickets")
	f.map.free()

	f=fixture();service=f.service
	var shared:=add_job(service,SHARED,["target","far_shared"])
	var far:=add_job(service,"reference:building",["far_building"])
	for item:Dictionary in service.pending:
		if item.path==SHARED:item.reference_prepared=true
	service._prepared_paths[SHARED]=true
	service.set_demand_scope(["transfer:7"]);service.set_process(false)
	check(not shared.token.is_cancelled() and far.token.is_cancelled(),"mixed ready model keeps required target work while unrelated completed building is cancelled")
	for i in 3:service._process(0)
	check(f.document.calls==["target"] and service.profile.instances==1,"only target is published from a model that also contained a ready distant instance")
	check(service.is_idle() and not service.is_complete() and service.pending.size()==4,"target reaches idle without consuming distant building or shared-model pending instances")
	check(service._jobs.is_empty() and service._admission.reserved_bytes==0,"consumed target and cancelled far jobs release all their charged results")
	check(service._demands.has("building_render") and service._demands.has("navigation:old"),"skipped origin and far tickets still exist after target completion")
	service.set_demand_scope([]);service.set_process(false)
	check(demanded_ids(service)==["far_building","far_shared","origin"],"rollback or commit restores remaining origin and distant demand without republishing target")
	f.map.free()

	f=fixture();service=f.service
	var gate:=Semaphore.new();var worker:=Thread.new()
	worker.start(func():gate.wait();return {"error":""})
	var old_job:=add_job(service,SHARED,["far_shared"],worker)
	service.set_demand_scope(["transfer:7"]);service.set_process(false)
	check(old_job.token.is_cancelled() and worker.is_alive(),"far-only running job is cancelled even when its model path is also needed by target")
	service._process(0)
	check(worker.is_alive() and service._jobs.has(SHARED) and service._admission.reserved_bytes==32,"scope and process return without joining the live worker or releasing its charge early")
	service.set_demand_scope([]);service.set_process(false)
	check(old_job.token.is_cancelled() and demanded_ids(service).has("far_shared"),"rollback restores the ticket while already-cancelled work remains cancelled until join")
	gate.post()
	var deadline:=Time.get_ticks_msec()+2000
	while worker.is_alive() and Time.get_ticks_msec()<deadline:await process_frame
	service._process(0)
	check(not worker.is_started() and service._jobs.is_empty() and service._admission.reserved_bytes==0,"completed cancelled worker is reaped before its slot and bytes are reused")
	check(service.error.is_empty() and service.path_errors.is_empty() and service.instance_errors.is_empty() and service.pending.size()==5,"cooperative cancellation preserves all unpublished instances without poisoning rollback with an asset error")
	service.set_demand_scope(["transfer:7"]);service.set_process(false)
	requests=service._reference_requests(SHARED)
	check(requests.size()==1 and requests[0].compact_record.uuid=="target","target retry after cancelled shared-model job has only the scoped reference request")
	f.map.free()
	print("DEFERRED_DEMAND_SCOPE passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
