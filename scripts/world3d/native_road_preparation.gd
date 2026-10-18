extends RefCounted
## CPU-only scheduling estimate and immutable array handoff for native roads.
## This is not an allocator measurement or a substitute for source validation.
const Road = preload("res://scripts/world3d/road_surface.gd")
const PACKED_VERTEX_BYTES := 48 # position, normal, UV and four tangent floats
const WORK_VERTEX_BYTES := 1024 # SurfaceTool vertices plus tangent-generation work
const FIXED_BYTES := 4 * 1024 * 1024
const MAX_ESTIMATED_BYTES := 616497152

static func estimate(record: Dictionary) -> Dictionary:
	if not record.has("road_mesh") or not Road.valid(record):
		return {"ok": false, "estimated_bytes": 0, "vertex_limit": 0, "output_bytes": 0, "reason": "Invalid or unsupported native road"}
	return _estimate_validated(record)

## Internal math only. The caller must just have passed Road.valid on the same
## immutable record. Worker admission always enters through estimate() above.
static func _estimate_validated(record:Dictionary)->Dictionary:
	var top := 0; var sides := 0; var points := 0; var kerb_vertices := 0
	for polygon: Array in record.road_mesh.polygons:
		points += polygon.size()
		top += 3 * (polygon.size() - 2)
		sides += 6 * polygon.size()
	var kerbs: Array = record.road_mesh.get("kerbs", [])
	for part: Dictionary in kerbs:
		kerb_vertices += 36 + (12 if part.cap_a else 0) + (12 if part.cap_b else 0)
	var vertices := 2 * top + sides + kerb_vertices
	var output := vertices * PACKED_VERTEX_BYTES
	# Surfaces are constructed sequentially, but earlier packed arrays remain
	# resident. Reserve two complete outputs for publication/handoff, the largest
	# SurfaceTool workspace, local polygon/triangle scratch and kerb temporaries.
	var work_vertices := maxi(maxi(top, sides), kerb_vertices)
	var estimated := 2 * output + work_vertices * WORK_VERTEX_BYTES + points * 256 + kerbs.size() * 4096 + FIXED_BYTES
	return {"ok": true, "estimated_bytes": estimated, "vertex_limit": vertices, "output_bytes": output, "reason": ""}

static func _cancelled(token: RefCounted) -> bool:
	return token != null and token.is_cancelled()

static func _fail(reason: String, cancelled: bool = false) -> Dictionary:
	return {"error": reason, "cancelled": cancelled, "arrays": [], "estimated_bytes": 0, "output_bytes": 0, "elapsed_us": 0}

static func prepare(record: Dictionary, token: RefCounted = null) -> Dictionary:
	if _cancelled(token): return _fail("Native road preparation cancelled", true)
	var budget := estimate(record)
	if not budget.ok: return _fail(budget.reason)
	if _cancelled(token): return _fail("Native road preparation cancelled", true)
	var started := Time.get_ticks_usec()
	# Reuse the exact authoring generator, without constructing Mesh, Material,
	# Node or GPU resources. SurfaceTool's bounded single-road operation is not
	# interruptible; a cancelled result is discarded before it can be published.
	var arrays: Array = Road.arrays(record)
	if _cancelled(token): return _fail("Native road preparation cancelled", true)
	return {"error": "", "cancelled": false, "arrays": arrays, "estimated_bytes": budget.estimated_bytes, "output_bytes": budget.output_bytes, "elapsed_us": Time.get_ticks_usec() - started}
