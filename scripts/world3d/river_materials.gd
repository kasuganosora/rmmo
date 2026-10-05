extends RefCounted
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Data=preload("res://scripts/world3d/river_material_data.gd")
static var cache: Dictionary={}
static var hidden_slab: ShaderMaterial

static func bind(material: ShaderMaterial, prefix: String, definition: Dictionary,path_checks:Variant=null) -> void:
	var c: Array=definition.color
	material.set_shader_parameter(prefix+"_color",Color(c[0],c[1],c[2],c[3]))
	var tile: Array=definition.get("tile_size",[2,2])
	material.set_shader_parameter(prefix+"_tile",Vector2(tile[0],tile[1]))
	for pair in [["albedo","texture_path"],["normal","normal_path"],["rough","roughness_path"],["metal","metallic_path"],["ao","ao_path"],["height","height_path"]]:
		material.set_shader_parameter(prefix+"_"+pair[0],Paint.texture(definition,pair[1],path_checks))
	material.set_shader_parameter(prefix+"_has_height",not str(definition.get("height_path","")).is_empty())
	for pair in [["albedo","texture_path"],["rough","roughness_path"],["metal","metallic_path"],["ao","ao_path"]]:
		material.set_shader_parameter(prefix+"_has_"+pair[0],not str(definition.get(pair[1],"")).is_empty() or (pair[0]=="albedo" and definition.get("pattern","")=="checker"))
	material.set_shader_parameter(prefix+"_roughness",definition.roughness)
	material.set_shader_parameter(prefix+"_metallic",definition.get("metallic",1.0 if definition.has("metallic_path") else 0.0))
	material.set_shader_parameter(prefix+"_strength",definition.get("normal_strength",1.0) if definition.has("normal_path") else 0.0)

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
	if cache.has(key) and cache[key].get_meta("terrain_signature",[])==signature: return cached(key)
	var result:=ShaderMaterial.new(); result.shader=preload("res://scripts/world3d/river_terrain.gdshader")
	result.set_meta("terrain_signature",signature.duplicate(true))
	result.resource_name="River depth blend" if depth_enabled else ("Terrain slope blend" if record.has("terrain_slope_blend") else "Terrain PBR")
	var checks:Variant=context.get("texture_checks")
	bind(result,"base",base,checks); bind(result,"sand",config.sand_material if depth_enabled else base,checks); bind(result,"rock",config.get("rock_material",base),checks)
	bind(result,"soil",config.get("transition_material",base),checks)
	result.set_shader_parameter("transition_width",config.get("transition_width",0) if transition_enabled else 0.)
	for param in ["edge_noise","height_blend_strength"]: result.set_shader_parameter(param,config.get(param,0.))
	if transition_enabled:
		var t: Dictionary=record.terrain_mesh; var heights:=PackedFloat32Array()
		for height in t.heights: heights.append(float(height)*record.size[1])
		var image: Image=context.get("image",Image.create_from_data(int(t.columns)+1,int(t.rows)+1,false,Image.FORMAT_RF,heights.to_byte_array()))
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
		var image:Image=context.get("region_mask")
		if image==null:image=preload("res://scripts/world3d/terrain_regions.gd").mask(record)
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
		result.set_shader_parameter("normal_strength",source.normal_scale if source.normal_enabled else 0.0)
		result.set_shader_parameter("roughness",source.roughness)
	return remember(key,result)

static func bank(config: Dictionary, source: StandardMaterial3D) -> ShaderMaterial:
	var key:="bank:"+JSON.stringify(config)+":"+str(source.get_instance_id())
	if cache.has(key): return cached(key)
	var result:=ShaderMaterial.new(); result.shader=preload("res://scripts/world3d/river_bank.gdshader")
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

static func apply(node: MeshInstance3D, record: Dictionary, context: Dictionary={},validation_cache:Variant=null,validated:bool=false) -> void:
	if not record.has("terrain_depth_blend") and not record.has("terrain_slope_blend") and not record.has("terrain_regions") and not record.has("terrain_saturation") and not record.has("water_depth_effect") and not record.has("bank_wetness"): return
	if not validated and (not Data.valid(record) or not Paint.valid(record,false,"",validation_cache)): node.set_meta("paint_error","地形/河道材质参数无效"); return
	# Cooked source geometry is CPU-only. Instance material overrides require a
	# real mesh RID with surface slots, even during immutable runtime indexing.
	if node.mesh.get_script()==preload("res://scripts/world3d/ground_cpu_mesh.gd"):
		node.mesh=node.mesh.restore()
	if record.has("terrain_depth_blend") or record.has("terrain_slope_blend") or record.has("terrain_regions") or record.has("terrain_saturation"):
		var material:=terrain(record,context)
		node.set_surface_override_material(0,material)
		for slot in range(2,node.mesh.get_surface_count()): node.set_surface_override_material(slot,material)
		# Natural exposed cut edges use the same slope rule; legacy depth-only maps stay unchanged.
		if material.get_shader_parameter("slope_aware"):
			for slot in range(1,node.mesh.get_surface_count()): node.set_surface_override_material(slot,material)
	if record.has("bank_wetness"):
		for slot in node.mesh.get_surface_count():
			var source: Material=node.get_active_material(slot)
			if source is StandardMaterial3D: node.set_surface_override_material(slot,bank(record.bank_wetness,source))
	if record.has("water_depth_effect"):
		if hidden_slab==null:
			hidden_slab=ShaderMaterial.new(); hidden_slab.shader=Shader.new()
			hidden_slab.shader.code="shader_type spatial; void fragment() { discard; }"
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Only horizontal upper faces; never shade slab undersides/vertical edges as water.
		for slot in node.mesh.get_surface_count():
			var normals: PackedVector3Array=node.mesh.surface_get_arrays(slot)[Mesh.ARRAY_NORMAL]
			if not normals.is_empty() and normals[0].y>.99:
				node.set_surface_override_material(slot,water(record.water_depth_effect,node.get_active_material(slot)))
			else: node.set_surface_override_material(slot,hidden_slab)

static func cached(key: String) -> ShaderMaterial:
	var value: ShaderMaterial=cache[key]
	cache.erase(key); cache[key]=value
	return value

static func remember(key: String,value: ShaderMaterial) -> ShaderMaterial:
	# Evict one least-recently-used entry, not every other live patch's material.
	if cache.size()>=128: cache.erase(cache.keys()[0])
	cache[key]=value
	return value
