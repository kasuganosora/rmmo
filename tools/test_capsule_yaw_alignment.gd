extends SceneTree
const Clearance=preload("res://scripts/world3d/player_clearance.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func actor(layer:int)->CharacterBody3D:
	var body:=CharacterBody3D.new();body.collision_layer=layer;body.collision_mask=0
	var shape:=CollisionShape3D.new();shape.name="CollisionShape3D"
	var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.9
	shape.shape=capsule;shape.position.y=.05;body.add_child(shape)
	var visual:=Node3D.new();visual.name="Visual";visual.position=Vector3(.1,.2,.3);body.add_child(visual)
	root.add_child(body);body.position=Vector3(3,.9,-2)
	return body
func run()->void:
	var legacy:=actor(1);var aligned:=actor(2);var rays:=0;var mismatches:=0
	var collider:CollisionShape3D=aligned.get_node("CollisionShape3D")
	for turn in 24:
		var yaw:float=-PI+turn*TAU/24
		legacy.rotation.y=yaw;aligned.rotation.y=yaw
		var visual:Transform3D=aligned.get_node("Visual").global_transform
		var body_pose:=aligned.global_transform;var offset:=collider.position
		var saved:Variant=Clearance.begin_capsule_motion(aligned)
		if collider.position!=offset:failures+=1
		if not (aligned.global_basis*collider.basis).is_equal_approx(Basis.IDENTITY):failures+=1
		await physics_frame;await physics_frame
		var space:=root.world_3d.direct_space_state
		for y:float in [-.9,-.75,0.,.75,.9]:
			for angle in 12:
				var direction:=Vector3(cos(angle*TAU/12),0,sin(angle*TAU/12))
				var center:=aligned.position+Vector3(0,.05+y,0)
				var a:=space.intersect_ray(PhysicsRayQueryParameters3D.create(center+direction,center,1))
				var b:=space.intersect_ray(PhysicsRayQueryParameters3D.create(center+direction,center,2))
				rays+=1
				if a.is_empty() or b.is_empty() or a.position.distance_to(b.position)>.0005 or a.normal.distance_to(b.normal)>.001:mismatches+=1
		Clearance.end_capsule_motion(aligned,saved)
		if aligned.global_transform!=body_pose or aligned.get_node("Visual").global_transform!=visual:failures+=1
	check(mismatches==0,"1440 capsule surface rays preserve positions/normals across actor yaw: "+str(mismatches))
	check(failures==0,"visual facing, body transform, capsule offset and world axes preserved")
	for variant in ["tilted_body","scaled_body","tilted_shape","offset_shape","compound_shape","box"]:
		aligned.transform=Transform3D.IDENTITY;collider.transform=Transform3D.IDENTITY
		match variant:
			"tilted_body":aligned.rotation.x=.3
			"scaled_body":aligned.scale=Vector3(2,1,1)
			"tilted_shape":collider.rotation.z=.2
			"offset_shape":collider.position.x=.1
			"compound_shape":aligned.shape_owner_add_shape(aligned.get_shape_owners()[0],SphereShape3D.new())
			"box":collider.shape=BoxShape3D.new()
		var before:=collider.transform;var before_body:=aligned.global_transform
		var saved:Variant=Clearance.begin_capsule_motion(aligned)
		check(saved==null and collider.transform==before and aligned.global_transform==before_body,"leave non-equivalent shape unchanged: "+variant)
		if variant=="compound_shape":aligned.shape_owner_remove_shape(aligned.get_shape_owners()[0],1)
	legacy.free();aligned.free()
	print("CAPSULE_YAW_ALIGNMENT failures=",failures," rays=",rays);quit(1 if failures else 0)
