extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(900,430);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	var views:Array=[]
	for col in range(3):
		var view:=View.new();root.add_child(view);view.set_process(false);view.display.visible=false
		view.configure("female",{"part_ids":{"FrontHair1":[13,14,15][col]}},{"Clothing1":3,"Boots":2,"HeadAccessory":1})
		view.play("idle","back_left",true);view.model.set_process(false)
		view.viewport.size=Vector2i(300,400);view.camera.size=1.25;view.camera.position=Vector3(0,1.7,5);view.camera.look_at(Vector3(0,1.5,0))
		var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*300,30);rect.size=Vector2(295,400);root.add_child(rect);views.append(view)
	var label:=Label.new();label.position=Vector2(25,4);root.add_child(label)
	DirAccess.make_dir_recursive_absolute(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/wind_frames"))
	for frame in range(100):
		label.text="站立 · 风吹向右 →" if frame<40 else ("站立 · 风吹向左 ←" if frame<75 else "停风 · 回落")
		for view in views:
			view.model.environment_wind=Vector2.RIGHT if frame<40 else (Vector2.LEFT if frame<75 else Vector2.ZERO)
			for step in range(4):view.model._process(1.0/60)
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/wind_frames/%03d.png")%frame)
	print("HAIR_WIND_CAPTURE_OK");quit()
