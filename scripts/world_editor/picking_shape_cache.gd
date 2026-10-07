extends RefCounted
## Scene-scoped immutable triangle shapes; bodies and mutable boxes stay separate.
const Cpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const MAX_ENTRIES := 1024
var _entries: Dictionary = {}

func clear() -> void:
	_entries.clear()

func shape_for(source: Mesh) -> ConcavePolygonShape3D:
	# capture() invalidates its CPU object on source.changed, so geometry and
	# material edits cannot reuse a shape built for an earlier source revision.
	var cpu: Mesh = Cpu.capture(source)
	var key := cpu.get_instance_id()
	var previous: Dictionary = _entries.get(key, {})
	if not previous.is_empty() and previous.source.get_ref() == cpu:
		return previous.shape
	var faces: PackedVector3Array = cpu.collision_faces()
	if faces.is_empty(): return null
	var shape := ConcavePolygonShape3D.new()
	# Preserve surface/index order for picking, without Mesh.get_faces()'s
	# intermediate TriangleMesh/BVH. Physics builds its own acceleration data.
	shape.set_faces(faces)
	if _entries.size() >= MAX_ENTRIES: _entries.erase(_entries.keys()[0])
	_entries[key] = {"source": weakref(cpu), "shape": shape}
	return shape
