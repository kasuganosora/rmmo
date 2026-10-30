extends RefCounted
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Data=preload("res://scripts/world3d/river_material_data.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const StreamingShader=preload("res://scripts/world3d/streaming_surface_shader.gd")
const CPU_SURFACE_OVERRIDES_META=&"runtime_cpu_surface_overrides"
const WATER_PROJECTIONS_META=&"runtime_water_projections"
static var cpu_index_overrides_enabled:=true # Probe-only old/new comparison.
static var water_cpu_normals_enabled:=true # Probe-only old/new comparison.
static var water_cpu_index_enabled:=true # Keep water independent from ground batching.
static var water_visible_surfaces_enabled:=true # Diagnostic legacy control.
static var water_projection_builds:=0
static var water_projection_reuses:=0
static var water_hidden_surface_skips:=0
static var water_cpu_normal_hits:=0
# Main-thread runtime indexing counters; the entry probe resets between runs.
static var cpu_index_override_count:=0
static var cpu_index_legacy_restore_count:=0
static var region_mask_prepared_hits:=0
static var region_mask_fallback_generations:=0
static var lazy_terrain_height_enabled:=true # Diagnostic eager-fallback control.
static var terrain_height_profile_enabled:=false
static var terrain_height_context_hits:=0
static var terrain_height_fallback_generations:=0
static var cache: Dictionary={}
static var hidden_slab: ShaderMaterial

static func invalidate_texture_source(path:String)->void:
	# Terrain signatures contain the authored material definitions. Remove only
	# matching derived cache entries; existing scene owners retain old materials.
	for key:String in cache.keys():
		if not key.begins_with("terrain:"):continue
		var signature:Variant=cache[key].get_meta("terrain_signature",[])
		var pending:Array=[signature];var found:=false
		while not pending.is_empty() and not found:
			var value:Variant=pending.pop_back()
			if value is Dictionary:
				for field:String in Paint.MAP_FIELDS:
					if value.get(field,"")==path:found=true;break
				if not found:
					for child:Variant in value.values():
						if child is Dictionary or child is Array:pending.append(child)
			elif value is Array:
				for child:Variant in value:
					if child is Dictionary or child is Array:pending.append(child)
		if found:cache.erase(key)

static func reset_index_profile()->void:
	cpu_index_override_count=0;cpu_index_legacy_restore_count=0
	water_cpu_normal_hits=0
	water_projection_builds=0;water_projection_reuses=0;water_hidden_surface_skips=0
	region_mask_prepared_hits=0;region_mask_fallback_generations=0

## Main-thread publication borrows the private worker Image. Editing and other
## synchronous callers retain the existing fallback when no context was prepared.
static func _region_mask(record:Dictionary,context:Dictionary)->Image:
	var image:Image=context.get("region_mask")
	if image!=null:
		region_mask_prepared_hits+=1
		return image
	region_mask_fallback_generations+=1
	return preload("res://scripts/world3d/terrain_regions.gd").mask(record)

static func _terrain_height_image(record:Dictionary,context:Dictionary)->Image:
	# Dictionary.get evaluates its fallback eagerly in GDScript. A prepared
	# context already owns the exact padded image; never rebuild the unpadded
	# height buffer unless the key is actually absent. Preserve explicit null.
	if lazy_terrain_height_enabled and context.has("image"):
		if terrain_height_profile_enabled:terrain_height_context_hits+=1
		return context["image"]
	var t:Dictionary=record.terrain_mesh
	var heights:=PackedFloat32Array()
	for height in t.heights:heights.append(float(height)*record.size[1])
	if terrain_height_profile_enabled:
		terrain_height_fallback_generations+=1
		if context.has("image"):terrain_height_context_hits+=1
	return context.get("image",Image.create_from_data(int(t.columns)+1,int(t.rows)+1,false,Image.FORMAT_RF,heights.to_byte_array()))

static func bind(material: ShaderMaterial, prefix: String, definition: Dictionary,path_checks:Variant=null) -> void:
	var started:=Time.get_ticks_usec() if Trace.enabled else 0
	var c: Array=definition.color
	material.set_shader_parameter(prefix+"_color",Color(c[0],c[1],c[2],c[3]))
	var tile: Array=definition.get("tile_size",[2,2])
	material.set_shader_parameter(prefix+"_tile",Vector2(tile[0],tile[1]))
	for pair in [["albedo","texture_path"],["normal","normal_path"],["rough","roughness_path"],["metal","metallic_path"],["ao","ao_path"],["height","height_path"]]:
		var texture:Texture2D=Paint.texture(definition,pair[1],path_checks)
		material.set_shader_parameter(prefix+"_"+pair[0],texture)
		if pair[0]=="normal":material.set_shader_parameter(prefix+"_normal_xy",texture!=null and texture.get_meta("runtime_normal_xy",false))
	material.set_shader_parameter(prefix+"_has_height",not str(definition.get("height_path","")).is_empty())
	for pair in [["albedo","texture_path"],["rough","roughness_path"],["metal","metallic_path"],["ao","ao_path"]]:
		material.set_shader_parameter(prefix+"_has_"+pair[0],not str(definition.get(pair[1],"")).is_empty() or (pair[0]=="albedo" and definition.get("pattern","")=="checker"))
	material.set_shader_parameter(prefix+"_roughness",definition.roughness)
	material.set_shader_parameter(prefix+"_metallic",definition.get("metallic",1.0 if definition.has("metallic_path") else 0.0))
	material.set_shader_parameter(prefix+"_strength",definition.get("normal_strength",1.0) if definition.has("normal_path") else 0.0)
	if Trace.enabled:Trace.elapsed("river.bind",started,{"prefix":prefix})

static func _terrain_textures_current(material:ShaderMaterial,record:Dictionary,base:Dictionary,config:Dictionary,depth_enabled:bool)->bool:
	# A live ShaderMaterial can outlast both texture catalogues. Compare only
	# this cache entry with the current prepared/pinned owners, without IO.
	var definitions:Dictionary={"base":base,"sand":config.sand_material if depth_enabled else base,"rock":config.get("rock_material",base),"soil":config.get("transition_material",base)}
	if record.has("terrain_regions"):
		definitions.region_a=record.terrain_regions.materials[0]
		definitions.region_b=record.terrain_regions.materials[1] if record.terrain_regions.materials.size()>1 else base
	for prefix:String in definitions:
		var definition:Dictionary=definitions[prefix]
		for pair:Array in [["albedo","texture_path"],["normal","normal_path"],["rough","roughness_path"],["metal","metallic_path"],["ao","ao_path"],["height","height_path"]]:
			var path:String=definition.get(pair[1],"")
			if path.is_empty():continue
			var key:String=Paint.definition_texture_key(definition,pair[1])
			var owner:RefCounted=Paint.prepared_images.get(key)
			if owner==null:owner=Paint.retained_texture(key)
			if owner==null:continue
			var expected:String=owner.get_meta("runtime_source_sha256","")
			if expected.is_empty():continue
			var texture:Texture2D=material.get_shader_parameter(prefix+"_"+pair[0])
			if texture==null or texture.get_meta("runtime_source_sha256","")!=expected:return false
	return true

static func terrain(record: Dictionary, context: Dictionary={}) -> ShaderMaterial:
	var depth_enabled: bool=record.has("terrain_depth_blend")
	var config: Dictionary=record.terrain_depth_blend if depth_enabled else record.get("terrain_slope_blend",{})
	var base: Dictionary=record.get("terrain_material",{"name":"Terrain","color":record.get("color",[1.0,1.0,1.0]).slice(0,3)+[1.0],"roughness":.92})
	var transition_enabled: bool=config.get("transition_width",0)>0 and config.has("transition_material") and (not depth_enabled or config.get("bank_profile","depth")=="natural")
	var coverage: Dictionary=record.get("terrain_regions",{}).duplicate(true)
	for region in coverage.get("regions",[]): region.erase("furrows")
	var signature: Array=[record.get("terrain_saturation",1.),coverage,depth_enabled,config,base,record.terrain_mesh if transition_enabled else {},record.size if transition_enabled or record.has("terrain_regions") else []]
	if transition_enabled: signature.append(context.get("signature",[]))
	var key:="terrain:"+str(hash(signature))
	# Avoid serializing thousands of heights on every hit. Verify equality so a
	# hash collision is a cache miss, never another patch's heights/materials.
	if cache.has(key) and cache[key].get_meta("terrain_signature",[])==signature:
		if _terrain_textures_current(cache[key],record,base,config,depth_enabled):return cached(key)
		cache.erase(key)
	var started:=Time.get_ticks_usec() if Trace.enabled else 0
	var result:=ShaderMaterial.new(); result.shader=StreamingShader.terrain()
	if Trace.enabled:Trace.elapsed("river.terrain_create",started)
	result.set_meta("terrain_signature",signature.duplicate(true))
	result.resource_name="River depth blend" if depth_enabled else ("Terrain slope blend" if record.has("terrain_slope_blend") else "Terrain PBR")
	var checks:Variant=context.get("texture_checks")
	bind(result,"base",base,checks); bind(result,"sand",config.sand_material if depth_enabled else base,checks); bind(result,"rock",config.get("rock_material",base),checks)
	bind(result,"soil",config.get("transition_material",base),checks)
	result.set_shader_parameter("transition_width",config.get("transition_width",0) if transition_enabled else 0.)
	for param in ["edge_noise","height_blend_strength"]: result.set_shader_parameter(param,config.get(param,0.))
	if transition_enabled:
		var image:Image=_terrain_height_image(record,context)
		result.set_meta("terrain_height_image",image)
		result.set_shader_parameter("terrain_heights",ImageTexture.create_from_image(image))
		result.set_shader_parameter("terrain_span",Vector2(record.size[0],record.size[2]))
	result.set_shader_parameter("terrain_padding",context.get("padding",Vector2.ZERO) if transition_enabled else Vector2.ZERO)
	result.set_shader_parameter("terrain_saturation",record.get("terrain_saturation",1.))
	result.set_shader_parameter("depth_enabled",depth_enabled)
	result.set_shader_parameter("ground_enabled",record.has("terrain_regions"))
	if record.has("terrain_regions"):
		var regions: Dictionary=record.terrain_regions
		result.set_shader_parameter("terrain_span",Vector2(record.size[0],record.size[2]))
		var image:=_region_mask(record,context)
		result.set_meta("ground_mask_image",image)
		result.set_shader_parameter("ground_mask",ImageTexture.create_from_image(image))
		bind(result,"region_a",regions.materials[0],checks)
		bind(result,"region_b",regions.materials[1] if regions.materials.size()>1 else base,checks)
	if depth_enabled:
		for param in ["water_level","shore_start","shore_end","rock_start","rock_end"]: result.set_shader_parameter(param,config[param])
		result.set_shader_parameter("wet_height",config.get("wet_height",.3))
		result.set_shader_parameter("wet_darkening",config.get("wet_darkening",0.))
	result.set_shader_parameter("slope_aware",record.has("terrain_slope_blend") or (depth_enabled and config.get("bank_profile","depth")=="natural"))
	result.set_shader_parameter("steep_start",config.get("steep_start",40.0)); result.set_shader_parameter("steep_end",config.get("steep_end",65.0))
	return remember(key,result)

static func water(config: Dictionary, source: Material) -> ShaderMaterial:
	var key:="water:"+JSON.stringify(config)+":"+str(source.get_instance_id() if source!=null else 0)
	if cache.has(key): return cached(key)
	var result:=ShaderMaterial.new(); result.shader=preload("res://scripts/world3d/river_water.gdshader")
	result.resource_name="River depth water"
	result.set_shader_parameter("absorption",config.absorption)
	for key_ in ["shallow_color","deep_color"]:
		var c: Array=config[key_]; result.set_shader_parameter(key_,Color(c[0],c[1],c[2]))
	if source is StandardMaterial3D:
		result.set_shader_parameter("normal_tex",source.normal_texture)
		result.set_shader_parameter("normal_xy",source.normal_texture!=null and source.normal_texture.get_meta("runtime_normal_xy",false))
		result.set_shader_parameter("normal_strength",source.normal_scale if source.normal_enabled else 0.0)
		result.set_shader_parameter("roughness",source.roughness)
	return remember(key,result)

static func bank(config: Dictionary, source: StandardMaterial3D) -> ShaderMaterial:
	var key:="bank:"+JSON.stringify(config)+":"+str(source.get_instance_id())
	if cache.has(key): return cached(key)
	var result:=ShaderMaterial.new(); result.shader=StreamingShader.bank()
	result.resource_name="Canal lining wetness"
	var params:={"tint":source.albedo_color,"roughness":source.roughness,"metallic":source.metallic,"normal_strength":source.normal_scale if source.normal_enabled else 0.0,"uv_scale":source.uv1_scale,"uv_offset":source.uv1_offset,"water_level":config.water_level,"wet_height":config.wet_height}
	for key_ in params: result.set_shader_parameter(key_,params[key_])
	for pair in [["rough_channel",source.roughness_texture_channel],["metal_channel",source.metallic_texture_channel],["ao_channel",source.ao_texture_channel]]:
		var mask:=Vector4.ZERO
		if pair[1]<4: mask[int(pair[1])]=1.
		else: mask=Vector4(.333333,.333333,.333333,0.)
		result.set_shader_parameter(pair[0],mask)
	for pair in [["albedo_tex","albedo_texture"],["normal_tex","normal_texture"],["rough_tex","roughness_texture"],["metal_tex","metallic_texture"],["ao_tex","ao_texture"]]: result.set_shader_parameter(pair[0],source.get(pair[1]))
	return remember(key,result)

static func _set_override(node:MeshInstance3D,slot:int,material:Material,cpu_overrides:Variant)->void:
	if cpu_overrides!=null:cpu_overrides[slot]=material
	else:node.set_surface_override_material(slot,material)

static func _active_material(node:MeshInstance3D,slot:int,cpu_overrides:Variant)->Material:
	if cpu_overrides==null:return node.get_active_material(slot)
	# Match MeshInstance3D's override precedence without requiring a mesh RID.
	if node.material_override!=null:return node.material_override
	return cpu_overrides[slot] if cpu_overrides[slot]!=null else node.mesh.surface_get_material(slot)

static func water_top(record:Dictionary,slot:int,normals:PackedVector3Array)->bool:
	if normals.is_empty():return false
	# Native profiled channels use Slab's explicit top/underside/edge slots.
	# A steep top is still water; never infer its role from the first triangle's
	# near-horizontal normal. Side and underside slots remain hidden regardless
	# of their normal. Painted meshes can reorder/merge slots, so retain their
	# existing material classification rather than assuming the native layout.
	if record.get("channel_mesh",{}).has("elevations") and not record.has("surface_paint"):
		if slot!=0:return false
		for normal:Vector3 in normals:
			if normal.y<=0:return false
		return true
	return normals[0].y>.99

static func apply(node: MeshInstance3D, record: Dictionary, context: Dictionary={},validation_cache:Variant=null,validated:bool=false,cpu_index:bool=false) -> void:
	if not record.has("terrain_depth_blend") and not record.has("terrain_slope_blend") and not record.has("terrain_regions") and not record.has("terrain_saturation") and not record.has("water_depth_effect") and not record.has("bank_wetness"): return
	if not validated and (not Data.valid(record) or not Paint.valid(record,false,"",validation_cache)): node.set_meta("paint_error","地形/河道材质参数无效"); return
	var cpu_overrides:Variant=null
	# Keep the verified CPU arrays across restore. Reading them back from the
	# newly uploaded ArrayMesh synchronizes with RenderingServer unnecessarily.
	# Existing caches are invalidated by Mesh.changed; never capture a new mesh
	# here just to inspect normals (that would read every surface back instead).
	var normal_source:Mesh=node.mesh
	if water_cpu_normals_enabled and record.has("water_depth_effect") and not normal_source is Cpu:
		normal_source=normal_source.get_meta("ground_cpu_cache",normal_source)
	if node.mesh is Cpu:
		if cpu_index and cpu_index_overrides_enabled:
			# Immutable terrain/water indexing only needs override references. Upload
			# once at actual stream spawn, not into a temporary node freed by _spec.
			cpu_overrides=[];cpu_overrides.resize(node.mesh.get_surface_count())
			# Match native Material getters' OBJECT-null, not Array.resize's NIL.
			# Zero is an invalid ObjectID: the native API returns that empty Variant
			# without allocating a node or copying an existing material_override.
			cpu_overrides.fill(instance_from_id(0))
			node.set_meta(CPU_SURFACE_OVERRIDES_META,cpu_overrides)
			cpu_index_override_count+=1
		else:
			if cpu_index:cpu_index_legacy_restore_count+=1
			var restore_started:=Time.get_ticks_usec() if Trace.enabled else 0
			node.mesh=node.mesh.restore()
			if Trace.enabled:Trace.elapsed("river.mesh_restore",restore_started,{"uuid":record.get("uuid","")})
	if record.has("terrain_depth_blend") or record.has("terrain_slope_blend") or record.has("terrain_regions") or record.has("terrain_saturation"):
		var material:=terrain(record,context)
		_set_override(node,0,material,cpu_overrides)
		for slot in range(2,node.mesh.get_surface_count()): _set_override(node,slot,material,cpu_overrides)
		# Natural exposed cut edges use the same slope rule; legacy depth-only maps stay unchanged.
		if record.has("terrain_slope_blend") or (record.has("terrain_depth_blend") and record.terrain_depth_blend.get("bank_profile","depth")=="natural"):
			for slot in range(1,node.mesh.get_surface_count()): _set_override(node,slot,material,cpu_overrides)
	if record.has("bank_wetness"):
		for slot in node.mesh.get_surface_count():
			var source: Material=_active_material(node,slot,cpu_overrides)
			if source is StandardMaterial3D: _set_override(node,slot,bank(record.bank_wetness,source),cpu_overrides)
	if record.has("water_depth_effect"):
		var project_visible:bool=water_visible_surfaces_enabled and cpu_overrides is Array and node.mesh is Cpu and node.material_override==null and node.material_overlay==null
		var visible_slots:Array[int]=[]
		if not project_visible and hidden_slab==null:
			hidden_slab=ShaderMaterial.new(); hidden_slab.shader=Shader.new()
			hidden_slab.shader.code="shader_type spatial; void fragment() { discard; }"
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Only upper faces; never shade slab undersides/vertical edges as water.
		for slot in node.mesh.get_surface_count():
			var normals_started:=Time.get_ticks_usec() if Trace.enabled else 0
			var use_cpu:=water_cpu_normals_enabled and normal_source is Cpu
			var normals: PackedVector3Array=(normal_source if use_cpu else node.mesh).surface_get_arrays(slot)[Mesh.ARRAY_NORMAL]
			if use_cpu:water_cpu_normal_hits+=1
			if Trace.enabled:Trace.elapsed("river.water_normals",normals_started,{"uuid":record.get("uuid",""),"slot":slot})
			var water_started:=Time.get_ticks_usec() if Trace.enabled else 0
			if water_top(record,slot,normals):
				_set_override(node,slot,water(record.water_depth_effect,_active_material(node,slot,cpu_overrides)),cpu_overrides)
				if project_visible:visible_slots.append(slot)
			elif not project_visible: _set_override(node,slot,hidden_slab,cpu_overrides)
			if Trace.enabled:Trace.elapsed("river.water_material",water_started,{"uuid":record.get("uuid",""),"slot":slot})
		if project_visible:_project_water_surfaces(node,visible_slots,cpu_overrides)

static func _project_water_surfaces(node:MeshInstance3D,slots:Array[int],overrides:Array)->void:
	# Only an immutable runtime directory visual reaches this path. Preserve the
	# authored solid for physics; discard-only surfaces never need a GPU mesh,
	# material RID, shader compilation, pipeline or draw call.
	var source:Mesh=node.mesh
	var visible_overrides:Array=[]
	var signature:Array=[]
	for slot:int in slots:
		visible_overrides.append(overrides[slot])
		signature.append(slot);signature.append(overrides[slot].get_instance_id())
	# A repeated placement must share the same CPU/GPU generation. Cache only
	# weak owners and scalar material IDs so it cannot pin departed materials or
	# meshes. The source is immutable; final material identity covers variants.
	var projections:Dictionary=source.get_meta(WATER_PROJECTIONS_META,{})
	var reference:WeakRef=projections.get(signature)
	var projected:Mesh=reference.get_ref() if reference!=null else null
	water_hidden_surface_skips+=source.get_surface_count()-slots.size()
	if projected==null:
		water_projection_builds+=1
		for key:Array in projections.keys():
			if projections[key].get_ref()==null:projections.erase(key)
		projected=Cpu.new();projected.bounds=source.bounds
		for slot:int in slots:
			projected.surfaces.append(source.surfaces[slot])
			projected.lods.append(source._surface_get_lods(slot))
			projected.materials.append(overrides[slot])
		preload("res://scripts/world3d/prepared_cpu_upload.gd").select_surfaces(source,projected,slots)
		projections[signature]=weakref(projected)
		source.set_meta(WATER_PROJECTIONS_META,projections)
	else:water_projection_reuses+=1
	if not node.has_meta("collision_solid"):node.set_meta("collision_solid",node.get_meta("paint_source",source))
	node.mesh=projected;node.set_meta(CPU_SURFACE_OVERRIDES_META,visible_overrides)

static func cached(key: String) -> ShaderMaterial:
	var value: ShaderMaterial=cache[key]
	cache.erase(key); cache[key]=value
	return value

static func remember(key: String,value: ShaderMaterial) -> ShaderMaterial:
	# Evict one least-recently-used entry, not every other live patch's material.
	if cache.size()>=128: cache.erase(cache.keys()[0])
	cache[key]=value
	return value
