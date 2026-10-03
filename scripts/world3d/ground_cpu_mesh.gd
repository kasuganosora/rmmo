extends Mesh
## Authoring/collision geometry without a RenderingServer mesh allocation.
var surfaces: Array = []
var materials: Array[Material] = []
var bounds := AABB()
var box_size := Vector3.ZERO

static func capture(source: Mesh) -> Mesh:
	if source.get_script() == load("res://scripts/world3d/ground_cpu_mesh.gd"): return source
	if source.has_meta("ground_cpu_cache"): return source.get_meta("ground_cpu_cache")
	var result = load("res://scripts/world3d/ground_cpu_mesh.gd").new()
	result.bounds = source.get_aabb()
	if source is BoxMesh: result.box_size = source.size
	for slot in source.get_surface_count():
		result.surfaces.append(source.surface_get_arrays(slot))
		result.materials.append(source.surface_get_material(slot))
	source.set_meta("ground_cpu_cache",result)
	source.changed.connect(invalidate.bind(weakref(source)),CONNECT_ONE_SHOT)
	return result

static func invalidate(reference: WeakRef) -> void:
	var source: Mesh=reference.get_ref()
	if source != null and source.has_meta("ground_cpu_cache"): source.remove_meta("ground_cpu_cache")

func restore() -> Mesh:
	if box_size != Vector3.ZERO:
		var box := BoxMesh.new(); box.size = box_size; box.material = materials[0]
		return box
	var result := ArrayMesh.new()
	for slot in surfaces.size():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[slot])
		result.surface_set_material(slot, materials[slot])
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
