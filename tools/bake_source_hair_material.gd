extends RefCounted
const Source="D:/code/rmmo_runtime/assets/characters/source_hair/koikatu/"
static var textures:Dictionary={}
static func texture(path:String)->Texture2D:
	if not textures.has(path):
		var image:=Image.load_from_file(path)
		assert(image!=null and not image.is_empty(),"Missing hair material texture: "+path)
		image.generate_mipmaps();textures[path]=ImageTexture.create_from_image(image)
	return textures[path]
static func decorate(mat:ShaderMaterial,src:Dictionary,data:Dictionary,folder:String)->void:
	var values:Dictionary={}
	for parameter in ["hair_color","hair_color2","hair_color3","color_mask","has_mask"]:values[parameter]=mat.get_shader_parameter(parameter)
	mat.shader=load("res://scripts/char/character_source_hair.gdshader")
	for parameter in values:mat.set_shader_parameter(parameter,values[parameter])
	var defaults:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Source+"lighting/program_defaults.json"))
	mat.set_shader_parameter("gloss_map",texture(Source+"lighting/"+defaults.gloss_texture+".png"))
	mat.set_shader_parameter("ramp_map",texture(Source+"lighting/"+defaults.ramp_texture+".png"))
	var ambient:Array=defaults.ambient_shadow_rgb
	mat.set_shader_parameter("ambient_shadow",Vector4(ambient[0],ambient[1],ambient[2],defaults.shadow_depth))
	var floats:Dictionary={"_SpeclarHeight":"specular_height","_ShadowExtend":"shadow_extend","_rimpower":"rim_width","_rimV":"rim_strength"}
	for pair in src.m_SavedProperties.m_Floats:
		if floats.has(pair[0]):mat.set_shader_parameter(floats[pair[0]],pair[1])
	for pair in src.m_SavedProperties.m_Colors:
		if pair[0]=="_ShadowColor":
			var c:Dictionary=pair[1];mat.set_shader_parameter("shadow_color",Color(c.r,c.g,c.b,c.a))
	for pair in src.m_SavedProperties.m_TexEnvs:
		if pair[0]=="_DetailMask" and pair[1].m_Texture.m_PathID!="0":
			mat.set_shader_parameter("detail_mask",texture(folder+"/"+data.textures[pair[1].m_Texture.m_PathID].file))
			mat.set_shader_parameter("has_detail",true)
