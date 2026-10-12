extends SceneTree
## Real dispatch loop with CPU-only reference jobs. No models or GPU resources.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
class Probe extends Deferred:
	var request_calls:=0
	func _make_prepare_task(_path:String,_digest:String,token:RefCounted,_item:Dictionary,_faces:bool,_root:String,_requests:Array,_native:bool,_need_model:bool)->Callable:
		return held.bind(token)
	static func held(token:RefCounted)->Dictionary:
		while not token.is_cancelled():OS.delay_usec(100)
		return {"error":"cancelled"}
	func _reference_requests(_path:String)->Array:
		request_calls+=1;return []
	func _estimate_job(item:Dictionary,_requests:Array,_need_model:bool=true)->Dictionary:return item.memory
var passed:=0
var failures:=0
func check(value:bool,label_:String)->void:
	print("PASS: " if value else "FAIL: ",label_)
	if value:passed+=1
	else:failures+=1
func _initialize()->void:run.call_deferred()
func item(id:String,x:float,memory:Dictionary)->Dictionary:
	return {"record":{"uuid":id},"path":"reference:"+id,"bounds":AABB(Vector3(x,0,0),Vector3.ONE),"digest":"","native_reference":true,"memory":memory}
func fixture()->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	var service:=Probe.new();map.add_child(service);service.activate(map);service.set_process(false)
	service._admission.byte_limit=100;service._admission.worker_limit=2
	service.pending=[item("busy",0,{"estimated_bytes":10,"exclusive":false}),item("foreground",10,{"estimated_bytes":120,"exclusive":false})]
	for i in 20:service.pending.append(item("far_%d"%i,100+i,{"estimated_bytes":1,"exclusive":false}))
	service.set_demand("background",AABB(Vector3(-1,-1,-1),Vector3(200,2,2)),10)
	service.set_demand("foreground",AABB(Vector3(9,-1,-1),Vector3(3,2,2)),-2)
	service.set_process(false)
	service._admission.reserve("reference:busy",{"estimated_bytes":10,"exclusive":false})
	service._jobs["reference:busy"]={"accepted":true,"result":{},"token":Deferred.Drainer.CancelToken.new(),"publication_ids":["busy"]}
	return {"map":map,"service":service}
func run()->void:
	var f:=fixture();var service:Node=f.service
	for i in 8:
		service._process(0)
		if service._jobs.has("reference:foreground"):break
		await process_frame
	check(service._jobs.size()==1 and service._admission.count()==1,"exclusive foreground retires lower-priority ready output without refilling scenery")
	check(int(service.profile.get("priority_retirements",0))==1,"only the joined lower-priority closure is retired for the exclusive foreground")
	check(service._jobs.has("reference:foreground"),"foreground starts after the prior result owners and reservation are released")
	check(service._admission.reserved_bytes==120,"exclusive work keeps its actual byte reservation without overlap")
	await service.quiesce();f.map.free()
	f=fixture();service=f.service;service._process(0)
	# Remove the target from all tickets. The fence must not outlive demand.
	service.release_demand("foreground")
	service.set_demand("background",AABB(Vector3(99,-1,-1),Vector3(40,2,2)),10)
	service.set_process(false)
	for i in 8:
		service._process(0)
		if service._jobs.size()==2 and not service._jobs.has("reference:foreground"):break
		await process_frame
	check(not service._jobs.has("reference:foreground") and service._jobs.size()==2 and str(service.profile.admission_drain_path).is_empty(),"cancelling exclusive demand releases the fence and admits independent work")
	await service.quiesce();f.map.free()
	f=fixture();service=f.service
	service._admission.release("reference:busy")
	service._admission.reserve("reference:busy",{"estimated_bytes":1,"exclusive":true})
	var job:Dictionary=service._jobs["reference:busy"];var worker:=Thread.new();job.worker=worker
	service._drainer=Deferred.Drainer.for_tree(self);service._drainer.watch(worker,job.token)
	worker.start(Probe.held.bind(job.token));service._refresh_demanded();service._process(0)
	check(service.request_calls==0 and service._jobs.size()==1 and service._admission.reserved_bytes==1,"live exclusive worker keeps its reservation until joined even after a critical cancellation")
	await service.quiesce();f.map.free()
	print("DEFERRED_ADMISSION_PRIORITY passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
