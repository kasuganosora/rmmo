extends RefCounted
## Render-only conversion. Never changes authoring topology or collision meshes.
const Cpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const TERRAIN_SHADER = preload("res://scripts/world3d/river_terrain.gdshader")
const MAX_MEMBERS := 16
const MAX_VERTICES := 65536
const MAX_FORTIFICATION_MEMBERS := 256

static func category(record: Dictionary) -> String:
	return "fortification" if record.has("fortification") else ("building" if record.has("building") else "ground")

static func member_limit(record: Dictionary) -> int:
	return MAX_FORTIFICATION_MEMBERS if record.has("fortification") or record.has("building") else MAX_MEMBERS

static func candidate(record: Dictionary) -> bool:
	if record.has("house_prefab"):return false
	if record.get("kind") != "box" or record.get("invisible", false): return false
	if record.has("building"):
		for field in ["fortification","event","event_template","hostile","ally","seat"]:
			if record.has(field):return false
		return record.get("wind_response",{}).get("profile","off")=="off"
	if record.has("fortification"):
		for field in ["building", "fixture", "event", "event_template", "hostile", "ally", "seat", "bank_wetness", "water_depth_effect"]:
			if record.has(field): return false
		return record.get("wind_response", {}).get("profile", "off") == "off"
	for field in ["building", "fixture", "fortification", "channel_mesh", "tile3d", "event", "hostile", "ally", "seat", "bank_wetness", "water_depth_effect"]:
		if record.has(field): return false
	if record.get("wind_response", {}).get("profile", "off") != "off": return false
	if record.has("terrain_mesh") or record.has("road_mesh") or record.has("rock_bank"): return true
	return record.get("surface_id", "") == "ground" and record.get("size", [1,1,1])[1] <= 2

static func material_key(material: Material) -> String:
	if material == null: return "default"
	if material.next_pass != null: return ""
	var values: Array = []
	if material is ShaderMaterial:
		if material.shader != TERRAIN_SHADER: return ""
		for property in material.shader.get_shader_uniform_list():
			var name: String = property.name
			if name in ["terrain_heights", "terrain_span", "ground_mask"] or name.begins_with("batch_"): continue
			# Disabled layers are unused. Godot may lazily populate their defaults
			# when duplicating a material; that must not invalidate an existing batch.
			if not material.get_shader_parameter("ground_enabled") and (name.begins_with("region_a_") or name.begins_with("region_b_")): continue
			var value: Variant = material.get_shader_parameter(name)
			values.append([name, value.get_instance_id() if value is Resource else value])
	elif material is StandardMaterial3D:
		if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED: return ""
		# Object-local procedural coordinates, growing and fading need separate draws.
		if material.uv1_triplanar or material.uv2_triplanar or material.grow or material.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED: return ""
		for property in material.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and not str(property.name).begins_with("resource_") and property.name != "script":
				var value: Variant = material.get(property.name)
				values.append([property.name, value.get_instance_id() if value is Resource else value])
	else: return ""
	# Group keys repeat once per source object. Keep the full material comparison
	# in this digest rather than repeatedly serializing kilobytes of properties.
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(values));return digest.finish().hex_encode()

static func vertex_count(mesh: Mesh) -> int:
	var total := 0
	var cpu: Mesh = Cpu.capture(mesh)
	for arrays: Array in cpu.surfaces: total += arrays[Mesh.ARRAY_VERTEX].size()
	return total

static func height_image(record: Dictionary) -> Image:
	var t: Dictionary = record.terrain_mesh
	var heights := PackedFloat32Array()
	for height in t.heights: heights.append(float(height) * record.size[1])
	return Image.create_from_data(int(t.columns)+1, int(t.rows)+1, false, Image.FORMAT_RF, heights.to_byte_array())

static func build(members: Array, origin: Vector3, defer_upload: bool = false) -> Dictionary:
	if (members[0].record.has("fortification") or members[0].record.has("building")) and not members[0].materials.any(func(material):return material is ShaderMaterial): return build_fortification(members,origin,defer_upload)
	var slots := {}
	var before := 0
	var before_vertices := 0
	var render_vertices := 0
	var origins := PackedVector4Array()
	var spans := PackedVector4Array()
	var images: Array[Image] = []
	var masks: Array[Image] = []
	for source: Dictionary in members:
		var record: Dictionary = source.record
		var local: Transform3D = source.transform
		local.origin -= origin
		var layer := origins.size()
		origins.append(Vector4(local.origin.x, local.origin.y, local.origin.z, 0))
		spans.append(Vector4(record.size[0], record.size[2], local.basis.x.x, local.basis.z.x))
		if record.has("terrain_mesh"):
			images.append(source.materials[0].get_meta("terrain_height_image") if source.materials[0] is ShaderMaterial and source.materials[0].has_meta("terrain_height_image") else height_image(record))
			if record.has("terrain_regions"):
				# Snapshot uses the cached image; never rerasterize on the batch worker.
				masks.append(source.materials[0].get_meta("ground_mask_image"))
		for slot in source.surfaces.size():
			var material: Material = source.materials[slot]
			var key: String = source.keys[slot]
			var arrays: Array = source.surfaces[slot]
			var layout := 0
			for channel in Mesh.ARRAY_INDEX:
				if arrays[channel] != null and not arrays[channel].is_empty(): layout |= 1 << channel
			key += ":layout=" + str(layout)
			if not slots.has(key): slots[key] = {"arrays": [], "material": material, "layered": material is ShaderMaterial}
			var row: Dictionary = slots[key]
			before += 1; before_vertices += arrays[Mesh.ARRAY_VERTEX].size()
			if slot == 1 and record.has("terrain_mesh") and not record.terrain_mesh.holes.has(true) and not record.has("surface_paint"):
				var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
				append_surface(st, arrays, Transform3D.IDENTITY, 0, false, record, slot)
				st.index(); arrays = st.commit_to_arrays()
			append_arrays(row, arrays, local, layer)
	for row: Dictionary in slots.values(): render_vertices+=row.arrays[Mesh.ARRAY_VERTEX].size()
	var data:={"slots":slots.values(),"images":images,"masks":masks,"origins":origins,"spans":spans,"source_surfaces":before,"source_vertices":before_vertices,"render_vertices":render_vertices,"compressed":members[0].record.has("fortification")}
	return data if defer_upload else upload(data)

static func build_fortification(members: Array, origin: Vector3, defer_upload: bool) -> Dictionary:
	# Native append_from transforms positions/normals/tangents and rebases indices
	# in C++, avoiding millions of interpreted per-vertex operations. The source
	# is a worker-owned CPU Mesh, so this never downloads or uploads GPU buffers.
	var slots: Dictionary={}; var before:=0; var vertices:=0; var after:=0
	for source: Dictionary in members:
		var cpu:=Cpu.new(); cpu.surfaces=source.surfaces
		var pose: Transform3D=source.transform; pose.origin-=origin
		for slot in source.surfaces.size():
			var arrays: Array=source.surfaces[slot]; var layout:=0
			for channel in Mesh.ARRAY_INDEX:
				if arrays[channel]!=null and not arrays[channel].is_empty(): layout|=1<<channel
			# Keep indexed/non-indexed buffers separate: native append_from cannot
			# mix implicit triangles and explicit index buffers in the same surface.
			var indexed: bool=arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty()
			var key: String=source.keys[slot]+":layout="+str(layout)+":"+str(indexed)
			if not slots.has(key): slots[key]={"builder":SurfaceTool.new(),"material":source.materials[slot],"layered":false}
			slots[key].builder.append_from(cpu,slot,pose)
			before+=1; vertices+=arrays[Mesh.ARRAY_VERTEX].size()
	for row: Dictionary in slots.values():
		row.arrays=row.builder.commit_to_arrays(); row.erase("builder"); after+=row.arrays[Mesh.ARRAY_VERTEX].size()
	var data:={"slots":slots.values(),"images":[],"masks":[],"origins":PackedVector4Array(),"spans":PackedVector4Array(),"source_surfaces":before,"source_vertices":vertices,"render_vertices":after,"compressed":true}
	return data if defer_upload else upload(data)

static func upload(data: Dictionary) -> Dictionary:
	# GPU resources must be created on the main thread. Joining a worker during
	# undo/save/scene exit must never wait for a RenderingServer main-thread call.
	assert(Thread.is_main_thread())
	var result:=ArrayMesh.new()
	var height_array: Texture2DArray
	if not data.images.is_empty():
		height_array=Texture2DArray.new()
		if height_array.create_from_images(data.images)!=OK: return {}
	var mask_array: Texture2DArray
	if not data.masks.is_empty():
		mask_array=Texture2DArray.new()
		if mask_array.create_from_images(data.masks)!=OK: return {}
	var origins: PackedVector4Array=data.origins; var spans: PackedVector4Array=data.spans
	while origins.size()<MAX_MEMBERS: origins.append(Vector4.ZERO); spans.append(Vector4.ONE)
	for row: Dictionary in data.slots:
		var material: Material=row.material
		if row.layered:
			material=material.duplicate()
			material.set_shader_parameter("batch_enabled",true)
			material.set_shader_parameter("batch_heights",height_array)
			material.set_shader_parameter("batch_ground_masks",mask_array)
			material.set_shader_parameter("batch_origins",origins)
			material.set_shader_parameter("batch_spans",spans)
		var flags:=Mesh.ARRAY_CUSTOM_R_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT if row.layered else 0
		if data.get("compressed",false) and row.arrays[Mesh.ARRAY_NORMAL]!=null and row.arrays[Mesh.ARRAY_TANGENT]!=null: flags|=Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,row.arrays,[],{},flags)
		result.surface_set_material(result.get_surface_count()-1,material)
	return {"mesh":result,"source_surfaces":data.source_surfaces,"source_vertices":data.source_vertices,"render_vertices":data.render_vertices}

static func append_arrays(row: Dictionary, source: Array, transform: Transform3D, layer: int) -> void:
	var arrays := source.duplicate()
	# Packed arrays are reference values in GDScript. Joining or rebasing an index
	# buffer must never modify the CPU authoring mesh that the snapshot also owns.
	for channel in Mesh.ARRAY_MAX:
		if source[channel] != null: arrays[channel] = source[channel].duplicate()
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	arrays[Mesh.ARRAY_VERTEX] = transform * arrays[Mesh.ARRAY_VERTEX]
	if not transform.basis.is_equal_approx(Basis.IDENTITY):
		arrays[Mesh.ARRAY_NORMAL] = Transform3D(transform.basis,Vector3.ZERO) * arrays[Mesh.ARRAY_NORMAL]
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for i in count:
				var t := transform.basis * Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])
				tangents[i*4]=t.x; tangents[i*4+1]=t.y; tangents[i*4+2]=t.z
			arrays[Mesh.ARRAY_TANGENT] = tangents
	if arrays[Mesh.ARRAY_INDEX] == null or arrays[Mesh.ARRAY_INDEX].is_empty():
		var indices := PackedInt32Array(); indices.resize(count)
		for i in count: indices[i]=i
		arrays[Mesh.ARRAY_INDEX]=indices
	if row.layered:
		var layers := PackedFloat32Array(); layers.resize(count); layers.fill(float(layer))
		arrays[Mesh.ARRAY_CUSTOM0] = layers
	if row.arrays.is_empty(): row.arrays = arrays; return
	var output: Array = row.arrays
	var offset: int = output[Mesh.ARRAY_VERTEX].size()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in indices.size(): indices[i] += offset
	arrays[Mesh.ARRAY_INDEX] = indices
	for channel in Mesh.ARRAY_MAX:
		if arrays[channel] != null:
			if output[channel] == null: output[channel]=arrays[channel]
			else:
				var joined: Variant = output[channel]; joined.append_array(arrays[channel]); output[channel]=joined

static func append_surface(st: SurfaceTool, arrays: Array, transform: Transform3D, layer: int, layered: bool, record: Dictionary, slot: int) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in vertices.size(): indices[i] = i
	# Only the sealed, flat underside can be reduced without changing silhouettes,
	# painted faces, holes or the top heightfield. Source arrays stay untouched.
	var compact: bool = slot == 1 and record.has("terrain_mesh") and not record.terrain_mesh.holes.has(true) and not record.has("surface_paint")
	var bottom_corners := {}
	var low := Vector3(INF, INF, INF); var high := Vector3(-INF, -INF, -INF)
	for face in range(0, indices.size(), 3):
		var a := indices[face]; var b := indices[face+1]; var c := indices[face+2]
		if compact and normals[a].y < -.999 and normals[b].y < -.999 and normals[c].y < -.999:
			for at in [a,b,c]:
				low = low.min(vertices[at]); high = high.max(vertices[at]); bottom_corners[Vector2(vertices[at].x,vertices[at].z)] = at
			continue
		for at in [a,b,c]: emit_vertex(st, arrays, at, transform, layer, layered)
	if not bottom_corners.is_empty():
		for p in [Vector2(low.x,low.z),Vector2(high.x,high.z),Vector2(high.x,low.z),Vector2(low.x,low.z),Vector2(low.x,high.z),Vector2(high.x,high.z)]:
			emit_vertex(st, arrays, bottom_corners[p], transform, layer, layered)

static func emit_vertex(st: SurfaceTool, arrays: Array, at: int, transform: Transform3D, layer: int, layered: bool) -> void:
	st.set_normal((transform.basis * arrays[Mesh.ARRAY_NORMAL][at]).normalized())
	if arrays[Mesh.ARRAY_TEX_UV] != null: st.set_uv(arrays[Mesh.ARRAY_TEX_UV][at])
	if arrays[Mesh.ARRAY_TEX_UV2] != null: st.set_uv2(arrays[Mesh.ARRAY_TEX_UV2][at])
	if arrays[Mesh.ARRAY_COLOR] != null: st.set_color(arrays[Mesh.ARRAY_COLOR][at])
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var t: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]; var v := transform.basis * Vector3(t[at*4], t[at*4+1], t[at*4+2])
		st.set_tangent(Plane(v.normalized(), t[at*4+3]))
	if layered: st.set_custom(0, Color(float(layer),0,0,0))
	st.add_vertex(transform * arrays[Mesh.ARRAY_VERTEX][at])
