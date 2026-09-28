extends SceneTree
const Body=preload("res://scripts/char/female_axis_body.gd")
const Regional=preload("res://scripts/char/character_regional_skin.gd")
const Custom=preload("res://scripts/char/customization.gd")
func _initialize()->void:call_deferred("run")
func inspect(model:Node3D)->Dictionary:
	var result:Dictionary={"skin":[],"iris":[],"other_eyes":[],"ids":[]}
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var material:Material=mesh.get_active_material(surface)
			result.ids.append(material.get_instance_id())
			if not material is ShaderMaterial:continue
			var region:String=material.get_meta("appearance_region","")
			if region in ["skin","iris"]:result[region].append(material)
			elif material.resource_name=="eyes_brown_01":result.other_eyes.append(material)
	return result
func run()->void:
	var studio=preload("res://tools/character_skin_studio.gd").new();root.add_child(studio);studio.show_new_base()
	var first:Node3D=studio.regional_preview
	var second:=Body.new();root.add_child(second);second.initialize();second.position.x=4
	var static_body:Node3D=Regional.create_preview();root.add_child(static_body);static_body.position.x=-4
	first.set_test_pose("sit")
	var geometry:PackedByteArray=first.positions_texture.get_image().get_data()
	var pose:Dictionary=first.angles_by_name.duplicate(true)
	var ids:Array=[first.get_instance_id(),first.skeleton.get_instance_id(),first.mesh_instance.mesh.get_instance_id(),studio.surface_wardrobe.get_instance_id()]
	var materials:Dictionary=inspect(first);var untouched:Dictionary=inspect(second)
	print("Material roles: skin=",materials.skin.size()," iris=",materials.iris.size()," other eyes=",materials.other_eyes.size())
	assert(materials.skin.size()==16 and materials.iris.size()==1 and materials.other_eyes.size()==2)
	var palette:Array=Custom.MV.palette_for("skin");assert(palette.size()>1)
	var reference:Color=Custom.MV.row_color(Custom.MV.default_row("skin"))
	var texture_count:int=Regional.texture_cache.size()
	var recipe:Dictionary=Custom.new().to_dict();recipe.skin_row=int(palette[-1].index);recipe.eye_color="#62aabb"
	# This is the existing save format, not a second preview-only recipe.
	var restored:Dictionary=Custom.from_dict(JSON.parse_string(JSON.stringify(recipe))).to_dict()
	for step in 100:
		var current:Dictionary=restored.duplicate(true);current.skin_row=int(palette[step%palette.size()].index)
		studio.set_body_colors(current)
		for material:ShaderMaterial in materials.skin:assert(material.get_shader_parameter("skin_tone")==Custom.MV.row_color(current.skin_row))
		assert(materials.iris[0].get_shader_parameter("override_iris")==true)
		assert(materials.iris[0].get_shader_parameter("iris_color")==Color(restored.eye_color))
	assert(inspect(first).ids==materials.ids and Regional.texture_cache.size()==texture_count)
	assert([first.get_instance_id(),first.skeleton.get_instance_id(),first.mesh_instance.mesh.get_instance_id(),studio.surface_wardrobe.get_instance_id()]==ids)
	assert(first.angles_by_name==pose and first.positions_texture.get_image().get_data()==geometry)
	for material:ShaderMaterial in untouched.skin:assert(material.get_shader_parameter("skin_tone")==reference,"Another actor inherited this actor's colour")
	assert(not untouched.iris[0].get_shader_parameter("override_iris"))
	for material:ShaderMaterial in materials.other_eyes:assert(not material.get_shader_parameter("override_iris"),"Sclera or pupil was recoloured")
	first.set_colors(restored);Regional.apply_colors(static_body,restored)
	var static_materials:Dictionary=inspect(static_body)
	assert(static_materials.skin[0].get_shader_parameter("skin_tone")==materials.skin[0].get_shader_parameter("skin_tone"))
	assert(static_materials.iris[0].get_shader_parameter("iris_color")==materials.iris[0].get_shader_parameter("iris_color"))
	studio.skin_selector.select(0);studio.skin_selector.item_selected.emit(0)
	for material:ShaderMaterial in materials.skin:assert(material.get_shader_parameter("skin_tone")==reference)
	studio.eye_picker.color=Color("78b368");studio.eye_picker.color_changed.emit(studio.eye_picker.color)
	assert(materials.iris[0].get_shader_parameter("iris_color")==Color("78b368"))
	studio.find_children("*","Button",true,false).filter(func(button):return button.text=="原瞳色")[0].pressed.emit()
	assert(not materials.iris[0].get_shader_parameter("override_iris"))
	first.set_colors({"skin_row":999999,"eye_color":"invalid"})
	assert(materials.skin[0].get_shader_parameter("skin_tone")==reference and not materials.iris[0].get_shader_parameter("override_iris"))
	studio.configure_body("female")
	var old_appearance:Dictionary=studio.model.appearance.duplicate(true)
	var old_rig_id:int=studio.model.rig.get_instance_id()
	studio.model.elapsed=.25
	studio.set_body_colors(restored)
	assert(studio.model.rig.get_instance_id()==old_rig_id and studio.model.elapsed==.25)
	assert(studio.model.appearance.get("hair_on")==old_appearance.get("hair_on"),"Skin controls changed an unrelated hair setting")
	studio.show_new_base()
	assert(first==studio.regional_preview and materials.iris[0].get_shader_parameter("iris_color")==Color(restored.eye_color))
	static_body.free();second.free();studio.free()
	for frame in 4:await process_frame
	print("PASS saved colour recipe, 100 live changes, instance isolation, skin regions, iris-only tint, static/dynamic parity, restore and UI signals");quit()
