extends Node
## A separate meter-space navigation map; bridges and ground remain separate polygons.
var ready_for_queries := false
var map := RID()
var region := RID()
var mesh := NavigationMesh.new()
var source := NavigationMeshSourceGeometryData3D.new()
var version := 0
var fully_ready := false
var _staged := false
var _full_mesh: NavigationMesh
var _disposed := false
var _specs: Array = []
var _faces := {}
var _box_faces := PackedVector3Array()
var nearby_source_count := 0
var full_source_count := 0
var face_extractions := 0
var _phase := ""
var _cursor := 0
var _origin: Variant
var _bounds := AABB()
var _has_bounds := false
var _clip := AABB()
var _publish_wait := 0
var _publish_final := true


func build(specs: Array, origin: Variant = null) -> void:
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_set_active(map, true)
	NavigationServer3D.map_set_cell_size(map, 0.15)
	NavigationServer3D.map_set_cell_height(map, 0.1)
	mesh.cell_size = 0.15
	mesh.cell_height = 0.1
	# One voxel of clearance beyond the capsule avoids polygon simplification
	# placing ramp corner waypoints on the rounded capsule's contact boundary.
	mesh.agent_radius = 0.45
	mesh.agent_height = 1.8
	mesh.agent_max_climb = 0.4
	mesh.agent_max_slope = 40.0
	mesh.filter_walkable_low_height_spans = true
	_specs = specs
	_origin = origin
	_phase = "bounds"

func _process(_delta: float) -> void:
	if _phase.is_empty(): return
	var started := Time.get_ticks_usec()
	while _cursor < _specs.size() and Time.get_ticks_usec() - started < 3000:
		var spec: Dictionary = _specs[_cursor]
		_cursor += 1
		if not _collides(spec): continue
		var box: AABB = spec["transform"] * spec["mesh"].get_aabb()
		if _phase == "bounds":
			_bounds = _bounds.merge(box) if _has_bounds else box
			_has_bounds = true
		else:
			if _clip.has_volume() and not _clip.intersects(box): continue
			var shape: Shape3D = spec.get("shape")
			var geometry: Resource = shape if shape is ConcavePolygonShape3D else spec["mesh"]
			if geometry is BoxMesh and not geometry.flip_faces:
				# Generated buildings contain thousands of differently sized boxes. Their
				# exact navigation hull is one unit cube; avoid one GPU readback per box.
				if _box_faces.is_empty():
					var cube := BoxMesh.new(); cube.size = Vector3.ONE
					_box_faces = cube.get_faces(); face_extractions += 1
				source.add_faces(_box_faces, spec["transform"] * Transform3D(Basis.from_scale(geometry.size), Vector3.ZERO))
			else:
				var key := geometry.get_instance_id()
				if not _faces.has(key):
					_faces[key] = geometry.get_faces()
					face_extractions += 1
				source.add_faces(_faces[key], spec["transform"])
			full_source_count += 1
	if _cursor < _specs.size(): return
	_cursor = 0
	if _phase == "bounds":
		if _origin is Vector3 and (_bounds.size.x > 192 or _bounds.size.z > 192):
			_staged = true
			_clip = AABB(Vector3(_origin.x - 80, _bounds.position.y - 2, _origin.z - 80), Vector3(160, _bounds.size.y + 4, 160))
			mesh.filter_baking_aabb = _clip
		_phase = "source"
		return
	_phase = ""
	var owner_ref: WeakRef = weakref(self)
	if not ready_for_queries:
		nearby_source_count = full_source_count
		NavigationServer3D.bake_from_source_geometry_data_async(mesh, source, func():
			var owner = owner_ref.get_ref()
			if owner != null and not owner._disposed: owner._baked()
		)
	else:
		NavigationServer3D.bake_from_source_geometry_data_async(_full_mesh, source, func():
			var owner = owner_ref.get_ref()
			if owner != null and not owner._disposed: owner._full_baked()
		)


func _collides(spec: Dictionary) -> bool:
	var extras: Dictionary = spec.get("extras", {})
	return str(extras.get("rmmo_collision", "")) != "none" and not bool(extras.get("hostile", false)) and not bool(extras.get("ally", false))


func _baked() -> void:
	region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_use_async_iterations(region, false)
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	call_deferred("_publish", not _staged)


func _publish(final: bool = true) -> void:
	_publish_wait = 2
	_publish_final = final

func _physics_process(_delta: float) -> void:
	if _publish_wait <= 0: return
	_publish_wait -= 1
	if _publish_wait > 0: return
	NavigationServer3D.map_force_update(map)
	version += 1
	ready_for_queries = true
	fully_ready = _publish_final
	if fully_ready:
		source.clear()
		_specs = []
		_faces.clear()
	else:
		source = NavigationMeshSourceGeometryData3D.new()
		_full_mesh = mesh.duplicate()
		_full_mesh.clear()
		_full_mesh.filter_baking_aabb = AABB()
		_clip = AABB()
		full_source_count = 0
		_cursor = 0
		_phase = "source"


func _full_baked() -> void:
	mesh = _full_mesh
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	_publish(true)


func near_surface(point: Vector3, horizontal_tolerance: float = 0.18, vertical_tolerance: float = 0.4) -> bool:
	if not ready_for_queries or mesh.get_polygon_count() == 0 or not point.is_finite():
		return false
	var nearest := NavigationServer3D.map_get_closest_point(map, point)
	return Vector2(nearest.x, nearest.z).distance_to(Vector2(point.x, point.z)) <= horizontal_tolerance and absf(nearest.y - point.y) <= vertical_tolerance


func find_path(start: Vector3, goal: Vector3) -> Dictionary:
	if not ready_for_queries:
		return {"ok": false, "reason": "not_ready", "path": PackedVector3Array()}
	if not near_surface(start, 0.35) or not near_surface(goal):
		return {"ok": false, "reason": "unreachable", "path": PackedVector3Array()}
	var points := NavigationServer3D.map_get_path(map, start, goal, true)
	if points.is_empty() or points[-1].distance_to(goal) > 0.4:
		return {"ok": false, "reason": "unreachable", "path": PackedVector3Array()}
	points[0] = start
	points[-1] = goal
	return {"ok": true, "reason": "", "path": points, "version": version}


func _exit_tree() -> void:
	_disposed = true
	if region.is_valid():
		NavigationServer3D.free_rid(region)
	if map.is_valid():
		NavigationServer3D.free_rid(map)
