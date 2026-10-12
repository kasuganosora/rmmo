extends SceneTree
## CPU-only lifetime test: a worker waits for a main-thread frame to release it.
## A blocking join would deadlock this fixture instead of completing the test.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
class Probe extends RefCounted:
	var scene_id:=0
	var cancelled:=false
var failures:=0
var passed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->void:
	print("PASS " if value else "FAIL ",label_)
	if value:passed+=1
	else:failures+=1
static func worker_result(gate:Semaphore,token:RefCounted,probe:Probe)->Dictionary:
	gate.wait()
	probe.cancelled=token.is_cancelled()
	var scene:=Node3D.new();probe.scene_id=scene.get_instance_id()
	return {"error":"", "scene":scene}
func drain(queue:Node,state:Dictionary)->void:
	await queue.quiesce();state.done=true
func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var queue:=Deferred.new();host.add_child(queue);queue.activate(host);queue.set_process(false)
	queue.pending=[{"record":{"uuid":"pending"},"path":"unfinished.glb","bounds":AABB(Vector3.ZERO,Vector3.ONE)}]
	queue._prepared_paths["cached.glb"]=true
	queue.source_signatures["cached.glb"]="stable"
	var publications:Dictionary={"count":0,"complete":0}
	queue.published.connect(func(_specs:Array):publications.count+=1)
	queue.completed.connect(func():publications.complete+=1)
	var estimate:={"estimated_bytes":1024,"exclusive":false}
	check(queue._admission.reserve("live",estimate) and queue._admission.reserve("ready",estimate),"both worker and unconsumed output reserve capacity")
	var ready_scene:=Node3D.new();var ready_id:=ready_scene.get_instance_id()
	var ready_token:=Drainer.CancelToken.new()
	queue._jobs.ready={"token":ready_token,"result":{"error":"","scene":ready_scene}}
	var gate:=Semaphore.new();var token:=Drainer.CancelToken.new();var probe:=Probe.new();var worker:=Thread.new()
	queue._drainer=Drainer.for_tree(self);queue._drainer.watch(worker,token)
	queue._jobs.live={"token":token,"worker":worker,"estimate":estimate}
	check(worker.start(worker_result.bind(gate,token,probe))==OK,"start bounded CPU fixture worker")
	var state:={"done":false};drain(queue,state)
	check(token.is_cancelled() and ready_token.is_cancelled(),"quiesce cancels running and completed jobs before yielding")
	check(not state.done and queue._admission.reserved_bytes==1024,"live worker retains reservation while ready result is retired")
	check(not is_instance_id_valid(ready_id),"completed unpublished scene is disposed")
	queue.set_demand("old_navigation",AABB(Vector3.ZERO,Vector3.ONE),-1)
	await process_frame
	check(not state.done and not queue._active and not queue.is_processing(),"main frame advances and navigation demand cannot restart suspended queue")
	gate.post()
	var deadline:=Time.get_ticks_msec()+5000
	while not state.done and Time.get_ticks_msec()<deadline:await process_frame
	check(state.done and not worker.is_started() and probe.cancelled,"worker completes cancellation and is joined asynchronously")
	check(probe.scene_id!=0 and not is_instance_id_valid(probe.scene_id),"late worker scene is disposed without publication")
	check(queue._jobs.is_empty() and queue._admission.count()==0 and queue._admission.reserved_bytes==0 and queue._drainer.jobs.is_empty(),"actual completion releases jobs, drainer ownership and byte reservations")
	check(publications.count==0 and publications.complete==0 and queue.pending.size()==1 and queue._prepared_paths.has("cached.glb") and queue.source_signatures.get("cached.glb")=="stable","quiesce retains retryable pending and prepared identities without publishing")
	check(not queue._cancelled and not queue._active and not queue.is_processing(),"temporary quiescence is distinct from permanent cancellation")
	queue.activate(host);queue.set_process(false)
	check(queue._active and queue.pending.size()==1 and queue._demands.has("old_navigation"),"rollback can reactivate the queue with previous demand and pending work")
	await queue.quiesce()
	check(queue._jobs.is_empty() and queue.pending.size()==1,"repeated quiesce is safe after all workers have retired")
	host.free()
	print("DEFERRED_QUIESCE_FINISHED passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
