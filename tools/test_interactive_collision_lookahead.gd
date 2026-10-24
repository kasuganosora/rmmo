extends SceneTree
## Actual interactive residency: identical geometry with serial or batched faces.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
class SlowLookahead extends "res://scripts/world3d/stream_collision_preparer.gd":
	func prefetch_request(spec:Dictionary)->Dictionary:
		OS.delay_usec(250)
		return super.prefetch_request(spec)
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture()->Node3D:
	var specs:Array=[]
	for i:int in 96:
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		var vertices:=PackedVector3Array()
		for triangle:int in (1100 if i>=72 else 30):
			var x:=float(triangle%40)*.01;var z:=float(triangle/40)*.01
			vertices.append_array(PackedVector3Array([Vector3(x,0,z),Vector3(x,0,z+.009),Vector3(x+.009,0,z)]))
		arrays[Mesh.ARRAY_VERTEX]=vertices
		var cpu:=Cpu.new();cpu.surfaces=[arrays];cpu.materials=[null];cpu.bounds=AABB(Vector3.ZERO,Vector3(.4,0,.3))
		var at:=Vector3(float(i%12),0,float(i/12));var pose:=Transform3D(Basis(Vector3.UP,.2) if i>=72 else Basis.IDENTITY,at)
		specs.append({"uuid":"source%03d"%i,"position":at,"rotation":pose.basis.get_euler(),"transform":pose,"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"mesh":cpu,"material_override":null,"surface_overrides":[],"cast_shadow":0,"extras":{"rmmo_collision":"walk","surface_id":"block"}})
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",specs)
	if "--slow-lookahead" in OS.get_cmdline_user_args():
		var p:=SlowLookahead.new();p.name="StreamCollisionPreparer";map.add_child(p)
	var indexed:=Index.build(specs)
	for field:String in indexed:map.set_meta(field,indexed[field])
	return map
func drain(map:Node3D,at:Vector3)->Dictionary:
	var steps:=0;var used:=0;var max_us:=0;var began:=Time.get_ticks_usec()
	while steps<300:
		var started:=Time.get_ticks_usec();Stream.sync(map,map,at,Stream.FRAME_BUDGET)
		var elapsed:=Time.get_ticks_usec()-started;used+=elapsed;max_us=maxi(max_us,elapsed);steps+=1
		if map.get_meta("stream_chunk",Vector2i(-999,-999))==Stream.chunk_key(at) and map.get_meta("stream_jobs",[]).is_empty():break
		await process_frame
	return {"steps":steps,"cpu_us":used,"max_us":max_us,"wall_us":Time.get_ticks_usec()-began}
func exact_bodies(map:Node3D)->bool:
	var bodies:Dictionary=map.get_meta("stream_bodies",{})
	if bodies.size()!=96:return false
	for spec:Dictionary in map.get_meta("stream_library"):
		var body:StaticBody3D=bodies[spec.uuid];var faces:=PackedVector3Array()
		for child:Node in body.get_children():
			if child is CollisionShape3D:faces.append_array(body.transform*child.shape.get_faces())
		var expected:PackedVector3Array=spec.transform*spec.mesh.surfaces[0][Mesh.ARRAY_VERTEX]
		if faces.size()!=expected.size():return false
		for i:int in faces.size():
			if not faces[i].is_equal_approx(expected[i]):return false
	return true
func run()->void:
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	Stream.white_collision_prefetch_enabled=not "--baseline" in OS.get_cmdline_user_args()
	var map:=fixture();var origin:=Vector3(4,0,4)
	var first:=await drain(map,origin)
	check(exact_bodies(map),"all ordinary and rotated sliced bodies contain exactly the original triangles")
	if failures:
		print("INTERACTIVE_COLLISION_STALLED ",first," bodies=",map.get_meta("stream_bodies",{}).size());map.free();quit(1);return
	var preparer:Node=map.get_node("StreamCollisionPreparer")
	var workers:int=preparer.face_worker_starts+preparer._terrain.face_expansions
	var queue:Dictionary=preparer._face_prefetch.profile.duplicate()
	if not "--baseline" in OS.get_cmdline_user_args():
		if "--slow-lookahead" in OS.get_cmdline_user_args():
			check(first.steps<200,"an expensive optional lookahead cannot starve ready collision attachment")
		else:
			check(workers<16 and first.steps<96,"interactive small requests do not incur one serial worker/frame per source")
			check(queue.batches>0 and queue.hits==96,"interactive cursor consumes all actual batched face outputs")
	check(queue.reserved_bytes==0,"completed consumers release the complete lookahead reservation")
	var away:=await drain(map,Vector3(3000,0,3000))
	check(map.get_meta("stream_bodies").is_empty() and map.get_meta("stream_meshes").is_empty(),"moving away unloads visuals and bodies")
	var returned:=await drain(map,origin)
	check(exact_bodies(map),"return preserves all UUIDs and transformed triangle geometry")
	map.free();await process_frame
	print("INTERACTIVE_COLLISION_LOOKAHEAD ",JSON.stringify({"first":first,"away":away,"returned":returned,"serial_workers":workers,"queue":queue,"failures":failures}))
	quit(1 if failures else 0)
