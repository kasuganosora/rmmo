extends RefCounted
## Authored asset LOD ranges shared by native import, editor and streaming.
## Metadata survives glTF save/reopen; invalid ranges have no side effects.
static func apply(root: Node) -> void:
	for mesh in preload("res://scripts/world3d/surface_materials.gd").meshes(root): register(mesh)

static func register(mesh: MeshInstance3D) -> void:
	var raw: Variant = mesh.get_meta("extras", {}).get("rmmo_visibility_range")
	if not raw is Dictionary: return
	var begin: Variant = raw.get("begin")
	var end: Variant = raw.get("end")
	for value in [begin, end]:
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 100000.0: return
	if float(end) != 0.0 and float(end) <= float(begin): return
	var bounds: Variant = raw.get("bounds")
	if not bounds is Array or bounds.size() != 6: return
	for value in bounds:
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)): return
	if float(bounds[3]) <= 0.0 or float(bounds[4]) <= 0.0 or float(bounds[5]) <= 0.0: return
	mesh.custom_aabb = AABB(Vector3(bounds[0], bounds[1], bounds[2]), Vector3(bounds[3], bounds[4], bounds[5]))
	mesh.visibility_range_begin = float(begin)
	mesh.visibility_range_end = float(end)
	mesh.visibility_range_begin_margin = 1.0 if float(begin) > 0.0 else 0.0
	mesh.visibility_range_end_margin = 1.0 if float(end) > 0.0 else 0.0
	mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
