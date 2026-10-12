extends "res://tools/test_collision_basis_preparation.gd"
## Private-desktop scene/physics regression. Only synthetic in-memory resources.
## Reuse the exact-face/holes/capsule helpers, not the original test's run list.

func small_source()->Mesh:
	var faces:=PackedVector3Array()
	for z in 6:
		for x in 6:
			if x==2 and z==2:continue
			var a:=Vector3(x,0,z);var b:=a+Vector3.RIGHT
			var c:=a+Vector3(1,0,1);var d:=a+Vector3.BACK
			faces.append_array(PackedVector3Array([a,b,c,a,c,d]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=faces
	var mesh:=Cpu.new();mesh.surfaces=[arrays];mesh.materials=[null]
	mesh.bounds=AABB(Vector3.ZERO,Vector3(6,.01,6))
	return mesh

func finish_ordinary(fixture:Dictionary,record:Dictionary)->bool:
	var deadline:=Time.get_ticks_msec()+10000
	while not fixture.preparer.prepare(record,fixture.host,24000):
		if Time.get_ticks_msec()>deadline:return false
		await process_frame
	return record.get("shape") is ConcavePolygonShape3D

func ordinary_cached()->void:
	var fixture:=world();var mesh:=small_source()
	var expected:PackedVector3Array=mesh.collision_faces().duplicate()
	var record:=spec(mesh,"cached_actual_collision",Transform3D(Basis.IDENTITY,Vector3(10,0,0)))
	# A paint/visual source may differ. Only the actual collision_mesh is valid.
	var visual:=BoxMesh.new();visual.size=Vector3(100,100,100);record.mesh=visual
	fixture.preparer.profile_enabled=true
	check(fixture.preparer.prepare(record,fixture.host,24000),"ordinary completed faces are ready in the first call")
	check(fixture.preparer._thread==null and fixture.preparer.last_profile.path=="prepared_faces","ordinary cached route creates no extraction worker")
	if check(record.get("shape") is ConcavePolygonShape3D,"actual collision source creates an exact concave shape"):
		check(record.shape.get_faces()==expected,"ordinary cache preserves collision_solid faces instead of visual box")
		var first:=Stream._make_body(fixture.host,record)
		var again:=spec(mesh,"ordinary_translation",Transform3D(Basis.IDENTITY,Vector3(20,0,0)))
		Preparer.prepared_faces_enabled=false
		check(fixture.preparer.prepare(again,fixture.host) and again.shape==record.shape,"existing shape cache wins even when prepared-face fast path is disabled")
		Preparer.prepared_faces_enabled=true
		await physics_frame;await physics_frame
		var space:PhysicsDirectSpaceState3D=fixture.host.get_world_3d().direct_space_state
		var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(10.5,2,.5),Vector3(10.5,-2,.5),1))
		var hole_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(12.5,2,2.5),Vector3(12.5,-2,2.5),1))
		check(not floor_hit.is_empty() and hole_hit.is_empty(),"ordinary cached collider retains real floor and authored hole")
		check(first.get_meta("uuid")==record.uuid and first.global_transform==record.transform,"ordinary publication retains UUID and transform")
	check(mesh._collision_faces==expected,"ordinary source cached faces remain unchanged")
	fixture.viewport.free()

func ordinary_fallback(cache_present:bool)->void:
	var fixture:=world();var mesh:=small_source()
	if cache_present:mesh.collision_faces()
	var expected:PackedVector3Array=mesh.surfaces[0][Mesh.ARRAY_VERTEX].duplicate()
	var record:=spec(mesh,"ordinary_disabled" if cache_present else "ordinary_empty",Transform3D.IDENTITY)
	Preparer.prepared_faces_enabled=not cache_present
	check(not fixture.preparer.prepare(record,fixture.host) and fixture.preparer._thread!=null,"ordinary empty/disabled cache retains asynchronous extraction: %s"%cache_present)
	check(await finish_ordinary(fixture,record),"ordinary fallback joins and completes: %s"%cache_present)
	if record.get("shape") is ConcavePolygonShape3D:check(record.shape.get_faces()==expected,"ordinary fallback retains every triangle: %s"%cache_present)
	if not cache_present:check(mesh._collision_faces.is_empty(),"fallback private extraction does not partially fill shared Cpu cache")
	Preparer.prepared_faces_enabled=true
	fixture.viewport.free()

func sliced_cached()->void:
	var fixture:=world();var mesh:=source()
	var expected:PackedVector3Array=mesh.collision_faces().duplicate()
	var record:=spec(mesh,"sliced_cached",Transform3D(Basis.IDENTITY,Vector3(12,0,0)))
	check(not fixture.preparer.prepare(record,fixture.host,1),"prepared faces still respect the exact-shape slice budget")
	check(fixture.preparer._terrain._thread==null and fixture.preparer._terrain._faces==expected,"identity slices consume completed faces without extraction worker")
	var unpublished:Variant=fixture.preparer._terrain._body
	check(is_instance_valid(unpublished) and unpublished.collision_layer==0 and unpublished.collision_mask==0,"cached-face partial body stays collision-disabled")
	var first:=await prepared(fixture,record)
	if first!=null:
		geometry_equal(first,mesh,record.transform,"cached identity slices")
		check(first.get_child_count()>1,"cached path keeps exact multi-shape slicing")
		var translated:=spec(mesh,"translated_cached",Transform3D(Basis.IDENTITY,Vector3(40,2,0)))
		Terrain.prepared_faces_enabled=false
		var second:=await prepared(fixture,translated)
		Terrain.prepared_faces_enabled=true
		if second!=null:
			check(shapes_same(first,second),"existing identity shape cache precedes disabled prepared-face route")
			geometry_equal(second,mesh,translated.transform,"translated existing slices")
	check(mesh._collision_faces==expected,"identity slices never alter borrowed source faces")
	fixture.viewport.free()

func sliced_fallback(cache_present:bool)->void:
	var fixture:=world();var mesh:=source()
	if cache_present:mesh.collision_faces()
	var record:=spec(mesh,"sliced_disabled" if cache_present else "sliced_empty",Transform3D.IDENTITY)
	Terrain.prepared_faces_enabled=not cache_present
	check(not fixture.preparer.prepare(record,fixture.host) and fixture.preparer._terrain._thread!=null,"sliced empty/disabled cache retains extraction worker: %s"%cache_present)
	var body:=await prepared(fixture,record)
	if body!=null:geometry_equal(body,mesh,record.transform,"sliced fallback %s"%cache_present)
	Terrain.prepared_faces_enabled=true
	fixture.viewport.free()

func cancellation_and_basis()->void:
	var fixture:=world();var mesh:=source()
	var expected:PackedVector3Array=mesh.collision_faces().duplicate()
	var record:=spec(mesh,"cancel_cached",Transform3D.IDENTITY)
	check(not fixture.preparer.prepare(record,fixture.host,1),"cached sliced request enters bounded partial preparation")
	var partial:Variant=fixture.preparer._terrain._body
	var partial_id:int=partial.get_instance_id() if is_instance_valid(partial) else 0
	fixture.preparer.cancel_pending()
	check(partial_id!=0 and not is_instance_id_valid(partial_id) and not record.has("prepared_body"),"cancel removes cached-face partial body and unpublished ownership")
	record.transform=Transform3D(Basis(Vector3.UP,.45).scaled_local(Vector3(1.2,1.1,.9)),Vector3(20,0,0))
	record.position=record.transform.origin
	check(not fixture.preparer.prepare(record,fixture.host,24000) and fixture.preparer._terrain._thread!=null,"cached local faces do not move basis transformation onto the main thread")
	# Switching an active request must not accept the old basis worker's result.
	record.transform=Transform3D(Basis(Vector3.UP,1.1).scaled_local(Vector3(.9,1.2,1.1)),Vector3(40,0,0))
	record.position=record.transform.origin
	var body:=await prepared(fixture,record)
	if body!=null:
		check(body.global_basis==Basis.IDENTITY and body.get_meta("collision_basis_baked",false),"replacement derived body retains translation-only publication")
		geometry_equal(body,mesh,record.transform,"cancel/replacement basis")
	check(mesh._collision_faces==expected,"basis worker never mutates shared completed faces")
	# A completed result not yet published remains cancellable with the fast path.
	var replacement:=source();replacement.collision_faces()
	var waiting:=spec(replacement,"cancel_complete",Transform3D.IDENTITY)
	var deadline:=Time.get_ticks_msec()+10000
	while not fixture.preparer.prepare(waiting,fixture.host,24000) and Time.get_ticks_msec()<deadline:await process_frame
	var waiting_body:Variant=waiting.get("prepared_body")
	var waiting_id:int=waiting_body.get_instance_id() if is_instance_valid(waiting_body) else 0
	fixture.preparer.cancel_pending()
	check(waiting_id!=0 and not is_instance_id_valid(waiting_id) and not waiting.has("prepared_body"),"cancel releases completed cached-face body before publication")
	fixture.viewport.free()

func source_replacement()->void:
	var fixture:=world();var source_mesh:=small_source();var gpu_mesh:ArrayMesh=source_mesh.restore()
	var original:Mesh=Cpu.capture(gpu_mesh);original.collision_faces()
	var old_record:=spec(original,"old_source",Transform3D.IDENTITY)
	check(fixture.preparer.prepare(old_record,fixture.host),"original immutable source uses completed cache")
	var old_shape:ConcavePolygonShape3D=old_record.shape
	var arrays:Array=source_mesh.surfaces[0].duplicate()
	var changed:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
	for i in changed.size():changed[i]+=Vector3.UP
	arrays[Mesh.ARRAY_VERTEX]=changed
	gpu_mesh.clear_surfaces();gpu_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var updated:Mesh=Cpu.capture(gpu_mesh)
	check(updated!=original and updated._collision_faces.is_empty(),"source.changed invalidates prior CPU cache instead of borrowing stale faces")
	var fresh_record:=spec(updated,"new_source",Transform3D.IDENTITY)
	check(not fixture.preparer.prepare(fresh_record,fixture.host),"changed source with empty cache keeps async fallback")
	check(await finish_ordinary(fixture,fresh_record),"changed source fallback completes")
	if fresh_record.get("shape") is ConcavePolygonShape3D:
		check(fresh_record.shape!=old_shape and fresh_record.shape.get_faces()==changed,"changed source receives new exact shape identity")
	check(old_shape.get_faces()==original._collision_faces,"prior shape remains intact for its existing owners")
	fixture.viewport.free()

func run()->void:
	create_timer(90).timeout.connect(func():push_error("prepared collision faces timeout");quit(2))
	var previous_slicing:=Preparer.terrain_slicing_enabled
	var previous_ordinary:=Preparer.prepared_faces_enabled
	var previous_sliced:=Terrain.prepared_faces_enabled
	Preparer.terrain_slicing_enabled=true;Preparer.prepared_faces_enabled=true;Terrain.prepared_faces_enabled=true
	await ordinary_cached()
	await ordinary_fallback(false)
	await ordinary_fallback(true)
	await sliced_cached()
	await sliced_fallback(false)
	await sliced_fallback(true)
	await cancellation_and_basis()
	await source_replacement()
	# Existing independent monolithic/sliced world comparison includes real rays,
	# a 0.2m sphere sweep, floor/door openings, and capsule motion with a baked basis.
	await query_equivalence()
	Preparer.terrain_slicing_enabled=previous_slicing
	Preparer.prepared_faces_enabled=previous_ordinary
	Terrain.prepared_faces_enabled=previous_sliced
	await process_frame
	print("PREPARED_COLLISION_FACES checks=",checks," failures=",failures)
	quit(1 if failures else 0)
