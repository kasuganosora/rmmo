extends RefCounted
## Authored response only. Never infer flexibility from a material or file name.
const Schema = preload("res://scripts/world3d/document_schema.gd")
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const GROUP := "world3d_wind_receivers"

static func schema() -> Dictionary:
	return {"type":"object", "additionalProperties":false, "properties":{
		"profile":{"type":"string","enum":["off","foliage","cloth"]},
		"mesh":{"type":"string","maxLength":512},
		"amplitude":Schema.number(0,1.5), "stiffness":Schema.number(0,1),
		"anchor":{"type":"string","enum":["bottom","top","left","right"]},
		"shelter":{"type":"boolean"}}}

static func defaults() -> Dictionary:
	return {"profile":"off", "mesh":"*", "amplitude":.35, "stiffness":.5, "anchor":"bottom", "shelter":true}

static func resolve(record: Dictionary) -> Dictionary:
	return defaults().merged(record.get("wind_response",{}),true)

static func valid(record: Dictionary) -> bool:
	if not record.has("wind_response"): return true
	return record.get("kind") in ["box","asset"] and not record.has("building") and not record.has("tile3d") and Schema.validate(record.wind_response,schema()).is_empty()

static func material_error(material: Material) -> String:
	if material == null: return ""
	if not material is StandardMaterial3D: return "仅支持 StandardMaterial3D；自定义着色器 / ORM 材质需单独适配风场"
	if material.next_pass != null or material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED: return "多 Pass 或公告板材质暂不支持受风"
	if material.transparency not in [BaseMaterial3D.TRANSPARENCY_DISABLED,BaseMaterial3D.TRANSPARENCY_ALPHA,BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]: return "此透明模式暂不支持受风"
	if material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX: return "逐顶点光照材质暂不支持受风"
	if material.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY or material.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX: return "此漫反射 / 高光模型暂不支持受风"
	if material.blend_mode != BaseMaterial3D.BLEND_MODE_MIX or material.no_depth_test or material.disable_receive_shadows or material.disable_ambient_light: return "此混合 / 深度 / 光照设置暂不支持受风"
	if material.ao_on_uv2 or material.emission_on_uv2: return "第二套 UV 的 AO / 自发光暂不支持受风"
	for feature in ["uv1_triplanar","uv2_triplanar","detail_enabled","heightmap_enabled","refraction_enabled","rim_enabled","clearcoat_enabled","subsurf_scatter_enabled","backlight_enabled","grow_enabled","proximity_fade_enabled"]:
		if material.get(feature): return "材质特性 %s 暂不支持受风" % feature
	if material.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED: return "距离淡出材质暂不支持受风"
	return ""

static func mesh_error(node: MeshInstance3D) -> String:
	if node.skin != null or (node.mesh is ArrayMesh and node.mesh.get_blend_shape_count() > 0): return "骨骼 / 变形网格已有动画，不能叠加此地图风变形"
	if node.mesh.get_surface_count() > 32: return "单网格最多支持 32 个材质槽"
	for slot in node.mesh.get_surface_count():
		var error := material_error(base_material(node,slot))
		if not error.is_empty(): return error
	return ""

static func base_material(node: MeshInstance3D, slot: int) -> Material:
	# Wind preview is an instance-only override. Authoring reads the original material.
	return Paint.source_material(node,slot)

static func catalog(root: Node3D) -> Array:
	var rows: Array = []
	if root == null: return rows
	for node in Paint.meshes(root):
		var reason := mesh_error(node)
		rows.append({"mesh":str(root.get_path_to(node)), "supported":reason.is_empty(), "reason":reason})
	return rows

static func validate_target(root: Node3D, config: Dictionary) -> String:
	var count := 0
	for node in Paint.meshes(root):
		if config.mesh != "*" and str(root.get_path_to(node)) != config.mesh: continue
		count += 1
		var error := mesh_error(node)
		if not error.is_empty(): return str(root.get_path_to(node))+"："+error
		var axis := 1 if config.anchor in ["top","bottom"] else 0
		if node.get_aabb().size[axis] < .001: return "固定轴没有长度，请更换固定边或网格"
	return "未找到此物件内的网格" if count == 0 else ""

static func annotate(root: Node3D, record: Dictionary) -> void:
	if not valid(record): return
	var config := resolve(record)
	if config.profile == "off": return
	for node in Paint.meshes(root):
		if config.mesh != "*" and str(root.get_path_to(node)) != config.mesh: continue
		var extras: Dictionary = node.get_meta("extras",{}).duplicate(true)
		extras.rmmo_wind = config.duplicate(true)
		node.set_meta("extras",extras)
		register(node)

static func register(node: MeshInstance3D) -> void:
	var config: Variant = node.get_meta("extras",{}).get("rmmo_wind")
	if config is Dictionary and Schema.validate(config,schema()).is_empty() and config.get("profile","off") != "off": node.add_to_group(GROUP)
