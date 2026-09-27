extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func screen_foot(view:Node)->Vector2:
	var model=view.model
	var point:Vector3=model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.bones.footR).origin
	return view.global_position+view.camera.unproject_position(point)*view.render_scale
func run()->void:
	var view:=View.new();view.render_scale=View.WORLD_RENDER_SCALE;root.add_child(view);view.set_process(false)
	view.configure("female",{},{});view.model.set_process(false);view.play("dash","right",true)
	view.model._from_rotations.clear();view._sync_locomotion(.016)
	for step in [[8.0,.04],[8.0,.02]]:
		view.model.elapsed=view.model.action_duration()*.08;view.model.pose_at(view.model.elapsed)
		var before:=screen_foot(view)
		view.position.x+=step[0];view._sync_locomotion(step[1]);view.model._process(step[1])
		var slip:float=absf(screen_foot(view).x-before.x)
		print("support slip ",slip," px at ",step[0]/step[1]," px/s")
		assert(slip<1.0,"Support foot slides against the map")
	var phase:float=view.model.elapsed
	view._sync_locomotion(.03);view.model._process(.03)
	assert(is_equal_approx(view.model.elapsed,phase),"Blocked character runs in place")
	view.position.x+=200;view._sync_locomotion(.03);view.model._process(.03)
	assert(is_equal_approx(view.model.elapsed,phase),"Teleport advances gait")
	print("PASS distance driven run: support foot at two speeds, stopped actor, teleport")
	view.free();quit()
