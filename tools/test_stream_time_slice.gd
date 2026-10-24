extends SceneTree
## Real residency transitions: count-limited control versus the same time slice.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
var failures:=0
var slow:=false
var calls:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func inserted(node:Node)->void:
	if slow and str(node.name).begins_with("source"):OS.delay_usec(1100)
func fixture()->Node3D:
	var box:=BoxMesh.new();box.size=Vector3(.2,.3,.4)
	var cpu:=Cpu.capture(box);var library:Array=[]
	for i:int in 360:
		var position:=Vector3(float(i%20)*.4,0,float(i/20)*.4)
		var id:="source%04d"%i
		library.append({"uuid":id,"position":position,"rotation":Vector3.ZERO,"transform":Transform3D(Basis.IDENTITY,position),"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"mesh":cpu,"material_override":null,"surface_overrides":[],"cast_shadow":GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"extras":{"rmmo_collision":"walk" if i%17==0 else "none","surface_id":"block"}})
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",library)
	var indexed:=Index.build(library)
	for key:String in indexed:map.set_meta(key,indexed[key])
	return map
func drain(map:Node3D,at:Vector3,budget:int=Stream.FRAME_BUDGET)->Dictionary:
	var steps:=0;var cpu_us:=0;var maximum:=0;var max_progress:=0
	while steps<2000:
		var before:int=map.get_meta("stream_meshes",{}).size()
		var started:=Time.get_ticks_usec();Stream.sync(map,map,at,budget)
		var elapsed:=Time.get_ticks_usec()-started
		cpu_us+=elapsed;maximum=maxi(maximum,elapsed);steps+=1
		max_progress=maxi(max_progress,absi(map.get_meta("stream_meshes",{}).size()-before))
		if map.get_meta("stream_chunk",Vector2i(-999,-999))==Stream.chunk_key(at) and map.get_meta("stream_jobs",[]).is_empty():break
		await process_frame
	return {"steps":steps,"cpu_us":cpu_us,"max_us":maximum,"max_progress":max_progress}
func snapshot(map:Node3D)->Dictionary:
	var result:Dictionary={"meshes":{},"bodies":{}}
	for id:String in map.get_meta("stream_meshes",{}):result.meshes[id]=map.get_meta("stream_meshes")[id].transform
	for id:String in map.get_meta("stream_bodies",{}):result.bodies[id]=map.get_meta("stream_bodies")[id].transform
	return result
func run()->void:
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	Stream.white_time_slice_enabled=not "--baseline" in OS.get_cmdline_user_args()
	node_added.connect(inserted)
	var map:=fixture()
	var first:=await drain(map,Vector3(4,0,4));var expected:=snapshot(map)
	check(expected.meshes.size()==360 and expected.bodies.size()==22,"all original mesh and exact collision owners are resident")
	var away:=await drain(map,Vector3(3000,0,3000))
	check(map.get_meta("stream_meshes").is_empty() and map.get_meta("stream_bodies").is_empty(),"departure removes both visuals and collision bodies")
	var returned:=await drain(map,Vector3(4,0,4))
	check(snapshot(map)==expected,"return restores the exact UUIDs and transforms")
	check(first.max_progress>12 and away.max_progress>12 if Stream.white_time_slice_enabled else first.max_progress<=12 and away.max_progress<=12,"cheap work uses its time allowance; the control stops at twelve")
	calls=[first,away,returned];map.free();await process_frame
	map=fixture();slow=true
	var slow_step:=await drain(map,Vector3(4,0,4));slow=false
	check(slow_step.max_progress<=4 and slow_step.steps>90,"costly engine callbacks stop the existing time slice before a long object batch")
	map.free();await process_frame
	map=fixture()
	var explicit:=await drain(map,Vector3(4,0,4),1)
	check(explicit.max_progress<=1,"explicit one-object callers retain their limit")
	map.free();await process_frame
	Controls.white_materials=false
	map=fixture()
	var textured:=await drain(map,Vector3(4,0,4))
	check(textured.max_progress<=12,"non-white callers keep their existing object ceiling")
	map.free();await process_frame
	print("STREAM_TIME_SLICE ",JSON.stringify({"calls":calls,"slow":slow_step,"explicit":explicit,"nonwhite":textured,"failures":failures}))
	quit(1 if failures else 0)
