extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1200,780);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	var cases:Array=[["idle","front",0.4,""],["idle","left",.4,""],["dash","front_left",.18,""],["dash","front_left",.48,""],["attack","front_left",.25,"attack_jab"],["attack","front_left",.5,"attack_sword_a"]]
	for row in range(2):
		for col in range(6):
			var view:=View.new();root.add_child(view);view.set_process(false);view.display.visible=false
			var gear:Dictionary=preload("res://scripts/char/starter_equipment.gd").PARTS.duplicate();gear.WeaponMain=1 if col==5 else null
			view.configure("female" if row==0 else "male",{"part_ids":{"FrontHair1":15 if row==0 else 11},"hair_on":true,"hair_row":1012},gear)
			view.play(cases[col][0],cases[col][1],true,cases[col][3]);view.model.set_process(false);view.model.pose_at(cases[col][2])
			view.viewport.size=Vector2i(320,600);view.camera.size=2.15;view.camera.position=Vector3(0,.98,5);view.camera.look_at(Vector3(0,.98,0))
			var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*200,row*390+20);rect.size=Vector2(198,365);root.add_child(rect)
			var label:=Label.new();label.text=["站立正面","站立侧面","跑步 A","跑步 B","空手刺拳","剑击 A"][col];label.position=Vector2(col*200+30,row*390);root.add_child(label)
	await create_timer(.4).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/character_3d/combat_motion_preview.png")
	print("PREVIEW_OK");quit()
