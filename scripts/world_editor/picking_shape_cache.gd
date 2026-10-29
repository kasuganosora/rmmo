extends RefCounted
## Scene-scoped immutable triangle shapes; bodies and mutable boxes stay separate.
const Cpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const MAX_ENTRIES := 1024
var _entries: Dictionary = {}
var _parent:WeakRef
var built:=0

## Candidates borrow existing immutable shapes without changing the live cache.
func fork()->RefCounted:
	var candidate=load("res://scripts/world_editor/picking_shape_cache.gd").new()
	candidate._parent=weakref(self)
	return candidate

## Only successful scene publication transfers private cache entries.
func adopt(candidate:RefCounted)->void:
	for key:int in candidate._entries:
		var entry:Dictionary=candidate._entries[key]
		if entry.source.get_ref()==null:continue
		if _entries.size()>=MAX_ENTRIES and not _entries.has(key):_entries.erase(_entries.keys()[0])
		_entries[key]=entry
	built+=candidate.built

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
	var parent:RefCounted=_parent.get_ref() if _parent!=null else null
	if parent!=null:
		previous=parent._entries.get(key,{})
		if not previous.is_empty() and previous.source.get_ref()==cpu:
			_entries[key]=previous
			return previous.shape
	var faces: PackedVector3Array = cpu.collision_faces()
	if faces.is_empty(): return null
	var shape := ConcavePolygonShape3D.new()
	# Preserve surface/index order for picking, without Mesh.get_faces()'s
	# intermediate TriangleMesh/BVH. Physics builds its own acceleration data.
	shape.set_faces(faces)
	built+=1
	if _entries.size() >= MAX_ENTRIES: _entries.erase(_entries.keys()[0])
	_entries[key] = {"source": weakref(cpu), "shape": shape}
	return shape
