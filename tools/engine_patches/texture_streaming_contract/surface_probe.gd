extends "camera_probe.gd"
## Actual terrain/bank shader feedback and same-camera ImageTexture reference.
## Temporary geometry/products only; no authored map or source changes.
const Variants=preload("res://scripts/world3d/streaming_surface_shader.gd")

func capture()->Image:
	for i:int in 6:await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func save_preview(image:Image,name:String)->void:
	var path:=output.path_join(name+".webp")
	check(image.save_webp(path,true,.9)==OK,"write Q90 preview: "+name)
	report.get_or_add("previews",[]).append({"path":path,"quality":90,"lossy":true,"width":image.get_width(),"height":image.get_height(),"sha256":FileAccess.get_sha256(path)})

func run()->void:
	create_timer(160).timeout.connect(func():quit(2))
	Engine.max_fps=60
	if source.is_empty() or output.is_empty():push_error("--source and --output required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	report.engine=Engine.get_version_info();report.scope="production surface shaders, same-camera rendering and automatic mip feedback; not whole-map performance"
	report.source_sha256=FileAccess.get_sha256(source)
	var supports:=Variants.enabled()
	report.streaming_enabled=supports
	if Engine.get_version_info().minor>=8:check(supports,"4.8 fixture enables streamed surface variants")
	else:check(not supports,"older engine uses original shaders")
	if supports:
		streaming=Engine.get_singleton("TextureStreaming")
		report.memory_before=streaming.call("get_memory_budget_bytes_used")
	check(Variants.terrain()==Variants.terrain() and Variants.bank()==Variants.bank(),"shader variants are shared across materials")
	check(Variants.is_terrain(Variants.TERRAIN) and Variants.is_terrain(Variants.terrain()) and not Variants.is_terrain(Variants.bank()),"batching recognizes original and streamed terrain only")
	var image:=Image.load_from_file(source);image.convert(Image.FORMAT_RGBA8);image.generate_mipmaps()
	var path:=output.path_join("source_pixels.stex");write_stex(image,path)
	var reference:=ImageTexture.create_from_image(image)
	var height_image:=Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8)
	height_image.fill(Color(0.,0.,0.,1.));height_image.generate_mipmaps()
	var height_path:=output.path_join("zero_height.stex");write_stex(height_image,height_path)
	var height_reference:=ImageTexture.create_from_image(height_image)
	var mask_image:=Image.create(2,2,false,Image.FORMAT_RG8);mask_image.fill(Color(1.,0.,0.))
	var mask:=ImageTexture.create_from_image(mask_image)
	var scene:=Node3D.new();root.add_child(scene)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.03,.04,.05)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=1.
	scene.add_child(environment)
	var camera:=Camera3D.new();scene.add_child(camera);camera.current=true
	var cases:Array=[
		{"name":"planar_base","sampler":"base_albedo","params":{"base_has_albedo":true}},
		{"name":"planar_normal","sampler":"base_normal","params":{"base_strength":1.}},
		{"name":"triplanar_rock","sampler":"rock_albedo","tilt":1.3,"params":{"slope_aware":true,"rock_has_albedo":true}},
		{"name":"painted_region","sampler":"region_a_albedo","params":{"ground_enabled":true,"region_a_has_albedo":true}},
		{"name":"height_eliminated_layer","height":true,"sampler":"base_height","params":{"depth_enabled":true,"water_level":-.775,"slope_aware":true,"transition_width":.5,"edge_noise":0.,"height_blend_strength":1.,"base_has_height":true,"sand_has_height":true,"base_color":Color(1.,0.,0.,1.),"sand_tile":Vector2(.02,.02),"soil_tile":Vector2(.02,.02)}},
		{"name":"unused_layer_tile","sampler":"base_albedo","distance":20.,"coarse":true,"params":{"base_has_albedo":true,"base_tile":Vector2(.02,.02),"rock_tile":Vector2(500.,500.)}},
		{"name":"bank_scaled_uv","sampler":"albedo_tex","bank":true,"distance":25.,"params":{"uv_scale":Vector3(.01,.01,1.)}},
	]
	for entry:Dictionary in cases:
		var bank:bool=entry.get("bank",false)
		var source_image:Image=height_image if entry.get("height",false) else image
		var source_texture:Texture2D=height_reference if entry.get("height",false) else reference
		var mesh:=MeshInstance3D.new()
		if bank:mesh.mesh=QuadMesh.new()
		else:
			var plane:=PlaneMesh.new();plane.size=Vector2(2,2);mesh.mesh=plane
		scene.add_child(mesh);mesh.rotation.x=entry.get("tilt",0.)
		var normal:=mesh.global_basis.z if bank else mesh.global_basis.y
		camera.position=normal*float(entry.get("distance",.5));camera.look_at(Vector3.ZERO,Vector3.UP if bank else Vector3.FORWARD)
		var material:=ShaderMaterial.new();mesh.material_override=material
		material.shader=Variants.BANK if bank else Variants.TERRAIN
		if not bank:
			material.set_shader_parameter("depth_enabled",false)
			for prefix:String in ["base","sand","rock","soil","region_a","region_b"]:material.set_shader_parameter(prefix+"_strength",0.)
			material.set_shader_parameter("ground_mask",mask);material.set_shader_parameter("terrain_span",Vector2(2,2))
		for key:String in entry.params:material.set_shader_parameter(key,entry.params[key])
		material.set_shader_parameter(entry.sampler,source_texture)
		var expected:=await capture()
		if entry.get("height",false):
			var center:=expected.get_pixel(expected.get_width()/2,expected.get_height()/2)
			check(is_equal_approx(center.r,center.g) and is_equal_approx(center.g,center.b),"height sample removes the red base layer from final visible coverage")
		var texture:Texture2D
		if supports:
			texture=ClassDB.instantiate("StreamedTexture2D")
			check(texture.call("load",height_path if entry.get("height",false) else path)==OK,entry.name+": load source streaming product")
			material.set_shader_parameter(entry.sampler,texture)
			# Red reproduction uses the actual original world-coordinate shader.
			if entry.name=="planar_base":
				await create_timer(3).timeout
				check(sample(texture,"actual_terrain_missing_feedback").get_width()==image.get_width()>>3,"original terrain shader stays coarse without feedback")
		material.shader=Variants.bank() if bank else Variants.terrain()
		if supports:
			if entry.get("coarse",false):
				await create_timer(2).timeout
				check(sample(texture,entry.name).get_width()==image.get_width()>>3,"unused large-tile layer does not request finer mips")
			else:
				check(await wait_for_bytes(source_image.get_data_size(),source_image.get_data_size(),15),entry.name+": actual shader automatically promotes to full detail")
				check(sample(texture,entry.name).get_data()==source_image.get_data(),entry.name+": uploaded source mip chain is exact")
		var actual:=await capture()
		check(actual.get_size()==expected.get_size() and actual.get_format()==expected.get_format() and actual.get_data()==expected.get_data(),entry.name+": same-camera pixels match full ImageTexture / original shader")
		save_preview(actual,entry.name)
		material.set_shader_parameter(entry.sampler,null);mesh.material_override=null
		material=null;texture=null;mesh.queue_free();mesh=null
		if supports:check(await wait_for_bytes(int(report.memory_before),int(report.memory_before),10),entry.name+": final owner release drains")
	scene.queue_free();reference=null;height_reference=null;mask=null
	check(FileAccess.get_sha256(source)==report.source_sha256,"source pixels unchanged")
	finish()
