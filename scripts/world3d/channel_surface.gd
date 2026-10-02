extends RefCounted
## Horizontal terrain patches share the proven slab mesher, without road clearance.
const Slab=preload("res://scripts/world3d/road_surface.gd")

static func proxy(record: Dictionary) -> Dictionary:
	var value:=record.duplicate(true); value.road_mesh=value.channel_mesh; value.erase("channel_mesh")
	return value
static func valid(record: Dictionary) -> bool:
	if not record.has("channel_mesh"): return not record.has("channel_clearance")
	if not preload("res://scripts/world3d/document_schema.gd").validate(record.get("channel_clearance",0),preload("res://scripts/world3d/document_schema.gd").number(0,20)).is_empty(): return false
	if record.has("road_mesh") or record.has("road_source") or record.has("road_clearance"): return false
	return Slab.valid(proxy(record))
static func mesh(record: Dictionary, material: Material) -> ArrayMesh:
	var value:=proxy(record)
	# JSON decimal roundtrips can cross a float32 rounding boundary in vertex
	# multiplication. Canonical inputs keep face signatures and PBR bindings stable.
	value.size=value.size.map(func(v):return snappedf(float(v),.000001))
	value.road_mesh.uv_origin=value.road_mesh.uv_origin.map(func(v):return snappedf(float(v),.000001))
	for poly in value.road_mesh.polygons:
		for point in poly:
			point[0]=snappedf(float(point[0]),.000000001); point[1]=snappedf(float(point[1]),.000000001)
	return Slab.mesh(value,material)
static func vertices(record: Dictionary) -> Array[Vector3]: return Slab.vertices(proxy(record))
static func local_polygons(record: Dictionary) -> Array: return Slab.local_polygons(proxy(record))
