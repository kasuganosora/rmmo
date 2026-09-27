extends RefCounted
## Shared soft skin response. This is intentionally separate from hair/cloth.
## Direct lighting reveals form; the low fill protects colour without flattening it.
const SURFACE="""
float skin_grain(vec2 uv) {
    vec2 p=uv*640.0;
    float fade=1.0-smoothstep(0.25,0.8,length(fwidth(p)));
    return sin(p.x*6.283185)*sin(p.y*6.283185)*fade;
}
vec3 skin_fill(vec3 normal, mat4 inverse_view) {
    vec3 world_normal=normalize((inverse_view*vec4(normal,0.0)).xyz);
    float sky=smoothstep(-0.5,0.8,world_normal.y);
    return mix(vec3(0.24,0.22,0.215),vec3(0.34,0.33,0.32),sky);
}
"""
const LIGHT="""
void light() {
    float nl=dot(NORMAL,LIGHT);
    float diffuse=max((nl+0.4)/1.4,0.0);
    vec3 warmth=mix(vec3(1.0,0.9,0.85),vec3(1.0),smoothstep(-0.15,0.65,nl));
    DIFFUSE_LIGHT+=LIGHT_COLOR*ATTENUATION*diffuse*warmth*0.48/PI;
    vec3 half_vector=normalize(LIGHT+VIEW);
    float nh=max(dot(NORMAL,half_vector),0.0);
    // Wide, low-intensity dielectric sheen, not a white plastic highlight.
    float broad=pow(nh,mix(38.0,12.0,ROUGHNESS));
    float fine=pow(nh,90.0);
    SPECULAR_LIGHT+=LIGHT_COLOR*ATTENUATION*max(nl,0.0)*(broad*0.10+fine*0.012)*SPECULAR_AMOUNT/PI;
}
"""
static var details:Dictionary={}
static var maps:Dictionary={}
static func apply_maps(material:ShaderMaterial,gender:String)->void:
	if not maps.has(gender):
		var textures:Dictionary={}
		for name in ["basecolor","normal","orm"]:
			var path=preload("res://scripts/asset/art_paths.gd").path("characters/imported/%s/skin_%s.png"%[gender,name])
			if not FileAccess.file_exists(path):continue
			var source=Image.load_from_file(path)
			if source==null or source.is_empty():continue
			source.generate_mipmaps();textures[name]=ImageTexture.create_from_image(source)
		maps[gender]=textures
	var textures:Dictionary=maps[gender]
	material.set_shader_parameter("skin_maps_enabled",textures.size()==3)
	for name in textures:material.set_shader_parameter("skin_"+name,textures[name])
static func detail_for(gender:String)->Dictionary:
	if not details.has(gender):
		var path=preload("res://scripts/asset/art_paths.gd").path("characters/imported/%s/skin_detail.json"%gender)
		var parsed=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		details[gender]=parsed.get("samples",{}) if parsed is Dictionary and parsed.get("version")==1 else {}
	return details[gender]
static func key(p:Vector3)->String:
	return "%d,%d,%d"%[roundi(p.x*10000),roundi(p.y*10000),roundi(p.z*10000)]
