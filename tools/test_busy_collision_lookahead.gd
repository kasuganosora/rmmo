extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
class Preparer extends "res://scripts/world3d/stream_collision_preparer.gd":
	var requests:=0
	func prefetch_request(spec:Dictionary)->Dictionary:
		requests+=1;return super.prefetch_request(spec)
class Gate extends RefCounted:
	var semaphore:=Semaphore.new()
	func start(worker:Thread,task:Callable)->int:
		return worker.start(func():semaphore.wait();return task.call())
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var map:=Node3D.new();root.add_child(map)
	var preparer:=Preparer.new();preparer.name="StreamCollisionPreparer";map.add_child(preparer)
	var queue:RefCounted=preparer._face_prefetch;var gate:=Gate.new();queue.thread_starter=gate.start
	var jobs:Array=[]
	for i:int in 40:
		var cpu:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]);cpu.surfaces=[arrays]
		jobs.append({"uuid":"source_%d"%i,"mesh":cpu,"chunk":Vector2i.ZERO})
	var area:={"low":Vector2i(-1,-1),"high":Vector2i(1,1)}
	Stream._prefetch_collisions(map,map,jobs,0,area,{})
	check(queue.profile.batches==1,"actual lookahead starts one worker")
	var before:=preparer.requests;var began:=Time.get_ticks_usec()
	for frame:int in 120:Stream._prefetch_collisions(map,map,jobs,0,area,{})
	var repeated:=preparer.requests-before;var elapsed:=Time.get_ticks_usec()-began
	if "--baseline" not in OS.get_cmdline_user_args():check(repeated==0,"busy worker causes no repeated spec classification")
	var expected_bytes:int=16*36*(12 if Preparer.small_worker_bvh_enabled and preload("res://scripts/world3d/collision_bvh_preparation.gd").active() else 1)
	check(queue.profile.batches==1 and queue.profile.reserved_bytes==expected_bytes and expected_bytes<=queue.byte_limit,"busy worker retains exactly one bounded lease including BVH workspace")
	gate.semaphore.post()
	var deadline:=Time.get_ticks_msec()+10000
	while queue._thread!=null and Time.get_ticks_msec()<deadline:
		queue.poll();await process_frame
	check(queue._ready.size()==16,"completed worker retains every exact result")
	queue.request([],self,false)
	check(queue._ready.size()==16 and queue.profile.reserved_bytes==expected_bytes,"a truncated lookahead prefix does not discard unseen ready outputs")
	queue.thread_starter=Callable()
	Stream._prefetch_collisions(map,map,jobs,16,area,{})
	check(queue.profile.batches==2,"new cursor scans and admits next batch after completion")
	while queue._thread!=null and Time.get_ticks_msec()<deadline:
		queue.poll();await process_frame
	queue.cancel();queue.poll()
	check(queue.profile.reserved_bytes==0 and not queue.has_source_owners(),"cancellation releases all leases and source owners")
	map.free();print("BUSY_COLLISION_LOOKAHEAD ",JSON.stringify({"repeated_calls":repeated,"us":elapsed,"failures":failures}));quit(1 if failures else 0)
