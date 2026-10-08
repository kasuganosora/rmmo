extends RefCounted
## Read-only source accessor bounds, not an importer or vertex-buffer validator.
## Unknown is deliberately eager. No nodes, image decoding, or resource caches.
const MAX_JSON := 4 * 1024 * 1024
const MAX_NODES := 65536
const MAX_COORD := 1.0e12
const MATERIAL_EXTENSIONS := ["KHR_materials_specular", "KHR_materials_transmission", "KHR_materials_unlit", "KHR_materials_emissive_strength", "KHR_materials_pbrSpecularGlossiness"]

static func unknown(reason: String) -> Dictionary:
	return {"known": false, "reason": reason}

static func read(path: String, record: Dictionary = {}) -> Dictionary:
	var started := Time.get_ticks_usec()
	if path.get_extension().to_lower() != "glb": return unknown("not_glb")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 28: return unknown("missing_or_short")
	var length := file.get_length()
	if file.get_32() != 0x46546c67 or file.get_32() != 2 or file.get_32() != length: return unknown("glb_header")
	var json_size := file.get_32()
	if file.get_32() != 0x4e4f534a or json_size < 4 or json_size > MAX_JSON or json_size % 4 != 0 or json_size + 28 > length: return unknown("json_chunk")
	var bytes := file.get_buffer(json_size)
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary: return unknown("json")
	var bin_size := file.get_32()
	if file.get_32() != 0x004e4942 or bin_size % 4 != 0 or file.get_position() + bin_size != length: return unknown("bin_chunk")
	var result := from_json(json.data, bin_size)
	var hash_ := HashingContext.new(); hash_.start(HashingContext.HASH_SHA256); hash_.update(bytes)
	result.json_sha256 = hash_.finish().hex_encode()
	result.path = path
	result.file_length = length
	result.json_bytes = json_size
	result.elapsed_us = Time.get_ticks_usec() - started
	if result.known and not record.is_empty(): return apply_record(result, record)
	return result

static func from_json(data: Dictionary, bin_size: int) -> Dictionary:
	if not data.get("asset") is Dictionary or data.asset.get("version") != "2.0": return unknown("asset_version")
	if has_native_identity(data): return unknown("native_map_identity")
	if not _extension_safe(data): return unknown("uri_or_extension")
	for key in ["skins", "animations"]:
		if data.has(key) and (not data[key] is Array or not data[key].is_empty()): return unknown("deformed_or_animated")
	var buffers: Variant = data.get("buffers")
	if not buffers is Array or buffers.size() != 1 or not buffers[0] is Dictionary: return unknown("buffers")
	var size: Variant = buffers[0].get("byteLength")
	if not _uint(size) or size <= 0 or size > bin_size or bin_size - int(size) > 3: return unknown("buffer_length")
	var nodes: Variant = data.get("nodes")
	var meshes: Variant = data.get("meshes")
	var accessors: Variant = data.get("accessors")
	var views: Variant = data.get("bufferViews")
	var scenes: Variant = data.get("scenes")
	if not nodes is Array or nodes.is_empty() or nodes.size() > MAX_NODES: return unknown("nodes")
	if not meshes is Array or not accessors is Array or not views is Array or not scenes is Array or scenes.is_empty(): return unknown("arrays")
	for view in views:
		if not view is Dictionary or not _index(view.get("buffer"),1) or not _uint(view.get("byteOffset", 0)) or not _uint(view.get("byteLength")): return unknown("buffer_view")
		if view.byteLength <= 0 or view.get("byteOffset", 0) > size or view.byteLength > size - view.get("byteOffset", 0): return unknown("buffer_view_range")
	var mesh_boxes: Array[AABB] = []
	for mesh in meshes:
		if not mesh is Dictionary or mesh.has("weights") or not mesh.get("primitives") is Array or mesh.primitives.is_empty(): return unknown("mesh_or_morph")
		var merged := AABB(); var first := true
		for primitive in mesh.primitives:
			if not primitive is Dictionary or primitive.has("targets") or not primitive.get("attributes") is Dictionary: return unknown("primitive_or_morph")
			if not _index(primitive.get("mode",4),7): return unknown("primitive_mode")
			var index: Variant = primitive.attributes.get("POSITION")
			if not _index(index, accessors.size()): return unknown("position_accessor")
			var bounds := _accessor_bounds(accessors[int(index)], views)
			if not bounds.known: return bounds
			merged = bounds.bounds if first else merged.merge(bounds.bounds)
			first = false
		mesh_boxes.append(merged)
	var parents := PackedInt32Array(); parents.resize(nodes.size()); parents.fill(-1)
	var transforms: Array[Transform3D] = []
	for i in nodes.size():
		var node: Variant = nodes[i]
		if not node is Dictionary or node.has("skin") or node.has("weights"): return unknown("node_or_deformation")
		for key in node:
			if key not in ["name", "children", "mesh", "matrix", "translation", "rotation", "scale", "extras", "extensions"]: return unknown("unknown_node_field")
		var pose := _node_transform(node)
		if not pose.known: return pose
		transforms.append(pose.transform)
		if node.has("mesh") and not _index(node.mesh, meshes.size()): return unknown("mesh_index")
		var children: Variant = node.get("children", [])
		if not children is Array: return unknown("children")
		for child in children:
			if not _index(child, nodes.size()) or int(child) == i or parents[int(child)] != -1: return unknown("multiple_parent_or_child")
			parents[int(child)] = i
	var queue: Array[int] = []
	for i in nodes.size():
		if parents[i] == -1: queue.append(i)
	var walked := 0
	while walked < queue.size():
		var index := queue[walked]; walked += 1
		for child in nodes[index].get("children", []): queue.append(int(child))
	if walked != nodes.size(): return unknown("cycle")
	var scene_id: Variant = data.get("scene", 0)
	if not _index(scene_id, scenes.size()): return unknown("scene_index")
	for scene in scenes:
		if not scene is Dictionary or not scene.get("nodes", []) is Array: return unknown("scene_roots")
		var seen := {}
		for index in scene.get("nodes", []):
			if not _index(index, nodes.size()) or parents[int(index)] != -1 or seen.has(int(index)): return unknown("scene_parent_or_duplicate")
			seen[int(index)] = true
	var pending: Array = []
	for index in scenes[int(scene_id)].get("nodes", []): pending.append({"index":int(index), "parent":Transform3D.IDENTITY})
	var parts: Array = []; var total := AABB(); var first := true
	var cursor := 0
	while cursor < pending.size():
		var entry: Dictionary = pending[cursor]; cursor += 1
		var index: int = entry.index
		var transform: Transform3D = entry.parent * transforms[index]
		if not _finite_transform(transform): return unknown("transform_overflow")
		var node: Dictionary = nodes[index]
		if node.has("mesh"):
			var box: AABB = transform * mesh_boxes[int(node.mesh)]
			if not _finite_box(box): return unknown("bounds_overflow")
			parts.append({"id":"node:%d" % index, "node_index":index, "mesh_index":int(node.mesh), "transform":transform, "mesh_bounds":mesh_boxes[int(node.mesh)], "bounds":box})
			total = box if first else total.merge(box); first = false
		for child in node.get("children", []): pending.append({"index":int(child), "parent":transform})
	if first or not _finite_box(total): return unknown("empty_or_invalid_bounds")
	return {"known":true, "reason":"source_accessor_bounds", "local_bounds":total, "world_bounds":total, "mesh_nodes":parts, "scene_index":int(scene_id)}

static func apply_record(manifest: Dictionary, record: Dictionary) -> Dictionary:
	if not manifest.get("known", false): return manifest
	for field in ["house_prefab", "bridge_mesh", "tree_settings", "banner", "fixture"]:
		if record.has(field): return unknown("record_geometry_override")
	if not _vector(record.get("position"), 3) or not _vector(record.get("rotation"), 3) or not _vector(record.get("size"), 3): return unknown("record_transform")
	var basis := Basis.from_euler(_vec(record.rotation) * PI / 180.0).scaled_local(_vec(record.size))
	var pose := Transform3D(basis, _vec(record.position))
	var bounds: AABB = pose * manifest.local_bounds
	if not _finite_transform(pose) or not _finite_box(bounds): return unknown("record_overflow")
	var result := manifest.duplicate()
	result.world_bounds = bounds
	result.record_transform = pose
	# Authored cached bounds may be stale. They never decide source eligibility.
	result.authored_bounds_present = record.has("bounds_position") and record.has("bounds_size")
	return result

static func _accessor_bounds(value: Variant, views: Array) -> Dictionary:
	if not value is Dictionary or value.get("type") != "VEC3" or value.get("componentType") != 5126 or value.has("sparse") or value.get("normalized", false) != false: return unknown("position_format")
	if not _index(value.get("bufferView"), views.size()) or not _uint(value.get("count")) or value.count <= 0 or not _uint(value.get("byteOffset", 0)): return unknown("position_storage")
	if not _vector(value.get("min"), 3) or not _vector(value.get("max"), 3): return unknown("position_min_max")
	var low := _vec(value.min); var high := _vec(value.max)
	if low.x > high.x or low.y > high.y or low.z > high.z: return unknown("position_order")
	var view: Dictionary = views[int(value.bufferView)]
	var stride: Variant = view.get("byteStride", 12)
	if not _uint(stride) or stride < 12 or stride > 252 or int(stride) % 4 != 0: return unknown("position_stride")
	var offset: int = int(value.get("byteOffset", 0))
	if offset % 4 != 0 or int(view.get("byteOffset", 0)) % 4 != 0: return unknown("position_alignment")
	# Division avoids integer overflow with hostile counts.
	if offset > view.byteLength or view.byteLength - offset < 12 or value.count - 1 > (view.byteLength - offset - 12) / int(stride): return unknown("position_range")
	return {"known":true, "bounds":AABB(low, high - low)}

static func _node_transform(node: Dictionary) -> Dictionary:
	var transform := Transform3D.IDENTITY
	if node.has("matrix"):
		if node.has("translation") or node.has("rotation") or node.has("scale") or not _vector(node.matrix, 16): return unknown("matrix_trs")
		var m: Array = node.matrix
		if m[3] != 0 or m[7] != 0 or m[11] != 0 or m[15] != 1: return unknown("non_affine_matrix")
		transform = Transform3D(Basis(Vector3(m[0],m[1],m[2]),Vector3(m[4],m[5],m[6]),Vector3(m[8],m[9],m[10])),Vector3(m[12],m[13],m[14]))
	else:
		var t: Variant = node.get("translation", [0,0,0]); var r: Variant = node.get("rotation", [0,0,0,1]); var s: Variant = node.get("scale", [1,1,1])
		if not _vector(t,3) or not _vector(r,4) or not _vector(s,3): return unknown("trs")
		var rotation := Quaternion(r[0],r[1],r[2],r[3])
		if absf(rotation.length_squared() - 1.0) > .00001: return unknown("quaternion")
		transform = Transform3D(Basis(rotation.normalized()).scaled_local(_vec(s)),_vec(t))
	if not _finite_transform(transform): return unknown("transform_overflow")
	return {"known":true, "transform":transform}

static func _extension_safe(value: Variant, path: Array = []) -> bool:
	if value is Dictionary:
		for key in value:
			if key == "uri": return false
			if key in ["extensionsUsed", "extensionsRequired"]:
				if not path.is_empty(): return false
				# Native exported models can contain null declarations; no payload
				# is enabled by null (same policy as EmbeddedGlb eligibility).
				if value[key] == null: continue
				if not value[key] is Array: return false
				if key == "extensionsRequired" and not value[key].is_empty(): return false
				for extension in value[key]:
					if extension not in MATERIAL_EXTENSIONS: return false
			if key == "extensions":
				if not value[key] is Dictionary: return false
				if not value[key].is_empty():
					if path.size() != 2 or path[0] != "materials": return false
					for extension in value[key]:
						if extension not in MATERIAL_EXTENSIONS or not value[key][extension] is Dictionary: return false
			if not _extension_safe(value[key],path + [key]): return false
	elif value is Array:
		for index in value.size():
			if not _extension_safe(value[index],path + [index]): return false
	return true

## Native map extras activate Io.generate_scene's map-specific effects and
## shared material caches. They cannot use independent worker-scene creation.
static func has_native_identity(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if key in ["rmmo_format", "rmmo_records", "rmmo_storage", "rmmo_resource_dependencies"]: return true
			if has_native_identity(value[key]): return true
	elif value is Array:
		for child in value:
			if has_native_identity(child): return true
	return false

static func _uint(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 4294967295 and value == floor(float(value))
static func _index(value: Variant, count: int) -> bool: return _uint(value) and value < count
static func _vector(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > MAX_COORD: return false
	return true
static func _vec(value: Array) -> Vector3: return Vector3(value[0],value[1],value[2])
static func _finite_transform(value: Transform3D) -> bool:
	return value.is_finite() and value.origin.length() <= MAX_COORD and value.basis.x.length() <= MAX_COORD and value.basis.y.length() <= MAX_COORD and value.basis.z.length() <= MAX_COORD
static func _finite_box(value: AABB) -> bool:
	return value.position.is_finite() and value.end.is_finite() and value.size.x >= 0 and value.size.y >= 0 and value.size.z >= 0 and value.position.abs().length() <= MAX_COORD and value.end.abs().length() <= MAX_COORD
