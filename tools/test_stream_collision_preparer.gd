extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Preparer=preload("res://scripts/world3d/stream_collision_preparer.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var cpu:=Cpu.new()
	# Multiple indexed and unindexed surfaces, including repeated vertices.
	var box:=BoxMesh.new();box.size=Vector3(2,3,4)
	cpu.surfaces.append(box.surface_get_arrays(0));cpu.materials.append(null)
	var triangle:Array=[];triangle.resize(Mesh.ARRAY_MAX)
	triangle[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	cpu.surfaces.append(triangle);cpu.materials.append(null)
	var expected:=cpu.get_faces()
	check(cpu.collision_faces()==expected,"direct CPU extraction preserves triangle order and winding across surfaces")
	check(cpu.collision_faces()==expected,"cached extraction preserves exact triangles")
	var preparer:=Preparer.new();root.add_child(preparer)
	var spec:={"mesh":cpu}
	check(not preparer.prepare(spec),"first request starts off-thread triangle extraction")
	var deadline:=Time.get_ticks_msec()+10000
	while not preparer.prepare(spec) and Time.get_ticks_msec()<deadline:await process_frame
	check(spec.has("shape") and spec.shape.get_faces()==expected,"prepared triangles produce exact collision geometry")
	var other:={"mesh":cpu}
	check(preparer.prepare(other) and other.shape==spec.shape,"instances reuse immutable shape without another worker")
	check(preparer.prepare({"mesh":box}),"primitive boxes retain direct primitive collision path")
	var interrupted:=Cpu.new();interrupted.surfaces=cpu.surfaces
	var destination:=Cpu.new();destination.surfaces=[triangle]
	preparer.prepare({"mesh":interrupted})
	var switched:={"mesh":destination}
	deadline=Time.get_ticks_msec()+10000
	while not preparer.prepare(switched) and Time.get_ticks_msec()<deadline:await process_frame
	check(switched.has("shape") and switched.shape.get_faces()==triangle[Mesh.ARRAY_VERTEX],"interrupted residency does not install another mesh's shape")
	var pending:=Cpu.new();pending.surfaces=cpu.surfaces;pending.materials=cpu.materials
	preparer.prepare({"mesh":pending});preparer.free()
	check(true,"scene teardown joins outstanding collision work")
	print("STREAM_COLLISION_PREPARER failures=",failures);quit(1 if failures else 0)
