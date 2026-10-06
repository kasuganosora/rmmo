extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(900,800);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	var views:Array=[]
	var baseline:String=preload("res://scripts/util/json_util.gd").content_root()+"/review_backups/run/female_combat.res"
	var old:AnimationLibrary=load(baseline) if FileAccess.file_exists(baseline) else null
	if old==null:
		root.size.y=400;root.content_scale_size=root.size;bg.size=Vector2(root.size)
	for row in range(2 if old!=null else 1):
		for col in range(3):
			var view:=View.new();root.add_child(view);view.set_process(false);view.display.visible=false
			view.configure("female",{"part_ids":{"FrontHair1":15}},preload("res://scripts/char/starter_equipment.gd").PARTS.duplicate())
			if old!=null and row==0:view.model.imported_rig.animations.clips["dash_female"]=old.get_animation("dash_female")
			view.play("dash",["front","left","back"][col],true);view.model.set_process(false)
			view.viewport.size=Vector2i(300,370);view.camera.size=1.95;view.camera.position=Vector3(0,.86,5);view.camera.look_at(Vector3(0,.86,0))
			var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*300,row*400+28);rect.size=Vector2(300,370);root.add_child(rect)
			var label:=Label.new();label.text=("修改前" if old!=null and row==0 else "当前")+" · "+["正面","侧面","背面"][col];label.position=Vector2(col*300+100,row*400+4);root.add_child(label)
			var line:=ColorRect.new();line.color=Color("748894");line.position=Vector2(col*300+30,row*400+376);line.size=Vector2(240,1);root.add_child(line)
			views.append(view)
	DirAccess.make_dir_recursive_absolute(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/run_frames"))
	await create_timer(.3).timeout
	for frame in range(48):
		for view in views:view.model.pose_at(view.model.action_duration()*frame/48.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/run_frames/%03d.png")%frame)
	print("RUN_CAPTURE_OK");quit()
