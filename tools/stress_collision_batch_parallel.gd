extends SceneTree
const Prefetch=preload("res://scripts/world3d/collision_face_prefetch.gd")
const Fixture=preload("res://tools/stress_small_collision_preparation.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
static func parallel(snapshots:Array,token:RefCounted,workers:int)->Dictionary:
	if workers==3:return Prefetch._build_parallel(snapshots,token,workers)
	var buckets:Array=[]
	for i:int in workers:buckets.append([])
	for i:int in snapshots.size():buckets[i%workers].append(snapshots[i])
	var threads:Array[Thread]=[];var packets:Array=[]
	for i:int in range(1,workers):
		var thread:=Thread.new()
		if thread.start(Prefetch._build.bind(buckets[i],token))==OK:threads.append(thread)
		else:packets.append(Prefetch._build(buckets[i],token))
	packets.append(Prefetch._build(buckets[0],token))
	for thread:Thread in threads:packets.append(thread.wait_to_finish())
	var result:={"faces":{},"prepared":{}}
	for packet:Dictionary in packets:
		if packet.is_empty():return {}
		result.faces.merge(packet.faces);result.prepared.merge(packet.prepared)
	return result
func run()->void:
	var small:=Fixture.faces();var large:=PackedVector3Array()
	for i:int in 4:large.append_array(Transform3D(Basis.IDENTITY,Vector3(0,0,i*8))*small)
	var snapshots:Array=[];var bytes:=0
	for i:int in 12:
		var faces:PackedVector3Array=large if i<8 else small
		snapshots.append({"id":str(i),"faces":faces,"basis":Basis.from_euler(Vector3(0,.25,0)) if i%2 else Basis.IDENTITY,"surfaces":[],"count":faces.size(),"prepare_bvh":true})
		bytes+=faces.size()*12*12
	check(bytes<=16*1024*1024,"fixed mixed batch fits the production byte reservation")
	var token:=Prefetch.Drainer.CancelToken.new();var original:=var_to_bytes(snapshots)
	var reference:=Prefetch._build(snapshots,token);var trials:Array=[]
	for workers:int in [1,3,12,12,3,1]:
		var began:=Time.get_ticks_usec();var result:Dictionary={}
		for repeat:int in 8:
			var coordinator:=Thread.new();check(coordinator.start(parallel.bind(snapshots,token,workers))==OK,"private batch coordinator starts")
			result=coordinator.wait_to_finish()
		var elapsed:=Time.get_ticks_usec()-began;var exact:bool=result.faces.size()==reference.faces.size()
		for id:String in reference.faces:
			exact=exact and result.faces[id]==reference.faces[id] and result.prepared[id].size()==reference.prepared[id].size()
			for slot:int in reference.prepared[id].size():
				var a:Dictionary=reference.prepared[id][slot];var b:Dictionary=result.prepared[id][slot]
				exact=exact and a.faces.to_byte_array()==b.faces.to_byte_array() and a.backface_collision==b.backface_collision
		check(exact,"parallel batch retains every exact face and prepared slice")
		await compare_queries(result,snapshots)
		trials.append({"workers":workers,"elapsed_us":elapsed,"shapes":96,"reserved_bytes_per_batch":bytes})
	check(var_to_bytes(snapshots)==original,"shared inputs remain unchanged")
	var fallback:=Prefetch._build_parallel(snapshots,token,3,func(_thread:Thread,_task:Callable):return ERR_CANT_CREATE)
	check(fallback.faces.size()==snapshots.size() and fallback.workers==1,"child start failure executes all admitted work on the coordinator")
	await compare_queries(fallback,snapshots)
	var cancellation:=CancelDuringStart.new();cancellation.token=Prefetch.Drainer.CancelToken.new()
	check(Prefetch._build_parallel(snapshots,cancellation.token,3,cancellation.start).is_empty(),"cancellation while child tasks exist cannot publish partial results")
	check(cancellation.threads.size()==2 and cancellation.threads.all(func(thread:Thread):return not thread.is_started()),"every cancelled child is joined before coordinator completion")
	token.cancel();check(parallel(snapshots,token,3).is_empty(),"cancellation joins every child without publishing partial output")
	print("COLLISION_BATCH_PARALLEL ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)

func compare_queries(packet:Dictionary,snapshots:Array)->void:
	# Native prepared CPU objects have independent identities. Validate the
	# installed trees against ordinary shape construction, not Object encoding.
	var spaces:Array[RID]=[];var bodies:Array[RID]=[];var owners:Array[Shape3D]=[]
	var exact:=true;var hits:=0;var expected:=0
	for prepared:bool in [false,true]:
		var space:=PhysicsServer3D.space_create();PhysicsServer3D.space_set_active(space,true);spaces.append(space)
		for row:Dictionary in snapshots:
			var body:=PhysicsServer3D.body_create();bodies.append(body)
			PhysicsServer3D.body_set_mode(body,PhysicsServer3D.BODY_MODE_STATIC)
			PhysicsServer3D.body_set_collision_layer(body,1)
			PhysicsServer3D.body_set_state(body,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,Vector3(int(row.id)*100,0,0)))
			for product:Dictionary in packet.prepared[row.id]:
				var shape:=ConcavePolygonShape3D.new();owners.append(shape)
				if prepared:shape.call(&"set_prepared_faces",product)
				else:shape.set_faces(product.faces)
				exact=exact and shape.get_faces().to_byte_array()==product.faces.to_byte_array()
				PhysicsServer3D.body_add_shape(body,shape.get_rid())
			PhysicsServer3D.body_set_space(body,space)
	await physics_frame;await physics_frame;await process_frame
	for row:Dictionary in snapshots:
		for slice:int in packet.prepared[row.id].size():
			for i:int in 16:
				expected+=1
				var start:Vector3=row.basis*Vector3((i%8)*7+.25,-10,slice*8+(i/8)*3+.35)+Vector3(int(row.id)*100,0,0)
				var query:=PhysicsRayQueryParameters3D.create(start,start+Vector3(0,20,0))
				var a:=PhysicsServer3D.space_get_direct_state(spaces[0]).intersect_ray(query)
				var b:=PhysicsServer3D.space_get_direct_state(spaces[1]).intersect_ray(query)
				exact=exact and a.is_empty()==b.is_empty()
				if not a.is_empty() and not b.is_empty():
					hits+=1;exact=exact and a.position==b.position and a.normal==b.normal and a.face_index==b.face_index and a.shape==b.shape
	check(exact and hits==expected,"installed BVHs retain exact ray positions, normals, face indices and slice selection (%d rays)"%hits)
	for body:RID in bodies:PhysicsServer3D.free_rid(body)
	for space:RID in spaces:PhysicsServer3D.free_rid(space)

class CancelDuringStart extends RefCounted:
	var token:RefCounted
	var threads:Array[Thread]=[]
	var gate:=Semaphore.new()
	func start(thread:Thread,task:Callable)->int:
		var error:=thread.start(func():gate.wait();return task.call())
		if error!=OK:return error
		threads.append(thread)
		if threads.size()==2:
			token.cancel();gate.post();gate.post()
		return OK
