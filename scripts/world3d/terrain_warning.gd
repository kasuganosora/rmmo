extends RefCounted
## Samples only the skill's vertical damage band. Never bridges gaps or cliffs.
const HEIGHT_BAND := 1.0
const LIFT := 0.025
const MAX_CELLS := 32

static func build(space: PhysicsDirectSpaceState3D, center: Vector3, radius: float, exclude: Array[RID] = []) -> ArrayMesh:
	var cells := clampi(ceili(radius * 2.0 / 0.35), 2, MAX_CELLS)
	var step := radius * 2.0 / cells
	var points: Array = []
	for z in range(cells + 1):
		for x in range(cells + 1):
			var offset := Vector3(-radius + x * step, 0, -radius + z * step)
			var query := PhysicsRayQueryParameters3D.create(center + offset + Vector3.UP * (HEIGHT_BAND + 0.01), center + offset - Vector3.UP * (HEIGHT_BAND + 0.01))
			query.exclude = exclude
			var hit := space.intersect_ray(query)
			if hit.is_empty() or hit.normal.y < cos(deg_to_rad(40)) or absf(hit.position.y - center.y) > HEIGHT_BAND:
				points.append(null)
			else:
				points.append(hit.position - center + Vector3.UP * LIFT)
	var vertices := PackedVector3Array()
	for z in cells:
		for x in cells:
			var a := z * (cells + 1) + x
			_triangle(points, [a, a + cells + 1, a + 1], vertices)
			_triangle(points, [a + 1, a + cells + 1, a + cells + 2], vertices)
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _triangle(points: Array, indices: Array, vertices: PackedVector3Array) -> void:
	for i in indices:
		if points[i] == null: return
	for i in 3:
		var delta: Vector3 = points[indices[i]] - points[indices[(i + 1) % 3]]
		if absf(delta.y) > Vector2(delta.x, delta.z).length() * tan(deg_to_rad(40)) + 0.01: return
	for i in indices: vertices.append(points[i])
