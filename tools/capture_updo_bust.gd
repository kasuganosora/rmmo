extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1000,500);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	for col in range(4):
		var view:=View.new();root.add_child(view);view.set_process(false);view.display.visible=false
		view.configure("female",{"part_ids":{"FrontHair1":1},"hair_on":true,"hair_row":1012,"bust_size":.5},preload("res://scripts/char/starter_equipment.gd").PARTS)
		view.configure("female",{"part_ids":{"FrontHair1":1},"hair_on":true,"hair_row":[1206,1132,1158,1012][col],"bust_size":col/3.0},preload("res://scripts/char/starter_equipment.gd").PARTS)
		view.play("idle","front_left",true);view.model.set_process(false);view.model.pose_at(.2)
		view.viewport.size=Vector2i(350,600);view.camera.size=1.25;view.camera.position=Vector3(0,1.5,5);view.camera.look_at(Vector3(0,1.5,0))
		var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*250,20);rect.size=Vector2(245,450);root.add_child(rect)
	await create_timer(.4).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/character_3d/updo_bust_fixed.png")
	print("PREVIEW_OK");quit()
