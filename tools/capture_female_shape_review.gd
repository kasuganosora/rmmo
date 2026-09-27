extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(480,640)
	var gender:="male" if "--male" in OS.get_cmdline_user_args() else "female"
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
	studio.camera.size=2.15;studio.camera.position=Vector3(0,1.0,5);studio.camera.look_at(Vector3(0,1,0))
	for outfit in (["starter"] if "--starter" in OS.get_cmdline_user_args() else ["base","maid"]):
		var sheet:=Image.create(1440,2560,false,Image.FORMAT_RGB8)
		for column in 3:
			var parts:Dictionary={} if outfit=="base" else {"Clothing1":2,"Boots":2,"HeadAccessory":1}
			if outfit=="starter":parts=preload("res://scripts/char/starter_equipment.gd").PARTS
			studio.model.configure(gender,{"bust_size":column*.5},parts)
			var cases=[["idle","front_left",0.0],["idle","back",0.0],["dash","front_left",.2],["sit_chair","left",0.0]]
			for row in cases.size():
				var entry:Array=cases[row];studio.model.play(entry[0],entry[1],true);studio.model.pose_at(entry[2])
				for i in 4:await process_frame
				await RenderingServer.frame_post_draw
				var captured:=root.get_texture().get_image();captured.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(captured,Rect2i(0,0,480,640),Vector2i(column*480,row*640))
		sheet.save_png(Art.review_path("character_3d/%s_shape_%s.png"%[gender,outfit]))
	studio.free();print("PASS ",gender," shape captures: three sizes, front/back/run/seated, base/maid");quit()
