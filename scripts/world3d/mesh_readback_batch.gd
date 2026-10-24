extends Node
## Read exact renderer arrays in bounded main-thread batches. Private workers
## retain their graphs and admission leases until the request completes.
const NODE_NAME:="MeshReadbackBatch"
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
# A whole ArrayMesh capture is indivisible. Budget checks between meshes cannot
# bound a large surface's decoder, so those remain on the private worker.
# This is an admission estimate, not measured memory usage.
const MAX_DECODE_BYTES:=128*1024
const MAX_SURFACES:=8
static var enabled:=true
static var _mutex:=Mutex.new()
static var _online:=false
static var _requests:Array=[]
static var counters:Dictionary={"requests":0,"meshes":0,"cancelled":0,"slices":0,"main_us":0,"max_slice_us":0}
static func accepts(mesh:ArrayMesh)->bool:
	if mesh.get_surface_count()>MAX_SURFACES:return false
	var bytes:=0
	for slot:int in mesh.get_surface_count():
		bytes+=mesh.surface_get_array_len(slot)*128+mesh.surface_get_array_index_len(slot)*4
		if bytes>MAX_DECODE_BYTES:return false
	return true
class Request extends RefCounted:
	var sources:Array=[]
	var token:RefCounted
	var cursor:=0
	var ready:=Semaphore.new()
	var result:Dictionary={"handled":true,"cancelled":false,"readback_main_us":0,"readback_meshes":0}
	func finish(cancelled:bool)->void:
		sources.clear() # Last renderer owners, if any, release on main.
		result.cancelled=cancelled;ready.post()
static func for_tree(tree:SceneTree)->void:
	if tree.root.has_node(NODE_NAME):return
	var service:=new();service.name=NODE_NAME;service.process_mode=Node.PROCESS_MODE_ALWAYS
	_mutex.lock();_online=true;_mutex.unlock();tree.root.add_child(service)
static func capture(sources:Array,token:RefCounted=null)->Dictionary:
	if not enabled or Thread.is_main_thread() or DisplayServer.get_name()=="headless" or sources.is_empty():return {"handled":false}
	var request:=Request.new();request.sources=sources;request.token=token
	_mutex.lock()
	if not _online:_mutex.unlock();return {"handled":false}
	_requests.append(request);counters.requests+=1;_mutex.unlock()
	var began:=Time.get_ticks_usec()
	# The service also runs during explicit worker shutdown. No renderer-owned
	# buffer or request is destroyed by a cancellation callback on the worker.
	request.ready.wait()
	var result:=request.result.duplicate();result.readback_wait_us=Time.get_ticks_usec()-began
	return result
static func pump(budget_usec:int=1500)->void:
	if not Thread.is_main_thread():return
	var began:=Time.get_ticks_usec();var processed:=0
	while true:
		_mutex.lock();var request:Request=_requests[0] if not _requests.is_empty() else null;_mutex.unlock()
		if request==null:break
		var cancelled:bool=request.token!=null and request.token.is_cancelled()
		if not cancelled and request.cursor<request.sources.size():
			var started:=Time.get_ticks_usec()
			Cpu.capture(request.sources[request.cursor]);request.cursor+=1;processed+=1
			request.result.readback_main_us+=Time.get_ticks_usec()-started;request.result.readback_meshes+=1
		if cancelled or request.cursor==request.sources.size():
			_mutex.lock();_requests.pop_front()
			if cancelled:counters.cancelled+=1
			_mutex.unlock();request.finish(cancelled)
		if budget_usec>0 and Time.get_ticks_usec()-began>=budget_usec:break
	if processed>0:
		var elapsed:=Time.get_ticks_usec()-began
		_mutex.lock();counters.meshes+=processed;counters.slices+=1;counters.main_us+=elapsed;counters.max_slice_us=maxi(counters.max_slice_us,elapsed);_mutex.unlock()
		Trace.elapsed("mesh.batched_readback",began,{"meshes":processed})
static func snapshot()->Dictionary:
	_mutex.lock();var result:=counters.duplicate();result.pending=_requests.size();result.online=_online;_mutex.unlock();return result
func _process(_delta:float)->void:pump()
func _exit_tree()->void:
	_mutex.lock();_online=false;var pending:=_requests;_requests=[];_mutex.unlock()
	for request:Request in pending:request.finish(true)
