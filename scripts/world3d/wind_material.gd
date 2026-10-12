extends RefCounted
const Response = preload("res://scripts/world3d/wind_response.gd")
static var shaders := {}

# Main-thread cache. A Shader is ready only after its first material/uniform use.
static func variant_key(source:StandardMaterial3D)->String:
	if source==null:source=StandardMaterial3D.new()
	return "%d/%d/%d/%s/%d/%s" % [source.cull_mode,source.transparency,source.shading_mode,source.texture_repeat,source.texture_filter,source.backlight_enabled]

static func variant_is_prepared(key:String)->bool:
	return shaders.has(key) and shaders[key].get_meta("wind_variant_prepared",false)

static func channel(value: int) -> Vector4:
	if value == BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: return Vector4(1.0/3,1.0/3,1.0/3,0)
	var out := Vector4.ZERO; out[clampi(value,0,3)] = 1; return out

static func make(source: StandardMaterial3D, config: Dictionary, bounds: AABB, timing:Dictionary={}, allow_cold:bool=true) -> ShaderMaterial:
	assert(Thread.is_main_thread())
	var started:=Time.get_ticks_usec()
	if source == null: source = StandardMaterial3D.new()
	var key:=variant_key(source)
	timing.merge({"key":key,"cold":not variant_is_prepared(key),"cache_miss":false,"shader_source_ms":0.0,"shader_new_ms":0.0,"shader_code_ms":0.0,"material_new_ms":0.0,"material_shader_ms":0.0,"uniforms_ms":0.0,"first_uniform_ms":0.0,"textures_ms":0.0},true)
	if not allow_cold and not variant_is_prepared(key):
		timing.cache_miss=true;timing.total_ms=(Time.get_ticks_usec()-started)/1000.0
		return null
	if not shaders.has(key):
		var phase:=Time.get_ticks_usec()
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
		code = code.replace("// BACKLIGHT_INSERT","BACKLIGHT = backlight + texture(backlight_tex,UV).rgb;" if source.backlight_enabled else "")
		timing.shader_source_ms=(Time.get_ticks_usec()-phase)/1000.0
		phase=Time.get_ticks_usec()
		var shader:=Shader.new()
		timing.shader_new_ms=(Time.get_ticks_usec()-phase)/1000.0
		phase=Time.get_ticks_usec();shader.code=code
		timing.shader_code_ms=(Time.get_ticks_usec()-phase)/1000.0
		shaders[key]=shader
	var phase:=Time.get_ticks_usec()
	var result:=ShaderMaterial.new()
	timing.material_new_ms=(Time.get_ticks_usec()-phase)/1000.0
	phase=Time.get_ticks_usec();result.shader=shaders[key]
	timing.material_shader_ms=(Time.get_ticks_usec()-phase)/1000.0
	phase=Time.get_ticks_usec();result.render_priority=source.render_priority
	var params := {"tint":source.albedo_color,"uv_scale":source.uv1_scale,"uv_offset":source.uv1_offset,
		"vertex_color":source.vertex_color_use_as_albedo, "roughness":source.roughness,"metallic":source.metallic,"specular":source.metallic_specular,
		"normal_enabled":source.normal_enabled,"normal_scale":source.normal_scale,"ao_enabled":source.ao_enabled,"ao_light":source.ao_light_affect,
		"rough_channel":channel(source.roughness_texture_channel),"metal_channel":channel(source.metallic_texture_channel),"ao_channel":channel(source.ao_texture_channel),
		"emission":source.emission if source.emission_enabled else Color.BLACK, "emission_energy":source.emission_energy_multiplier if source.emission_enabled else 0.0,
		"emission_multiply":source.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY,"alpha_cut":source.alpha_scissor_threshold,
		"emission_texture_present":source.emission_texture != null,
		"backlight_enabled":source.backlight_enabled,"backlight":source.backlight,
		"amplitude":config.amplitude,"stiffness":config.stiffness,"cloth":config.profile == "cloth",
		"anchor_reverse":config.anchor in ["top","right"]}
	var axis := 1 if config.anchor in ["top","bottom"] else 0
	var axis_vector := Vector3.ZERO; axis_vector[axis] = 1
	params.anchor_axis = axis_vector; params.anchor_min = bounds.position[axis]; params.anchor_span = maxf(.001,bounds.size[axis])
	var first:=true
	for uniform_name in params:
		var began:=Time.get_ticks_usec() if first else 0
		result.set_shader_parameter(uniform_name,params[uniform_name])
		if first:timing.first_uniform_ms=(Time.get_ticks_usec()-began)/1000.0;first=false
	timing.uniforms_ms=(Time.get_ticks_usec()-phase)/1000.0
	phase=Time.get_ticks_usec()
	for pair in [["albedo_tex","albedo_texture"],["normal_tex","normal_texture"],["rough_tex","roughness_texture"],["metal_tex","metallic_texture"],["ao_tex","ao_texture"],["emission_tex","emission_texture"]]:
		var texture: Texture2D = source.get(pair[1])
		if texture != null: result.set_shader_parameter(pair[0],texture)
	if source.backlight_texture!=null:result.set_shader_parameter("backlight_tex",source.backlight_texture)
	timing.textures_ms=(Time.get_ticks_usec()-phase)/1000.0
	shaders[key].set_meta("wind_variant_prepared",true)
	timing.total_ms=(Time.get_ticks_usec()-started)/1000.0
	return result
