extends SceneTree
## Isolated, actual-GPU source/legacy/candidate filtering and normal review.
var checks:Array=[]

func _initialize()->void:run.call_deferred()

func texture(path:String)->ImageTexture:
	var image:=Image.new()
	var error:=image.load_dds_from_buffer(FileAccess.get_file_as_bytes(path)) if path.ends_with(".dds") else image.load(path)
	if error!=OK:push_error("decode "+path);return null
	if not image.is_compressed() and not image.has_mipmaps():image.generate_mipmaps()
	checks.append({"path":path,"sha256":FileAccess.get_sha256(path),"bytes":image.get_data_size(),"mips":image.get_mipmap_count(),"format":image.get_format()})
	var result:=ImageTexture.create_from_image(image)
	result.set_meta("runtime_normal_xy",image.get_format()==Image.FORMAT_RGTC_RG)
	return result

func run()->void:
	var input:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):input=arg.trim_prefix("--manifest=")
	if input.is_empty():quit(2);return
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input))
	var viewport:=SubViewport.new();viewport.size=Vector2i(640,480);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world:=Node3D.new();viewport.add_child(world)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.12,.12,.12)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.25
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;world.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-25,-35,0);light.light_energy=1.6;world.add_child(light)
	var mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(4,4);mesh.mesh=plane;world.add_child(mesh)
	var camera:=Camera3D.new();camera.fov=50;world.add_child(camera);camera.current=true
	for sample:Dictionary in manifest.samples:
		for variant:String in ["source","legacy","candidate"]:
			print("DDS_GPU_REVIEW_SAMPLE ",sample.name," ",variant)
			var material:=StandardMaterial3D.new();material.roughness=.8
			material.albedo_texture=texture(sample[variant].albedo);material.normal_texture=texture(sample[variant].normal);material.normal_enabled=true
			material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			material.texture_repeat=true
			if material.albedo_texture==null or material.normal_texture==null:quit(4);return
			if variant=="candidate":
				var saved:String=manifest.output.path_join(sample.name+"_candidate.res")
				if ResourceSaver.save(material,saved)!=OK:quit(5);return
				material=ResourceLoader.load(saved,"StandardMaterial3D",ResourceLoader.CACHE_MODE_IGNORE)
				if material==null or material.normal_texture==null:quit(6);return
				checks.append({"saved_material":saved,"sha256":FileAccess.get_sha256(saved),"normal_mips_after_reopen":material.normal_texture.get_image().get_mipmap_count(),"normal_format_after_reopen":material.normal_texture.get_image().get_format()})
			var terrain:ShaderMaterial
			if manifest.get("terrain_shader",false):
				terrain=ShaderMaterial.new();terrain.shader=preload("res://scripts/world3d/river_terrain.gdshader")
				terrain.set_shader_parameter("base_normal",material.normal_texture)
				terrain.set_shader_parameter("base_normal_xy",material.normal_texture.get_meta("runtime_normal_xy",false))
				terrain.set_shader_parameter("base_tile",Vector2(4,4));terrain.set_shader_parameter("base_strength",1.)
				terrain.set_shader_parameter("slope_aware",manifest.get("slope_aware",false))
				if variant=="candidate":
					var saved:String=manifest.output.path_join(sample.name+"_terrain_candidate.res")
					if ResourceSaver.save(terrain,saved)!=OK:quit(7);return
					terrain=ResourceLoader.load(saved,"ShaderMaterial",ResourceLoader.CACHE_MODE_IGNORE)
					if terrain==null or terrain.get_shader_parameter("base_normal_xy")!=true:quit(8);return
					checks.append({"terrain_saved_material":saved,"sha256":FileAccess.get_sha256(saved),"normal_xy_after_reopen":true})
			mesh.material_override=terrain if terrain!=null else material
			for mode:String in ["near","mid","far","normal_detail"]:
				material.albedo_texture=null if mode=="normal_detail" else material.albedo_texture
				material.albedo_color=Color(.55,.55,.55) if mode=="normal_detail" else Color.WHITE
				if terrain!=null:terrain.set_shader_parameter("base_color",Color(.55,.55,.55))
				var distance:=1.9 if mode=="normal_detail" else (2.9 if mode=="near" else (6.0 if mode=="mid" else 12.0))
				camera.position=Vector3(0,distance*.7,distance);camera.look_at(Vector3.ZERO)
				for unused in 4:await process_frame
				await RenderingServer.frame_post_draw
				var output:String=manifest.output.path_join(sample.name+"_"+mode+"_"+variant+".png")
				if viewport.get_texture().get_image().save_png(output)!=OK:quit(3);return
	var result:=FileAccess.open(manifest.output.path_join("gpu_decode.json"),FileAccess.WRITE);result.store_string(JSON.stringify({"checks":checks,"version":Engine.get_version_info()},"  "));result.close()
	print("DDS_GPU_REVIEW_COMPLETE ",checks.size());quit(0)
