extends SceneTree
## Real physics/scene regression. Run on the private GPU desktop, never headless.
## Temporary synthetic geometry; no user maps or resources are read or written.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Preparer=preload("res://scripts/world3d/stream_collision_preparer.gd")
const Terrain=preload("res://scripts/world3d/terrain_collision_preparer.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
var failures:=0
var checks:=0

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok

func source()->Mesh:
	var faces:=PackedVector3Array()
	# Non-repeated tessellated floor, with a genuine one-metre hole.
	for z in 32:
		for x in 48:
			var point:=Vector3(-6+x*.25,0,-4+z*.25)
			if point.x>=3 and point.x<4 and point.z>=1 and point.z<2:continue
			var a:=point;var b:=a+Vector3(.25,0,0);var c:=a+Vector3(.25,0,.25);var d:=a+Vector3(0,0,.25)
			faces.append_array(PackedVector3Array([a,b,c,a,c,d]))
	# Wall z=0, with a two-metre-wide, 2.5-metre-high opening.
	for y in 16:
		for x in 48:
			var point:=Vector3(-6+x*.25,y*.25,0)
			if point.x>=-1 and point.x<1 and point.y<2.5:continue
			var a:=point;var b:=a+Vector3(.25,0,0);var c:=a+Vector3(.25,.25,0);var d:=a+Vector3(0,.25,0)
			faces.append_array(PackedVector3Array([a,b,c,a,c,d]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=faces
	var mesh:=Cpu.new();mesh.surfaces=[arrays];mesh.materials=[null];mesh.bounds=AABB(Vector3(-6,0,-4),Vector3(12,4,8))
	return mesh

func spec(mesh:Mesh,id:String,pose:Transform3D)->Dictionary:
	return {"uuid":id,"mesh":mesh,"collision_mesh":mesh,"transform":pose,"position":pose.origin,"rotation":pose.basis.get_euler(),"extras":{"rmmo_collision":"walk","surface_id":"ground"}}

func world()->Dictionary:
	var viewport:=SubViewport.new();viewport.own_world_3d=true;viewport.disable_3d=true;root.add_child(viewport)
	var host:=Node3D.new();viewport.add_child(host)
	var preparer:=Preparer.new();host.add_child(preparer)
	return {"viewport":viewport,"host":host,"preparer":preparer}

func prepared(fixture:Dictionary,record:Dictionary)->StaticBody3D:
	var before:Transform3D=record.transform
	var deadline:=Time.get_ticks_msec()+15000
	while not fixture.preparer.prepare(record,fixture.host,1500) and Time.get_ticks_msec()<deadline:await process_frame
	if not check(is_instance_valid(record.get("prepared_body")),"prepared complete: "+str(record.uuid)):return null
	check(record.transform==before,"authoritative spec transform unchanged: "+str(record.uuid))
	var body:StaticBody3D=Stream._make_body(fixture.host,record)
	check(body!=null and not record.has("prepared_body"),"publication transfers body ownership: "+str(record.uuid))
	return body

func world_faces(body:StaticBody3D)->PackedVector3Array:
	var result:=PackedVector3Array()
	for child:Node in body.get_children():
		if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
			result.append_array(child.global_transform*child.shape.get_faces())
	return result

func geometry_equal(body:StaticBody3D,mesh:Mesh,pose:Transform3D,label:String)->void:
	var actual:=world_faces(body);var expected:PackedVector3Array=pose*mesh.collision_faces()
	var error:=0.
	if actual.size()==expected.size():
		for i in expected.size():error=maxf(error,actual[i].distance_to(expected[i]))
	else:error=INF
	check(error<.0001,label+" world triangles preserve count/order/winding within 0.1 mm (error %.9f m)"%error)

func shapes_same(first:StaticBody3D,second:StaticBody3D)->bool:
	if first.get_child_count()!=second.get_child_count():return false
	for i in first.get_child_count():
		if first.get_child(i).shape!=second.get_child(i).shape:return false
	return true

func sharing_and_eviction()->void:
	var fixture:=world();var mesh:=source();var source_bytes:=var_to_bytes(mesh.surfaces)
	check(mesh.collision_faces().size()/3>3072,"synthetic fixture has over 3072 genuine triangles and authored openings")
	var basis:=Basis(Vector3.UP,.61).scaled_local(Vector3(1.3,1.1,.85))
	var a:=spec(mesh,"share_a",Transform3D(basis,Vector3(0,0,0)))
	var b:=spec(mesh,"share_b",Transform3D(basis,Vector3(30,2,0)))
	var visual:=MeshInstance3D.new();visual.mesh=mesh.restore();fixture.host.add_child(visual);visual.global_transform=a.transform
	var render_pose:=visual.global_transform;var render_arrays:=var_to_bytes(visual.mesh.surface_get_arrays(0))
	var first:=await prepared(fixture,a);var second:=await prepared(fixture,b)
	if first==null or second==null:fixture.viewport.free();return
	check(first.global_basis==Basis.IDENTITY and second.global_basis==Basis.IDENTITY,"eligible bodies keep translation only")
	check(first.global_position==a.transform.origin and second.global_position==b.transform.origin,"each instance retains its own translation")
	check(first.get_meta("collision_basis_baked",false) and second.get_meta("collision_basis_baked",false),"published bodies identify derived basis geometry")
	check(shapes_same(first,second),"different translations with exactly the same basis share immutable shapes")
	geometry_equal(first,mesh,a.transform,"first translation")
	geometry_equal(second,mesh,b.transform,"second translation")
	var rotated:=spec(mesh,"another_yaw",Transform3D(Basis(Vector3.UP,1.07).scaled_local(Vector3(1.3,1.1,.85)),Vector3(60,0,0)))
	var third:=await prepared(fixture,rotated)
	if third==null:fixture.viewport.free();return
	check(not shapes_same(first,third),"same source with another yaw cannot reuse the previous basis shapes")
	geometry_equal(third,mesh,rotated.transform,"different yaw")
	var retained:WeakRef=weakref(first.get_child(0).shape)
	var key:String=Terrain._basis_variant(a).key
	var bounded:=true
	for i in 10:
		var variant:=spec(mesh,"variant_%d"%i,Transform3D(Basis(Vector3.UP,.1+i*.11).scaled_local(Vector3(1.1,1.05,.95)),Vector3(100+i*25,0,0)))
		var body:=await prepared(fixture,variant)
		if body==null:bounded=false;break
		bounded=bounded and mesh.get_meta("runtime_terrain_basis_shapes",{}).get("entries",{}).size()<=Terrain.BASIS_VARIANT_LIMIT
		body.free()
	var cache:Dictionary=mesh.get_meta("runtime_terrain_basis_shapes",{})
	check(bounded and cache.get("entries",{}).size()<=8,"source basis cache never exceeds eight variants")
	check(not cache.get("entries",{}).has(key),"old inactive-cache key is evicted after newer bases are prepared")
	check(retained.get_ref()!=null and first.get_child(0).shape==retained.get_ref() and shapes_same(first,second),"active bodies retain valid shared shapes after cache eviction")
	geometry_equal(first,mesh,a.transform,"active body after cache eviction")
	check(var_to_bytes(mesh.surfaces)==source_bytes,"basis derivation never mutates shared source mesh arrays")
	check(visual.global_transform==render_pose and var_to_bytes(visual.mesh.surface_get_arrays(0))==render_arrays and a.mesh==mesh,"render transform/geometry and spec mesh identity stay unchanged")
	fixture.viewport.free()

func transformed_host()->void:
	var fixture:=world();var mesh:=source()
	fixture.host.transform=Transform3D(Basis(Vector3.UP,.23).scaled_local(Vector3.ONE*1.25),Vector3(8,2,4))
	var pose:=Transform3D(Basis(Vector3.UP,.7).scaled_local(Vector3(1.4,.9,.8)),Vector3(-12,3,20))
	var record:=spec(mesh,"transformed_host",pose)
	var body:=await prepared(fixture,record)
	if body!=null:
		check(body.global_transform.is_equal_approx(Transform3D(Basis.IDENTITY,pose.origin)),"transformed host still yields the requested world translation and identity world basis")
		geometry_equal(body,mesh,pose,"nonidentity host")
	fixture.viewport.free()

func cancelled_basis(same_dictionary:bool)->void:
	var fixture:=world();var mesh:=source()
	var first:=spec(mesh,"cancel_first",Transform3D(Basis(Vector3.UP,.4).scaled_local(Vector3(1.2,1.1,.9)),Vector3.ZERO))
	check(not fixture.preparer.prepare(first,fixture.host,1),"basis preparation initially starts an asynchronous CPU job")
	var second:Dictionary=first if same_dictionary else spec(mesh,"cancel_second",first.transform)
	second.transform=Transform3D(Basis(Vector3.UP,1.2).scaled_local(Vector3(1.1,1.15,.8)),Vector3(20,0,0))
	second.position=second.transform.origin
	var replacement:=await prepared(fixture,second)
	if replacement!=null:
		geometry_equal(replacement,mesh,second.transform,"cancel/restart same dictionary" if same_dictionary else "cancel/restart different dictionary")
		check(replacement.global_basis==Basis.IDENTITY,"cancelled worker cannot reinstall its old body basis")
		if not same_dictionary:check(not first.has("prepared_body"),"old basis request has no orphaned prepared result")
		var active:=0
		for child:Node in fixture.host.get_children():
			if child is StaticBody3D:active+=1
		check(active==1,"basis switch leaves exactly one published body")
	fixture.viewport.free()

func fallbacks_and_fixture()->void:
	var fixture:=world();var mesh:=source()
	var bases:Dictionary={"identity":Basis.IDENTITY,"mirror":Basis.from_scale(Vector3(-1,1,1)),"shear":Basis(Vector3(1,0,0),Vector3(.2,1,0),Vector3(0,0,1)),"pitch":Basis(Vector3.RIGHT,.3)}
	for label:String in bases:
		var record:=spec(mesh,label,Transform3D(bases[label],Vector3.ZERO))
		check(Terrain._basis_variant(record).key.is_empty(),label+" rejects derived basis cache")
		var body:=await prepared(fixture,record)
		if body==null:continue
		check(not body.get_meta("collision_basis_baked",false) and body.global_transform.is_equal_approx(record.transform),label+" retains established body transform path")
		geometry_equal(body,mesh,record.transform,label+" fallback")
		body.free()
	check(mesh.has_meta("runtime_terrain_shapes"),"identity/fallbacks preserve legacy local-space shape cache")
	var record:=spec(mesh,"hinged_door",Transform3D(Basis(Vector3.UP,.5).scaled_local(Vector3.ONE*1.2),Vector3(10,0,0)))
	record.extras.fixture={"id":"door_1","kind":"door","pivot":[-1,0,0],"angle":75.,"open":0.}
	record.extras.building={"id":"fixture_house"}
	Fixtures.prepare_spec(record)
	check(Terrain._basis_variant(record).key.is_empty(),"hinged fixture is excluded even with eligible pure yaw and positive scale")
	var door:=await prepared(fixture,record)
	if door!=null:
		check(not door.get_meta("collision_basis_baked",false) and door.global_transform.is_equal_approx(record.transform),"dynamic door begins with its original basis")
		var map:=Node3D.new();fixture.host.add_child(map)
		map.set_meta("stream_library",[record]);map.set_meta("stream_bodies",{record.uuid:door})
		var closed:Transform3D=record.transform
		var opened:Dictionary=Fixtures.set_runtime(map,"fixture_house","door_1",1.,0.)
		var expected:Transform3D=Fixtures.pose(record.closed_transform,record.extras.fixture,1.)
		check(opened.ok and not door.global_transform.is_equal_approx(closed) and door.global_transform.is_equal_approx(expected),"production fixture open updates the real body transform")
		geometry_equal(door,mesh,expected,"opened fixture without double transform")
		var shut:Dictionary=Fixtures.set_runtime(map,"fixture_house","door_1",0.,0.)
		check(shut.ok and door.global_transform.is_equal_approx(closed),"production fixture close restores original pose")
		geometry_equal(door,mesh,closed,"closed fixture")
	fixture.viewport.free()

func reference_body(host:Node3D,mesh:Mesh,pose:Transform3D)->StaticBody3D:
	var body:=StaticBody3D.new();var shape:=ConcavePolygonShape3D.new();shape.set_faces(mesh.collision_faces())
	var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider);host.add_child(body);body.global_transform=pose
	return body

func player(host:Node3D,point:Vector3)->CharacterBody3D:
	var result:=CharacterBody3D.new();result.floor_snap_length=.2
	var collider:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=.3;shape.height=1.8;collider.shape=shape;result.add_child(collider)
	host.add_child(result);result.global_position=point;result.set_physics_process(false)
	return result

func queries(fixture:Dictionary,pose:Transform3D)->Dictionary:
	var space:PhysicsDirectSpaceState3D=fixture.host.get_world_3d().direct_space_state
	var rays:Dictionary={};var spheres:Dictionary={}
	var segments:Dictionary={"floor":[Vector3(-3,2,-2),Vector3(-3,-2,-2)],"hole":[Vector3(3.5,2,1.5),Vector3(3.5,-2,1.5)],"wall_front":[Vector3(3,1.5,2),Vector3(3,1.5,-2)],"wall_back":[Vector3(3,1.5,-2),Vector3(3,1.5,2)],"door_front":[Vector3(0,1.5,2),Vector3(0,1.5,-2)],"door_back":[Vector3(0,1.5,-2),Vector3(0,1.5,2)]}
	for label:String in segments:
		var from:Vector3=pose*segments[label][0];var to:Vector3=pose*segments[label][1]
		var hit:Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))
		rays[label]={"hit":not hit.is_empty(),"position":hit.get("position",Vector3.ZERO)}
		var query:=PhysicsShapeQueryParameters3D.new();var sphere:=SphereShape3D.new();sphere.radius=.2
		query.shape=sphere;query.transform=Transform3D(Basis.IDENTITY,from);query.motion=to-from;query.margin=.015;query.collision_mask=1
		spheres[label]=space.cast_motion(query)
	return {"rays":rays,"spheres":spheres}

func query_equivalence()->void:
	var baseline:=world();var derived:=world();var mesh:=source()
	var pose:=Transform3D(Basis(Vector3.UP,.63).scaled_local(Vector3(1.3,1.1,.85)),Vector3(12,1,-8))
	var original:=reference_body(baseline.host,mesh,pose)
	var body:=await prepared(derived,spec(mesh,"query_subject",pose))
	if body==null:baseline.viewport.free();derived.viewport.free();return
	await physics_frame;await physics_frame;await process_frame
	var before:=queries(baseline,pose);var after:=queries(derived,pose)
	check(before.rays.floor.hit and not before.rays.hole.hit and not before.rays.door_front.hit and not before.rays.door_back.hit and (before.rays.wall_front.hit or before.rays.wall_back.hit),"reference fixture has real floor, hole, doorway and solid wall")
	var rays_equal:=true;var spheres_equal:=true
	for label:String in before.rays:
		rays_equal=rays_equal and before.rays[label].hit==after.rays[label].hit
		if before.rays[label].hit and after.rays[label].hit:rays_equal=rays_equal and before.rays[label].position.distance_to(after.rays[label].position)<.0001
		for i in 2:spheres_equal=spheres_equal and absf(before.spheres[label][i]-after.spheres[label][i])<.002
	check(rays_equal,"real rays retain hit/miss and world hit positions across floor, hole, wall and doorway")
	check(spheres_equal,"0.2m sphere cast_motion keeps safe/unsafe fractions within 0.002")
	var start:=pose*Vector3(-3,0,-2)+Vector3.UP*.902
	var first:=player(baseline.host,start);var second:=player(derived.host,start)
	await physics_frame;await physics_frame
	var floor_equal:=true;var motion_equal:=true;var grounded:=0
	for tick in 24:
		await physics_frame
		var velocity_:Vector3=pose.basis*Vector3(.3,0,0)+Vector3.DOWN*.5
		first.velocity=velocity_;second.velocity=velocity_
		first.move_and_slide();second.move_and_slide()
		floor_equal=floor_equal and first.is_on_floor()==second.is_on_floor()
		motion_equal=motion_equal and first.global_position.distance_to(second.global_position)<.002
		if first.is_on_floor() and second.is_on_floor():grounded+=1
	check(floor_equal and grounded>=23,"real capsule movement retains floor contact across physics ticks")
	check(motion_equal,"real capsule move_and_slide retains trajectory within 2 mm")
	check(original.global_transform.is_equal_approx(pose) and body.global_basis==Basis.IDENTITY,"query comparison used original transformed body versus translation-only derived body")
	baseline.viewport.free();derived.viewport.free()

func run()->void:
	create_timer(180).timeout.connect(func():push_error("collision basis preparation timeout");quit(2))
	var previous:=Preparer.terrain_slicing_enabled;Preparer.terrain_slicing_enabled=true
	await sharing_and_eviction()
	await transformed_host()
	await cancelled_basis(false)
	await cancelled_basis(true)
	await fallbacks_and_fixture()
	await query_equivalence()
	Preparer.terrain_slicing_enabled=previous
	await process_frame
	print("COLLISION_BASIS_PREPARATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
