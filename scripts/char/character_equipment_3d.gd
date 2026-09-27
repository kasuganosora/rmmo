extends RefCounted
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
## One equipment variant ID across body types; fitted meshes share canonical bones.
static var packed:Dictionary={}
const SLOT_CATEGORY:Dictionary={"MaidDress":"Clothing1","MaidShoes":"Boots","MaidStockings":"Boots","MaidHeadpiece":"HeadAccessory"}
const STOCKINGS_MATERIAL:="""shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 skin_color : source_color = vec4(1.0,0.824,0.706,1.0);
void fragment() {
    // Composite the thin weave with the wearer's own skin colour. The body's
    // covered polygons are masked, so alpha blending would expose empty space.
    float grazing = pow(1.0-clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.0,1.0),1.5);
    float coverage = mix(0.90,0.965,grazing);
    ALBEDO = mix(skin_color.rgb,vec3(0.009,0.007,0.011),coverage);
    ROUGHNESS = 0.60;
    SPECULAR = 0.26;
    METALLIC = 0.0;
}
"""
const DRESS_PALETTE:="""shader_type spatial;
render_mode unshaded, cull_disabled;
"""+preload("res://scripts/char/character_garment_motion.gd").VERTEX_FIT+"""
uniform sampler2D source_texture : source_color, filter_linear_mipmap;
uniform bool black_variant = false;
void fragment() {
    vec4 texel = texture(source_texture, UV);
    if (texel.a < 0.5) { discard; }
    vec3 color = texel.rgb;
    float pink = smoothstep(0.025, 0.12, min(color.r-color.g, color.r-color.b));
    float shade = dot(color,vec3(0.299,0.587,0.114));
    vec3 charcoal = vec3(0.025,0.028,0.035) * (0.4+shade);
    ALBEDO = (black_variant ? mix(color,charcoal,pink) : color) * COLOR.r;
}
"""
static func install(model:Node3D,adapter:RefCounted)->void:
	var path:String=ArtPaths.path("characters/equipment/maid/")+model.body_type+"/outfit.glb"
	if not FileAccess.file_exists(path):return
	if not packed.has(path):
		var document:=GLTFDocument.new();var state:=GLTFState.new()
		if document.append_from_file(path,state)!=OK:return
		var scene:=document.generate_scene(state);var resource:=PackedScene.new()
		var error:=resource.pack(scene);scene.free()
		if error!=OK:return
		packed[path]=resource
	var source:Node3D=packed[path].instantiate();model.rig.add_child(source)
	var skeletons:=source.find_children("*","Skeleton3D",true,false)
	if skeletons.is_empty():source.free();return
	var source_skeleton:Skeleton3D=skeletons[0]
	for mesh:MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		if not SLOT_CATEGORY.has(str(mesh.name)):continue
		var transform:Transform3D=model.rig.global_transform.affine_inverse()*mesh.global_transform
		var skin:=Skin.new()
		for binding in range(mesh.skin.get_bind_count()):
			var bone_name:String=mesh.skin.get_bind_name(binding)
			if bone_name.is_empty():bone_name=source_skeleton.get_bone_name(mesh.skin.get_bind_bone(binding))
			assert(model.skeleton.find_bone(bone_name)>=0,"Equipment bone must exist on the shared body")
			skin.add_named_bind(bone_name,mesh.skin.get_bind_pose(binding))
		mesh.reparent(model.rig,false);mesh.transform=transform;mesh.skin=skin
		mesh.skeleton=mesh.get_path_to(model.skeleton)
		var extras:Dictionary=mesh.get_meta("extras",{})
		if extras.has("garment_kind"):mesh.set_meta("garment_kind",str(extras.garment_kind))
		if extras.has("source_triangle_count"):mesh.set_meta("source_triangle_count",int(extras.source_triangle_count))
		if extras.has("source_triangle_count"):mesh.set_meta("source_triangle_count",int(extras.source_triangle_count))
		mesh.set_meta("equipment_variant",2)
		if mesh.name=="MaidStockings":
			var material:=ShaderMaterial.new();var shader:=Shader.new();shader.code=STOCKINGS_MATERIAL;material.shader=shader
			material.set_shader_parameter("skin_color",model._color(model.appearance,"skin",Color("ffeadb")))
			mesh.material_override=material
		if mesh.name=="MaidHeadpiece":mesh.set_meta("equipment_variant",1)
		if mesh.name=="MaidDress":
			mesh.set_meta("flexible_garment",mesh.get_meta("garment_kind","")=="skirt")
			mesh.set_meta("equipment_variants",[2,3])
			var original:StandardMaterial3D=mesh.get_active_material(0)
			var material:=ShaderMaterial.new();var shader:=Shader.new();shader.code=DRESS_PALETTE;material.shader=shader
			material.set_shader_parameter("source_texture",original.albedo_texture if original.albedo_texture!=null else original.emission_texture)
			mesh.material_override=material
		var category:String=SLOT_CATEGORY[str(mesh.name)]
		model.gear[category].append(mesh)
		if mesh.name=="MaidDress" and model.body_type=="female":
			adapter._apply_bust(mesh,Customization.valid_bust_size(model.appearance.get("bust_size",.5)))
	source.free()
