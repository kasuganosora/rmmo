extends RefCounted
## Region-aware PBR material for the Base Female UV layout, not the legacy avatar UV.
const Art=preload("res://scripts/asset/art_paths.gd")
const Custom=preload("res://scripts/char/customization.gd")
static var texture_cache:Dictionary={}
const EYE_CODE="""shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform float roughness_value = 0.24;
uniform bool override_iris = false;
uniform vec4 iris_color : source_color = vec4(1.0);
uniform float expression_heart = 0.0;
uniform float expression_star = 0.0;
uniform float expression_circle = 0.0;
void fragment() {
	ALBEDO = texture(albedo_map, UV).rgb;
	if(override_iris){ALBEDO=iris_color.rgb*max(ALBEDO.r,max(ALBEDO.g,ALBEDO.b));}
	// Source eye atlas has two islands centred at (.25,.75), (.75,.75).
	vec2 p=(UV-vec2(UV.x<0.5?0.25:0.75,0.75))/0.18;
	p.y=-p.y;
	float heart_base=dot(p,p)-1.0;
	float h=heart_base*heart_base*heart_base-p.x*p.x*p.y*p.y*p.y;
	float heart=1.0-smoothstep(-max(fwidth(h),0.001),max(fwidth(h),0.001),h);
	float angle=atan(p.y,p.x);
	float star_edge=length(p)-(0.63+0.27*cos(5.0*(angle-1.5707963)));
	float star=1.0-smoothstep(-max(fwidth(star_edge),0.001),max(fwidth(star_edge),0.001),star_edge);
	float ring_edge=abs(length(p)-0.66)-0.12;
	float ring=1.0-smoothstep(-max(fwidth(ring_edge),0.001),max(fwidth(ring_edge),0.001),ring_edge);
	vec3 ink=expression_heart*mix(vec3(1.0,0.94,0.96),vec3(0.85,0.03,0.18),heart)
	 +expression_star*mix(vec3(0.2,0.07,0.2),vec3(1.0,0.75,0.10),star)
	 +expression_circle*mix(vec3(1.0),vec3(0.22,0.06,0.16),ring);
	float total=expression_heart+expression_star+expression_circle;
	ALBEDO=mix(ALBEDO,ink/max(total,0.00001),min(total,1.0));
	ROUGHNESS = roughness_value;
	SPECULAR = 0.5;
}
"""
const REGIONS={
	"face":["Nostrils","Lips","Face"],
	"torso":["Head","Neck","Hips","Torso","Nipples","Ears"],
	"limbs":["Legs","Toenails","Fingernails","Hands","Shoulders","Forearms","Feet"]}
const CODE="""shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D gloss_map : filter_linear_mipmap_anisotropic;
uniform sampler2D specular_map : filter_linear_mipmap_anisotropic;
uniform vec4 skin_tone : source_color = vec4(1.0);
uniform vec4 reference_skin_tone : source_color = vec4(1.0);
uniform float expression_blush = 0.0;
void fragment() {
	ALBEDO = texture(albedo_map, UV).rgb*skin_tone.rgb/max(reference_skin_tone.rgb,vec3(0.001));
	// Face-UV mask follows all identity and expression deformation automatically.
	vec2 cheek=(UV-vec2(UV.x<0.5?0.3632:0.6369,0.577))/vec2(0.065,0.045);
	float blush=exp(-dot(cheek,cheek)*1.8)*expression_blush*0.5;
	ALBEDO=mix(ALBEDO,vec3(0.82,0.16,0.20),blush);
	ROUGHNESS = mix(0.65, 0.28, texture(gloss_map, UV).r);
	SPECULAR = 0.4 * texture(specular_map, UV).r;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = 0.35;
	SSS_STRENGTH = 0.1;
}
"""
static func create_preview(screen_space_sss:bool=true)->Node3D:
	var state:=GLTFState.new();var document:=GLTFDocument.new()
	if document.append_from_file(Art.path("characters/base/female_base_v2/female_base_v2_display.glb"),state)!=OK:
		push_error("female_base_v2: cannot load external base mesh");return null
	var materials:Dictionary={};var shader:=Shader.new()
	# Transparent viewport rendering has no screen-space SSS pass in Godot.
	# Keep all skin maps/parameters identical; omit only that unavailable feature.
	shader.code=CODE if screen_space_sss else CODE.replace("SSS_STRENGTH = 0.1;","")
	for region:String in REGIONS:
		var material:=ShaderMaterial.new();material.shader=shader;material.resource_name="skin_porcelain_01_"+region
		material.set_meta("appearance_region","skin")
		for semantic in ["albedo","normal","gloss","specular"]:
			var path:String=Art.path("characters/materials/skin_porcelain_01/%s_%s.jpg"%[region,semantic])
			var modified:=FileAccess.get_modified_time(path)
			if not texture_cache.has(path) or texture_cache[path].modified!=modified:
				var image:=Image.load_from_file(path)
				if image==null or image.is_empty():push_error("Missing skin map: "+path);return null
				image.generate_mipmaps(semantic=="normal")
				texture_cache[path]={"modified":modified,"texture":ImageTexture.create_from_image(image)}
			material.set_shader_parameter(semantic+"_map",texture_cache[path].texture)
		for name:String in REGIONS[region]:materials[name]=material
	var model:Node3D=document.generate_scene(state)
	var eye_path:String=Art.path("characters/materials/eyes_brown_01/albedo.jpg")
	var eye_modified:=FileAccess.get_modified_time(eye_path)
	if not texture_cache.has(eye_path) or texture_cache[eye_path].modified!=eye_modified:
		var eye_image:=Image.load_from_file(eye_path)
		if eye_image==null or eye_image.is_empty():push_error("Missing eye atlas: "+eye_path);model.free();return null
		eye_image.generate_mipmaps()
		texture_cache[eye_path]={"modified":eye_modified,"texture":ImageTexture.create_from_image(eye_image)}
	var eye_material:=ShaderMaterial.new();var eye_shader:=Shader.new();eye_shader.code=EYE_CODE;eye_material.shader=eye_shader
	eye_material.resource_name="eyes_brown_01";eye_material.set_shader_parameter("albedo_map",texture_cache[eye_path].texture)
	var iris_material:ShaderMaterial=eye_material.duplicate()
	iris_material.set_meta("appearance_region","iris")
	var native_face:Dictionary=preload("res://scripts/char/character_native_face.gd").create_materials()
	if native_face.size()!=8:model.free();return null
	var assigned:=0
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original:Material=mesh.mesh.surface_get_material(surface)
			var name:String=original.resource_name
			if materials.has(name):
				mesh.set_surface_override_material(surface,materials[name]);assigned+=1
			elif name in ["Irises","Pupils","Sclera"]:
				mesh.set_surface_override_material(surface,iris_material if name=="Irises" else eye_material)
			elif native_face.has(name):
				mesh.set_surface_override_material(surface,native_face[name])
			else:
				# Wet eye overlays remain pending their source shader translation.
				var neutral:=StandardMaterial3D.new();neutral.roughness=.45;neutral.resource_name="preview_"+name
				neutral.albedo_color=Color("ded5c6")
				if name in ["EyeReflection","Cornea","Tear"]:
					neutral.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;neutral.albedo_color.a=0.0
				mesh.set_surface_override_material(surface,neutral)
	if assigned!=16:
		push_error("Base Female UV region mismatch: expected 16 skin surfaces, got %s"%assigned)
		model.free();return null
	model.set_meta("skin_id","skin_porcelain_01");model.set_meta("skin_surface_count",assigned);model.set_meta("eye_id","eyes_brown_01")
	apply_colors(model,{})
	return model

## Consume the existing saved character recipe. Only supported colour fields
## are applied here; shape, hair and equipment remain separate operations.
static func apply_colors(model:Node3D,recipe:Dictionary)->void:
	var custom:=Custom.from_dict(recipe)
	var reference:Color=Custom.MV.row_color(Custom.MV.default_row("skin"))
	var tone:Color=reference
	if custom.skin_on:
		for entry:Dictionary in Custom.MV.palette_for("skin"):
			if int(entry.index)==custom.skin_row:tone=Custom.MV.row_color(custom.skin_row);break
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var material:Material=mesh.get_active_material(surface)
			if not material is ShaderMaterial:continue
			match material.get_meta("appearance_region",""):
				"skin":
					material.set_shader_parameter("skin_tone",tone)
					material.set_shader_parameter("reference_skin_tone",reference)
				"iris":
					material.set_shader_parameter("override_iris",not custom.eye_color.is_empty())
					material.set_shader_parameter("iris_color",Color(custom.eye_color) if not custom.eye_color.is_empty() else Color.WHITE)
	model.set_meta("color_customization",{"skin_row":custom.skin_row,"skin_on":custom.skin_on,"eye_color":custom.eye_color})
