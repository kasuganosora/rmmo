extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(650,800);root.content_scale_size=root.size
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("899ba6");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.42;root.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,32,0);root.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.5;root.add_child(camera)
	camera.position=Vector3(0,1.25,5);camera.look_at(Vector3(0,1.1,0))
	var model=Model.create("female",{}, {"Clothing1":2,"Boots":2,"HeadAccessory":1,"WeaponMain":1});root.add_child(model);model.set_process(false)
	var cases=[["idle","front",0.0],["idle","left",0.0],["attack","front_left",.3],["dash","front_left",.2]]
	for gender in ["female","male"]:
		model.configure(gender,{}, {"Clothing1":2,"Boots":2,"HeadAccessory":1,"WeaponMain":1})
		for i in cases.size():
			model.play(cases[i][0],cases[i][1],true);model.pose_at(cases[i][2])
			for frame in 4:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/weapon_fit_%s_%d.png"%[gender,i]))
	model.free();quit()

