extends "res://tools/test_physical_traversal.gd"
const Doc=preload("res://scripts/world3d/world_document.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	var audit:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/nonperformance_fixes_20261012/audit.json"))
	var record:Dictionary=audit.records.filter(func(r):return r.uuid=="obj_200935")[0].duplicate(true)
	record.position=[0,0,0];record.rotation=[0,0,0]
	host=Node3D.new();root.add_child(host)
	box(Vector3(30,.2,30),Vector3(0,-.1,0))
	var doc=Doc.new();var prop:Node3D=doc._asset(record);host.add_child(prop)
	check(not prop.has_meta("missing_asset"),"actual user planter imported")
	for mesh:MeshInstance3D in Doc.SurfaceMaterials.meshes(prop):
		var spec:={"uuid":str(mesh.get_path()),"mesh":mesh.get_meta("collision_solid",mesh.get_meta("paint_source",mesh.mesh)),"transform":mesh.global_transform,"extras":mesh.get_meta("extras",{})}
		if OS.get_environment("RMMO_TEST_BAKE_SCALE")=="1":
			var shape:=Stream._triangle_shape(spec.mesh);var faces:=shape.get_faces()
			for i in faces.size():faces[i]=mesh.global_transform.basis*faces[i]
			shape.set_faces(faces);spec.shape=shape;spec.transform=Transform3D(Basis.IDENTITY,mesh.global_position)
		Stream._make_body(host,spec)
	body=Body.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D"
	var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;body.add_child(collider);host.add_child(body);body.floor_snap_length=.2
	var nav:=NavStub.new();host.add_child(nav);var authority:=Authority.new();authority.mount(body,nav,"test/real-planter")
	if "--profile" in OS.get_cmdline_user_args():body.set_meta("profile_frame",true)
	if not OS.get_environment("RMMO_TEST_MARGIN").is_empty():body.safe_margin=float(OS.get_environment("RMMO_TEST_MARGIN"))
	authority.traversal_guard=func(_bounds:AABB)->Dictionary:return {"ok":true,"physics_published_frame":0}
	await physics_frame;await physics_frame
	for direction:Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		body.position=Vector3(0,2,0);body.velocity=Vector3.ZERO
		for i in 45:await move(authority,Vector3.ZERO)
		check(body.is_on_floor() and body.position.y>1.05,"actual planter supports standing "+str(direction))
		if "--probe" in OS.get_cmdline_user_args():
			for rise in [.002,.005,.01,.02,.05,.1]:
				var contact:=KinematicCollision3D.new()
				var blocked:=body.test_move(body.global_transform,Vector3.UP*rise,contact)
				var q:=PhysicsShapeQueryParameters3D.new();q.shape=capsule;q.transform=body.global_transform;q.transform.origin.y+=rise;q.exclude=[body.get_rid()];q.collision_mask=1
				print("RECOVERY_PROBE ",rise," blocked=",blocked," travel=",contact.get_travel() if blocked else Vector3.ZERO," normal=",contact.get_normal() if blocked else Vector3.ZERO," occupied=",host.get_world_3d().direct_space_state.intersect_shape(q,16).size())
			authority.release();host.free();quit();return
		var start:=body.position
		for i in 15:await move(authority,direction)
		check((body.position-start).dot(direction)>.35,"actual planter permits horizontal walking "+str(direction))
		if "--profile" in OS.get_cmdline_user_args():print("PLANTER_WALK ",direction," start=",start," end=",body.position," timing=",body.get_meta("motion_timing",{}))
		body.position=Vector3(0,2,0);body.velocity=Vector3.ZERO
		for i in 45:await move(authority,Vector3.ZERO)
		var y:=body.position.y;await move(authority,direction,true)
		check(body.velocity.y>0 and body.position.y>y,"actual planter permits jumping "+str(direction))
		for i in 90:await move(authority,direction)
		check((body.position-start).dot(direction)>3 and body.is_on_floor() and body.position.y<1,"actual planter can be exited to ground "+str(direction))
	body.position=Vector3(0,2,0);body.velocity=Vector3.ZERO
	for i in 45:await move(authority,Vector3.ZERO)
	var before:=body.position
	var ceiling:=box(Vector3(2,.1,2),body.position+Vector3.UP*.9505)
	await physics_frame;await physics_frame
	check(not preload("res://scripts/world3d/floor_contact_recovery.gd").recover(body) and body.position==before,"floor recovery cannot cross even a half-millimetre head clearance")
	ceiling.free();await physics_frame;await physics_frame
	check(preload("res://scripts/world3d/floor_contact_recovery.gd").recover(body) and is_equal_approx(body.position.y-before.y,.002),"only the verified unoccupied two-millimetre floor separation is applied")
	authority.release();host.free();print("PLANTER_PHYSICAL passed=",passed," failures=",failures);quit(1 if failures else 0)
