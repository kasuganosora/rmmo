extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Gear=preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1024,640);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	var views:Array=[]
	for row in range(2):
		for col in range(4):
			var view:=View.new();root.add_child(view);view.set_process(false);view.display.visible=false
			view.configure("male" if row==0 else "female",{},Gear.PARTS)
			view.play(["walk","dash","cast","death"][col],"left" if col<2 else "front_left",true)
			view.model.set_process(false);views.append(view)
			view.camera.size=3.4 if col==3 else 2.6;view.camera.position=Vector3(0,2.3,5);view.camera.look_at(Vector3(0,.83,0))
			var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*256,row*320+32);rect.size=Vector2(256,280);root.add_child(rect)
			var label:=Label.new();label.text=("男性 · " if row==0 else "女性 · ")+["行走","冲刺","施法","死亡"][col];label.position=Vector2(col*256+65,row*320+8);root.add_child(label)
	DirAccess.make_dir_recursive_absolute("res://artifacts/character_3d/library_frames")
	for frame in range(80):
		for view in views:view.model.pose_at(frame/24.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/character_3d/library_frames/%03d.png"%frame)
	print("LIBRARY_PREVIEW_OK");quit()
