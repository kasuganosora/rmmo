extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Gear=preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1440,840);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	for row in range(3):
		for col in range(6):
			var view:=View.new();root.add_child(view);view.set_process(false);view.display.visible=false
			view.configure("male" if row==2 else "female",{"part_ids":{"FrontHair1":10+col}},Gear.PARTS)
			view.play("idle","back_left" if row==1 else "front",true)
			view.model.set_process(false);view.model.pose_at(.2)
			view.viewport.size=Vector2i(256,300);view.camera.size=1.05;view.camera.position=Vector3(0,1.7,5);view.camera.look_at(Vector3(0,1.5,0))
			var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*240,row*280+25);rect.size=Vector2(235,255);root.add_child(rect)
			var label:=Label.new();label.text=preload("res://scripts/char/character_hair_3d.gd").OPTIONS[10+col];label.position=Vector2(col*240+5,row*280+5);root.add_child(label)
	await create_timer(.3).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/hairstyles.png"))
	print("HAIR_PREVIEW_OK");quit()
