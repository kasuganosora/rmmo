extends RefCounted
const Response = preload("res://scripts/world3d/wind_response.gd")
static var shaders := {}

# Main-thread cache. Worker results publish only after their first material/uniform use.
static func variant_key(source:StandardMaterial3D)->String:
	if source==null:source=StandardMaterial3D.new()
	return "%d/%d/%d/%s/%d/%s/%s/%d/%d" % [source.cull_mode,source.transparency,source.shading_mode,source.texture_repeat,source.texture_filter,source.backlight_enabled,source.detail_enabled,source.detail_blend_mode,source.detail_uv_layer]

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
	# Covered/legacy callers must not duplicate a variant already being prepared.
	if _pending_variants.has(key):
		var pending:Preparation=_pending_variants[key]
		if pending.task>=0 and WorkerThreadPool.is_task_completed(pending.task):_finish_variant(pending)
		if not variant_is_prepared(key):
			timing.cache_miss=true;timing.total_ms=(Time.get_ticks_usec()-started)/1000.0
			return null
	if not allow_cold and not variant_is_prepared(key):
		timing.cache_miss=true;timing.total_ms=(Time.get_ticks_usec()-started)/1000.0
		return null
	if not shaders.has(key):
		var phase:=Time.get_ticks_usec()
		var code:String=_shader_code(_shader_options(source))
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
	if source.detail_enabled:
		result.set_shader_parameter("detail_uv_scale",source.uv2_scale);result.set_shader_parameter("detail_uv_offset",source.uv2_offset)
		if source.detail_albedo!=null:result.set_shader_parameter("detail_albedo_tex",source.detail_albedo)
		if source.detail_mask!=null:result.set_shader_parameter("detail_mask_tex",source.detail_mask)
	timing.textures_ms=(Time.get_ticks_usec()-phase)/1000.0
	shaders[key].set_meta("wind_variant_prepared",true)
	timing.total_ms=(Time.get_ticks_usec()-started)/1000.0
	return result

# One shared cold shader task at a time. Consumers retain authored materials;
# no Node, shared Shader or source Material is accessed by the worker.
static var _pending_variants:Dictionary={}
static var _variant_queue:Array=[]
static var _active_variant:Preparation
static var _background_started:=0
static var _background_completed:=0
static var _background_cancelled:=0
static var _background_usec:=0
static var _background_on_main:=0
static var preparation_test_gate:Semaphore # Null in production; deterministic blocked-worker regression.

class Preparation extends RefCounted:
	var key:String
	var options:Dictionary
	var owners:Dictionary={}
	var task:=-1
	var shader:Shader
	var warmup:ShaderMaterial
	var elapsed_usec:=0
	var ran_on_main:=false
	var gate:Semaphore

static func request_variant(source:StandardMaterial3D,owner:Node,key:String="")->void:
	assert(Thread.is_main_thread())
	if not is_instance_valid(owner) or not owner.is_inside_tree():return
	if key.is_empty():key=variant_key(source)
	if variant_is_prepared(key):return
	var job:Preparation=_pending_variants.get(key)
	if job==null:
		job=Preparation.new();job.key=key;job.options=_shader_options(source)
		_pending_variants[key]=job;_variant_queue.append(job)
	job.owners[owner.get_instance_id()]=weakref(owner)
	_start_next_variant()

static func variant_is_preparing(key:String)->bool:return _pending_variants.has(key)

static func background_profile()->Dictionary:
	return {"mode":"background_variants","blocking":false,"started":_background_started,"completed":_background_completed,"cancelled":_background_cancelled,"pending":_pending_variants.size(),"active":int(_active_variant!=null),"worker_usec":_background_usec,"main_thread_builds":_background_on_main}

static func _start_next_variant()->void:
	if _active_variant!=null:return
	while not _variant_queue.is_empty():
		var job:Preparation=_variant_queue.pop_front()
		var wanted:=false
		for ref:WeakRef in job.owners.values():
			var owner:Variant=ref.get_ref()
			if is_instance_valid(owner) and owner.is_inside_tree() and owner.needs_wind_variant(job.key):wanted=true;break
		if not wanted or variant_is_prepared(job.key):
			_pending_variants.erase(job.key);_background_cancelled+=1;continue
		_active_variant=job;job.gate=preparation_test_gate
		job.task=WorkerThreadPool.add_task(_prepare_variant.bind(job),false,"WindShader:"+job.key)
		_background_started+=1
		return

static func _prepare_variant(job:Preparation)->void:
	job.ran_on_main=Thread.is_main_thread()
	if job.gate!=null:job.gate.wait()
	var started:=Time.get_ticks_usec()
	job.shader=Shader.new();job.shader.code=_shader_code(job.options)
	job.warmup=ShaderMaterial.new();job.warmup.shader=job.shader
	# Prepare a private material RID via the engine's worker-safe shader path.
	# A shader-uniform-list getter would synchronously wait for the main thread.
	job.warmup.set_shader_parameter("tint",Color.WHITE)
	job.warmup.get_rid()
	job.elapsed_usec=Time.get_ticks_usec()-started
	_finish_variant.call_deferred(job)

static func _finish_variant(job:Preparation)->void:
	assert(Thread.is_main_thread())
	if _active_variant!=job:return
	if not WorkerThreadPool.is_task_completed(job.task):
		var tree:=Engine.get_main_loop() as SceneTree
		if tree!=null:tree.process_frame.connect(_finish_variant.bind(job),CONNECT_ONE_SHOT)
		return
	# Only completed tasks are joined; a disappearing world never waits for it.
	WorkerThreadPool.wait_for_task_completion(job.task)
	job.shader.set_meta("wind_variant_prepared",true);shaders[job.key]=job.shader
	_pending_variants.erase(job.key);_active_variant=null
	_background_completed+=1;_background_usec+=job.elapsed_usec
	_background_on_main+=int(job.ran_on_main)
	job.warmup=null;job.owners.clear();job.options.clear()
	_start_next_variant()

static func _shader_options(source:StandardMaterial3D)->Dictionary:
	if source==null:source=StandardMaterial3D.new()
	return {"cull_mode":source.cull_mode,"transparency":source.transparency,"shading_mode":source.shading_mode,"texture_repeat":source.texture_repeat,"texture_filter":source.texture_filter,"backlight_enabled":source.backlight_enabled,"detail_enabled":source.detail_enabled,"detail_blend_mode":source.detail_blend_mode,"detail_uv_layer":source.detail_uv_layer}

static func _shader_code(options:Dictionary)->String:
	var code: String = preload("res://scripts/world3d/wind_material.gdshader").code
	var cull: String = ["cull_back","cull_front","cull_disabled"][options.cull_mode]
	if options.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: cull += ", unshaded"
	code = code.replace("render_mode cull_back;", "render_mode "+cull+";")
	if not options.texture_repeat: code = code.replace("repeat_enable","repeat_disable")
	var filters := ["filter_nearest","filter_linear","filter_nearest_mipmap","filter_linear_mipmap","filter_nearest_mipmap_anisotropic","filter_linear_mipmap_anisotropic"]
	code = code.replace("filter_linear_mipmap_anisotropic",filters[options.texture_filter])
	var alpha := ""
	if options.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA: alpha = "ALPHA = base.a;"
	elif options.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR: alpha = "ALPHA = base.a; ALPHA_SCISSOR_THRESHOLD = alpha_cut;"
	code = code.replace("// ALPHA_INSERT",alpha)
	code = code.replace("// BACKLIGHT_INSERT","BACKLIGHT = backlight + texture(backlight_tex,UV).rgb;" if options.backlight_enabled else "")
	var detail:=""
	if options.detail_enabled:
		var uv:="UV2*detail_uv_scale.xy+detail_uv_offset.xy" if options.detail_uv_layer==BaseMaterial3D.DETAIL_UV_2 else "UV"
		var blend:String=["art.rgb","ALBEDO+art.rgb","ALBEDO-art.rgb","ALBEDO*art.rgb"][options.detail_blend_mode]
		detail="vec4 art=texture(detail_albedo_tex,"+uv+"); ALBEDO=mix(ALBEDO,"+blend+",art.a*texture(detail_mask_tex,UV).r);"
	code=code.replace("// DETAIL_INSERT",detail)
	return code
