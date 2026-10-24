extends SceneTree
const Batch=preload("res://scripts/world3d/mesh_readback_batch.gd")
const Prep=preload("res://scripts/world3d/static_mesh_cpu_preparation.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture(count:int)->Node3D:
	var scene:=Node3D.new();var box:=BoxMesh.new();var arrays:=box.surface_get_arrays(0)
	for i:int in count:
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var node:=MeshInstance3D.new();node.mesh=mesh;scene.add_child(node)
	return scene
static func work(scene:Node,token:RefCounted)->Dictionary:return Prep.capture(scene,true,token)
func run()->void:
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Drainer.for_tree(self)
	var trials:Array=[];var expected:=PackedVector3Array()
	for enabled:bool in [false,true,true,false]:
		Batch.enabled=enabled
		var scene:=fixture(512);var worker:=Thread.new();var token:=Drainer.CancelToken.new()
		var began:=Time.get_ticks_usec();check(worker.start(work.bind(scene,token))==OK,"start private geometry worker")
		while worker.is_alive():await process_frame
		var result:Dictionary=worker.wait_to_finish();var elapsed:=Time.get_ticks_usec()-began
		check(result.error.is_empty() and result.captured_meshes==512,"all private meshes captured once")
		var equal:=true
		for node:MeshInstance3D in scene.get_children():
			var cpu:Mesh=Cpu.capture(node.mesh)
			if expected.is_empty():expected=cpu.collision_faces()
			equal=equal and cpu.collision_faces()==expected and cpu.surfaces[0]==node.mesh.surface_get_arrays(0)
		check(equal,"all GPU-decoded channels and collision arrays match the serial reference")
		check(Batch.snapshot().pending==0,"completed worker leaves no readback owners")
		trials.append({"batched":enabled,"elapsed_us":elapsed,"capture":result})
		scene.free();await process_frame
	Batch.enabled=true
	var mixed:=fixture(2)
	var sphere:=SphereMesh.new();sphere.radial_segments=128;sphere.rings=64
	var large:=ArrayMesh.new();large.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,sphere.surface_get_arrays(0))
	var large_node:=MeshInstance3D.new();large_node.mesh=large;mixed.add_child(large_node)
	check(not Batch.accepts(large) and Prep._readback_sources(mixed,null,Prep.CollisionGeometry.ALL).size()==2,"large decoder remains on worker while small meshes retain batching")
	var mixed_worker:=Thread.new();mixed_worker.start(work.bind(mixed,null))
	while mixed_worker.is_alive():await process_frame
	var mixed_result:Dictionary=mixed_worker.wait_to_finish()
	check(mixed_result.error.is_empty() and mixed_result.captured_meshes==3 and mixed_result.readback_meshes==2 and Cpu.capture(large).surfaces[0]==large.surface_get_arrays(0),"mixed batch captures every exact array and sends only two small meshes to main")
	mixed.free()
	var scene:=fixture(512);var token:=Drainer.CancelToken.new();var worker:=Thread.new()
	var service:Node=root.get_node(Batch.NODE_NAME);service.set_process(false)
	worker.start(work.bind(scene,token))
	var deadline:=Time.get_ticks_msec()+5000
	while Batch.snapshot().pending==0 and worker.is_alive() and Time.get_ticks_msec()<deadline:await process_frame
	check(Batch.snapshot().pending==1,"cancellation fixture has a real waiting renderer request")
	token.cancel();Batch.pump(1000)
	while worker.is_alive():await process_frame
	var cancelled:Dictionary=worker.wait_to_finish()
	check(cancelled.get("cancelled",false) and Batch.snapshot().pending==0 and is_instance_valid(scene),"cancellation wakes worker without releasing its graph on the wrong thread")
	scene.free();service.set_process(true)
	scene=fixture(8);worker=Thread.new();service.set_process(false);worker.start(work.bind(scene,null))
	deadline=Time.get_ticks_msec()+5000
	while Batch.snapshot().pending==0 and worker.is_alive() and Time.get_ticks_msec()<deadline:await process_frame
	check(Batch.snapshot().pending==1,"service teardown fixture has an actual waiting request")
	service.free()
	while worker.is_alive():await process_frame
	var stopped:Dictionary=worker.wait_to_finish()
	check(stopped.get("cancelled",false) and Batch.snapshot().pending==0 and not Batch.snapshot().online,"service exit releases waiters without destroying their private graphs")
	scene.free()
	print("MESH_READBACK_BATCH ",JSON.stringify({"trials":trials,"service":Batch.snapshot(),"failures":failures}));quit(1 if failures else 0)
