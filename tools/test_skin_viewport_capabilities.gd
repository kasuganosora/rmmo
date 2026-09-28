extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func skin_materials(body:Node3D)->Array[ShaderMaterial]:
	var result:Array[ShaderMaterial]=[]
	for i in body.mesh_instance.mesh.get_surface_count():
		var mat:Material=body.mesh_instance.get_active_material(i)
		if mat is ShaderMaterial and mat.get_meta("appearance_region","")=="skin":result.append(mat)
	assert(result.size()==16)
	return result
func run()->void:
	var recipe:Dictionary={"body_model":"female_base_v2","part_ids":{"FrontHair1":0}}
	var view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(view)
	view.configure("female",recipe,{})
	var world:=Model.new();world.body_type="female";world.appearance=recipe.duplicate(true);root.add_child(world)
	var preview_mats:=skin_materials(view.model.axis_rig.body)
	var world_mats:=skin_materials(world.axis_rig.body)
	for i in preview_mats.size():
		assert(not preview_mats[i].shader.code.contains("SSS_STRENGTH"))
		assert(world_mats[i].shader.code.contains("SSS_STRENGTH = 0.1;"))
		for parameter in ["albedo_map","normal_map","gloss_map","specular_map","skin_tone","reference_skin_tone"]:
			assert(preview_mats[i].get_shader_parameter(parameter)==world_mats[i].get_shader_parameter(parameter),"Preview altered skin data to hide a renderer limitation")
	for frame in 5:await process_frame
	world.free();view.free()
	for frame in 3:await process_frame
	print("PASS 16 skin surfaces: transparent capability fallback, opaque SSS retained, maps/tone shared unchanged")
	quit()
