extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Fit=preload("res://scripts/char/character_equipment_fit.gd")
func _initialize()->void:call_deferred("run")
func palm(model:Node3D)->Vector3:
	var hand:Transform3D=model.rig.global_transform.affine_inverse()*model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.bones.handL)
	return (hand*model.gear.WeaponMain[0].transform).origin
func run()->void:
	for gender in ["female","male"]:
		var model=Model.create(gender,{}, {"WeaponMain":1});root.add_child(model);model.set_process(false)
		var sk:Skeleton3D=model.skeleton
		var finger:int=sk.find_bone("mixamorig_RightHandIndex2")
		model.set_equipment({})
		model.play("idle","front",true);model.pose_at(0)
		var unarmed:Array[Quaternion]=[]
		for i in sk.get_bone_count():unarmed.append(sk.get_bone_pose_rotation(i))
		model.set_equipment({"WeaponMain":1})
		model.play("idle","front",true);model.pose_at(0)
		var grip:Quaternion=sk.get_bone_pose_rotation(finger)
		var hand_to_weapon:Transform3D=model.gear.WeaponMain[0].transform
		assert(hand_to_weapon.basis.determinant()>0,"Weapon socket must not mirror its mesh")
		model.set_equipment({"WeaponMain":null});model.pose_at(0)
		for i in sk.get_bone_count():
			if "RightHand" in sk.get_bone_name(i):assert(sk.get_bone_pose_rotation(i).angle_to(unarmed[i])<.001,"Removing the weapon must restore animation fingers")
		model.set_equipment({"WeaponMain":1})
		# Synthetic garments deliberately have no maid name, item ID or skin.
		var previous:float=0
		for width in [.24,.34,.44]:
			var garment:=MeshInstance3D.new();var mesh:=CylinderMesh.new()
			mesh.top_radius=width;mesh.bottom_radius=width;mesh.height=.65;mesh.rings=24
			garment.mesh=mesh;model.rig.add_child(garment);garment.position.y=1.25;model.gear.Clothing1.append(garment)
			model.pose_at(0)
			var x:float=absf(palm(model).x)
			assert(x>width+.025,"The actual hand must clear a garment of arbitrary width")
			assert(x>previous,"Wider garments must move the hand farther out")
			previous=x
			for pair in [["armL","forearmL"],["forearmL","handL"]]:
				var a:int=model.bones[pair[0]];var b:int=model.bones[pair[1]]
				assert(is_equal_approx(sk.get_bone_global_rest(a).origin.distance_to(sk.get_bone_global_rest(b).origin),sk.get_bone_global_pose(a).origin.distance_to(sk.get_bone_global_pose(b).origin)),"Clearance must rotate, never stretch the arm")
			model.gear.Clothing1.erase(garment);garment.free()
		# Both empty hands must clear unrelated garments too. This catches
		# the old weapon-only early return and the unhandled off hand.
		model.set_equipment({})
		for width in [.24,.34,.44]:
			var garment:=MeshInstance3D.new();var cylinder:=CylinderMesh.new()
			cylinder.top_radius=width;cylinder.bottom_radius=width;cylinder.height=.8
			garment.mesh=cylinder;model.rig.add_child(garment);garment.position.y=1.25;model.gear.Clothing1.append(garment)
			for action in ["idle","walk","dash"]:
				model.play(action,"front",true)
				for phase in [0.0,.2,.5]:
					model.pose_at(phase)
					var relative:Transform3D=model.rig.global_transform.affine_inverse()*sk.global_transform
					for side in ["L","R"]:
						var name:String=sk.get_bone_name(model.bones["hand"+side])
						for bone in sk.get_bone_count():
							if sk.get_bone_name(bone).begins_with(name):
								var point:Vector3=(relative*sk.get_bone_global_pose(bone)).origin
								if point.y>.85 and point.y<1.65:assert(Vector2(point.x,point.z).length()>width,"Empty hand/fingers must clear the actual cylinder surface: %s %s %s %s"%[gender,action,side,point])
			model.gear.Clothing1.erase(garment);garment.free()
		# A wide rear bow is disjoint from the hands and must not spread arms.
		model.set_equipment({});model.play("idle","front",true);model.pose_at(0)
		var before:Vector3=sk.get_bone_global_pose(model.bones.handL).origin
		var rear:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(1.5,.5,.1)
		rear.mesh=box;rear.position=Vector3(0,1.2,-.65);model.rig.add_child(rear);model.gear.Clothing1.append(rear)
		model.pose_at(0)
		assert(before.distance_to(sk.get_bone_global_pose(model.bones.handL).origin)<.0001,"Rear decorations cannot push a disjoint hand outward")
		model.gear.Clothing1.erase(rear);rear.free()
		model.set_equipment({"Clothing1":2});model.pose_at(0)
		var relative:Transform3D=model.rig.global_transform.affine_inverse()*sk.global_transform
		for side in ["L","R"]:
			var shoulder:Vector3=(relative*sk.get_bone_global_pose(model.bones["arm"+side])).origin
			var elbow:Vector3=(relative*sk.get_bone_global_pose(model.bones["forearm"+side])).origin
			assert(absf(elbow.x-shoulder.x)<shoulder.distance_to(elbow)*.32,"Idle upper arms remain near the torso")
			var foot:Vector3=(relative*sk.get_bone_global_pose(model.bones["foot"+side])).origin
			assert(absf(foot.y-model.imported_rig.rest_positions["foot"+side].y)<.003,"Relaxed idle feet stay on the floor")
		model.set_equipment({"WeaponMain":1})
		for action in ["idle","walk","dash","attack","cast","sit_chair"]:
			model.play(action,"front",true)
			for phase in [0.0,.2,.5,.8]:
				model.pose_at(phase)
				assert(sk.get_bone_pose_rotation(finger).angle_to(grip)<.001,"Grip must survive all animation tracks")
				assert(model.gear.WeaponMain[0].transform.is_equal_approx(hand_to_weapon),"The weapon must not drift from its hand socket")
		model.set_equipment({"Clothing1":2,"WeaponMain":1});model.play("walk","front",true)
		for i in 15:model._process(1.0/60)
		assert(sk.get_bone_pose_rotation(finger).angle_to(grip)<.001,"Animation blending must not reopen the hand")
		model.set_equipment({"Clothing1":2,"Boots":2})
		for action in ["dash","sit_chair","sit_ground","death"]:
			model.play(action,"front",true);model.pose_at(1.5)
			for base in model.gear.BaseBottom:assert(base.visible,"Active skirt must retain fitted coverage for every pose")
			for material in model.imported_rig.body_materials:assert(material.get_shader_parameter("wearing_dress"),"Skirt coverage must be driven by garment metadata")
			if action=="sit_chair":
				for side in ["L","R"]:
					var foot:Vector3=(sk.global_transform*sk.get_bone_global_pose(model.bones["foot"+side])).origin
					var standing:float=model.imported_rig.rest_positions["foot"+side].y*model.rig.scale.y
					assert(absf(foot.y-standing)<.003,"Sitting keeps feet at standing floor height")
		model.play("dash","front",true)
		for i in 120:model._process(1.0/60)
		var cloth=model.imported_rig.garment_motion
		assert(cloth.sway.is_finite() and cloth.sway.length()<=cloth.leg_radius*.31,"Hem motion must remain bounded")
		print("PASS ",gender," adaptive garment widths, unchanged limb lengths, grip/unequip/animation transitions")
		model.free()
	quit()
