extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Library=preload("res://scripts/char/character_animation_library.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	for gender in ["female","male"]:
		var model:=Model.new();root.add_child(model);model.set_process(false);model.configure(gender,{}, {})
		var library=model.imported_rig.animations
		for armed in [false,true]:
			model.set_equipment({"WeaponMain":1 if armed else null})
			var seen:Dictionary={}
			for i in range(3):
				model.play("attack","front",true)
				seen[model.animation_clip]=true
				assert(model.animation_clip.begins_with("attack_sword")==armed)
			assert(seen.size()==3)
		for key in Library.ATTACKS.keys()+Library.CASTS.keys():
			assert(library.clips.has(key))
			model.play("attack" if key in Library.ATTACKS else "cast","front_left",true,key)
			assert(model.animation_clip==key and model.action_duration()==library.clips[key].length)
			for phase in [.0,.25,.5,.75,1.0]:
				model.pose_at(model.action_duration()*phase)
				for bone in range(model.skeleton.get_bone_count()):assert(model.skeleton.get_bone_global_pose(bone).is_finite())
		model.play("idle","front",true);model.pose_at(.3)
		for side in ["L","R"]:
			var relative:Transform3D=model.rig.global_transform.affine_inverse()*model.skeleton.global_transform
			var a:Vector3=(relative*model.skeleton.get_bone_global_pose(model.bones["arm"+side])).origin
			var b:Vector3=(relative*model.skeleton.get_bone_global_pose(model.bones["forearm"+side])).origin
			assert((b-a).normalized().dot(Vector3.DOWN)>.95,"Idle arms must hang down")
		model.play("dash","front",true)
		assert(model.animation_clip==("dash_female" if gender=="female" else "dash"))
		model.free()
	var creator=load("res://scenes/character_create.tscn").instantiate();root.add_child(creator)
	await process_frame;await process_frame
	var selector:OptionButton=creator.find_child("ActionPreview",true,false)
	assert(selector.item_count==20)
	selector.item_selected.emit(11)
	await process_frame;await process_frame
	assert(creator._view_3d.model.animation_clip=="attack_sword_a" and creator._view_3d.model.equipment.WeaponMain==1)
	selector.item_selected.emit(8)
	await process_frame;await process_frame
	assert(creator._view_3d.model.animation_clip=="attack_jab" and creator._view_3d.model.equipment.WeaponMain==null)
	print("PASS 12 combat variants, armed/unarmed rotation, durations, finite poses, relaxed arms, female run, creator previews")
	quit()
