extends "res://tools/test_prepared_collision_faces.gd"
func run()->void:
	var fixture:=world();var records:Array=[];var requests:Array=[];var expected:Array=[]
	for i:int in 12:
		var mesh:=small_source()
		if i%2==0:mesh.collision_faces()
		var record:=spec(mesh,"small_%d"%i,Transform3D(Basis.IDENTITY,Vector3(i*10.,0,0)))
		records.append(record);expected.append(mesh.surfaces[0][Mesh.ARRAY_VERTEX].duplicate())
		requests.append(fixture.preparer.prefetch_request(record))
	check(requests.all(func(row):return row.get("prepare_bvh",false)),"small shapes enter the existing bounded BVH batch")
	check(fixture.preparer._face_prefetch.request(requests,self),"one lookahead worker accepts all small shapes")
	var deadline:=Time.get_ticks_msec()+10000
	while fixture.preparer._face_prefetch._thread!=null and Time.get_ticks_msec()<deadline:
		fixture.preparer._face_prefetch.poll();await process_frame
	var ready:=true
	for i:int in records.size():
		ready=ready and fixture.preparer.prepare(records[i],fixture.host,24000)
		check(records[i].get("shape") is ConcavePolygonShape3D and records[i].shape.get_faces()==expected[i],"prepared ordinary shape keeps exact faces %d"%i)
		Stream._make_body(fixture.host,records[i])
	check(ready and fixture.preparer.face_worker_starts==0 and fixture.preparer.bvh_worker_shapes==12 and fixture.preparer.bvh_main_shapes==0,"consume one batch without serial extraction or main BVH rebuild")
	check(fixture.preparer._face_prefetch.profile.reserved_bytes==0,"consuming all small shapes returns every lookahead byte lease")
	await physics_frame;await physics_frame
	var space:PhysicsDirectSpaceState3D=fixture.host.get_world_3d().direct_space_state
	for i:int in records.size():
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(i*10.+.5,2,.5),Vector3(i*10.+.5,-2,.5),1))
		var hole:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(i*10.+2.5,2,2.5),Vector3(i*10.+2.5,-2,2.5),1))
		check(not hit.is_empty() and hole.is_empty(),"small batched collider keeps floor and authored hole %d"%i)
	fixture.viewport.free();await process_frame
	print("SMALL_COLLISION_PREFETCH failures=",failures);quit(1 if failures else 0)
