extends RefCounted
## Region-aware PBR material for the Base Female UV layout, not the legacy avatar UV.
const Art=preload("res://scripts/asset/art_paths.gd")
static var texture_cache:Dictionary={}
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
void fragment() {
	ALBEDO = texture(albedo_map, UV).rgb;
	ROUGHNESS = mix(0.65, 0.28, texture(gloss_map, UV).r);
	SPECULAR = 0.4 * texture(specular_map, UV).r;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = 0.35;
	SSS_STRENGTH = 0.1;
}
"""
static func create_preview()->Node3D:
	var state:=GLTFState.new();var document:=GLTFDocument.new()
	if document.append_from_file(Art.path("characters/base/female_base_v2/female_base_v2_display.glb"),state)!=OK:
		push_error("female_base_v2: cannot load external base mesh");return null
	var materials:Dictionary={};var shader:=Shader.new();shader.code=CODE
	for region:String in REGIONS:
		var material:=ShaderMaterial.new();material.shader=shader;material.resource_name="skin_porcelain_01_"+region
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
	var assigned:=0
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original:Material=mesh.mesh.surface_get_material(surface)
			var name:String=original.resource_name
			if materials.has(name):
				mesh.set_surface_override_material(surface,materials[name]);assigned+=1
			else:
				# Explicit eye/mouth placeholders; never treat their UV as face skin.
				var neutral:=StandardMaterial3D.new();neutral.roughness=.45;neutral.resource_name="preview_"+name
				neutral.albedo_color=Color("ded5c6")
				if name=="Irises":neutral.albedo_color=Color("61442a")
				if name=="Pupils":neutral.albedo_color=Color("090909")
				if name in ["Gums","Tongue","InnerMouth"]:neutral.albedo_color=Color("985b60")
				if name in ["EyeReflection","Cornea","Tear","Eyelashes"]:
					neutral.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;neutral.albedo_color.a=0.0
				mesh.set_surface_override_material(surface,neutral)
	if assigned!=16:
		push_error("Base Female UV region mismatch: expected 16 skin surfaces, got %s"%assigned)
		model.free();return null
	model.set_meta("skin_id","skin_porcelain_01");model.set_meta("skin_surface_count",assigned)
	return model
