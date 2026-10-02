extends RefCounted
const Response = preload("res://scripts/world3d/wind_response.gd")
static var shaders := {}

static func channel(value: int) -> Vector4:
	if value == BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: return Vector4(1.0/3,1.0/3,1.0/3,0)
	var out := Vector4.ZERO; out[clampi(value,0,3)] = 1; return out

static func make(source: StandardMaterial3D, config: Dictionary, bounds: AABB) -> ShaderMaterial:
	if source == null: source = StandardMaterial3D.new()
	var key := "%d/%d/%d/%s/%d" % [source.cull_mode,source.transparency,source.shading_mode,source.texture_repeat,source.texture_filter]
	if not shaders.has(key):
		var code: String = preload("res://scripts/world3d/wind_material.gdshader").code
		var cull: String = ["cull_back","cull_front","cull_disabled"][source.cull_mode]
		if source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: cull += ", unshaded"
		code = code.replace("render_mode cull_back;", "render_mode "+cull+";")
		if not source.texture_repeat: code = code.replace("repeat_enable","repeat_disable")
		var filters := ["filter_nearest","filter_linear","filter_nearest_mipmap","filter_linear_mipmap","filter_nearest_mipmap_anisotropic","filter_linear_mipmap_anisotropic"]
		code = code.replace("filter_linear_mipmap_anisotropic",filters[source.texture_filter])
		var alpha := ""
		if source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA: alpha = "ALPHA = base.a;"
		elif source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR: alpha = "ALPHA = base.a; ALPHA_SCISSOR_THRESHOLD = alpha_cut;"
		code = code.replace("// ALPHA_INSERT",alpha)
		var shader := Shader.new(); shader.code = code; shaders[key] = shader
	var result := ShaderMaterial.new(); result.shader = shaders[key]; result.render_priority = source.render_priority
	var params := {"tint":source.albedo_color,"uv_scale":source.uv1_scale,"uv_offset":source.uv1_offset,
		"vertex_color":source.vertex_color_use_as_albedo, "roughness":source.roughness,"metallic":source.metallic,"specular":source.metallic_specular,
		"normal_enabled":source.normal_enabled,"normal_scale":source.normal_scale,"ao_enabled":source.ao_enabled,"ao_light":source.ao_light_affect,
		"rough_channel":channel(source.roughness_texture_channel),"metal_channel":channel(source.metallic_texture_channel),"ao_channel":channel(source.ao_texture_channel),
		"emission":source.emission if source.emission_enabled else Color.BLACK, "emission_energy":source.emission_energy_multiplier if source.emission_enabled else 0.0,
		"emission_multiply":source.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY,"alpha_cut":source.alpha_scissor_threshold,
		"emission_texture_present":source.emission_texture != null,
		"amplitude":config.amplitude,"stiffness":config.stiffness,"cloth":config.profile == "cloth",
		"anchor_reverse":config.anchor in ["top","right"]}
	var axis := 1 if config.anchor in ["top","bottom"] else 0
	var axis_vector := Vector3.ZERO; axis_vector[axis] = 1
	params.anchor_axis = axis_vector; params.anchor_min = bounds.position[axis]; params.anchor_span = maxf(.001,bounds.size[axis])
	for uniform_name in params: result.set_shader_parameter(uniform_name,params[uniform_name])
	for pair in [["albedo_tex","albedo_texture"],["normal_tex","normal_texture"],["rough_tex","roughness_texture"],["metal_tex","metallic_texture"],["ao_tex","ao_texture"],["emission_tex","emission_texture"]]:
		var texture: Texture2D = source.get(pair[1])
		if texture != null: result.set_shader_parameter(pair[0],texture)
	return result
