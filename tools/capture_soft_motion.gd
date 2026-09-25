extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Gear=preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1024,520);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	var views:Array=[]
	for col in range(4):
		var view:=View.new();root.add_child(view);view.set_process(false);view.display.visible=false
		view.configure("female",{"bust_size":.65},Gear.PARTS)
		view.play("walk" if col<2 else "dash","front_left",true)
		view.model.set_process(false);views.append(view)
		view.viewport.size=Vector2i(384,512)
		view.camera.size=2.2;view.camera.position=Vector3(0,1.6,5);view.camera.look_at(Vector3(0,1,0))
		var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*256,45);rect.size=Vector2(256,470);root.add_child(rect)
		var label:=Label.new();label.text=["行走 · 原效果","行走 · 柔性回弹","跑步 · 原效果","跑步 · 柔性回弹"][col];label.position=Vector2(col*256+35,12);root.add_child(label)
	DirAccess.make_dir_recursive_absolute("res://artifacts/character_3d/soft_frames")
	for frame in range(96):
		for i in range(4):
			var model=views[i].model
			if frame==64:model.play("idle","front_left",false)
			model._process(1.0/24)
			if i%2==0:
				for bone in model.imported_rig.soft_motion.indices:
					model.skeleton.set_bone_pose_position(bone,model.skeleton.get_bone_rest(bone).origin)
					model.skeleton.set_bone_pose_rotation(bone,model.skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/character_3d/soft_frames/%03d.png"%frame)
	print("SOFT_PREVIEW_OK");quit()
