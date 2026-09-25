extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	for gender in ["female","male"]:
		for choice in [10,11,12,13,14,15]:
			var model:=Model.new();root.add_child(model);model.set_process(false)
			model.configure(gender,{"part_ids":{"FrontHair1":choice}},{"Clothing1":1})
			var motion=model.imported_rig.hair_motion
			# Short male hair naturally clears the body: inflate the test-only head
			# proxy to exercise a genuine contact and the same displacement budget.
			if choice==11:motion.body_capsules[-1].radius=.30
			var contacts:=0
			for action in ["idle","walk","dash","cast","death","idle"]:
				model.play(action,"front_left",true);model.environment_wind=Vector2(1,1).normalized()
				for frame in range(45):
					model._process(1.0/30);contacts+=motion.collision_contacts
					for bone in motion.indices:
						var parent:=model.skeleton.get_bone_parent(bone)
						var basis:Basis=(model.skeleton.global_transform*model.skeleton.get_bone_global_pose(parent)).basis
						var offset:Vector3=basis*(model.skeleton.get_bone_pose_position(bone)-model.skeleton.get_bone_rest(bone).origin)
						assert(offset.is_finite() and offset.length()<=motion.max_collision_offset+.00001,"Collision must not stretch hair across frames or action blends")
			assert(contacts>0,"Exercise active collisions, not an inert solver")
			print("PASS ",gender," hairstyle ",choice," bounded contacts across six actions")
			model.free()
	quit()
