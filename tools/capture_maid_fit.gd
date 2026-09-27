extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(650,800);root.content_scale_size=root.size
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("899ba6");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.42;root.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,32,0);root.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.0;root.add_child(camera)
	camera.position=Vector3(0,1.9,5);camera.look_at(Vector3(0,1.65,0))
	var model=Model.create("female",{}, {"Clothing1":2,"Boots":2,"HeadAccessory":1,"WeaponMain":1});root.add_child(model);model.set_process(false)
	var cases=[["idle","front",0.0],["idle","left",0.0],["attack","front_left",.3],["dash","front_left",.2],["idle","back",0.0],["attack","back_left",.3],["dash","back_left",.2]]
	for gender in ["female","male"]:
		model.configure(gender,{}, {"Clothing1":2,"Boots":2,"HeadAccessory":1,"WeaponMain":1})
		var opaque:bool="--opaque-cloth" in OS.get_cmdline_user_args()
		if opaque:
			for mesh in model.gear.Clothing1:
				if mesh.visible and mesh.material_override is ShaderMaterial:
					var shader:=Shader.new();shader.code=mesh.material_override.shader.code.replace("if (texel.a < 0.5) { discard; }", "")
					mesh.material_override.shader=shader
		var hide_body:bool="--no-body" in OS.get_cmdline_user_args()
		if hide_body:
			for mesh in model.gear.Body:mesh.visible=false
		for i in cases.size():
			model.play(cases[i][0],cases[i][1],true);model.pose_at(cases[i][2])
			var skeleton:Skeleton3D=model.skeleton
			var head:int=model.bones.head
			var chest:int=model.bones.spine
			var focus:Vector3=skeleton.global_transform*(skeleton.get_bone_global_pose(head).origin.lerp(skeleton.get_bone_global_pose(chest).origin,.5))
			camera.position=focus+Vector3(0,.15,5);camera.look_at(focus)
			for frame in 4:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/maid_fit_%s_%d%s.png"%[gender,i,"_opaque" if opaque else "_no_body" if hide_body else ""]))
	model.free();quit()
