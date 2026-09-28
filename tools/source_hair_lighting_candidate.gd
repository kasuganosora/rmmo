extends RefCounted
const Art=preload("res://scripts/asset/art_paths.gd")
static func texture(path:String)->Texture2D:
	var image:=Image.load_from_file(path)
	assert(image!=null and not image.is_empty(),"Missing source lighting texture: "+path)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
static func apply(hair:Node3D,gloss:bool,key:DirectionalLight3D)->void:
	var source:Node3D=hair.source
	var updated:Array[ShaderMaterial]=[]
	var base:String=Art.path("characters/source_hair/koikatu/")
	var defaults:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"lighting/program_defaults.json"))
	var gloss_map:=texture(base+"lighting/"+defaults.gloss_texture+".png")
	var ramp_map:=texture(base+"lighting/"+defaults.ramp_texture+".png")
	for part in source.get_children():
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+str(part.name)+"/source.json"))
		for mesh:MeshInstance3D in part.find_children("*","MeshInstance3D",true,false):
			for i in mesh.mesh.get_surface_count():
				var old:Material=mesh.get_active_material(i)
				if not old is ShaderMaterial:continue
				var mat:=ShaderMaterial.new()
				mat.resource_name=old.resource_name
				for parameter in ["hair_color","hair_color2","hair_color3"]:
					var original_key:String="source_"+parameter
					mat.set_meta(original_key,old.get_meta(original_key,old.get_shader_parameter(parameter)))
				mat.shader=load("res://scripts/char/character_source_hair.gdshader")
				mat.set_shader_parameter("source_key_enabled",true)
				for parameter in ["hair_color","hair_color2","hair_color3","color_mask","has_mask"]:
					mat.set_shader_parameter(parameter,old.get_shader_parameter(parameter))
				mat.set_shader_parameter("gloss_map",gloss_map)
				mat.set_shader_parameter("ramp_map",ramp_map)
				mat.set_shader_parameter("gloss_enabled",gloss)
				mat.set_shader_parameter("source_key_direction",key.global_transform.basis.z.normalized())
				var ambient:Array=defaults.ambient_shadow_rgb
				mat.set_shader_parameter("ambient_shadow",Vector4(ambient[0],ambient[1],ambient[2],defaults.shadow_depth))
				var original:Dictionary={}
				for item:Dictionary in data.materials.values():
					if item.m_Name==old.resource_name:original=item;break
				assert(not original.is_empty(),"Cannot trace material to source")
				for pair in original.m_SavedProperties.m_Floats:
					if pair[0]=="_SpeclarHeight":mat.set_shader_parameter("specular_height",pair[1])
					if pair[0]=="_ShadowExtend":mat.set_shader_parameter("shadow_extend",pair[1])
					if pair[0]=="_rimpower":mat.set_shader_parameter("rim_width",pair[1])
					if pair[0]=="_rimV":mat.set_shader_parameter("rim_strength",pair[1])
				for pair in original.m_SavedProperties.m_Colors:
					if pair[0]=="_ShadowColor":
						var c:Dictionary=pair[1]
						mat.set_shader_parameter("shadow_color",Color(c.r,c.g,c.b,c.a))
				for pair in original.m_SavedProperties.m_TexEnvs:
					if pair[0]=="_DetailMask" and pair[1].m_Texture.m_PathID!="0":
						mat.set_shader_parameter("detail_mask",texture(base+str(part.name)+"/"+data.textures[pair[1].m_Texture.m_PathID].file))
						mat.set_shader_parameter("has_detail",true)
				mesh.set_surface_override_material(i,mat)
				updated.append(mat)
	hair.materials=updated
