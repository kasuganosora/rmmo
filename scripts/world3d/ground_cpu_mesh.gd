extends Mesh
## Authoring/collision geometry without a RenderingServer mesh allocation.
var surfaces: Array = []
var materials: Array[Material] = []
var bounds := AABB()
var box_size := Vector3.ZERO
var source_reference: WeakRef
var _collision_faces:=PackedVector3Array()
static var _unit_box_arrays: Array=[]

static func primitive_arrays(source: Mesh, slot: int) -> Array:
	# PrimitiveMesh.surface_get_arrays also reads through RenderingServer.
	# An ordinary box has invariant topology/UVs; scale one canonical CPU copy.
	if source is BoxMesh and not source.flip_faces and not source.add_uv2 and source.subdivide_width==0 and source.subdivide_height==0 and source.subdivide_depth==0 and source.size.x>0 and source.size.y>0 and source.size.z>0:
		if _unit_box_arrays.is_empty():
			var unit:=BoxMesh.new(); unit.size=Vector3.ONE
			_unit_box_arrays=unit.surface_get_arrays(0)
		var arrays: Array=_unit_box_arrays.duplicate()
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
		for i in vertices.size(): vertices[i]*=source.size
		arrays[Mesh.ARRAY_VERTEX]=vertices
		return arrays
	return source.surface_get_arrays(slot)

static func remember(source: Mesh, arrays: Array) -> Mesh:
	# Procedural meshers already own these CPU arrays. Retain them at upload time
	# instead of synchronously downloading thousands of GPU buffers on first use.
	var result=load("res://scripts/world3d/ground_cpu_mesh.gd").new()
	result.source_reference=weakref(source); result.bounds=source.get_aabb(); result.surfaces=arrays
	for slot in source.get_surface_count(): result.materials.append(source.surface_get_material(slot))
	source.set_meta("ground_cpu_cache",result)
	source.changed.connect(invalidate.bind(weakref(source)),CONNECT_ONE_SHOT)
	return result

func geometry_key() -> String:
	if not has_meta("static_batch_geometry_signature"):
		var context:=HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(var_to_bytes(surfaces)); set_meta("static_batch_geometry_signature",context.finish().hex_encode())
	return get_meta("static_batch_geometry_signature")

func collision_faces() -> PackedVector3Array:
	if _collision_faces.is_empty():
		# Mesh.get_faces() builds a TriangleMesh (including a BVH) first. Physics
		# and Recast only need the existing triangle soup, not that extra tree.
		var count:=0
		for arrays:Array in surfaces:
			var indices:Variant=arrays[Mesh.ARRAY_INDEX]
			count+=indices.size() if indices!=null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
		_collision_faces.resize(count)
		var offset:=0
		for arrays:Array in surfaces:
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:Variant=arrays[Mesh.ARRAY_INDEX]
			if indices!=null and not indices.is_empty():
				for index in indices:
					_collision_faces[offset]=vertices[index];offset+=1
			else:
				for vertex in vertices:
					_collision_faces[offset]=vertex;offset+=1
	return _collision_faces

static func capture(source: Mesh) -> Mesh:
	if source.get_script() == load("res://scripts/world3d/ground_cpu_mesh.gd"): return source
	if source.has_meta("ground_cpu_cache"): return source.get_meta("ground_cpu_cache")
	var result = load("res://scripts/world3d/ground_cpu_mesh.gd").new()
	result.source_reference = weakref(source)
	result.bounds = source.get_aabb()
	if source is BoxMesh: result.box_size = source.size
	for slot in source.get_surface_count():
		result.surfaces.append(primitive_arrays(source,slot))
		result.materials.append(source.surface_get_material(slot))
	source.set_meta("ground_cpu_cache",result)
	source.changed.connect(invalidate.bind(weakref(source)),CONNECT_ONE_SHOT)
	return result

static func invalidate(reference: WeakRef) -> void:
	var source: Mesh=reference.get_ref()
	if source != null and source.has_meta("ground_cpu_cache"): source.remove_meta("ground_cpu_cache")

func restore() -> Mesh:
	var original: Mesh=source_reference.get_ref() if source_reference!=null else null
	if original!=null:
		var compatible:=original.get_surface_count()==materials.size()
		for slot in materials.size():
			if not compatible or original.surface_get_material(slot)!=materials[slot]: compatible=false; break
		if compatible: return original
	if box_size != Vector3.ZERO:
		var box := BoxMesh.new(); box.size = box_size; box.material = materials[0]
		source_reference=weakref(box)
		return box
	var result := ArrayMesh.new()
	for slot in surfaces.size():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[slot])
		result.surface_set_material(slot, materials[slot])
	var cached: Mesh=remember(result,surfaces)
	# Repeated instances share this CPU object after loading. Remember the first
	# restored GPU mesh weakly so each instance does not upload the same buffers.
	source_reference=weakref(result)
	cached._collision_faces=_collision_faces
	if has_meta("static_batch_geometry_signature"): cached.set_meta("static_batch_geometry_signature",geometry_key())
	return result

func _get_aabb() -> AABB: return bounds
func _get_surface_count() -> int: return surfaces.size()
func _get_blend_shape_count() -> int: return 0
func _surface_get_arrays(index: int) -> Array: return surfaces[index]
func _surface_get_array_len(index: int) -> int: return surfaces[index][Mesh.ARRAY_VERTEX].size()
func _surface_get_array_index_len(index: int) -> int: return surfaces[index][Mesh.ARRAY_INDEX].size() if surfaces[index][Mesh.ARRAY_INDEX] != null else 0
func _surface_get_primitive_type(_index: int) -> int: return Mesh.PRIMITIVE_TRIANGLES
func _surface_get_format(index: int) -> int:
	var format := 0
	for i in Mesh.ARRAY_MAX:
		if surfaces[index][i] != null and surfaces[index][i].size() > 0: format |= 1 << i
	return format
func _surface_get_material(index: int) -> Material: return materials[index]
func _surface_set_material(index: int, material: Material) -> void: materials[index] = material
func _surface_get_lods(_index: int) -> Dictionary: return {}
func _surface_get_blend_shape_arrays(_index: int) -> Array[Array]: return []
