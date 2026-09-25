extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Gear=preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1200,900);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	var colors:=["#247de8","#8755c9","#ae6534"]
	for col in range(3):
		for row in range(2):
			var view:=View.new();view.portrait_mode=row==0;root.add_child(view);view.display.visible=false;view.viewport.size=Vector2i(480,480)
			view.configure("female",{"eye_color":colors[col],"bust_size":col*.5},Gear.PARTS)
			view.play("idle","front" if row==0 else "front_left");view.model.set_process(false);view.model.pose_at(0)
			var y:float=1.69 if row==0 else 1.32
			view.camera.size=.44 if row==0 else .86;view.camera.position=Vector3(0,y,5);view.camera.look_at(Vector3(0,y,0))
			var origin:=Vector2(col*400,row*450)
			var label:=Label.new();label.text=(["蓝色瞳孔","紫色瞳孔","棕色瞳孔"][col] if row==0 else "胸部大小 "+str(col*50));label.position=origin+Vector2(20,12);root.add_child(label)
			var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=origin+Vector2(10,42);rect.size=Vector2(380,380);root.add_child(rect)
	await create_timer(.4).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/character_3d/customization_options.png")
	print("CUSTOMIZATION_CAPTURE_OK");quit()
