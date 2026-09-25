extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var moving:bool="--moving" in OS.get_cmdline_user_args()
	root.size=Vector2i(1280,680);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	for row in range(2):
		for col in range(4):
			var view:=View.new();root.add_child(view);view.set_process(false);view.display.visible=false
			view.configure("female" if row==0 else "male",{}, {"Clothing1":2,"Boots":2 if col<3 else null})
			view.play("idle",["front","left","back","front_left"][col],true)
			view.model.set_process(false);view.model.pose_at(0)
			if moving and col<3:
				view.play("walk" if col==0 else "dash","front_left" if col==0 else "left",true)
				view.model.pose_at([.3,.2,.45][col])
			view.viewport.size=Vector2i(384,384);view.camera.size=.76
			view.camera.position=Vector3(0,.7,3);view.camera.look_at(Vector3(0,.14,0))
			if moving:view.camera.size=1.25;view.camera.look_at(Vector3(0,.32,0))
			var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*320,row*340+30);rect.size=Vector2(315,305);root.add_child(rect)
			var label:=Label.new();label.text=("女性 · " if row==0 else "男性 · ")+["鞋袜正面","侧面","背面","卸下鞋袜"][col];label.position=Vector2(col*320+65,row*340+5);root.add_child(label)
			if moving:label.text=("女性 · " if row==0 else "男性 · ")+["行走","跑步抬脚","跑步落脚","卸下鞋袜"][col]
	await create_timer(.3).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/character_3d/maid_footwear_moving.png" if moving else "res://artifacts/character_3d/maid_footwear_fixed.png")
	print("MAID_FOOTWEAR_PREVIEW_OK");quit()
