extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Gear=preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1200,840);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	for row in range(2):
		for col in range(4):
			var view:=View.new();root.add_child(view);view.set_process(false);view.display.visible=false
			view.configure("female",{"part_ids":{"FrontHair1":12}},Gear.PARTS)
			for mesh in view.model.gear.Hair:
				if mesh.visible:mesh.material_override.set_shader_parameter("hair_color",Color("62545a"))
			view.play("idle",["front","front_left","left","back"][col],true)
			view.model.set_process(false);view.model.pose_at(.2)
			for frame in range(30):view.model._process(1.0/60)
			view.viewport.size=Vector2i(400,500);view.camera.size=.79 if row==0 else 1.30;view.camera.position=Vector3(0,1.7,5);view.camera.look_at(Vector3(0,1.69 if row==0 else 1.42,0))
			var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=Vector2(col*300,row*420+30);rect.size=Vector2(295,390);root.add_child(rect)
			var label:=Label.new();label.text=["正面 · 无头饰","左前 · 无头饰","侧面 · 无头饰","背面 · 无头饰"][col];label.position=Vector2(col*300+5,row*420+5);root.add_child(label)
	await create_timer(.3).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/hime_collision.png"))
	print("HAIR_PREVIEW_OK");quit()
