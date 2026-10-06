extends SceneTree
const Assets=preload("res://scripts/char/character_axis_assets.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var folder:=preload("res://scripts/asset/art_paths.gd").path("characters/base/female_base_v2")
	var rig:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/female_axis_rig.json"))
	var topology:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/female_display_topology.json"))
	var mesh:=Assets.build_mesh(topology)
	var mesh_temp:=folder+"/axis_runtime_mesh.pending.res"
	assert(ResourceSaver.save(mesh,mesh_temp)==OK)
	var file:=FileAccess.open(folder+"/axis_runtime_data.pending.bin",FileAccess.WRITE)
	assert(file!=null)
	# Display quads, UVs and subdivision ranges already live in the baked mesh.
	# Keep only the base/contact topology needed by runtime deformation and cloth.
	var runtime_topology:Dictionary={}
	for key in ["points","base_faces","materials","stencil_size"]:runtime_topology[key]=topology[key]
	file.store_var({"signature":Assets.signature(folder),"mesh_sha256":FileAccess.get_sha256(mesh_temp),"rig":rig,"topology":runtime_topology});file.close()
	assert(DirAccess.rename_absolute(mesh_temp,folder+"/axis_runtime_mesh.res")==OK)
	assert(DirAccess.rename_absolute(folder+"/axis_runtime_data.pending.bin",folder+"/axis_runtime_data.bin")==OK)
	if "--geometry-only" in OS.get_cmdline_user_args():
		print("PASS atomically built external axis geometry/data");quit();return
	var materials:=Resource.new()
	materials.set_meta("signature",Assets.material_signature(folder))
	var modes:=Assets.build_materials()
	var textures:Dictionary={}
	for mode in modes.values():
		for material in mode.materials.values():
			if not material is ShaderMaterial:continue
			for uniform:Dictionary in material.shader.get_shader_uniform_list():
				var value:Variant=material.get_shader_parameter(uniform.name)
				if not value is ImageTexture:continue
				if not textures.has(value):
					var texture:=PortableCompressedTexture2D.new()
					texture.keep_compressed_buffer=true
					texture.create_from_image(value.get_image(),PortableCompressedTexture2D.COMPRESSION_MODE_BPTC,str(uniform.name)=="normal_map")
					assert(texture.get_width()==value.get_width() and texture.get_height()==value.get_height())
					textures[value]=texture
					print("Packed texture ",textures.size())
				material.set_shader_parameter(uniform.name,textures[value])
	materials.set_meta("modes",modes)
	assert(ResourceSaver.save(materials,folder+"/axis_runtime_materials.pending.res",ResourceSaver.FLAG_COMPRESS)==OK)
	assert(DirAccess.rename_absolute(folder+"/axis_runtime_materials.pending.res",folder+"/axis_runtime_materials.res")==OK)
	print("PASS built external axis runtime data and immutable display mesh")
	quit()
