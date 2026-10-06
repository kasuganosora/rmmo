extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Paths=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(400,560);root.content_scale_size=root.size
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("899ba6");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.42;root.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,32,0);root.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;root.add_child(camera)
	var model=Model.create("female",{},{});root.add_child(model);model.set_process(false)
	var cases=[["idle","front",0.0,""],["idle","left",0.0,""],["idle","back",0.0,""],["walk","front_left",.2,""],["walk","back_right",.6,""],["dash","front",.2,""],["dash","left",.6,""],["cast","front_left",.4,""],["attack","front_left",.25,"attack_sword_a"],["attack","left",.5,"attack_sword_b"],["attack","back_left",.4,"attack_sword_c"],["sit_chair","left",.3,""]]
	for gender in ["female","male"]:
		for outfit in ["starter","maid"]:
			var gear:Dictionary={"Clothing1":1,"Clothing2":1,"Boots":1,"Belt":1,"WeaponMain":1} if outfit=="starter" else {"Clothing1":2,"Boots":2,"HeadAccessory":1,"WeaponMain":1}
			model.configure(gender,{},gear)
			camera.size=2.85;camera.position=Vector3(0,1.55,5);camera.look_at(Vector3(0,1.15,0))
			var sheet:=Image.create(1600,1680,false,Image.FORMAT_RGB8)
			for i in cases.size():
				var entry:Array=cases[i];model.play(entry[0],entry[1],true,entry[3]);model.pose_at(entry[2])
				for frame in 3:await process_frame
				await RenderingServer.frame_post_draw
				var picture:Image=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(picture,Rect2i(0,0,400,560),Vector2i((i%4)*400,(i/4)*560))
			sheet.save_png(Paths.review_path("character_3d/equipment_review_%s_%s.png"%[gender,outfit]))
		# Close views of the actual hand, not a second preview-only rig.
		model.play("idle","front_left",true);model.pose_at(0)
		var hand:Vector3=(model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.bones.handL)).origin
		camera.size=.55;camera.position=hand+Vector3(0,.08,2);camera.look_at(hand+Vector3(0,-.1,0))
		for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(Paths.review_path("character_3d/weapon_hand_%s.png"%gender))
	model.free();quit()
