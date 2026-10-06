extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Gear=preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1600,1200);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	var actions:=["walk","dash","cast","death"]
	var samples:=[[0,.267,.533,.8,1.067],[0,.133,.267,.4,.533],[0,.3,.65,1.0,1.4667],[0,.4,.8,1.5,2.4]]
	for row in range(4):
		for col in range(5):
			var view:=View.new();root.add_child(view);view.display.visible=false;view.viewport.size=Vector2i(384,384)
			view.configure("male",{},Gear.PARTS);view.play(actions[row],"left" if row<2 else "front_left",true)
			view.model.set_process(false);view.model.pose_at(samples[row][col])
			view.camera.size=2.25;view.camera.position=Vector3(0,1.6,5);view.camera.look_at(Vector3(0,.88,0))
			var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*320,row*300+25);rect.size=Vector2(275,275);root.add_child(rect)
			var label:=Label.new();label.text=["走动","跑步","施法","死亡"][row]+"  "+str(samples[row][col])+"s";label.position=Vector2(col*320+12,row*300);root.add_child(label)
	await create_timer(.4).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/motion_phases.png"))
	print("MOTION_PHASES_OK");quit()
