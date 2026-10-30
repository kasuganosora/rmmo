extends RefCounted
## Render-only conversion. Never changes authoring topology or collision meshes.
const Cpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Trace = preload("res://scripts/world3d/load_trace.gd")
const TERRAIN_SHADER = preload("res://scripts/world3d/river_terrain.gdshader")
const MAX_MEMBERS := 16
const MAX_VERTICES := 65536
const MAX_FORTIFICATION_MEMBERS := 256
static var prepared_surfaces_enabled:=true
const PREPARE_SURFACE_METHOD:=&"mesh_prepare_surface_from_arrays"
# Dense cutouts require measured CPU margin, an entirely visible distant AABB,
# no native LOD and no occlusion. Other instances retain the engine draw path.
static var static_scatter_instances_enabled:=true
static var _terrain_schemas:Dictionary={}
static var _terrain_schema_mutex:=Mutex.new()

static func _invalidate_terrain_schema(shader:Shader)->void:
	_terrain_schema_mutex.lock()
	_terrain_schemas.erase(shader)
	_terrain_schema_mutex.unlock()

static func _terrain_schema(shader:Shader)->Array:
	# Only the two shared terrain shaders reach here. Cache immutable names and
	# native defaults, never material values. Missing parameters render with these
	# defaults; duplicate()/Inspector may populate them lazily without an edit.
	_terrain_schema_mutex.lock()
	if not _terrain_schemas.has(shader):
		var schema:Array=[]
		for property:Dictionary in shader.get_shader_uniform_list():
			var name:String=property.name
			if name in ["terrain_heights","terrain_span","ground_mask"] or name.begins_with("batch_"):continue
			var entry:Array=[name,RenderingServer.shader_get_parameter_default(shader.get_rid(),name)]
			entry.make_read_only();schema.append(entry)
		schema.make_read_only();_terrain_schemas[shader]=schema
		var invalidate:=_invalidate_terrain_schema.bind(shader)
		if not shader.changed.is_connected(invalidate):shader.changed.connect(invalidate)
	var result:Array=_terrain_schemas[shader]
	_terrain_schema_mutex.unlock()
	return result

static func category(record: Dictionary) -> String:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.category") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if record.get("vegetation_batch",false):return "vegetation"
	return "fortification" if record.has("fortification") else ("building" if record.has("building") else "ground")

static func member_limit(record: Dictionary) -> int:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.member_limit") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if record.get("vegetation_batch",false):return 64
	return MAX_FORTIFICATION_MEMBERS if record.has("fortification") or record.has("building") else MAX_MEMBERS

static func candidate(record: Dictionary) -> bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.candidate") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if preload("res://scripts/world3d/vegetation_render.gd").eligible(record):return true
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
	if record.has("terrain_mesh") or record.has("terrain_volume") or record.has("road_mesh") or record.has("rock_bank"): return true
	return record.get("surface_id", "") == "ground" and record.get("size", [1,1,1])[1] <= 2

static func material_supported(material:Material,cutout_instances:bool=false)->bool:
	# Eligibility needs no property serialization or hash. Keep this predicate
	# shared with exact grouping so a cheap admission test cannot widen policy.
	if material==null:return true
	if material.next_pass!=null:return false
	if material is ShaderMaterial:
		return preload("res://scripts/world3d/streaming_surface_shader.gd").is_terrain(material.shader)
	if not material is StandardMaterial3D:return false
	if material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED and not (static_scatter_instances_enabled and cutout_instances and material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR):return false
	if material.billboard_mode!=BaseMaterial3D.BILLBOARD_DISABLED:return false
	return not (material.uv1_triplanar or material.uv2_triplanar or material.grow or material.distance_fade_mode!=BaseMaterial3D.DISTANCE_FADE_DISABLED)

static func material_key(material: Material,cutout_instances:bool=false) -> String:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.material_key") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if material == null: return "default"
	if not material_supported(material,cutout_instances):return ""
	var values: Array = []
	if material is ShaderMaterial:
		for entry:Array in _terrain_schema(material.shader):
			var name:String=entry[0]
			# Disabled layers are unused. Godot may lazily populate their defaults
			# when duplicating a material; that must not invalidate an existing batch.
			if not material.get_shader_parameter("ground_enabled") and (name.begins_with("region_a_") or name.begins_with("region_b_")): continue
			var value: Variant = material.get_shader_parameter(name)
			if value==null:value=entry[1]
			values.append([name, value.get_instance_id() if value is Resource else value])
	elif material is StandardMaterial3D:
		if not preload("res://scripts/world3d/standard_material_schema.gd").enabled:
			for property in material.get_property_list():
				if property.usage & PROPERTY_USAGE_STORAGE and not str(property.name).begins_with("resource_") and property.name != "script":
					var value:Variant=material.get(property.name)
					values.append([property.name,value.get_instance_id() if value is Resource else value])
		else:
			for name:Variant in preload("res://scripts/world3d/standard_material_schema.gd").storage_names(material,true):
				if not str(name).begins_with("resource_") and name != "script":
					var value: Variant = material.get(name)
					values.append([name, value.get_instance_id() if value is Resource else value])
	else: return ""
	# Group keys repeat once per source object. Keep the full material comparison
	# in this digest rather than repeatedly serializing kilobytes of properties.
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(values));return digest.finish().hex_encode()

static func vertex_count(mesh: Mesh) -> int:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.vertex_count") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var total := 0
	var cpu: Mesh = Cpu.capture(mesh)
	for arrays: Array in cpu.surfaces: total += arrays[Mesh.ARRAY_VERTEX].size()
	return total

static func height_image(record: Dictionary) -> Image:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.height_image") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var t: Dictionary = record.terrain_mesh
	var heights := PackedFloat32Array()
	for height in t.heights: heights.append(float(height) * record.size[1])
	return Image.create_from_data(int(t.columns)+1, int(t.rows)+1, false, Image.FORMAT_RF, heights.to_byte_array())

static func build(members: Array, origin: Vector3, defer_upload: bool = false) -> Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.build") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if (members[0].record.has("fortification") or members[0].record.has("building")) and not members[0].materials.any(func(material):return material is ShaderMaterial): return build_fortification(members,origin,defer_upload)
	var slots := {}
	var before := 0
	var before_vertices := 0
	var render_vertices := 0
	var derive_lods:bool=preload("res://scripts/world3d/terrain_render_lod.gd").enabled and members.any(func(source):return source.record.has("terrain_mesh") and not source.record.terrain_mesh.holes.has(true) and not source.record.has("surface_paint"))
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
		# These arrays feed layered terrain shaders only. Plain terrain batches
		# need neither height textures nor region-mask metadata/material uploads.
		if record.has("terrain_mesh") and source.materials.any(func(material):return material is ShaderMaterial):
			if source.has("private_height_image"):
				images.append(source.private_height_image if source.private_height_image!=null else height_image(record))
			else:images.append(source.materials[0].get_meta("terrain_height_image") if source.materials[0] is ShaderMaterial and source.materials[0].has_meta("terrain_height_image") else height_image(record))
			if record.has("terrain_regions"):
				# Snapshot uses the cached image; never rerasterize on the batch worker.
				masks.append(source.private_ground_mask if source.has("private_ground_mask") else source.materials[0].get_meta("ground_mask_image"))
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
				arrays = compact_terrain_sides(arrays)
			if derive_lods:
				var candidate:Dictionary=preload("res://scripts/world3d/terrain_render_lod.gd").derive(record,arrays) if slot==0 else {}
				var base:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
				if base.is_empty():
					base.resize(arrays[Mesh.ARRAY_VERTEX].size())
					for i in base.size():base[i]=i
				if not row.has("lod_parts"):row.lod_parts=[]
				row.lod_parts.append({"offset":0 if row.arrays.is_empty() else row.arrays[Mesh.ARRAY_VERTEX].size(),"base":base,"candidate":candidate})
			append_arrays(row, arrays, local, layer)
	for row: Dictionary in slots.values():
		render_vertices+=row.arrays[Mesh.ARRAY_VERTEX].size()
		if not derive_lods:continue
		var previous:=0.
		for level in 3:
			var indices:=PackedInt32Array();var error:=0.;var reduced:=false
			for part:Dictionary in row.lod_parts:
				var data:Dictionary=part.candidate
				var source_indices:PackedInt32Array=data.indices[level] if not data.is_empty() else part.base
				if not data.is_empty():error=maxf(error,data.errors[level]);reduced=true
				for index:int in source_indices:indices.append(index+int(part.offset))
			if reduced and indices.size()<row.arrays[Mesh.ARRAY_INDEX].size():
				if not row.has("lods"):row.lods={}
				var distance:float=float(PackedFloat32Array([maxf(.02,maxf(error*8.,previous*1.5))])[0])
				row.lods[distance]=indices;previous=distance
		row.erase("lod_parts")
	var data:={"slots":slots.values(),"images":images,"masks":masks,"origins":origins,"spans":spans,"source_surfaces":before,"source_vertices":before_vertices,"render_vertices":render_vertices,"compressed":members[0].record.has("fortification"),"terrain_lod":derive_lods}
	prepare_upload(data)
	return data if defer_upload else upload(data)

static func build_fortification(members: Array, origin: Vector3, defer_upload: bool, prepare_surfaces:bool=true) -> Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.build_fortification") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
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
	# A derived proxy may still add LODs/change packing flags. Its worker packs
	# once after those edits, rather than submitting this premature snapshot.
	if prepare_surfaces:prepare_upload(data)
	return data if defer_upload else upload(data)

static func surface_flags(row:Dictionary,compressed:bool)->int:
	var flags:=Mesh.ARRAY_CUSTOM_R_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT if row.layered else 0
	if compressed and row.arrays[Mesh.ARRAY_NORMAL]!=null and row.arrays[Mesh.ARRAY_TANGENT]!=null:flags|=Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
	return flags

static func prepare_upload(data:Dictionary)->void:
	# CPU-only engine packing stays in the existing geometry worker. No GPU RID,
	# resource mutation or renderer round-trip is allowed before the handoff.
	# Standard engines retain the existing add_surface_from_arrays path.
	if not prepared_surfaces_enabled or not RenderingServer.has_method(PREPARE_SURFACE_METHOD):return
	var began:=Time.get_ticks_usec();var count:=0
	for row:Dictionary in data.slots:
		var packed:Dictionary=RenderingServer.call(PREPARE_SURFACE_METHOD,Mesh.PRIMITIVE_TRIANGLES,row.arrays,[],row.get("lods",{}),surface_flags(row,data.get("compressed",false)))
		if packed.is_empty():return
		row.prepared_surface=packed;count+=1
	data.prepared_surface_count=count
	data.surface_prepare_us=Time.get_ticks_usec()-began
	data.surface_prepare_thread=OS.get_thread_caller_id()

static func upload(data: Dictionary) -> Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.upload") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	assert(Thread.is_main_thread())
	return finish_upload(_upload_resources(data))

static func upload_private(data:Dictionary)->Dictionary:
	# Only the explicit private-material snapshot path may call this. It owns
	# its materials and retains the ordinary job's input/texture lease. The flag
	# also suppresses a second clone if any slots use layered ShaderMaterials.
	assert(not Thread.is_main_thread() and data.get("private_layered_materials",false))
	var retained:Array=[]
	var result:=_upload_resources(data,retained)
	# Even a failed texture-array upload hands its private resources back to
	# main for disposal. No scene-bound CPU-cache registration runs on a worker.
	if result.is_empty():return {"upload_failed":true,"retained_resources":retained}
	return result

static func finish_upload(data:Dictionary)->Dictionary:
	assert(Thread.is_main_thread())
	if not data.has("mesh"):return {}
	if data.has("upload_cpu_arrays"):
		Cpu.remember(data.mesh,data.upload_cpu_arrays,data.upload_cpu_lods)
		data.erase("upload_cpu_arrays");data.erase("upload_cpu_lods")
	return data

static func _upload_resources(data:Dictionary,retained:Variant=null)->Dictionary:
	var stage_started:=Time.get_ticks_usec() if Trace.enabled else 0
	var result:=ArrayMesh.new()
	if retained!=null:retained.append(result)
	var cpu_arrays:Array=[];var cpu_lods:Array=[]
	var packed_surfaces:Array=[]
	var prepared:bool=int(data.get("prepared_surface_count",0))==data.slots.size()
	var height_array: Texture2DArray
	if not data.images.is_empty():
		height_array=Texture2DArray.new()
		if retained!=null:retained.append(height_array)
		if height_array.create_from_images(data.images)!=OK: return {}
	var mask_array: Texture2DArray
	if not data.masks.is_empty():
		mask_array=Texture2DArray.new()
		if retained!=null:retained.append(mask_array)
		if mask_array.create_from_images(data.masks)!=OK: return {}
	if Trace.enabled:Trace.elapsed("batch.upload.layer_arrays",stage_started,{"heights":data.images.size(),"masks":data.masks.size()});stage_started=Time.get_ticks_usec()
	var origins: PackedVector4Array=data.origins; var spans: PackedVector4Array=data.spans
	while origins.size()<MAX_MEMBERS: origins.append(Vector4.ZERO); spans.append(Vector4.ONE)
	for row: Dictionary in data.slots:
		var material: Material=row.material
		if row.layered:
			if not data.get("private_layered_materials",false):material=material.duplicate()
			material.set_shader_parameter("batch_enabled",true)
			material.set_shader_parameter("batch_heights",height_array)
			material.set_shader_parameter("batch_ground_masks",mask_array)
			material.set_shader_parameter("batch_origins",origins)
			material.set_shader_parameter("batch_spans",spans)
		var levels:Dictionary=row.get("lods",{})
		if prepared:
			var surface:Dictionary=row.prepared_surface.duplicate()
			surface.material=material;packed_surfaces.append(surface)
		else:
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,row.arrays,[],levels,surface_flags(row,data.get("compressed",false)))
			result.surface_set_material(result.get_surface_count()-1,material)
		cpu_arrays.append(row.arrays);cpu_lods.append(levels)
	if Trace.enabled:Trace.elapsed("batch.upload.surface_descriptors",stage_started,{"surfaces":data.slots.size(),"prepared":prepared});stage_started=Time.get_ticks_usec()
	if prepared:result.set("_surfaces",packed_surfaces)
	if Trace.enabled:
		Trace.elapsed("batch.upload.install_surfaces",stage_started,{"surfaces":data.slots.size(),"vertices":data.render_vertices,"private":data.get("private_layered_materials",false)})
		# Strings only, after the measured installation. Never query a lazy RID
		# or retain live resource owners solely for a diagnostic observer.
		if Time.get_ticks_usec()-stage_started>=20000:
			var materials:Array=[]
			for row:Dictionary in data.slots:
				var material:Material=row.material
				var description:={"class":material.get_class() if material!=null else "null","name":material.resource_name if material!=null else "","path":material.resource_path if material!=null else ""}
				if material is ShaderMaterial and material.shader!=null:description.shader_path=material.shader.resource_path
				materials.append(description)
			Trace.instant("batch.upload.slow_materials",{"upload_started_us":stage_started,"materials":materials})
	if data.get("terrain_lod",false) and cpu_lods.any(func(levels):return not levels.is_empty()):result.set_meta("terrain_render_lod",true)
	return {"mesh":result,"upload_cpu_arrays":cpu_arrays,"upload_cpu_lods":cpu_lods,"source_surfaces":data.source_surfaces,"source_vertices":data.source_vertices,"render_vertices":data.render_vertices}

static func append_arrays(row: Dictionary, source: Array, transform: Transform3D, layer: int) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.append_arrays") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Transform operators allocate their result. Read-only UV/colour channels
	# can append directly from the source; duplicating every input channel first
	# only adds a second temporary copy. The first retained output still owns a
	# private buffer, and every in-place tangent/index edit first takes ownership.
	var count:int=source[Mesh.ARRAY_VERTEX].size()
	if row.arrays.is_empty():row.arrays.resize(Mesh.ARRAY_MAX)
	var output:Array=row.arrays
	var offset:int=0 if output[Mesh.ARRAY_VERTEX]==null else output[Mesh.ARRAY_VERTEX].size()
	var rotated:=not transform.basis.is_equal_approx(Basis.IDENTITY)
	for channel:int in Mesh.ARRAY_MAX:
		var values:Variant=source[channel];var owned:=false
		if channel==Mesh.ARRAY_VERTEX:
			values=transform*values;owned=true
		elif channel==Mesh.ARRAY_NORMAL and rotated and values!=null:
			values=Transform3D(transform.basis,Vector3.ZERO)*values;owned=true
		elif channel==Mesh.ARRAY_TANGENT and rotated and values!=null:
			var tangents:PackedFloat32Array=values.duplicate()
			for i:int in count:
				var at:=i*4;var t:=transform.basis*Vector3(tangents[at],tangents[at+1],tangents[at+2])
				tangents[at]=t.x;tangents[at+1]=t.y;tangents[at+2]=t.z
			values=tangents;owned=true
		elif channel==Mesh.ARRAY_INDEX:
			if values==null or values.is_empty():
				var indices:=PackedInt32Array();indices.resize(count)
				for i:int in count:indices[i]=offset+i
				values=indices;owned=true
			elif offset!=0:
				var indices:PackedInt32Array=values.duplicate()
				for i:int in indices.size():indices[i]+=offset
				values=indices;owned=true
		elif channel==Mesh.ARRAY_CUSTOM0 and row.layered:
			var layers:=PackedFloat32Array();layers.resize(count);layers.fill(float(layer))
			values=layers;owned=true
		if values==null:continue
		if output[channel]==null:output[channel]=values if owned else values.duplicate()
		else:
			var joined:Variant=output[channel];joined.append_array(values);output[channel]=joined

# Sealed unpainted heightfield underside only. Preserve the previous triangle
# selection and normalization, but submit packed channels once instead of one
# GDScript/native setter call per emitted vertex. Authoring/collision stays intact.
static func compact_terrain_sides(arrays:Array)->Array:
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(vertices.size())
		for i:int in vertices.size():indices[i]=i
	var selected:=PackedInt32Array();var corners:Dictionary={}
	var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
	for face:int in range(0,indices.size(),3):
		var a:=indices[face];var b:=indices[face+1];var c:=indices[face+2]
		if normals[a].y<-.999 and normals[b].y<-.999 and normals[c].y<-.999:
			for at:int in [a,b,c]:
				low=low.min(vertices[at]);high=high.max(vertices[at]);corners[Vector2(vertices[at].x,vertices[at].z)]=at
		else:selected.append(a);selected.append(b);selected.append(c)
	if not corners.is_empty():
		for p:Vector2 in [Vector2(low.x,low.z),Vector2(high.x,high.z),Vector2(high.x,low.z),Vector2(low.x,low.z),Vector2(low.x,high.z),Vector2(high.x,high.z)]:selected.append(corners[p])
	var owned:Array=[];owned.resize(Mesh.ARRAY_MAX)
	for channel:int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_COLOR]:owned[channel]=arrays[channel]
	# Identity multiplication also canonicalizes signed zeros, as emit_vertex
	# did. Omitting it changes native vertex hashing and therefore index order.
	owned[Mesh.ARRAY_VERTEX]=Transform3D.IDENTITY*vertices
	owned[Mesh.ARRAY_INDEX]=selected
	# Match the old per-emitted-vertex normalization, once per used source index.
	var used:Dictionary={}
	for at:int in selected:used[at]=true
	var normalized:PackedVector3Array=normals.duplicate()
	var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT].duplicate() if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
	for at:int in used:
		normalized[at]=(Basis.IDENTITY*normals[at]).normalized()
		if not tangents.is_empty():
			var i:=at*4;var t:Vector3=(Basis.IDENTITY*Vector3(tangents[i],tangents[i+1],tangents[i+2])).normalized()
			tangents[i]=t.x;tangents[i+1]=t.y;tangents[i+2]=t.z
	owned[Mesh.ARRAY_NORMAL]=normalized
	if arrays[Mesh.ARRAY_TANGENT]!=null:owned[Mesh.ARRAY_TANGENT]=tangents
	var st:=SurfaceTool.new();st.create_from_arrays(owned);st.deindex();st.index()
	return st.commit_to_arrays()
