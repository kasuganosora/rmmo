extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Gear=preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(960,850);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	for row in range(2):
		for col in range(3):
			var view:=View.new();root.add_child(view);view.set_process(false);view.display.visible=false
			var parts:Dictionary=Gear.PARTS.duplicate()
			parts.Clothing1=2 if col==0 else 3;parts.Boots=2;parts.HeadAccessory=1 if col<2 else 0
			view.configure("female" if row==0 else "male",{"bust_size":.65},parts)
			view.play("idle","front_left",true)
			view.model.set_process(false);view.model.pose_at(.2)
			view.viewport.size=Vector2i(384,512);view.camera.size=2.5;view.camera.position=Vector3(0,1.8,5);view.camera.look_at(Vector3(0,1,0))
			var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*320,row*425+30);rect.size=Vector2(315,390);root.add_child(rect)
			var label:=Label.new();label.text=("女性 · " if row==0 else "男性 · ")+["粉白款 + 头饰","黑白款 + 头饰","卸下头饰"][col];label.position=Vector2(col*320+35,row*425+5);root.add_child(label)
	await create_timer(.3).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/character_3d/maid_black_headpiece.png")
	print("MAID_PREVIEW_OK");quit()
