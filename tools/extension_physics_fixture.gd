extends RefCounted
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
static func attach(tree:SceneTree,doc:RefCounted)->Node3D:
	var viewport:=SubViewport.new();viewport.own_world_3d=true;tree.root.add_child(viewport)
	var host:=Node3D.new();viewport.add_child(host);host.set_meta("fixture_viewport",viewport)
	for r:Dictionary in doc.records:
		if r.get("collision")=="none":continue
		var node:Node3D=doc._asset(r) if r.kind=="asset" else doc._mesh(r)
		if node==null:continue
		host.add_child(node)
		for part:MeshInstance3D in Paint.meshes(node):
			Stream._make_body(host,{"uuid":r.uuid,"mesh":part.mesh,"transform":part.global_transform,"extras":{"rmmo_collision":r.get("collision","walk"),"uuid":r.uuid},"ground_batch_record":r})
		node.queue_free()
	return host
static func bridges(tree:SceneTree,doc:RefCounted,check:Callable)->void:
	var host:=attach(tree,doc)
	await tree.physics_frame;await tree.physics_frame
	var space:=host.get_world_3d().direct_space_state
	for z in [-16.,16.]:
		var center:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,10,z),Vector3(0,-2,z)))
		check.call(not center.is_empty() and absf(center.position.y-.7)<.015,"bridge physical deck at actual camber/elevation")
		var body:=CharacterBody3D.new();var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.height=1.8;capsule.radius=.3;shape.shape=capsule;body.add_child(shape);host.add_child(body);body.floor_snap_length=.3
		for direction in [-1,1]:
			body.position=Vector3(-11*direction,1.02+(1 if direction==-1 else 0),z);body.velocity=Vector3.ZERO
			for i in 200:
				await tree.physics_frame;body.velocity=Vector3(12*direction,-3,0);body.move_and_slide()
				if body.position.x*direction>11:break
			check.call(body.position.x*direction>11 and body.position.y>.85,"capsule crosses bridge both directions including approach")
		body.queue_free()
	for x in [-8.666667,0.,8.666667]:
		var hole:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,3,85),Vector3(x,3,95)))
		var roof:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,6,90),Vector3(x,10,90)))
		check.call(hole.is_empty() and not roof.is_empty(),"water arch has empty passage and solid vault")
	host.get_meta("fixture_viewport").queue_free()
static func cave(tree:SceneTree,doc:RefCounted,check:Callable)->void:
	var host:=attach(tree,doc);await tree.physics_frame;await tree.physics_frame
	var space:=host.get_world_3d().direct_space_state
	var tunnel:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(23,4,0),Vector3(37,4,0)))
	var ceiling:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(30,4,0),Vector3(30,8,0)))
	var floor_:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(30,4,0),Vector3(30,0,0)))
	check.call(tunnel.is_empty() and not ceiling.is_empty() and not floor_.is_empty(),"actual tunnel collision retains clear passage floor and ceiling")
	host.get_meta("fixture_viewport").queue_free()
static func closed_grilles(tree:SceneTree,doc:RefCounted,check:Callable)->void:
	var host:=attach(tree,doc);await tree.physics_frame;await tree.physics_frame
	var body:=CharacterBody3D.new();var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.height=1.8;capsule.radius=.3;shape.shape=capsule;body.add_child(shape);host.add_child(body)
	await tree.physics_frame;await tree.physics_frame
	for x in [-8.666667,0.,8.666667]:check.call(body.test_move(Transform3D(Basis.IDENTITY,Vector3(x,2,84)),Vector3(0,0,12)),"closed iron grille physically blocks capsule")
	host.get_meta("fixture_viewport").queue_free()
