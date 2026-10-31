extends SceneTree
const Queue=preload("res://tools/fixtures/node_retirement_candidate.gd")
var output:=""
var baseline:=false
var native_enabled:=false
var count_meshes:=4240
var count_bodies:=2141
var count_extra_shapes:=735
var count_other_map_nodes:=196
var checks:=0
var failures:Array[String]=[]

func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
	print("PASS " if ok else "FAIL ",message)

func _functional_contract()->void:
	var parent:=Node3D.new();root.add_child(parent)
	var child:=Node3D.new();parent.add_child(child)
	var hidden:=Node3D.new();parent.add_child(hidden,false,Node.INTERNAL_MODE_BACK)
	var shared:={"source":"borrowed","data":[[1,2,3],[4,5,6]]}
	parent.set_meta("extras",shared)
	var events:Array=[]
	parent.tree_exiting.connect(func():events.append(parent.get_meta("extras").source))
	var ids:=[parent.get_instance_id(),child.get_instance_id(),hidden.get_instance_id()]
	var queue:=make_queue()
	var owned:Array[Node]=[parent]
	queue.take(owned)
	check(not queue.step(1000) and queue.freed==0 and parent.is_inside_tree(),"queued live roots are not destroyed before permanent detach")
	root.remove_child(parent)
	check(events==["borrowed"] and is_instance_valid(parent) and not child.is_inside_tree(),"exit observers read intact data; logical scene exit is immediate")
	check(queue.step(0),"shutdown can synchronously drain the same postorder plan")
	check(queue.freed==3 and queue.snapshots==1,"internal children included; one child snapshot per nonleaf")
	check(ids.all(func(id):return instance_from_id(id)==null),"all donated node identities are gone")
	check(shared=={"source":"borrowed","data":[[1,2,3],[4,5,6]]},"borrowed metadata is untouched")
	var duplicate_root:=Node3D.new()
	var duplicate_child:=Node3D.new();duplicate_root.add_child(duplicate_child)
	queue=make_queue()
	var duplicate_owners:Array[Node]=[duplicate_root,duplicate_child]
	queue.take(duplicate_owners)
	check(queue.step(0) and queue.freed==2,"overlapping roots are released exactly once")
	var removed:=Node.new()
	queue=make_queue()
	var removed_roots:Array[Node]=[removed]
	queue.take(removed_roots);removed.free()
	check(queue.step(0) and queue.freed==0,"a root already destroyed by its owner is safely skipped")
	var nested:=Node.new();var inner:=Node.new();nested.add_child(inner)
	for index:int in 512:inner.add_child(Node.new())
	queue=make_queue()
	var nested_roots:Array[Node]=[nested]
	queue.take(nested_roots)
	check(not queue.step(1) and queue.freed<514,"a small outer tree cannot collapse a large inner tree into one native deletion")
	check(queue.step(0) and queue.freed==514,"nested bounded release still destroys every node")

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--baseline":baseline=true
		if arg=="--native":native_enabled=true
		if arg=="--small":count_meshes=16;count_bodies=8;count_extra_shapes=4;count_other_map_nodes=0
	if native_enabled:
		check(ClassDB.class_has_method("Node","rmmo_retire_detached_nodes_step"),"native stepping API is available")
		if not failures.is_empty():quit(2);return
	_functional_contract()
	if native_enabled:_native_contract()
	var host:=Node3D.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map)
	var shared_mesh:=BoxMesh.new()
	var shared_shape:=BoxShape3D.new()
	var identities:Array[int]=[map.get_instance_id()]
	for index:int in count_other_map_nodes:
		var node:=Node3D.new();map.add_child(node);identities.append(node.get_instance_id())
	for index:int in count_meshes:
		var mesh:=MeshInstance3D.new();mesh.mesh=shared_mesh
		mesh.position=Vector3((index%128)*3,0,(index/128)*3)
		map.add_child(mesh);mesh.owner=map
		identities.append(mesh.get_instance_id())
	var roots_to_retire:Array[Node]=[]
	for index:int in count_bodies:
		var body:=StaticBody3D.new();host.add_child(body)
		body.position=Vector3((index%128)*3,-1,(index/128)*3)
		identities.append(body.get_instance_id())
		for shape_index:int in (2 if index<count_extra_shapes else 1):
			var shape:=CollisionShape3D.new();shape.shape=shared_shape
			shape.position=Vector3(0,shape_index*2,0)
			body.add_child(shape);identities.append(shape.get_instance_id())
		roots_to_retire.append(body)
	roots_to_retire.append(map)
	await process_frame
	await physics_frame
	var queue:=make_queue()
	var committed:=Time.get_ticks_usec()
	var detach_us:=0
	if baseline:
		for node:Node in roots_to_retire:node.free()
	else:
		queue.take(roots_to_retire)
		for node:Node in roots_to_retire:host.remove_child(node)
		detach_us=Time.get_ticks_usec()-committed
	var commit_us:=Time.get_ticks_usec()-committed
	# The baseline deliberately fails this contract: whole trees are freed in
	# the commit call, instead of retiring after scene/physics detachment.
	check(is_instance_valid(map),"native destruction is deferred beyond the commit call")
	if not baseline:
		check(not map.is_inside_tree() and roots_to_retire.all(func(node):return not node.is_inside_tree()),"every retired root has left the active scene")
		check(roots_to_retire.slice(0,count_bodies).all(func(body):return not PhysicsServer3D.body_get_space(body.get_rid()).is_valid()),"old physics bodies immediately leave their space")
	var slices:=0;var release_us:=0;var max_slice_us:=0
	var complete:=baseline
	while not complete and slices<20000:
		var began:=Time.get_ticks_usec()
		complete=queue.step(1000)
		var elapsed:=Time.get_ticks_usec()-began
		release_us+=elapsed;max_slice_us=maxi(max_slice_us,elapsed);slices+=1
		await process_frame
	check(complete and identities.all(func(id):return instance_from_id(id)==null),"all original native node identities are eventually destroyed")
	if not baseline:check(queue.freed==identities.size(),"same node workload, no lost or duplicate release")
	check(slices>1 if count_meshes>16 else true,"large native destruction spans multiple budgeted slices")
	check(shared_mesh.get_aabb().size==Vector3.ONE and shared_shape.size==Vector3.ONE,"shared borrowed mesh and shape remain usable")
	var report:={"native":native_enabled,"baseline":baseline,"checks":checks,"failures":failures,"nodes":identities.size(),"meshes":count_meshes,"bodies":count_bodies,"commit_us":commit_us,"detach_us":detach_us,"release_us":release_us,"max_release_slice_us":max_slice_us,"slices":slices,"queue_freed":queue.freed,"child_snapshots":queue.snapshots,"contract":"native Node graph component; shared small geometry isolates lifetime work, not a map/FPS result"}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	host.free()
	print("NODE_RETIREMENT42 ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func make_queue()->Queue:
	var queue:=Queue.new()
	queue.native_enabled=native_enabled
	return queue

class ObservingParent extends Node:
	var observed:Array=[]
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:observed.append(get_child_count(true))

func _native_contract()->void:
	var observed:Array=[]
	var parent:=ObservingParent.new();parent.observed=observed
	var child:=Node.new();parent.add_child(child)
	var child_id:=child.get_instance_id()
	var queue:=make_queue()
	var roots_:Array[Node]=[parent]
	queue.take(roots_)
	check(queue.step(0) and observed==[1] and instance_from_id(child_id)==null,"scripted parent sees its children during original PREDELETE semantics")
	check(queue.native_state.atomic_subtrees==1,"opaque scripted subtree is counted as one unit without an extra size scan")
	parent=ObservingParent.new();observed=[];parent.observed=observed
	queue=make_queue();roots_=[parent];queue.take(roots_)
	var worker:=Thread.new()
	worker.start(_worker_reject.bind(queue.native_state))
	check(not worker.wait_to_finish() and is_instance_valid(parent) and observed.is_empty(),"worker calls cannot destroy nodes or invoke script destructors")
	var before:Dictionary=queue.native_state.duplicate(true)
	check(not ClassDB.class_call_static("Node","rmmo_retire_detached_nodes_step",queue.native_state,-1) and queue.native_state==before,"invalid budget fails without mutation")
	check(not ClassDB.class_call_static("Node","rmmo_retire_detached_nodes_step",{},1000),"invalid state is rejected without touching scene objects")
	check(queue.step(0) and observed==[0],"main-thread final drain still completes after rejected calls")

static func _worker_reject(state:Dictionary)->bool:
	return ClassDB.class_call_static("Node","rmmo_retire_detached_nodes_step",state,1000)
