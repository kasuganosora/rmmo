extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(400,560);root.content_scale_size=root.size
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("899ba6")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=.42;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,32,0);root.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.3;root.add_child(camera)
	camera.position=Vector3(0,1.15,5);camera.look_at(Vector3(0,1.05,0))
	var model=Model.create("female",{},{});root.add_child(model);model.set_process(false)
	var cases=[["idle","front",0.0],["idle","left",0.0],["idle","back",0.0],["walk","back",.2],["walk","front",.6],["dash","back",.2],["sit_chair","left",0.0],["attack","front_left",.3]]
	var idle_only:bool="--idle" in OS.get_cmdline_user_args()
	if idle_only:cases=cases.slice(0,3)
	for gender in ["female","male"]:
		for outfit in [2,3]:
			model.configure(gender,{}, {"Clothing1":outfit,"Boots":2,"HeadAccessory":1})
			var sheet:=Image.create(1200 if idle_only else 1600,560 if idle_only else 1120,false,Image.FORMAT_RGB8)
			for i in cases.size():
				model.play(cases[i][0],cases[i][1],true);model.pose_at(cases[i][2])
				if "--no-cloth" in OS.get_cmdline_user_args():
					for mesh in model.gear.Clothing1:
						if mesh.visible and mesh.material_override is ShaderMaterial:mesh.material_override.set_shader_parameter("leg_radius",0.0)
				for frame in 4:await process_frame
				await RenderingServer.frame_post_draw
				var picture:=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(picture,Rect2i(0,0,400,560),Vector2i((i%4)*400,(i/4)*560))
			sheet.save_png(Art.review_path("character_3d/garment_%s_%d%s.png"%[gender,outfit,"_idle" if idle_only else "_no_cloth" if "--no-cloth" in OS.get_cmdline_user_args() else ""]))
	model.free();quit()
