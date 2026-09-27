extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var studio=load("res://scenes/character_skin_studio.tscn").instantiate();root.add_child(studio)
	await process_frame
	assert(root.msaa_3d==Viewport.MSAA_8X)
	var buttons=studio.find_children("*","Button",true,false)
	assert(buttons.size()>=10)
	assert(studio.regional_preview!=null and studio.regional_preview.visible and not studio.model.visible)
	assert(studio.regional_preview.skeleton.get_bone_count()==80)
	assert(studio.outfit_buttons.all(func(b):return b.disabled))
	buttons.filter(func(b):return b.text=="旧男性对照")[0].pressed.emit();assert(studio.model.body_type=="male")
	assert(studio.model.visible and not studio.regional_preview.visible)
	assert(studio.outfit_buttons.all(func(b):return not b.disabled))
	buttons.filter(func(b):return b.text=="旧女性对照")[0].pressed.emit();assert(studio.model.body_type=="female")
	buttons.filter(func(b):return b.text=="裙装")[0].pressed.emit();assert(studio.model.equipment.HeadAccessory==1)
	buttons.filter(func(b):return b.text=="基础层")[0].pressed.emit();assert(studio.model.equipment.is_empty())
	buttons.filter(func(b):return b.text=="转身 45°")[0].pressed.emit();assert(is_equal_approx(studio.model.rotation.y,PI/4))
	buttons.filter(func(b):return b.text=="转灯 45°")[0].pressed.emit();assert(is_equal_approx(studio.lighting.rotation.y,PI/4))
	buttons.filter(func(b):return b.text=="棚拍 / 游戏")[0].pressed.emit();assert(not studio.studio_mode and not studio.fill.visible)
	buttons.filter(func(b):return b.text=="全身 / 近景")[0].pressed.emit();assert(is_equal_approx(studio.camera.size,2.3))
	buttons.filter(func(b):return b.text=="新素体 · 瓷白")[0].pressed.emit()
	assert(is_equal_approx(studio.regional_preview.rotation.y,PI/4))
	studio.pose_selector.select(4);studio.apply_body_pose()
	assert(studio.regional_preview.pose_name=="sit" and studio.chair!=null)
	var maximum_scene_depth:=0.0
	for part:Node3D in studio.chair.get_children():
		if not part is MeshInstance3D or not part.mesh is BoxMesh:continue
		var transform:Transform3D=part.global_transform.affine_inverse()*studio.regional_preview.global_transform
		for point:Vector3 in studio.regional_preview.posed_points:
			var clearance:Vector3=part.mesh.size*.5-(transform*(point+studio.regional_preview.root_offset)).abs()
			maximum_scene_depth=maxf(maximum_scene_depth,minf(clearance.x,minf(clearance.y,clearance.z)))
	assert(maximum_scene_depth<=.003,"White chair must not begin inside the sitting body")
	studio.pose_amount.value=.5
	assert(studio.chair==null)
	studio.pose_selector.select(5);studio.apply_body_pose()
	assert(studio.regional_preview.pose_name=="lie")
	studio.pose_play.button_pressed=true;studio._process(.2)
	assert(studio.pose_amount.value>=0 and studio.pose_amount.value<=1)
	studio.configure_body("male");assert(not studio.body_pose_controls.visible and not studio.floor_mesh.visible)
	studio.free();print("PASS interactive studio controls and shared actor recipe");quit()
