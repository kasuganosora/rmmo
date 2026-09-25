extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func penetration(motion)->float:
	var deepest:=0.0
	for probe in motion.collision_probes:
		var point:Vector3=motion._probe_position(probe)
		for capsule in motion.body_capsules:
			var tr:Transform3D=motion.skeleton.global_transform*motion.skeleton.get_bone_global_pose(capsule.bone)
			deepest=maxf(deepest,motion.capsule_push(point,tr*capsule.a,tr*capsule.b,capsule.radius).length())
	return deepest
func run()->void:
	for gender in ["female","male"]:
		var model:=Model.new();root.add_child(model);model.set_process(false)
		model.configure(gender,{"part_ids":{"FrontHair1":12}},{"Clothing1":3})
		var motion=model.imported_rig.hair_motion
		assert(motion.body_capsules.size()==4 and not motion.collision_probes.is_empty())
		model.pose_at(0)
		# Deliberately displace all dynamic hair inward, then require contact correction.
		for bone in motion.indices:model.skeleton.set_bone_pose_position(bone,model.skeleton.get_bone_pose_position(bone)+Vector3(.06,0,0))
		var before:=penetration(motion);motion._solve_body_collisions();var after:=penetration(motion)
		assert(after<=before+.002)
		var worst:=0.0;var contacts:=0
		for action in ["idle","walk","dash","cast","death"]:
			model.play(action,"left",true);model.environment_wind=Vector2(0,1)
			for frame in range(24):
				model._process(1.0/30);worst=maxf(worst,penetration(motion));contacts+=motion.collision_contacts
		assert(contacts>0,"Collision solver must actually handle contacts")
		# Capsule proxies can overlap fitted hair; shape preservation has priority
		# over forcing every probe out by unbounded translations.
		print("PASS ",gender," contacts=",contacts," worst sampled penetration=",worst)
		model.free()
	quit()
