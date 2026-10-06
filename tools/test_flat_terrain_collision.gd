extends SceneTree
const Flat=preload("res://scripts/world3d/flat_terrain_collision.gd")
const Surface=preload("res://scripts/world3d/terrain_surface.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var heights:Array=[];heights.resize(20);heights.fill(.25)
	var holes:Array=[];holes.resize(12);holes.fill(false)
	var record:={"kind":"box","size":[12.,.7,8.],"terrain_mesh":{"columns":4,"rows":3,"heights":heights,"holes":holes,"floor":-2.}}
	for variant in ["height","hole","furrow","missing","zero","malformed"]:
		var changed:Dictionary=record.duplicate(true)
		match variant:
			"height":changed.terrain_mesh.heights[7]+=.00001
			"hole":changed.terrain_mesh.holes[0]=true
			"furrow":changed.terrain_regions={"regions":[{"furrows":{"height":.1}}]}
			"missing":changed.erase("terrain_mesh")
			"zero":changed.terrain_mesh.floor=.25
			"malformed":changed.terrain_mesh.heights.pop_back()
		check(Flat.descriptor({"ground_batch_record":changed}).is_empty(),"preserve triangles for "+variant)
	var cpu:=Cpu.new();cpu.surfaces=Surface.arrays(record);cpu.materials=[null,null]
	var pose:=Transform3D(Basis.from_euler(Vector3(.15,.38,-.1)),Vector3(100,3,-80))
	var spec:={"uuid":"flat_fixture","mesh":cpu,"ground_batch_record":record,"transform":pose,"extras":{"surface_id":"grass","rmmo_collision":"walk"}}
	var host:=Node3D.new();root.add_child(host)
	var fast:=Stream._make_body(host,spec);fast.collision_layer=1
	var old:=StaticBody3D.new();old.collision_layer=2
	var shape:=CollisionShape3D.new();var triangles:=ConcavePolygonShape3D.new();triangles.set_faces(cpu.collision_faces());shape.shape=triangles
	old.add_child(shape);host.add_child(old);old.global_transform=pose
	check(fast.get_child_count()==1 and fast.get_child(0).shape is BoxShape3D,"runtime creates one primitive box for exact flat terrain")
	check(fast.get_meta("uuid")=="flat_fixture" and fast.get_meta("surface_id")=="grass" and fast.global_transform==pose,"UUID, surface and rotated world transform preserved")
	await physics_frame;await physics_frame
	var box:BoxShape3D=fast.get_child(0).shape;var center:Vector3=fast.get_child(0).position
	var mismatches:=0;var count:=0
	var space:=root.world_3d.direct_space_state
	for axis in 3:
		for sign_ in [-1.,1.]:
			for u in range(-4,5):
				for v in range(-4,5):
					var p:=center;p[axis]+=sign_*box.size[axis]*.5
					p[(axis+1)%3]+=u*.1*box.size[(axis+1)%3];p[(axis+2)%3]+=v*.1*box.size[(axis+2)%3]
					var direction:=Vector3.ZERO;direction[axis]=sign_
					var a:Vector3=pose*(p+direction*2);var b:Vector3=pose*(p-direction*.2)
					var lhs:=space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))
					var rhs:=space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,2))
					count+=1
					if lhs.is_empty() or rhs.is_empty() or lhs.position.distance_to(rhs.position)>.0001 or lhs.normal.distance_to(rhs.normal)>.001:mismatches+=1
	check(mismatches==0,"486 exterior rays match original top, bottom and sides with rotation and offset: "+str(mismatches))
	check(Flat.descriptor(spec).shape==box,"immutable stream spec reuses the primitive")
	host.free();print("FLAT_TERRAIN_COLLISION failures=",failures," rays=",count);quit(1 if failures else 0)
