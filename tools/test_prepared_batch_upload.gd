extends SceneTree
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Fixture=preload("res://tools/stress_mesh_surface_preparation.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
static func build(sources:Array)->Dictionary:return Geometry.build(sources,Vector3.ZERO,true)
func run()->void:
	check(DisplayServer.get_name()!="headless","prepared batch integration uses a real renderer")
	check(RenderingServer.has_method(Geometry.PREPARE_SURFACE_METHOD),"patched CPU surface packing is available")
	if failures:quit(1);return
	for building:bool in [false,true]:
		var arrays:Array=Fixture.surface(6000)
		var sources:Array=[];var record:={"kind":"box","size":[16.,1.,16.]}
		if building:record.building={}
		for at:int in 8:
			sources.append({"record":record,"surfaces":[arrays],"materials":[null],"keys":["default"],"transform":Transform3D(Basis(Vector3.UP,at*.15),Vector3(at*3,at,-at))})
		var original:=var_to_bytes(sources)
		Geometry.prepared_surfaces_enabled=false
		var old_worker:=Thread.new();old_worker.start(build.bind(sources))
		while old_worker.is_alive():await process_frame
		var baseline:Dictionary=old_worker.wait_to_finish()
		Geometry.prepared_surfaces_enabled=true
		var worker:=Thread.new();worker.start(build.bind(sources))
		while worker.is_alive():await process_frame
		var actual:Dictionary=worker.wait_to_finish()
		check(actual.get("surface_prepare_thread",OS.get_main_thread_id())!=OS.get_main_thread_id(),"native packing actually executes off the main thread")
		check(actual.prepared_surface_count==actual.slots.size(),"every final surface is prepared exactly once")
		check(var_to_bytes(sources)==original,"publication leaves input geometry and poses unchanged")
		check(actual.render_vertices==baseline.render_vertices and actual.source_surfaces==baseline.source_surfaces,"work and final geometry counts remain equal")
		var expected:Dictionary=Geometry.upload(baseline)
		var result:Dictionary=Geometry.upload(actual)
		check(expected.mesh.get("_surfaces")==result.mesh.get("_surfaces"),"production building/ground upload matches exact original packed bytes")
		check(expected.mesh.get_aabb()==result.mesh.get_aabb(),"production bounds remain identical")
		var cpu:Mesh=result.mesh.get_meta("ground_cpu_cache")
		check(cpu.surfaces.size()==actual.slots.size(),"CPU authoring/collision ownership survives prepared upload")
		for slot:int in actual.slots.size():check(cpu.surfaces[slot]==actual.slots[slot].arrays,"all retained CPU channels preserved")
		# The producer owns its packet. Main-thread material binding must not
		# modify it, which would race if the same completed packet were reused.
		for row:Dictionary in actual.slots:check(not row.prepared_surface.has("material"),"upload leaves worker packet immutable")
		await process_frame
	print("PREPARED_BATCH_UPLOAD failures=",failures)
	quit(1 if failures else 0)
