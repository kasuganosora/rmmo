extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func snapshot(model:Node3D)->Array[Quaternion]:
	var result:Array[Quaternion]=[]
	for i in range(model.skeleton.get_bone_count()):result.append(model.skeleton.get_bone_pose_rotation(i))
	return result
func run()->void:
	var model:=Model.new();root.add_child(model);model.set_process(false)
	for gender in ["male","female"]:
		model.configure(gender,{}, {})
		for action in ["walk","dash"]:
			model.play(action,"front",true)
			# Selected clips may override the action (female jog plays at 1.25x).
			var duration:float=model.action_duration()
			assert(model.imported_rig.animations.clips.has(action),"Real library clip must be loaded")
			var low:=INF;var high:=-INF
			for i in range(60):
				model.pose_at(i/60.0*duration)
				for side in ["L","R"]:
					var foot:Vector3=(model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.bones["foot"+side])).origin
					low=minf(low,foot.y);high=maxf(high,foot.y)
				for bone in range(model.skeleton.get_bone_count()):
					assert(model.skeleton.get_bone_pose_rotation(bone).is_finite())
			assert(low>-.04,"Ankles must not penetrate the ground")
			assert(high-low>.08,"Gait must contain an actual foot lift")
			print(gender," ",action," ankle height range ",low," .. ",high)
			model.pose_at(0);var start:=snapshot(model)
			model.pose_at(duration)
			for i in range(start.size()):assert(start[i].angle_to(model.skeleton.get_bone_pose_rotation(i))<.002,"Gait must loop without a joint snap")
		model.play("death","front",true);model.pose_at(Model.Motion.DURATION.death);var dead:=snapshot(model);var at_rest:Transform3D=model.rig.transform
		model.pose_at(5)
		assert(model.rig.transform.is_equal_approx(at_rest),"Death must settle and hold")
		for i in range(dead.size()):assert(dead[i].angle_to(model.skeleton.get_bone_pose_rotation(i))<.002)
		model.play("walk","front",true);model.pose_at(.2);var before:=snapshot(model)
		model.play("cast","front",false)
		for i in range(before.size()):assert(before[i].angle_to(model.skeleton.get_bone_pose_rotation(i))<.002,"Transition starts at displayed pose")
		for i in range(20):model._process(.016)
		assert(model._from_rotations.is_empty(),"Transition must finish, not keep restarting")
		print("PASS ",gender," library foot clearance, seamless gait, death hold and interrupted-action blend")
	var frames:=View.control_frames()
	assert(is_equal_approx(frames.get_frame_count("cast_front")/frames.get_animation_speed("cast_front"),Model.Motion.DURATION.cast),"Gameplay timer must allow the entire cast")
	var view:=View.new();root.add_child(view);view.set_process(false);view.model.set_process(false)
	view.configure("male",{},{})
	var density:float=view.viewport.size.y/view.camera.size
	for direction in Model.YAW:
		view.play("death",direction,true);view.model.pose_at(2.4)
		assert(is_equal_approx(view.viewport.size.y/view.camera.size,density),"Death framing must preserve character scale")
		assert((view.camera.unproject_position(Vector3.ZERO)*view.render_scale+view.display.position).length()<.001,"Map anchor must not move")
		for bone in range(view.model.skeleton.get_bone_count()):
			var point:Vector3=(view.model.skeleton.global_transform*view.model.skeleton.get_bone_global_pose(bone)).origin
			assert(Rect2(Vector2.ZERO,Vector2(view.viewport.size)).has_point(view.camera.unproject_position(point)),"Death skeleton must fit all eight directions")
	view.play("walk","front",true)
	assert(view.viewport.size==Vector2i(256,256),"Restore normal render cost after death")
	print("PASS death framing, scale and map anchor in all eight directions")
	quit()
