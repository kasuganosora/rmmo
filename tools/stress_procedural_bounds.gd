extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
var output:=""
var rows:Array=[]
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
static func prepare(helper:Script,surfaces:Array,count:int,gate:Semaphore)->Dictionary:
	gate.wait();var began:=Time.get_ticks_usec();var bounds:Array=[]
	for i:int in count:bounds.append(helper.bounds(surfaces))
	return {"bounds":bounds,"thread":OS.get_thread_caller_id(),"us":Time.get_ticks_usec()-began}
func run()->void:
	var vertices:=PackedVector3Array();vertices.resize(60000)
	for i:int in vertices.size():vertices[i]=Vector3(i%317-200,(i%13)*.1-6,i/317-400)
	var array:Array=[];array.resize(Mesh.ARRAY_MAX);array[Mesh.ARRAY_VERTEX]=vertices
	var surfaces:Array=[array];var source:=var_to_bytes(surfaces);var jobs:=48
	var expected:Mesh=Cpu.from_surfaces(surfaces,[null])
	var began:=Time.get_ticks_usec();var legacy:Array=[]
	for i:int in jobs:legacy.append(Cpu.from_surfaces(surfaces,[null]))
	var legacy_us:=Time.get_ticks_usec()-began
	var helper:Script=load("res://scripts/world3d/procedural_surface_bounds.gd") if FileAccess.file_exists("res://scripts/world3d/procedural_surface_bounds.gd") else null
	if helper!=null:
		for workers:int in [1,3,12,12,3,1]:
			var threads:Array=[];var gate:=Semaphore.new()
			for i:int in workers:
				var thread:=Thread.new();threads.append(thread);check(thread.start(prepare.bind(helper,surfaces,jobs/workers,gate))==OK,"worker starts")
			began=Time.get_ticks_usec()
			for i:int in workers:gate.post()
			var bounds:Array=[]
			for thread:Thread in threads:
				var packet:Dictionary=thread.wait_to_finish();bounds.append_array(packet.bounds);check(packet.thread!=OS.get_main_thread_id(),"scan runs off main thread")
			var wall:=Time.get_ticks_usec()-began
			began=Time.get_ticks_usec();var meshes:Array=[]
			for box:AABB in bounds:meshes.append(helper.make_cpu(surfaces,[null],box))
			var main_us:=Time.get_ticks_usec()-began;var exact:=meshes.size()==jobs
			for mesh:Mesh in meshes:exact=exact and mesh.get_aabb()==expected.get_aabb() and is_same(mesh.surfaces,surfaces)
			check(exact,"48 exact bounds and original geometry handoffs")
			rows.append({"workers":workers,"jobs":jobs,"prepare_wall_us":wall,"main_install_us":main_us})
		for points:PackedVector3Array in [PackedVector3Array(),PackedVector3Array([Vector3(-2,-3,-4)]),PackedVector3Array([Vector3(-8,-2,-4),Vector3(-2,-3,-9)])]:
			var row:Array=[];row.resize(Mesh.ARRAY_MAX);row[Mesh.ARRAY_VERTEX]=points
			check(helper.bounds([row])==Cpu.from_surfaces([row],[null]).get_aabb(),"empty, degenerate and negative bounds")
	check(var_to_bytes(surfaces)==source,"source geometry unchanged")
	var report:={"failures":failures,"jobs":jobs,"vertices":vertices.size(),"legacy_main_us":legacy_us,"runs":rows}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BOUNDS_STRESS ",JSON.stringify(report));quit(1 if failures else 0)
