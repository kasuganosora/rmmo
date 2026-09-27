extends SceneTree
## Reference-inspired studio, not the vendor's undisclosed Marmoset settings.
const Model=preload("res://scripts/char/character_model_3d.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(640,900)
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
	var sheet:=Image.create(640*3,900*2,false,Image.FORMAT_RGB8)
	for gender_index in 2:
		var gender:String=["female","male"][gender_index]
		studio.configure_body(gender);var model=studio.model
		for view_index in 3:
			var view:String=["front","front_left","back"][view_index]
			model.play("idle",view,true);model.pose_at(0)
			for frame in 4:await process_frame
			await RenderingServer.frame_post_draw
			var captured:=root.get_texture().get_image();captured.convert(Image.FORMAT_RGB8)
			captured.save_png(Art.review_path("character_3d/skin_studio_%s_%s.png"%[gender,view]))
			sheet.blit_rect(captured,Rect2i(0,0,640,900),Vector2i(view_index*640,gender_index*900))
	sheet.save_png(Art.review_path("character_3d/skin_studio_review.png"))
	studio.free();print("PASS skin studio render: fixed key/fill/rim, front/three-quarter/back, both bodies");quit()
