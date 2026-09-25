extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Gear=preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,850)
	var bg:=ColorRect.new();bg.color=Color("222937");bg.size=Vector2(1280,850);root.add_child(bg)
	var types:=["male","female","young_male","young_female"]
	var names:=["成年男性","成年女性","青年男性","青年女性"]
	for t in range(4):
		var label:=Label.new();label.text=names[t];label.position=Vector2(t*320+120,14);root.add_child(label)
		for row in range(3):
			var view:=View.new();view.portrait_mode=row==0;root.add_child(view);view.display.visible=false
			view.configure(types[t],{},Gear.PARTS if row!=2 else {})
			view.play("idle","front" if row!=2 else "front_left")
			var rect:=TextureRect.new();rect.texture=view.viewport.get_texture();rect.position=Vector2(t*320+32,45+row*256);rect.size=Vector2(256,256);root.add_child(rect)
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/character_3d/refined_review.png")
	print("REFINED_REVIEW_OK");quit()
