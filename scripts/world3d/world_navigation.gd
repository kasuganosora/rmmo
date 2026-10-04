extends Node
## A separate meter-space navigation map; bridges and ground remain separate polygons.
var loading_profile:Dictionary={}
var runtime_geometry_key:=""
var _cache_key:=""
var _cache_hit:=false
var ready_for_queries := false
var agent_height:=1.8
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
var _doors: Array=[]
var _resizing:=false

func resize_agent(height:float,specs:Array,origin:Vector3)->void:
	# Keep this Node stable: player, NPC and summon authorities hold weak refs.
	# Bake in a child map and swap only a complete result; never reset combat.
	if _resizing or not fully_ready or is_equal_approx(height,agent_height):return
	_resizing=true
	var replacement=get_script().new();replacement.agent_height=height;add_child(replacement)
	replacement.runtime_geometry_key=runtime_geometry_key
	replacement.build(specs,origin)
	while not replacement.fully_ready:await get_tree().process_frame
	NavigationServer3D.free_rid(region);NavigationServer3D.free_rid(map)
	map=replacement.map;region=replacement.region;mesh=replacement.mesh
	replacement.map=RID();replacement.region=RID()
	_doors=replacement._doors;agent_height=height;version+=1
	replacement.queue_free();_resizing=false


func build(specs: Array, origin: Variant = null) -> void:
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_set_active(map, true)
	NavigationServer3D.map_set_cell_size(map, 0.1)
	NavigationServer3D.map_set_cell_height(map, 0.1)
	# A 28cm tread needs at least two horizontal cells at every grid phase;
	# 15cm voxels can collapse a tread and disconnect an otherwise valid stair.
	mesh.cell_size = 0.1
	mesh.cell_height = 0.1
	# Extra clearance beyond the capsule avoids polygon simplification
	# placing ramp corner waypoints on the rounded capsule's contact boundary.
	mesh.agent_radius = 0.5
	mesh.agent_height = ceilf(agent_height/mesh.cell_height)*mesh.cell_height
	mesh.agent_max_climb = 0.4
	mesh.agent_max_slope = 40.0
	mesh.filter_walkable_low_height_spans = true
	_specs = specs
	# Hinges and handles follow the door but are not navigation obstacles.
	_doors=specs.filter(func(spec):return spec.get("extras",{}).get("fixture",{}).get("kind")=="door" and spec.extras.get("rmmo_collision","")!="none")
	_origin = origin
	_phase = "bounds"
	if not runtime_geometry_key.is_empty():
		_cache_key=runtime_geometry_key+str(mesh.agent_height)+FileAccess.get_sha256(get_script().resource_path)+FileAccess.get_sha256("res://scripts/world3d/navigation_cache.gd")
		_cache_hit=preload("res://scripts/world3d/navigation_cache.gd").restore(_cache_key,mesh)
		loading_profile.cache_hit=_cache_hit
		if _cache_hit:_phase="";_baked()

func _process(_delta: float) -> void:
	if _phase.is_empty(): return
	var started := Time.get_ticks_usec()
	while _cursor < _specs.size() and Time.get_ticks_usec() - started < (12000 if not ready_for_queries else 3000):
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
			var geometry: Resource = shape if shape is ConcavePolygonShape3D else spec.get("collision_mesh", spec["mesh"])
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
		loading_profile.bounds=Time.get_ticks_msec()
		_phase = "source"
		return
	loading_profile.source=Time.get_ticks_msec()
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
	if extras.get("fixture",{}).get("kind")=="door": return false
	return str(extras.get("rmmo_collision", "")) != "none" and not bool(extras.get("hostile", false)) and not bool(extras.get("ally", false))


func _baked() -> void:
	loading_profile.baked=Time.get_ticks_msec()
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
		if not _cache_hit:preload("res://scripts/world3d/navigation_cache.gd").store_mesh(_cache_key,mesh)
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


func find_path(start: Vector3, goal: Vector3, goal_tolerance:float=.18) -> Dictionary:
	if not ready_for_queries:
		return {"ok": false, "reason": "not_ready", "path": PackedVector3Array()}
	if not near_surface(start, 0.35) or not near_surface(goal,goal_tolerance):
		return {"ok": false, "reason": "unreachable", "path": PackedVector3Array()}
	# Recast erodes polygons by the agent radius. Visible floor beside a wall
	# remains a valid click; stop on the nearby walkable point, on this storey.
	if not near_surface(goal):goal=NavigationServer3D.map_get_closest_point(map,goal)
	var points := NavigationServer3D.map_get_path(map, start, goal, true)
	if points.is_empty() or points[-1].distance_to(goal) > 0.4:
		return {"ok": false, "reason": "unreachable", "path": PackedVector3Array()}
	points[0] = start
	points[-1] = goal
	for attempt in 8:
		var obstruction:=_door_obstruction(points)
		if obstruction.is_empty():return {"ok":true,"reason":"","path":points,"version":version}
		var door: Dictionary=obstruction.door
		var replacement:=PackedVector3Array()
		var first:int=obstruction.segment;var last:=first+1
		var inverse:Transform3D=door.transform.affine_inverse()
		var blocked_bounds:AABB=door.mesh.get_aabb().grow(.32)
		# Navmesh tessellation can put several consecutive waypoints inside the
		# open leaf's clearance envelope. Detour the whole span, not a segment
		# whose destination is itself inside the obstacle.
		while first>0 and blocked_bounds.has_point(inverse*(points[first]+Vector3.UP*.9)):first-=1
		while last<points.size()-1 and blocked_bounds.has_point(inverse*(points[last]+Vector3.UP*.9)):last+=1
		if float(door.extras.fixture.open)>.95: replacement=_around_open_leaf(points[first],points[last],door)
		if replacement.is_empty():return {"ok":false,"reason":"door_blocked","component_id":door.extras.fixture.id,"path":PackedVector3Array()}
		var amended:=points.slice(0,first);amended.append_array(replacement);amended.append_array(points.slice(last+1));points=amended
	return {"ok":false,"reason":"door_blocked","path":PackedVector3Array()}

func _door_obstruction(points: PackedVector3Array) -> Dictionary:
	if points.is_empty():return {}
	var route_bounds:=AABB(points[0]+Vector3.UP*.9,Vector3.ZERO)
	for point in points:route_bounds=route_bounds.expand(point+Vector3.UP*.9)
	for door in _doors:
		var bounds:AABB=door.transform*door.mesh.get_aabb().grow(.32)
		if not bounds.grow(.001).intersects(route_bounds.grow(.001)):continue
		var segment:=_door_segment(points,door)
		if segment>=0:return {"door":door,"segment":segment}
	return {}

func _door_segment(points:PackedVector3Array,door:Dictionary)->int:
	var inverse:Transform3D=door.transform.affine_inverse()
	var bounds:AABB=door.mesh.get_aabb().grow(.32)
	for i in points.size()-1:
		if bounds.intersects_segment(inverse*(points[i]+Vector3.UP*.9),inverse*(points[i+1]+Vector3.UP*.9))!=null:return i
	return -1

func _around_open_leaf(a: Vector3, b: Vector3, door: Dictionary) -> PackedVector3Array:
	# A fully open leaf is a small movable obstacle. Keep the static walk mesh
	# connected (especially narrow rotated doorways) and route around its corners.
	var candidates: Array[Vector3]=[]
	# A single generous offset can land beyond a narrow hall's opposite wall.
	# Sample clearance rings and snap to the actual walk surface before routing.
	for margin in [.37,.45,.55,.7]:
		var bounds:AABB=door.mesh.get_aabb().grow(margin)
		for x in [bounds.position.x,bounds.end.x]:
			for z in [bounds.position.z,bounds.end.z]:
				var point:Vector3=door.transform*Vector3(x,0,z);point.y=a.y
				if not near_surface(point,.2,.4):continue
				point=NavigationServer3D.map_get_closest_point(map,point)
				if not candidates.has(point):candidates.append(point)
	var best:=PackedVector3Array();var shortest:=INF
	for first in candidates:
		for last in candidates:
			var route:=PackedVector3Array();var valid:=true
			var stops: Array[Vector3]=[a,first,last,b]
			for i in 3:
				if stops[i].distance_to(stops[i+1])<.001:continue
				var segment:=NavigationServer3D.map_get_path(map,stops[i],stops[i+1],true)
				if segment.is_empty() or segment[-1].distance_to(stops[i+1])>.4:valid=false;break
				segment[0]=stops[i];segment[-1]=stops[i+1]
				# Resolve one leaf at a time; another leaf later on the candidate
				# route is handled by the outer loop, not grounds to reject this bend.
				if _door_segment(segment,door)>=0:valid=false;break
				route.append_array(segment)
			if not valid:continue
			var length:=0.0
			for i in route.size()-1:length+=route[i].distance_to(route[i+1])
			if length<shortest:shortest=length;best=route
	return best


func _exit_tree() -> void:
	_disposed = true
	if region.is_valid():
		NavigationServer3D.free_rid(region)
	if map.is_valid():
		NavigationServer3D.free_rid(map)
