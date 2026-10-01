extends RefCounted
## Convex footprints avoid treating rotated empty corners and courtyards as solid.
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")

static func from_points(points: Array[Vector3]) -> Dictionary:
	var flat := PackedVector2Array(); var bounds := AABB(points[0],Vector3.ZERO)
	for p in points: flat.append(Vector2(p.x,p.z)); bounds=bounds.expand(p)
	return {"polygon":Geometry2D.convex_hull(flat),"bounds":bounds}

static func record_shape(record: Dictionary) -> Dictionary: return from_points(Geometry.corners(record))

static func components(records: Array, origin: Vector3, basis: Basis) -> Array:
	var groups := {}
	for record in records:
		var part: String = record.building.part.get_slice("/",0)
		var key := part if part in ["wing","wing_left","wing_right","workshop","yard"] else "main"
		if not groups.has(key): groups[key]=[]
		groups[key].append(record)
	var result: Array = []
	for group in groups.values():
		var bounds := Geometry.bounds(group); var points: Array[Vector3]=[]
		for i in 8: points.append(origin+basis*bounds.get_endpoint(i))
		result.append(from_points(points))
	return result

static func overlaps(a: Dictionary, b: Dictionary, margin := .005) -> bool:
	if not a.bounds.grow(-margin).intersects(b.bounds.grow(-margin)): return false
	for polygon in [a.polygon,b.polygon]:
		for i in polygon.size()-1:
			var edge: Vector2 = polygon[i+1]-polygon[i]
			if edge.length_squared()<.00000001: continue
			var axis := Vector2(-edge.y,edge.x).normalized()
			var amin := INF; var amax := -INF; var bmin := INF; var bmax := -INF
			for point in a.polygon: amin=minf(amin,axis.dot(point)); amax=maxf(amax,axis.dot(point))
			for point in b.polygon: bmin=minf(bmin,axis.dot(point)); bmax=maxf(bmax,axis.dot(point))
			if amax<=bmin+margin or bmax<=amin+margin: return false
	return true

static func batches_overlap(a: Array, b: Array) -> bool:
	for left in a:
		for right in b:
			if overlaps(left,right): return true
	return false
