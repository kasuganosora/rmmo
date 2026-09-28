extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var model:=Model.new();model.body_type="female"
	model.appearance={"body_model":"female_base_v2","part_ids":{"FrontHair1":201}}
	root.add_child(model);model.set_process(false)
	var hair:Node3D=model.axis_rig.hair
	assert(hair.spring.simulators.size()==2)
	var source_bones:=0
	for skeleton:Skeleton3D in hair.source.find_children("*","Skeleton3D",true,false):
		for i in skeleton.get_bone_count():
			assert(skeleton.get_bone_rest(i).basis.get_scale().is_equal_approx(Vector3.ONE))
			source_bones+=1
	var max_response:=0.0
	var peak_enabled:=0.0
	var final_response:=0.0
	var max_length_error:=0.0
	for enabled in [false,true]:
		hair.spring.set_enabled(enabled)
		for frame in 140:
			var angle:=35.0*sin(clampf((frame-20)/40.0,0,1)*TAU) if frame<60 else 0.0
			model.axis_rig.body.set_angles({"head":Vector3(0,angle,0)})
			await process_frame
			var response:=0.0
			for simulator:SpringBoneSimulator3D in hair.spring.simulators:
				var skeleton:Skeleton3D=simulator.get_parent()
				if not hair.spring.snapshots.has(skeleton.get_instance_id()):continue
				var poses:Array=hair.spring.snapshots[skeleton.get_instance_id()]
				for i in skeleton.get_bone_count():
					assert(poses[i].origin.is_finite())
					response=maxf(response,(poses[i].origin-skeleton.get_bone_global_rest(i).origin).length())
					var parent:=skeleton.get_bone_parent(i)
					if parent>=0:
						var rest_length:float=skeleton.get_bone_rest(i).origin.length()
						max_length_error=maxf(max_length_error,absf(poses[i].origin.distance_to(poses[parent].origin)-rest_length))
			if enabled:peak_enabled=maxf(peak_enabled,response);final_response=response
			else:max_response=maxf(max_response,response)
	print("DIAGNOSTIC peak_m=",peak_enabled," final_m=",final_response," disabled_m=",max_response," length_error_m=",max_length_error)
	assert(max_response<.00001,"Disabled negative control moved")
	assert(peak_enabled>.001,"Enabled native modifier produced no inertia")
	# A fixed 25 cm displacement limit is invalid for a long chain: rotation
	# can move its tip further without stretching. Check the actual invariant.
	assert(max_length_error<.00001,"Native spring stretched the source bone chain")
	assert(final_response<peak_enabled*.25,"Native spring did not settle")
	print("PASS native spring negative control / turn / settle: bones=",source_bones," peak_m=",peak_enabled," final_m=",final_response," disabled_m=",max_response)
	model.free()
	for frame in 3:await process_frame
	quit()
