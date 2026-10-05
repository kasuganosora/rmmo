extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Preparer=preload("res://scripts/world3d/stream_collision_preparer.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func hit(point:Vector3)->bool:
	return not root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP*2)).is_empty()
func run()->void:
	var faces:=PackedVector3Array()
	for z in 92:
		for x in 92:
			if x==4 and z==4:continue
			var a:=Vector3(x,0,z);var b:=a+Vector3.RIGHT;var c:=a+Vector3(1,0,1);var d:=a+Vector3.BACK
			faces.append_array(PackedVector3Array([a,b,c,a,c,d]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=faces
	var cpu:=Cpu.new();cpu.surfaces=[arrays];cpu.materials=[null]
	var host:=Node3D.new();root.add_child(host)
	var preparer:=Preparer.new();root.add_child(preparer)
	var spec:={"uuid":"terrain","mesh":cpu,"ground_batch_record":{"terrain_mesh":{}},"transform":Transform3D(Basis.IDENTITY,Vector3(100,0,100))}
	var deadline:=Time.get_ticks_msec()+15000;var hidden:=true;var steps:=0
	while not preparer.prepare(spec,host) and Time.get_ticks_msec()<deadline:
		steps+=1
		for child in host.get_children():hidden=hidden and child.collision_layer==0 and child.collision_mask==0
		await process_frame
	check(spec.has("prepared_body") and hidden and steps>1,"large terrain is prepared across frames with every partial body disabled")
	await physics_frame;await physics_frame
	check(not hit(Vector3(110.5,0,110.5)),"completed but unpublished body cannot collide")
	var body:=Stream._make_body(host,spec)
	var actual:=PackedVector3Array()
	for child in body.get_children():actual.append_array(child.shape.get_faces())
	check(actual==faces,"all slices preserve every original vertex, winding and authored hole")
	check(body.get_meta("uuid")=="terrain" and body.global_position==Vector3(100,0,100),"body identity and transform survive publication")
	await physics_frame;await physics_frame
	var solid:=true
	for z in range(1,91,3):solid=solid and hit(Vector3(110.5,0,100+z))
	check(solid and not hit(Vector3(104.5,0,104.5)),"rays cross slice boundaries without cracks while the authored hole stays open")
	var cached:Array=cpu.get_meta("runtime_terrain_shapes");body.free()
	deadline=Time.get_ticks_msec()+15000
	while not preparer.prepare(spec,host) and Time.get_ticks_msec()<deadline:await process_frame
	body=Stream._make_body(host,spec)
	check(body.get_child(0).shape==cached[0],"returning terrain reuses cooked immutable slice shapes")
	body.free()
	preparer.prepare(spec,host);preparer.cancel_pending()
	check(host.get_child_count()==0 and not spec.has("prepared_body"),"interrupted destination discards unpublished bodies")
	deadline=Time.get_ticks_msec()+15000
	while not preparer.prepare(spec,host) and Time.get_ticks_msec()<deadline:await process_frame
	preparer.cancel_pending()
	check(host.get_child_count()==0 and not spec.has("prepared_body"),"cancellation also discards a completed body waiting for publication")
	var fresh:=Cpu.new();fresh.surfaces=[arrays];fresh.materials=[null]
	preparer.prepare({"uuid":"pending","mesh":fresh,"ground_batch_record":{"terrain_mesh":{}}},host)
	preparer.free();host.free()
	check(true,"scene exit joins terrain worker and frees unpublished physics")
	print("TERRAIN_COLLISION_SLICES failures=",failures);quit(1 if failures else 0)
