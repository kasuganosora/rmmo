extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(128,128)
	var scene:=Node3D.new();root.add_child(scene)
	var camera:=Camera3D.new();scene.add_child(camera);camera.position.z=2;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2
	var light:=DirectionalLight3D.new();scene.add_child(light);light.light_energy=1
	var env:=WorldEnvironment.new();scene.add_child(env)
	env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_DISABLED
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	var mesh:=MeshInstance3D.new();mesh.mesh=QuadMesh.new();scene.add_child(mesh)
	var mat:=ShaderMaterial.new();mat.shader=load("res://scripts/char/character_source_hair.gdshader");mesh.material_override=mat
	mat.set_shader_parameter("source_key_enabled",true)
	var mask:=Image.create(1,1,false,Image.FORMAT_RGB8);mask.fill(Color.RED)
	mat.set_shader_parameter("color_mask",ImageTexture.create_from_image(mask));mat.set_shader_parameter("has_mask",true)
	mat.set_shader_parameter("gloss_enabled",false);mat.set_shader_parameter("rim_strength",0.0)
	mat.set_shader_parameter("shadow_color",Color.WHITE)
	var ramp:=Image.create(1,1,false,Image.FORMAT_RGB8);ramp.fill(Color.WHITE)
	mat.set_shader_parameter("ramp_map",ImageTexture.create_from_image(ramp))
	for shade in [0.25,0.5,0.75]:
		mat.set_shader_parameter("hair_color",Color(shade,shade,shade,1))
		for frame in 4:await process_frame
		await RenderingServer.frame_post_draw
		var pixel:Color=root.get_texture().get_image().get_pixel(64,64)
		print("source pigment ",shade," rendered ",pixel.r)
		assert(absf(pixel.r-shade)<0.025,"Hair pigment multiplied twice or light normalization changed")
	scene.free()
	for frame in 3:await process_frame
	print("PASS source-hair light: 3 neutral pigment levels retain brightness")
	quit()
