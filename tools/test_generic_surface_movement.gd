extends "res://tools/test_physical_traversal.gd"
## Real authority + physics; deliberately no per-model identifiers or navmesh.
func run()->void:
	create_timer(50).timeout.connect(func():print("GENERIC_SURFACE_TIMEOUT");quit(2))
	host=Node3D.new();root.add_child(host)
	body=Body.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D"
	var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;body.add_child(collider)
	host.add_child(body);body.floor_snap_length=.2
	var nav:=NavStub.new();host.add_child(nav);nav.ready_for_queries=true
	var authority:=Authority.new();authority.mount(body,nav,"test/generic-surfaces")
	box(Vector3(100,.2,100),Vector3(0,-.1,0))
	# A block-labelled rooftop with a walkable pitch above the nav bake slope.
	var roof:=box(Vector3(6,.2,6),Vector3(0,4,0),Vector3(0,0,deg_to_rad(43)))
	roof.set_meta("surface_id","block")
	await physics_frame;await physics_frame
	for guarded in [false,true]:
		authority.traversal_guard=(func(_bounds:AABB)->Dictionary:return {"ok":true,"physics_published_frame":0}) if guarded else Callable()
		body.position=Vector3(0,5.2,0);body.velocity=Vector3.ZERO
		for i in 40:await move(authority,Vector3.ZERO)
		check(body.is_on_floor(),"43 degree roof physically supports capsule, guarded="+str(guarded))
		var start:=body.position
		for i in 12:await move(authority,Vector3.FORWARD)
		check(start.z-body.position.z>.3,"roof walking independent of block tag and absent nav polygons, guarded="+str(guarded))
		var y:=body.position.y;await move(authority,Vector3.FORWARD,true)
		check(body.velocity.y>0 and body.position.y>y,"supported roof permits jump, guarded="+str(guarded))
	roof.free()
	authority.traversal_guard=func(_bounds:AABB)->Dictionary:return {"ok":true,"physics_published_frame":0}
	for dimensions:Vector3 in [Vector3(.22,5,.22),Vector3(1,.6,3),Vector3(5,3,5)]:
		var prop:=box(dimensions,Vector3(0,dimensions.y*.5,0));prop.set_meta("surface_id","block")
		await physics_frame;await physics_frame
		body.position=Vector3(0,dimensions.y+.91,0);body.velocity=Vector3.ZERO
		await settle(authority)
		check(body.is_on_floor(),"arbitrary solid supports standing "+str(dimensions))
		var y:=body.position.y;await move(authority,Vector3.RIGHT,true)
		check(body.position.y>y and body.velocity.y>0,"jump off arbitrary solid "+str(dimensions))
		for i in 200:await move(authority,Vector3.RIGHT)
		check(body.position.x>6 and body.position.y<1 and body.is_on_floor(),"leave solid and land on lower ground "+str(dimensions))
		prop.free()
	authority.release();host.free()
	print("GENERIC_SURFACE passed=",passed," failures=",failures);quit(0 if failures==0 else 1)
