extends RefCounted
## Stream static vertex data into one glTF buffer. Godot still serializes the
## scene graph, materials, textures, animations, skins and unsupported meshes.
## This avoids repeatedly scanning/copying the growing full-world buffer.
var originals: Dictionary = {}
var deduplicated: Dictionary = {}
var file: FileAccess
var data: Dictionary
var buffer_index := 0

func prepare(state: GLTFState) -> void:
	for index in state.meshes.size():
		var mesh: ImporterMesh = state.meshes[index].mesh
		if not supported(mesh): continue
		originals[index] = mesh
		var proxy := ImporterMesh.new()
		proxy.resource_name = mesh.resource_name
		if mesh.has_meta("extras"): proxy.set_meta("extras", mesh.get_meta("extras"))
		var triangle := []
		triangle.resize(Mesh.ARRAY_MAX)
		triangle[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.BACK])
		for slot in mesh.get_surface_count():
			proxy.add_surface(Mesh.PRIMITIVE_TRIANGLES, triangle, [], {}, mesh.get_surface_material(slot), mesh.get_surface_name(slot))
		state.meshes[index].mesh = proxy

func restore(state: GLTFState) -> void:
	for index in originals: state.meshes[index].mesh = originals[index]

static func supported(mesh: ImporterMesh) -> bool:
	if mesh == null or mesh.get_blend_shape_count() != 0 or mesh.get_surface_count() == 0: return false
	for slot in mesh.get_surface_count():
		if mesh.get_surface_primitive_type(slot) != Mesh.PRIMITIVE_TRIANGLES: return false
		var arrays := mesh.get_surface_arrays(slot)
		for channel in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_INDEX):
			if arrays[channel] != null and arrays[channel].size() != 0: return false
		var count: int = arrays[Mesh.ARRAY_VERTEX].size()
		if count < 3: return false
		for channel in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			if arrays[channel] != null and arrays[channel].size() not in [0, count]: return false
		if arrays[Mesh.ARRAY_TANGENT] != null and arrays[Mesh.ARRAY_TANGENT].size() not in [0, count * 4]: return false
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices == null or indices.is_empty():
			if count % 3 != 0: return false
		else:
			if indices.size() % 3 != 0: return false
			for i in indices:
				if i < 0 or i >= count: return false
	return true

func finish(path: String, progress: Callable = Callable()) -> Error:
	if originals.is_empty(): return OK
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return ERR_FILE_CORRUPT
	data = parsed
	var name := path.get_file().get_basename() + ".geometry.bin"
	file = FileAccess.open(path.get_base_dir().path_join(name), FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	if not data.has("buffers"): data.buffers = []
	if not data.has("accessors"): data.accessors = []
	if not data.has("bufferViews"): data.bufferViews = []
	buffer_index = data.buffers.size()
	var completed := 0
	for index in originals:
		if progress.is_valid(): progress.call("geometry", completed, originals.size())
		var mesh: ImporterMesh = originals[index]
		if index >= data.get("meshes", []).size() or data.meshes[index].get("primitives", []).size() != mesh.get_surface_count():
			file.close(); return ERR_INVALID_DATA
		for slot in mesh.get_surface_count():
			var arrays := mesh.get_surface_arrays(slot)
			var primitive: Dictionary = data.meshes[index].primitives[slot]
			var attributes := {}
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var lo := vertices[0]; var hi := lo
			for vertex in vertices: lo = lo.min(vertex); hi = hi.max(vertex)
			attributes.POSITION = accessor(vertices.to_byte_array(), vertices.size(), "VEC3", 5126, 34962, {"min": [lo.x,lo.y,lo.z], "max": [hi.x,hi.y,hi.z]})
			for spec in [[Mesh.ARRAY_NORMAL,"NORMAL","VEC3"], [Mesh.ARRAY_TANGENT,"TANGENT","VEC4"], [Mesh.ARRAY_COLOR,"COLOR_0","VEC4"], [Mesh.ARRAY_TEX_UV,"TEXCOORD_0","VEC2"], [Mesh.ARRAY_TEX_UV2,"TEXCOORD_1","VEC2"]]:
				var values: Variant = arrays[spec[0]]
				if values == null or values.is_empty(): continue
				if spec[0] == Mesh.ARRAY_NORMAL:
					values = values.duplicate()
					for i in values.size(): values[i] = values[i].normalized()
				attributes[spec[1]] = accessor(values.to_byte_array(), vertices.size(), spec[2], 5126, 34962)
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX].duplicate()
			if indices.is_empty():
				indices.resize(vertices.size())
				for i in indices.size(): indices[i] = i
			# Godot is clockwise; glTF is counterclockwise. Never mutate source arrays.
			for i in range(0, indices.size(), 3):
				var swap := indices[i]; indices[i] = indices[i+2]; indices[i+2] = swap
			primitive.attributes = attributes
			primitive.indices = accessor(indices.to_byte_array(), indices.size(), "SCALAR", 5125, 34963)
		completed += 1
	data.buffers.append({"uri": name.uri_encode(), "byteLength": file.get_position()})
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK: return err
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null: return FileAccess.get_open_error()
	output.store_string(JSON.stringify(data))
	output.flush(); err = output.get_error(); output.close()
	return err

func accessor(bytes: PackedByteArray, count: int, type: String, component: int, target: int, extra: Dictionary = {}) -> int:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	# POSITION requires min/max even if an identical NORMAL stream came first.
	var key := "%s:%s:%d:%d:%s" % [hash.finish().hex_encode(), type, component, target, JSON.stringify(extra)]
	if deduplicated.has(key): return deduplicated[key]
	# Every supported component is 32 bit; each buffer view is naturally 4-byte aligned.
	var view: int = data.bufferViews.size()
	data.bufferViews.append({"buffer": buffer_index, "byteOffset": file.get_position(), "byteLength": bytes.size(), "target": target})
	file.store_buffer(bytes)
	var index: int = data.accessors.size()
	var entry := {"bufferView": view, "componentType": component, "count": count, "type": type}
	entry.merge(extra)
	data.accessors.append(entry)
	deduplicated[key] = index
	return index
