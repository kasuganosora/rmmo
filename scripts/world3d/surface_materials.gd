extends RefCounted
## Paint is record data. Rebuild an instance mesh; never mutate shared source assets.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const CpuMesh = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const MAX_TRIANGLES := 50000
const MAX_OVERRIDES := 128
const MAP_FIELDS := ["texture_path", "normal_path", "roughness_path", "metallic_path", "ao_path", "height_path"]
static var _textures := {}
static var prepared_images:Dictionary={}
static var _materials := {}

static func prepare_images(images:Dictionary)->void:
	var changed:=false
	for key in images:
		if _textures.has(key) and _textures[key].get_meta("runtime_source_sha256","")!=images[key].get_meta("runtime_source_sha256",""):
			_textures.erase(key);changed=true
	if changed:_materials.clear()
	prepared_images.merge(images,true)

static func fail(message: String) -> Dictionary: return {"ok": false, "error": message}

static func numbers(value: Variant, count: int, low: float, high: float) -> bool:
	if not value is Array or value.size() != count: return false
	for n in value:
		if not (n is int or n is float) or not is_finite(float(n)) or n < low or n > high: return false
	return true

static func material_valid(value: Variant, relative: bool = false, content_root: String = "", validation_cache: Variant = null) -> bool:
	# Callers may share this only within one immutable document validation.
	# Never persist it across loads, edits, or filesystem operations.
	if validation_cache==null: validation_cache={}
	var cache_key:Array=[relative,content_root,value]
	if validation_cache.has(cache_key): return true
	if not value is Dictionary or not value.get("name") is String: return false
	if not numbers(value.get("color"), 4, 0, 1) or not numbers([value.get("roughness")], 1, 0, 1): return false
	if value.get("pattern", "") not in ["", "checker"]: return false
	if value.get("normal_format", "opengl") not in ["opengl", "directx"]: return false
	if not numbers([value.get("normal_strength", 1.0)], 1, 0, 4): return false
	if not numbers([value.get("metallic", 0.0)], 1, 0, 1): return false
	if not numbers(value.get("tile_size", [1.0, 1.0]), 2, 0.01, 100): return false
	for field in MAP_FIELDS:
		var path: Variant = value.get(field, "")
		if not path is String: return false
		if path.is_empty(): continue
		if path.get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp"]: return false
		if not Paths.allowed(path,content_root) and not (relative and not path.is_absolute_path() and not path.contains(":") and not ".." in path.replace("\\", "/").split("/")): return false
	validation_cache[cache_key]=true
	return true

static func valid(record: Dictionary, relative: bool = false, content_root: String = "", validation_cache: Variant = null, immutable_paint_id:Variant=null) -> bool:
	if record.has("road_kerb_material"):
		if not record.get("road_mesh",{}).has("kerbs") or not material_valid(record.road_kerb_material,relative,content_root,validation_cache):return false
		if record.road_kerb_material.color[3]!=1:return false
	if not preload("res://scripts/world3d/rock_bank_mesh.gd").valid(record):return false
	for definition in record.get("rock_bank_materials",{}).values():
		if not material_valid(definition,relative,content_root,validation_cache):return false
		if definition.color[3]!=1:return false
	if validation_cache==null: validation_cache={}
	if not preload("res://scripts/world3d/streetlamp_banner.gd").valid(record):return false
	if record.has("banner") and not material_valid(record.banner.get("material"),relative,content_root,validation_cache):return false
	if record.has("fortification_art"):
		if not record.get("fortification_materials") is Dictionary or record.fortification_materials.size()!=4: return false
		for role in ["stone","trim","door","iron"]:
			if not material_valid(record.fortification_materials.get(role),relative,content_root,validation_cache): return false
			if record.fortification_materials[role].color[3]!=1: return false
	elif record.has("fortification_materials"): return false
	if not preload("res://scripts/world3d/bridge_data.gd").valid(record): return false
	if record.has("bridge_mesh"):
		if not record.get("bridge_materials") is Dictionary or record.bridge_materials.size()!=3: return false
		for role in ["deck","masonry","trim"]:
			if not material_valid(record.bridge_materials.get(role),relative,content_root,validation_cache): return false
			if record.bridge_materials[role].color[3]!=1: return false
	if not preload("res://scripts/world3d/river_material_data.gd").valid(record): return false
	if not preload("res://scripts/world3d/terrain_regions.gd").valid(record): return false
	if preload("res://scripts/world3d/terrain_furrows.gd").maximum_height(record)>0:
		if not preload("res://scripts/world3d/terrain_surface.gd").valid(record): return false
		if not preload("res://scripts/world3d/terrain_furrows.gd").generate(record).ok: return false
	if record.has("terrain_saturation") and (not record.has("terrain_mesh") or not numbers([record.terrain_saturation],1,0,1)): return false
	if record.has("terrain_saturation") and record.has("surface_paint"): return false
	for definition in record.get("terrain_regions",{}).get("materials",[]):
		if not material_valid(definition,relative,content_root,validation_cache) or definition.color[3]!=1: return false
	if record.has("terrain_depth_blend"):
		for key in ["sand_material","rock_material"]:
			if not material_valid(record.terrain_depth_blend[key],relative,content_root,validation_cache): return false
			if record.terrain_depth_blend[key].color[3]!=1: return false
	if record.has("terrain_material") and not material_valid(record.terrain_material,relative,content_root,validation_cache): return false
	if record.has("terrain_slope_blend"):
		if not material_valid(record.terrain_slope_blend.rock_material,relative,content_root,validation_cache) or record.terrain_slope_blend.rock_material.color[3]!=1: return false
	for field in ["terrain_depth_blend","terrain_slope_blend"]:
		if record.get(field,{}).has("transition_material"):
			var definition: Variant=record[field].transition_material
			if not material_valid(definition,relative,content_root,validation_cache) or definition.color[3]!=1: return false
	if (record.has("terrain_depth_blend") or record.has("terrain_slope_blend") or record.has("terrain_regions") or record.has("terrain_saturation")) and record.has("terrain_material") and record.terrain_material.color[3]!=1: return false
	# Cache only the repeated face-paint portion, after all terrain/bridge/river
	# constraints above. Caller cache lifetime is one immutable operation.
	# MapMetadataCache can supply its operation-local paint table index. That
	# avoids deeply hashing the same shared array once for every wall fragment.
	var paint_key:Array=["paint_record",relative,content_root,record.has("bank_wetness"),immutable_paint_id if immutable_paint_id!=null else record.get("surface_paint",[])]
	if validation_cache.has(paint_key):return true
	var entries: Variant = record.get("surface_paint", [])
	if not entries is Array or entries.size() > MAX_OVERRIDES: return false
	var seen := {}
	var checked_materials: Array = []
	for entry in entries:
		if not entry is Dictionary or not entry.get("mesh") is String or not entry.get("geometry") is String: return false
		if not numbers([entry.get("surface"), entry.get("face")], 2, 0, 1000000): return false
		if entry.surface != floor(entry.surface) or entry.face != floor(entry.face): return false
		var definition: Variant = entry.get("material")
		if not definition in checked_materials:
			if not material_valid(definition, relative, content_root,validation_cache): return false
			checked_materials.append(definition)
		if record.has("bank_wetness") and definition.color[3]!=1: return false
		if not numbers(entry.get("scale"), 2, 0.01, 100) or not numbers(entry.get("offset"), 2, -100, 100): return false
		if not numbers([entry.get("rotation")], 1, -3600, 3600) or entry.get("mapping") not in ["planar", "uv", "meters"]: return false
		var key := face_key(entry)
		if seen.has(key): return false
		seen[key] = true
	validation_cache[paint_key]=true
	return true

static func face_key(entry: Dictionary) -> String:
	return "%s|%d|%d" % [entry.mesh, entry.surface, entry.face]

static func meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root.get_meta("editor_shadow_proxy",false):return result
	if root is MeshInstance3D and root.mesh != null: result.append(root)
	for child in root.get_children(): result.append_array(meshes(child))
	return result

static func source(node: MeshInstance3D) -> Mesh:
	return node.get_meta("paint_source", node.mesh)

static func _root_of(parents: PackedInt32Array, at: int) -> int:
	while parents[at] != at: at = parents[at]
	return at

static func _vertex_key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 100000), roundi(point.y * 100000), roundi(point.z * 100000)]

static func geometry(node: MeshInstance3D) -> Dictionary:
	if node.has_meta("paint_geometry"): return node.get_meta("paint_geometry")
	var mesh := source(node)
	if mesh == null or (mesh is ArrayMesh and mesh.get_blend_shape_count() > 0) or node.skin != null: return fail("蒙皮或变形模型暂不支持表面绘制")
	if mesh.get_surface_count() > 128: return fail("模型材质槽超过 128 个")
	var surfaces: Array = []
	for slot in mesh.get_surface_count():
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(slot) != Mesh.PRIMITIVE_TRIANGLES: return fail("仅支持三角网格表面")
		var arrays: Array = mesh.get_meta("ground_cpu_cache").surfaces[slot] if mesh.has_meta("ground_cpu_cache") else CpuMesh.primitive_arrays(mesh,slot)
		if arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_BONES].size() > 0: return fail("蒙皮模型暂不支持表面绘制")
		for channel in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM3 + 1):
			if arrays[channel] != null and arrays[channel].size() > 0: return fail("含自定义顶点通道的模型暂不支持表面绘制")
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for index in vertices.size(): indices.append(index)
		var count := indices.size() / 3
		if count > MAX_TRIANGLES or count < 1: return fail("单个材质槽需包含 1–50000 个三角面")
		var parents := PackedInt32Array()
		var normals := PackedVector3Array()
		var origins := PackedVector3Array()
		var edges := {}
		for triangle in count:
			parents.append(triangle)
			var a := vertices[indices[triangle * 3]]
			var b := vertices[indices[triangle * 3 + 1]]
			var c := vertices[indices[triangle * 3 + 2]]
			var normal := (c - a).cross(b - a).normalized()
			normals.append(normal); origins.append(a)
			var points := [_vertex_key(a), _vertex_key(b), _vertex_key(c)]
			for edge in 3:
				var x: String = points[edge]
				var y: String = points[(edge + 1) % 3]
				var key := x + ";" + y if x < y else y + ";" + x
				if edges.has(key):
					var other: int = edges[key]
					if normal.dot(normals[other]) > 0.99999 and absf(normal.dot(origins[other] - a)) < 0.0001:
						var p := _root_of(parents, triangle)
						var q := _root_of(parents, other)
						parents[maxi(p, q)] = mini(p, q)
				else: edges[key] = triangle
		var faces := {}
		for triangle in count:
			var face := _root_of(parents, triangle)
			parents[triangle] = face
			if not faces.has(face): faces[face] = {"triangles": [], "normal": normals[face], "center": Vector3.ZERO}
			faces[face].triangles.append(triangle)
			for corner in 3: faces[face].center += vertices[indices[triangle * 3 + corner]]
		for face in faces.values(): face.center /= float(face.triangles.size() * 3)
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256); hasher.update(var_to_bytes([vertices, indices]))
		var signature := "box-v1" if mesh is BoxMesh or (mesh is CpuMesh and mesh.box_size != Vector3.ZERO) else hasher.finish().hex_encode()
		surfaces.append({"arrays": arrays, "indices": indices, "face_for_triangle": parents, "faces": faces, "signature": signature})
	var result := {"ok": true, "surfaces": surfaces}
	node.set_meta("paint_geometry", result)
	return result

static func texture(material: Dictionary, field: String = "texture_path",path_checks:Variant=null) -> Texture2D:
	var path := str(material.get(field, ""))
	# A caller-owned immutable-load scope checks each path once, never across
	# separate loads or edits. Texture cache hits alone do not authorize a path.
	if not path.is_empty() and (path_checks==null or not path_checks.has(path)):
		if not Paths.allowed(path) or not FileAccess.file_exists(path):return null
		if path_checks!=null:path_checks[path]=true
	var key := path if not path.is_empty() else (str(material.get("pattern", "")) if field == "texture_path" else "")
	var flip_normal: bool = field == "normal_path" and material.get("normal_format", "opengl") == "directx"
	var cache_key := key + ("|flip_y" if flip_normal else "")
	if key.is_empty(): return null
	if _textures.has(cache_key):
		prepared_images.erase(cache_key)
		return _textures[cache_key]
	var image: Image
	if key == "checker":
		image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64: image.set_pixel(x, y, Color("cba574") if (x / 16 + y / 16) % 2 == 0 else Color("526477"))
	else:
		image = prepared_images.get(cache_key)
		prepared_images.erase(cache_key)
		if image==null:image = preload("res://scripts/world3d/runtime_texture_cache.gd").image(path,flip_normal)
		if image==null:return null
	if not image.has_mipmaps():image.generate_mipmaps()
	var has_alpha:bool=image.detect_alpha()!=Image.ALPHA_NONE
	var result := ImageTexture.create_from_image(image)
	result.set_meta("surface_has_alpha",has_alpha)
	result.set_meta("runtime_source_sha256",image.get_meta("runtime_source_sha256",""))
	if _textures.size() >= 64: _textures.erase(_textures.keys()[0])
	_textures[cache_key] = result
	return result

static func texture_error(record: Dictionary, checks: Variant = null) -> String:
	# A declared image that cannot decode must not silently become an untextured
	# material in a new export. Cache only within the caller's immutable operation.
	for definition: Dictionary in definitions(record):
		for field: String in MAP_FIELDS:
			var path: String=definition.get(field,"")
			if path.is_empty():continue
			var key: Array=["decoded_texture",path,field=="normal_path" and definition.get("normal_format","opengl")=="directx"]
			var valid_image: bool
			if checks!=null and checks.has(key):valid_image=checks[key]
			else:
				valid_image=texture(definition,field,checks)!=null
				if checks!=null:checks[key]=valid_image
			if not valid_image:return "材质贴图无法读取："+path
	return ""

static func make_material(value: Dictionary, cull_mode: int = BaseMaterial3D.CULL_BACK) -> StandardMaterial3D:
	# Paint definitions are immutable; UVs live on the mesh. Reuse equivalent
	# materials so glTF packs ORM textures once, not once for every wall face.
	var key := str(cull_mode) + "|" + JSON.stringify(value, "", true)
	if _materials.has(key): return _materials[key]
	var result := StandardMaterial3D.new()
	result.cull_mode = cull_mode
	result.resource_name = value.name
	result.albedo_color = Color(value.color[0], value.color[1], value.color[2], value.color[3])
	result.roughness = value.roughness
	result.albedo_texture = texture(value)
	result.normal_texture = texture(value, "normal_path")
	result.normal_enabled = result.normal_texture != null
	result.normal_scale = float(value.get("normal_strength", 1.0))
	result.roughness_texture = texture(value, "roughness_path")
	result.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	result.metallic_texture = texture(value, "metallic_path")
	result.metallic = float(value.get("metallic", 1.0 if result.metallic_texture != null else 0.0))
	result.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	result.ao_texture = texture(value, "ao_path")
	result.ao_enabled = result.ao_texture != null
	result.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	result.texture_repeat = true
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if result.albedo_color.a < 1 or (result.albedo_texture != null and bool(result.albedo_texture.get_meta("surface_has_alpha",false))): result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if _materials.size() >= 128: _materials.erase(_materials.keys()[0])
	result.set_meta("runtime_paint_definition",value.duplicate(true))
	_materials[key] = result
	return result

static func _uvs(data: Dictionary, entry: Dictionary) -> PackedVector2Array:
	var vertices: PackedVector3Array = data.arrays[Mesh.ARRAY_VERTEX]
	var uv := PackedVector2Array()
	var face: Dictionary = data.faces[int(entry.face)]
	var normal: Vector3 = face.normal
	var u := (Vector3.RIGHT - normal * normal.x).normalized() if absf(normal.x) < 0.9 else (Vector3.BACK - normal * normal.z).normalized()
	var v := normal.cross(u).normalized()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for triangle in face.triangles:
		for corner in 3:
			var vertex := vertices[data.indices[triangle * 3 + corner]]
			var point := Vector2(vertex.dot(u), vertex.dot(v))
			low = low.min(point); high = high.max(point)
	var dimensions := (high - low).max(Vector2(0.00001, 0.00001))
	var original: Variant = data.arrays[Mesh.ARRAY_TEX_UV]
	for i in vertices.size():
		var point: Vector2 = original[i] if entry.mapping == "uv" and original != null and original.size() == vertices.size() else (Vector2(vertices[i].dot(u), vertices[i].dot(v)) - low) / dimensions
		if entry.mapping == "meters":
			var tile: Array = entry.material.get("tile_size", [1.0, 1.0])
			point = (Vector2(vertices[i].dot(u), vertices[i].dot(v)) - low) / Vector2(tile[0], tile[1])
		point = (point - Vector2(0.5, 0.5)).rotated(deg_to_rad(entry.rotation)) * Vector2(entry.scale[0], entry.scale[1]) + Vector2(0.5 + entry.offset[0], 0.5 + entry.offset[1])
		uv.append(point)
	return uv

static func _compact(arrays: Array) -> Array:
	# Keep only referenced vertices; each painted face must not duplicate the whole model.
	var old_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var unique := PackedInt32Array()
	var indices := PackedInt32Array()
	var remap := {}
	for old in old_indices:
		if not remap.has(old): remap[old] = unique.size(); unique.append(old)
		indices.append(remap[old])
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var result := arrays.duplicate()
	for channel in Mesh.ARRAY_INDEX:
		var values: Variant = arrays[channel]
		if values == null or values.size() == 0: continue
		var stride: int = values.size() / count
		var packed: Variant = values.slice(0, 0)
		for old in unique:
			for component in stride: packed.append(values[old * stride + component])
		result[channel] = packed
	result[Mesh.ARRAY_INDEX] = indices
	return result

static func source_material(node: MeshInstance3D, slot: int) -> Material:
	# Runtime wind is a temporary instance override, never an authored paint source.
	if node.has_meta("wind_original"):
		var original: Dictionary = node.get_meta("wind_original")
		if original.override != null: return original.override
		if original.surfaces[slot] != null: return original.surfaces[slot]
		return node.mesh.surface_get_material(slot)
	return node.get_active_material(slot)

static func painted_mesh(node: MeshInstance3D, entries: Array, keep_cpu: bool=false, texture_checks: Variant=null) -> Dictionary:
	if keep_cpu: CpuMesh.capture(source(node))
	var geo := geometry(node)
	if not geo.ok: return geo
	var mesh := source(node)
	var overrides := {}
	var checked_materials: Array = []
	for entry in entries:
		var slot := int(entry.surface)
		if slot >= geo.surfaces.size() or not geo.surfaces[slot].faces.has(int(entry.face)) or geo.surfaces[slot].signature != entry.geometry: return fail("模型几何已改变，请先清除旧面材质再重新绘制")
		# The optional cache belongs to one immutable runtime load. Ordinary
		# editor paint operations still check paths/textures afresh every time.
		if not entry.material in checked_materials:
			var material_key:=var_to_str(entry.material)
			if texture_checks==null or not texture_checks.has(material_key):
				for field in MAP_FIELDS:
					if not str(entry.material.get(field, "")).is_empty() and texture(entry.material, field) == null: return fail("表面贴图缺失或损坏：" + field)
				if texture_checks!=null: texture_checks[material_key]=true
			checked_materials.append(entry.material)
		var source_uv: Variant = geo.surfaces[slot].arrays[Mesh.ARRAY_TEX_UV]
		if entry.mapping == "uv" and (source_uv == null or source_uv.size() != geo.surfaces[slot].arrays[Mesh.ARRAY_VERTEX].size()): return fail("这个模型没有原始 UV，请选择平面投影")
		overrides["%d:%d" % [slot, entry.face]] = entry
	if mesh.get_surface_count() + entries.size() > 256: return fail("绘制后材质槽超过 256 个，请拆分模型")
	var output := ArrayMesh.new()
	var cpu_arrays: Array=[]
	var merged:Dictionary={}
	for slot in mesh.get_surface_count():
		var data: Dictionary = geo.surfaces[slot]
		var groups := {}
		var group_entries := {}
		var face_groups := {}
		# Original UV mapping is independent of the face plane. Identical UV
		# paint can share a draw surface while retaining per-face authoring data.
		# Curved walls otherwise export thousands of identical material slots.
		for face in data.faces:
			var face_key := "%d:%d" % [slot, face]
			if not overrides.has(face_key): continue
			var entry: Dictionary = overrides[face_key]
			var group_key := face_key
			if entry.mapping == "uv": group_key = "uv:" + JSON.stringify([entry.material, entry.scale, entry.offset, entry.rotation], "", true)
			face_groups[face_key] = group_key
			group_entries[group_key] = entry
		for triangle in data.face_for_triangle.size():
			var face: int = data.face_for_triangle[triangle]
			var key := "%d:%d" % [slot, face]
			key = face_groups.get(key, "original")
			if not groups.has(key): groups[key] = PackedInt32Array()
			for corner in 3: groups[key].append(data.indices[triangle * 3 + corner])
		for key in groups:
			var arrays: Array = data.arrays.duplicate()
			arrays[Mesh.ARRAY_INDEX] = groups[key]
			var material: Material = node.get_meta("paint_source_materials")[slot] if node.has_meta("paint_source_materials") else source_material(node,slot)
			if key != "original":
				arrays[Mesh.ARRAY_TEX_UV] = _uvs(data, group_entries[key])
				# Painted diffuse UVs differ from the source normal-map tangent space.
				arrays[Mesh.ARRAY_TANGENT] = null
				var painted := make_material(group_entries[key].material, material.cull_mode if material is BaseMaterial3D else BaseMaterial3D.CULL_BACK)
				material = painted
			var compact := _compact(arrays)
			if key != "original" and material is BaseMaterial3D and material.normal_enabled:
				# SurfaceTool reads Mesh arrays. Keep this temporary on the CPU:
				# uploading then reading every painted face stalls the render queue.
				var temporary := CpuMesh.new()
				temporary.surfaces = [compact]
				temporary.materials = [material]
				var builder := SurfaceTool.new()
				builder.create_from(temporary, 0); builder.generate_tangents()
				compact = builder.commit_to_arrays()
			# UVs/tangents are already baked per face. Their identical materials
			# now share one GPU surface instead of allocating a RID for every face.
			var layout:=0
			for channel in Mesh.ARRAY_MAX:
				if compact[channel]!=null and not compact[channel].is_empty():layout|=1<<channel
			var merge_key:=str(material.get_instance_id() if material!=null else 0)+":"+str(layout)
			if not merged.has(merge_key):merged[merge_key]={"builder":SurfaceTool.new(),"material":material}
			var cpu:=CpuMesh.new();cpu.surfaces=[compact];cpu.materials=[material]
			merged[merge_key].builder.append_from(cpu,0,Transform3D.IDENTITY)
	for row in merged.values():
		var arrays:Array=row.builder.commit_to_arrays()
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		output.surface_set_material(output.get_surface_count()-1,row.material)
		if keep_cpu:cpu_arrays.append(arrays)
	if keep_cpu: CpuMesh.remember(output,cpu_arrays)
	return {"ok": true, "mesh": output}

static func apply(root: Node3D, record: Dictionary, validation_cache: Variant=null, texture_checks: Variant=null) -> void:
	if not record.has("surface_paint"): return
	if not valid(record,false,"",validation_cache): root.set_meta("paint_error", "表面材质记录损坏"); return
	var unresolved: Array = record.surface_paint.duplicate()
	for node in meshes(root):
		var path := str(root.get_path_to(node))
		var entries: Array = record.surface_paint.filter(func(entry): return entry.mesh == path)
		if entries.is_empty(): continue
		for entry in entries: unresolved.erase(entry)
		var result := painted_mesh(node, entries, true, texture_checks)
		if not result.ok: root.set_meta("paint_error", result.error); continue
		var originals: Array = []
		for slot in node.mesh.get_surface_count(): originals.append(source_material(node,slot))
		node.set_meta("paint_source_materials", originals)
		node.set_meta("paint_source", node.mesh)
		node.mesh = result.mesh
		node.material_override = null
		for slot in node.get_surface_override_material_count(): node.set_surface_override_material(slot, null)
	if not unresolved.is_empty(): root.set_meta("paint_error", "模型节点已改变，请清除旧面材质")

static func definitions(record: Dictionary, include_paint:bool=true) -> Array:
	if record.has("house_prefab"):
		var definitions_:Array=record.get("prefab_materials",[]).duplicate()
		if include_paint:
			for entry in record.get("surface_paint",[]):definitions_.append(entry.material)
		return definitions_
	var result: Array=[]
	if record.has("road_kerb_material"):result.append(record.road_kerb_material)
	if record.has("banner"):result.append(record.banner.material)
	result.append_array(record.get("bridge_materials",{}).values())
	result.append_array(record.get("rock_bank_materials",{}).values())
	result.append_array(record.get("fortification_materials",{}).values())
	result.append_array(record.get("terrain_regions",{}).get("materials",[]))
	if include_paint:
		for entry in record.get("surface_paint",[]): result.append(entry.material)
	if record.has("terrain_material"): result.append(record.terrain_material)
	if record.has("terrain_depth_blend"):
		for key in ["sand_material","rock_material"]: result.append(record.terrain_depth_blend[key])
	if record.has("terrain_slope_blend"): result.append(record.terrain_slope_blend.rock_material)
	for field in ["terrain_depth_blend","terrain_slope_blend"]:
		if record.get(field,{}).has("transition_material"): result.append(record[field].transition_material)
	return result

static func missing(records: Array) -> Array:
	var paths: Array = []
	var checked:Dictionary={}
	for record in records:
		if record.has("fortification_art"):
			var model_path:String=record.fortification_art.asset_path
			if not checked.has(model_path):checked[model_path]=FileAccess.file_exists(model_path)
			if not checked[model_path]:paths.append(model_path)
		for definition in definitions(record):
			for field in MAP_FIELDS:
				var path := str(definition.get(field, ""))
				if path.is_empty():continue
				if not checked.has(path):checked[path]=FileAccess.file_exists(path)
				if not checked[path] and not paths.has(path):paths.append(path)
	return paths

static func _face_shape(data: Dictionary, face: int) -> Array:
	# Import/export can reorder or weld vertices. Compare actual triangles at fixed precision.
	var triangles: Array = []
	var vertices: PackedVector3Array = data.arrays[Mesh.ARRAY_VERTEX]
	for triangle in data.faces[face].triangles:
		var points: Array = []
		for corner in 3: points.append(_vertex_key(vertices[data.indices[triangle * 3 + corner]]))
		points.sort(); triangles.append(";".join(points))
	triangles.sort()
	return triangles

static func remap(entries: Array, before: Node3D, after: Node3D) -> Dictionary:
	var result: Array = []
	var old_meshes := {}; var new_meshes := {}
	for node in meshes(before): old_meshes[str(before.get_path_to(node))] = node
	for node in meshes(after): new_meshes[str(after.get_path_to(node))] = node
	for entry in entries:
		if not old_meshes.has(entry.mesh) or not new_meshes.has(entry.mesh): return fail("打包模型的节点结构改变，无法匹配已绘制表面")
		var old_geo := geometry(old_meshes[entry.mesh])
		var new_geo := geometry(new_meshes[entry.mesh])
		if not old_geo.ok or not new_geo.ok: return fail("模型网格不支持材质重映射")
		var slot := int(entry.surface)
		if slot >= old_geo.surfaces.size() or not old_geo.surfaces[slot].faces.has(int(entry.face)) or old_geo.surfaces[slot].signature != entry.geometry: return fail("原模型表面已变化")
		var old_data: Dictionary = old_geo.surfaces[slot]
		var shape := _face_shape(old_data, int(entry.face))
		var matches: Array = []
		for new_slot in new_geo.surfaces.size():
			var data: Dictionary = new_geo.surfaces[new_slot]
			for face in data.faces:
				if data.faces[face].triangles.size() != old_data.faces[int(entry.face)].triangles.size(): continue
				if data.faces[face].normal.dot(old_data.faces[int(entry.face)].normal) < 0.99999: continue
				if _face_shape(data, face) == shape: matches.append({"surface": new_slot, "face": face, "geometry": data.signature})
		if matches.size() != 1: return fail("打包模型的表面匹配不唯一，预制件未保存")
		var copy: Dictionary = entry.duplicate(true)
		copy.merge(matches[0], true)
		result.append(copy)
	return {"ok": true, "entries": result}
