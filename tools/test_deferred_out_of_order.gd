extends "res://tools/test_deferred_backpressure.gd"
## Real CPU workers with deterministic completion order, no GPU/assets.
## A blocked first worker must not serialize later preparation or publication.
const Backpressure=preload("res://tools/test_deferred_backpressure.gd")
class ControlledQueue extends Backpressure.Queue:
	var first_gate:=Semaphore.new()
	var held_path:="reference:held"
	func _make_prepare_task(path:String,_digest:String,token:RefCounted,_item:Dictionary,_faces:bool,_root:String,_requests:Array,_native:bool,_need_model:bool)->Callable:
		started.append(path)
		var records:Array=[]
		for row:Dictionary in _demanded_by_path[path]:records.append(row.record.duplicate(true))
		return ordered_work.bind(token,records,first_gate if path==held_path else null)
	static func ordered_work(token:RefCounted,records:Array,gate:Semaphore)->Dictionary:
		if gate!=null:gate.wait()
		return {"error":"cancelled" if token.is_cancelled() else "","records":records,"elapsed_us":1}

func controlled_fixture(rows:Array)->Dictionary:
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",[])
	var index:=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	map.set_meta("extras",{"rmmo_records":[]})
	var queue:=ControlledQueue.new();var document:=Document.new()
	queue._doc=document;queue.pending=rows;queue._reference_root=ProjectSettings.globalize_path("res://")
	map.add_child(queue);queue.activate(map)
	queue._admission.byte_limit=100;queue._admission.worker_limit=2;queue.ready_job_limit=2
	queue.set_demand("background",AABB(Vector3(-100,-1,-1),Vector3(200,3,3)),10)
	queue.set_process(false);queue._refresh_demanded()
	return {"map":map,"queue":queue,"document":document}

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var f:=controlled_fixture([item("held",0,10),item("fast",10,10),item("successor",20,10)])
	var queue:ControlledQueue=f.queue;queue.paused=true
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		if queue._jobs.get("reference:fast",{}).get("accepted",false):break
	var held:Dictionary=queue._jobs.get("reference:held",{})
	var first_worker:Thread=held.get("worker")
	check(queue.started==["reference:held","reference:fast"] and not queue.started.has("reference:successor"),"first worker starts before fast worker and the third path waits behind exactly two occupied slots")
	check(first_worker!=null and first_worker.is_alive() and not held.get("accepted",false),"semaphore keeps the first worker unfinished throughout out-of-order acceptance")
	check(queue._jobs.get("reference:fast",{}).get("accepted",false) and not queue._jobs.get("reference:fast",{}).has("worker"),"later worker is joined and accepted without waiting for the earlier live worker")
	check(f.document.calls.is_empty() and queue._admission.reserved_bytes==20 and queue._admission.active_workers()==1,"accepted second result parks execution but preserves both complete byte leases")
	queue.paused=false;deadline=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		if f.document.calls.get("successor",0)==1 and not queue._jobs.has("reference:successor"):break
	check(first_worker!=null and first_worker.is_alive() and not f.document.calls.has("held"),"fast publication and successor preparation occur while first worker still waits at the semaphore")
	check(f.document.calls.get("fast",0)==1 and f.document.calls.get("successor",0)==1 and queue.started==["reference:held","reference:fast","reference:successor"],"later result publishes exactly once and frees its existing slot for the third source")
	check(queue._jobs.keys()==["reference:held"] and queue._admission.reserved_bytes==10 and queue._admission.active_workers()==1,"consumed later results release only their own leases; the original live worker remains charged")
	# Always release the gate, including when an earlier assertion failed, so
	# the test's own failure path cannot strand a waiting thread in shutdown.
	queue.first_gate.post();deadline=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		if queue.is_complete():break
	check(queue.is_complete() and f.document.calls.size()==3 and f.document.calls.values().all(func(n):return n==1),"releasing the first worker completes all three instances exactly once")
	check(queue._jobs.is_empty() and queue._admission.reserved_bytes==0 and queue._admission.active_workers()==0 and int(queue.profile.max_total_jobs)<=2 and queue._admission.peak_workers<=2,"out-of-order completion preserves both caps and leaves zero task/byte leases")
	await queue.quiesce();f.map.free()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEFERRED_OUT_OF_ORDER passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
