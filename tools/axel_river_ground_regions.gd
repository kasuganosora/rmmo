extends RefCounted
## Local sand coverage only. One continuous world-space polygon per river avoids
## segment-end feather seams and repeated opacity; calls are split by terrain to
## stay below the existing mask-work budget without clipping those polygons.
const Regions = preload("res://scripts/world3d/terrain_regions.gd")
const Terrain = preload("res://scripts/world3d/terrain_surface.gd")
const Spline = preload("res://scripts/world3d/spline_route.gd")
const Poly = preload("res://scripts/world3d/roof_plan.gd")
const SAND := "pack:default:terrain/natural_sand/material"
const FEATHER := 1.5


static func simplify(points: Array, tolerance: float) -> Array:
	if points.size() <= 2:
		return points.duplicate()
	var farthest := 0.0
	var split := 0
	for i in range(1, points.size() - 1):
		var distance: float = points[i].distance_to(Geometry2D.get_closest_point_to_segment(points[i], points[0], points[-1]))
		if distance > farthest:
			farthest = distance
			split = i
	if farthest <= tolerance:
		return [points[0], points[-1]]
	var left: Array = simplify(points.slice(0, split + 1), tolerance)
	left.pop_back()
	left.append_array(simplify(points.slice(split), tolerance))
	return left


static func ribbon(points: Array, radius: float) -> Array:
	var path: Array = points.duplicate()
	# Continue past the outer terrain edge, rather than feathering across an
	# artificial end at the playable-map/buffer boundary.
	path[0] -= (path[1] - path[0]).normalized() * 2.0
	path[-1] += (path[-1] - path[-2]).normalized() * 2.0
	var left: Array = []
	var right: Array = []
	for i in path.size():
		var before: Vector2 = (path[i] - path[maxi(0, i - 1)]).normalized() if i > 0 else (path[1] - path[0]).normalized()
		var after: Vector2 = (path[mini(path.size() - 1, i + 1)] - path[i]).normalized() if i + 1 < path.size() else before
		var normal_a := Vector2(-before.y, before.x)
		var normal_b := Vector2(-after.y, after.x)
		var normal: Vector2 = (normal_a + normal_b).normalized()
		var offset: Vector2 = normal * radius / maxf(.7, normal.dot(normal_b))
		left.append(path[i] + offset)
		right.append(path[i] - offset)
	right.reverse()
	left.append_array(right)
	return left


static func capsule(a: Vector2, b: Vector2, radius: float) -> Array:
	var direction: float = (b - a).angle()
	var polygon: Array = []
	for i in 17:
		var angle: float = direction + PI * .5 + float(i) * PI / 16.0
		polygon.append(a + Vector2(cos(angle), sin(angle)) * radius)
	for i in 17:
		var angle: float = direction - PI * .5 + float(i) * PI / 16.0
		polygon.append(b + Vector2(cos(angle), sin(angle)) * radius)
	return polygon


static func requests(recipe: Dictionary) -> Array:
	var result: Array = []
	if not recipe.get("records") is Array:
		push_error("River ground regions require recipe terrain records")
		return []
	for key: String in ["main_river", "s12_stream"]:
		var river: Dictionary = recipe.get(key, {})
		if river.is_empty() or river.get("natural_materials", true):
			push_error("Local river regions require natural_materials=false for " + key)
			return []
		var sampled: Dictionary = Spline.sample(river.points, 2.0, false, .5 if river.get("curved", true) else 0.0)
		if not sampled.ok:
			push_error(str(sampled.error))
			return []
		var points: Array = sampled.points.map(func(p: Array): return Vector2(p[0], p[1]))
		var polygon: Array = []
		if key == "s12_stream":
			if river.points.size() != 2 or river.get("curved", true):
				push_error("S12 sand capsule requires the current straight stream")
				return []
			# Keep sand under the water and blend it out at the grassy waterline.
			polygon = capsule(points[0], points[-1], float(river.width) * .5 - .15)
		else:
			var simplified: Array = simplify(points, .5)
			if simplified.size() > 32:
				push_error("Main river sand outline exceeds 64 vertices at 0.5 m fidelity")
				return []
			polygon = ribbon(simplified, float(river.width) * .5 - .4)
		var raw: Array = polygon.map(func(p: Vector2): return [snappedf(p.x, .000001), snappedf(p.y, .000001)])
		if not Regions.polygon_valid(raw):
			push_error("Local river sand outline is invalid: " + key)
			return []
		var packed := PackedVector2Array(polygon)
		for record: Dictionary in recipe.records:
			if not record.has("terrain_mesh"):
				continue
			var pose: Transform3D = Terrain.transform(record)
			var corners: Array = Poly.rect([-record.size[0] * .5, -record.size[2] * .5, record.size[0] * .5, record.size[2] * .5])
			var bounds := Rect2()
			for i in corners.size():
				var world: Vector3 = pose * Vector3(corners[i].x, 0.0, corners[i].y)
				var point := Vector2(world.x, world.z)
				bounds = Rect2(point, Vector2.ZERO) if i == 0 else bounds.expand(point)
			bounds = bounds.grow(FEATHER)
			var tile := PackedVector2Array(Poly.rect([bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y]))
			if Geometry2D.intersect_polygons(packed, tile).is_empty():
				continue
			# Every neighboring tile receives the same complete polygon and ID;
			# paint_terrain_region performs its native world-to-local conversion.
			result.append({"id": str(river.id) + "_local_sand", "terrain_ids": [record.uuid], "polygon": raw.duplicate(true), "material_id": SAND, "feather": FEATHER, "opacity": 1.0})
	return result
