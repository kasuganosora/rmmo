extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Terrain=preload("res://scripts/world3d/terrain_collision_preparer.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map)
	var uncaptured:=Terrain.new()
	var uncaptured_spec:={"mesh":BoxMesh.new()}
	check(uncaptured.prepare(uncaptured_spec,host) and not uncaptured_spec.has("prepared_body") and uncaptured._thread==null,"uncaptured mesh retains fallback without reading missing metadata")
	uncaptured.finish()
	var solid:={"low":Vector2i.ZERO,"high":Vector2i.ZERO}
	var primitive:={"uuid":"box","chunk":Vector2i.ZERO,"mesh":BoxMesh.new()}
	check(Stream._prepare_collision(map,host,primitive,solid,{}) and not map.has_meta("collision_prepare_timing"),"normal streaming does not publish detailed diagnostics")
	map.set_meta("profile_collision_details",true)
	var faces:=PackedVector3Array()
	for i in 1030:
		var p:=Vector3(i%32,0,i/32);faces.append_array(PackedVector3Array([p,p+Vector3.RIGHT,p+Vector3.BACK]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=faces
	var cpu:=Cpu.new();cpu.surfaces=[arrays];cpu.materials=[null]
	var spec:={"uuid":"profile_fixture","chunk":Vector2i.ZERO,"mesh":cpu}
	var deadline:=Time.get_ticks_msec()+5000
	while not Stream._prepare_collision(map,host,spec,solid,{}) and Time.get_ticks_msec()<deadline:await process_frame
	check(spec.has("prepared_body"),"diagnostic route preserves completed collision publication")
	if not spec.has("prepared_body"):
		map.free();await process_frame;host.free();quit(1);return
	var timing:Dictionary=map.get_meta("collision_prepare_timing",{})
	check(timing.get("uuid")=="profile_fixture" and timing.get("frame")==Engine.get_process_frames() and timing.get("preparer",{}).get("path")=="terrain","slowest frame diagnostic identifies current receiver and terrain branch")
	var detail:Dictionary=timing.get("preparer",{})
	check(detail.get("stages",{}).has("needs_slices_ms") and detail.get("terrain",{}).get("details",{}).get("slice_count",0)==2,"stream eligibility and terrain slice count are correlated")
	var intervals:Array=detail.get("terrain",{}).get("details",{}).get("set_faces_intervals",[])
	check(not intervals.is_empty() and intervals[0].end_usec>=intervals[0].begin_usec,"shape timeline records an absolute interval for main-thread CPU correlation")
	var preparer=map.get_node("StreamCollisionPreparer")
	check(preparer._terrain.profile_rows.is_empty(),"real-route diagnostics retain current call instead of accumulating unbounded rows")
	await process_frame
	check(Stream._prepare_collision(map,host,spec,solid,{"profile_fixture":spec.prepared_body}),"resident-body gate still short circuits")
	timing=map.get_meta("collision_prepare_timing",{})
	check(not timing.has("preparer") and timing.frame==Engine.get_process_frames(),"fast gated frame never repeats an older preparer stage snapshot")
	var serial:int=preparer.profile_serial;map.remove_meta("profile_collision_details")
	Stream._prepare_collision(map,host,spec,solid,{})
	check(preparer.profile_serial==serial and not preparer._terrain.profile_enabled,"turning diagnostics off stops nested measurement")
	map.free();await process_frame;host.free()
	print("STREAM_COLLISION_PROFILE_FAILURES ",failures);quit(1 if failures else 0)
