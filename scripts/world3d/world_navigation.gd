extends Node
const CpuMesh=preload("res://scripts/world3d/ground_cpu_mesh.gd")
# Bound Recast's temporary voxel allocation while gameplay is already running.
# 350 m tiles at 10 cm precision created 12.25 million cells in one bake.
const TILE_SIZE:=128.0
## A separate meter-space navigation map; bridges and ground remain separate polygons.
var loading_profile:Dictionary={}
var runtime_geometry_key:=""
var _cache_key:=""
var _cache_hit:=false
var _initial_cache_key:=""
var _initial_cache_hit:=false
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
var _publish_iteration:=0
var _publish_region_iteration:=0
var _nearby_iteration:=0
var _nearby_region_iteration:=0
var _nearby_mesh:NavigationMesh
var _nearby_clip:=AABB()
var _deferred_full_publish:=false
var _doors: Array=[]
var _resizing:=false
var _tiles:Array[AABB]=[]
var _tile_mesh:NavigationMesh
var _tile_vertices:=PackedVector3Array()
var _tile_polygons:Array[PackedInt32Array]=[]
var _merge_vertices:=PackedVector3Array()
var _merge_offset:=0
var _local_clip:=AABB()
var _nearby:RefCounted
var _nearby_publish_wait:=0
var _final_pending:=false
var _bake_pending:=""
var _baking_mesh:NavigationMesh
var _cache_writer:Thread
var _surface_point:=Vector3.INF
var _surface_iteration:=-1
var _surface_map:=RID()
var surface_query_count:=0
var surface_cache_hits:=0
var surface_index_hits:=0
var _surface_index:RefCounted
var _surface_index_worker:Thread
var _surface_index_mesh:NavigationMesh
var _surface_index_map:=RID()
var _surface_index_iteration:=-1
var _face_worker:Thread
var _face_worker_key:=0
var _source_jobs:Dictionary={}
var _orphan_sources:Array=[]

func follow(position:Vector3,goal:Variant=null)->void:
	if not ready_for_queries or fully_ready or _final_pending or not _staged or _nearby!=null or _nearby_publish_wait>0:return
	if goal==null and _inside_local(position,48):return
	if goal is Vector3 and _inside_local(position,2) and _inside_local(goal,2):return
	if goal is Vector3 and Vector2(goal.x-position.x,goal.z-position.z).length()>160 and _inside_local(position,48):return
	var area:=AABB(Vector3(position.x-96,_bounds.position.y-2,position.z-96),Vector3(192,_bounds.size.y+4,192))
	# Foreground clicks cover nearby destinations; map-wide routes wait for
	# the full mesh rather than allocating an unbounded foreground bake.
	if goal is Vector3 and Vector2(goal.x-position.x,goal.z-position.z).length()<=160:
		area=area.expand(Vector3(goal.x-16,area.position.y,goal.z-16)).expand(Vector3(goal.x+16,area.end.y,goal.z+16))
	_nearby=preload("res://scripts/world3d/nearby_navigation.gd").new(mesh,area)

func _inside_local(point:Vector3,margin:float)->bool:
	return point.x>=_local_clip.position.x+margin and point.x<=_local_clip.end.x-margin and point.z>=_local_clip.position.z+margin and point.z<=_local_clip.end.z-margin

func _step_nearby()->void:
	if _nearby==null:return
	if fully_ready or _final_pending:_discard_source(_nearby.source);_nearby=null;return
	_nearby.step(self)
	if not _nearby.complete:return
	if _nearby.mesh.get_polygon_count()>0:
		_nearby_mesh=_nearby.mesh;_nearby_clip=_nearby.clip
		NavigationServer3D.region_set_use_async_iterations(region,true)
		_nearby_iteration=NavigationServer3D.map_get_iteration_id(map)
		_nearby_region_iteration=NavigationServer3D.region_get_iteration_id(region)
		NavigationServer3D.region_set_navigation_mesh(region,_nearby_mesh)
		_nearby_publish_wait=2
		loading_profile.nearby_refreshes=int(loading_profile.get("nearby_refreshes",0))+1
		loading_profile.nearby_last_ms=Time.get_ticks_msec()-_nearby.started_ms
	_nearby=null


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
	NavigationServer3D.map_set_use_async_iterations(map, true)
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
	if not has_meta("profile_frame"):
		_step_background();return
	var started:=Time.get_ticks_usec();var phase:=_phase
	_step_background()
	set_meta("background_timing",{"frame":Engine.get_process_frames(),"phase":phase,"ms":(Time.get_ticks_usec()-started)/1000.0})

func _step_background()->void:
	_step_surface_index()
	for i in range(_orphan_sources.size()-1,-1,-1):
		if _orphan_sources[i].poll():_orphan_sources.remove_at(i)
	if _cache_writer!=null and not _cache_writer.is_alive():
		_cache_writer.wait_to_finish();_cache_writer=null
	if not _bake_pending.is_empty() and not NavigationServer3D.is_baking_navigation_mesh(_baking_mesh):
		var completed:=_bake_pending;_bake_pending="";_baking_mesh=null
		if completed=="initial":_baked()
		elif completed=="tile":_tile_baked()
		else:_full_baked()
	_step_nearby()
	if _phase.is_empty(): return
	if _phase=="prepare_source":
		var prepared:=_prepare_source(source)
		if prepared==null:return
		source=prepared;_phase="";_submit_bake();return
	if _phase in ["tile_vertices","tile_polygons","assemble"]:
		_step_merge();return
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
			if not _add_source(source,spec):_cursor-=1;return
			full_source_count += 1
	if _cursor < _specs.size(): return
	_cursor = 0
	if _phase == "bounds":
		if _origin is Vector3 and (_bounds.size.x > 192 or _bounds.size.z > 192):
			_staged = true
			_clip = AABB(Vector3(_origin.x - 80, _bounds.position.y - 2, _origin.z - 80), Vector3(160, _bounds.size.y + 4, 160))
			mesh.filter_baking_aabb = _clip
			_local_clip=_clip
		loading_profile.bounds=Time.get_ticks_msec()
		if _staged and not _cache_key.is_empty():
			# The small spawn mesh is useful even when the player leaves before
			# the full-town bake finishes. Its exact clip is part of its identity.
			_initial_cache_key=_cache_key+"|initial|"+preload("res://scripts/world3d/map_metadata_cache.gd").checksum(var_to_bytes(_clip)).hex_encode()
			_initial_cache_hit=preload("res://scripts/world3d/navigation_cache.gd").restore(_initial_cache_key,mesh)
			loading_profile.initial_cache_hit=_initial_cache_hit
			if _initial_cache_hit:
				_phase="";_baked();return
		_phase = "source"
		return
	loading_profile.source=Time.get_ticks_msec()
	if ready_for_queries:
		_phase="prepare_source";return
	_phase = ""
	_submit_bake()

func _submit_bake()->void:
	# Poll completion on this live Node. A queued script callback must not
	# outlive the scene when leaving during a background bake.
	if not ready_for_queries:
		nearby_source_count = full_source_count
		_bake_pending="initial";_baking_mesh=mesh
	else:
		_bake_pending="tile" if _tile_mesh!=null else "full"
		_baking_mesh=_tile_mesh if _tile_mesh!=null else _full_mesh
	var submitted:=Time.get_ticks_usec() if has_meta("profile_frame") else 0
	NavigationServer3D.bake_from_source_geometry_data_async(_baking_mesh,source)
	if submitted>0 and Time.get_ticks_usec()-submitted>5000:print("NAV_SUBMIT_SLOW ",(Time.get_ticks_usec()-submitted)/1000.0)

func _queue_faces(target:NavigationMeshSourceGeometryData3D,faces:PackedVector3Array,pose:Transform3D)->void:
	if not ready_for_queries:target.add_faces(faces,pose);return
	if not target.has_meta("pending_faces"):target.set_meta("pending_faces",[])
	var chunks:Array=target.get_meta("pending_faces")
	chunks.append([faces,pose])

func _prepare_source(target:NavigationMeshSourceGeometryData3D)->NavigationMeshSourceGeometryData3D:
	if not target.has_meta("pending_faces"):return target
	if not _source_jobs.has(target):
		var job:=preload("res://scripts/world3d/navigation_source_job.gd").new()
		job.start(target.get_meta("pending_faces"));_source_jobs[target]=job
	var job:RefCounted=_source_jobs[target]
	if not job.poll():return null
	var result:NavigationMeshSourceGeometryData3D=job.result
	_source_jobs.erase(target);target.remove_meta("pending_faces")
	return result

func _discard_source(target:NavigationMeshSourceGeometryData3D)->void:
	if _source_jobs.has(target):
		_orphan_sources.append(_source_jobs[target]);_source_jobs.erase(target)


func _add_source(target:NavigationMeshSourceGeometryData3D,spec:Dictionary)->bool:
	var started:=Time.get_ticks_usec() if has_meta("profile_frame") else 0
	var shape: Shape3D = spec.get("shape")
	var geometry: Resource = shape if shape is ConcavePolygonShape3D else spec.get("collision_mesh", spec["mesh"])
	if geometry is BoxMesh and not geometry.flip_faces:
		# Generated buildings contain thousands of differently sized boxes. Their
		# exact navigation hull is one unit cube; avoid one GPU readback per box.
		if _box_faces.is_empty():
			var cube := BoxMesh.new(); cube.size = Vector3.ONE
			_box_faces = cube.get_faces(); face_extractions += 1
		_queue_faces(target,_box_faces,spec["transform"] * Transform3D(Basis.from_scale(geometry.size),Vector3.ZERO))
	else:
		var key := geometry.get_instance_id()
		if _face_worker!=null and not _face_worker.is_alive():
			_faces[_face_worker_key]=_face_worker.wait_to_finish();_face_worker=null
			face_extractions+=1
		if not _faces.has(key):
			var large_cpu:=false
			if geometry is CpuMesh:
				var count:=0
				for surface:Array in geometry.surfaces:
					var indices:Variant=surface[Mesh.ARRAY_INDEX]
					count+=indices.size() if indices!=null and not indices.is_empty() else surface[Mesh.ARRAY_VERTEX].size()
				large_cpu=count>1536
			if ready_for_queries and large_cpu:
				if _face_worker!=null:return false
				# Copy only immutable array references; the worker never touches the
				# live CPU mesh cache, scene, physics or RenderingServer.
				var arrays:Array=geometry.surfaces
				_face_worker=Thread.new();_face_worker_key=key
				if _face_worker.start(func():return preload("res://scripts/world3d/stream_collision_preparer.gd").build_faces(arrays))==OK:return false
				_face_worker=null
			_faces[key] = geometry.collision_faces() if geometry is CpuMesh else geometry.get_faces()
			if started>0 and Time.get_ticks_usec()-started>5000:print("NAV_FACES_SLOW ",spec.get("uuid","")," ",geometry.get_class()," cpu=",geometry is CpuMesh," ",(Time.get_ticks_usec()-started)/1000.0)
			face_extractions += 1
		_queue_faces(target,_faces[key],spec["transform"])
	if started>0 and Time.get_ticks_usec()-started>5000:print("NAV_SOURCE_SLOW ",spec.get("uuid","")," ",(Time.get_ticks_usec()-started)/1000.0)
	return true

func _collides(spec: Dictionary) -> bool:
	var extras: Dictionary = spec.get("extras", {})
	if extras.get("fixture",{}).get("kind")=="door": return false
	return str(extras.get("rmmo_collision", "")) != "none" and not bool(extras.get("hostile", false)) and not bool(extras.get("ally", false))


func _baked() -> void:
	loading_profile.baked=Time.get_ticks_msec()
	if _staged and not _initial_cache_hit:
		preload("res://scripts/world3d/navigation_cache.gd").store_mesh(_initial_cache_key,mesh)
	region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_use_async_iterations(region, false)
	_publish_region_iteration=NavigationServer3D.region_get_iteration_id(region)
	_publish_iteration=NavigationServer3D.map_get_iteration_id(map)
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	call_deferred("_publish", not _staged)


func _publish(final: bool = true) -> void:
	_publish_wait = 2
	_publish_final = final

func _physics_process(_delta: float) -> void:
	if not has_meta("profile_frame"):
		_step_publication();return
	var started:=Time.get_ticks_usec()
	_step_publication()
	set_meta("publication_timing",{"frame":Engine.get_process_frames(),"ms":(Time.get_ticks_usec()-started)/1000.0})

func _step_publication()->void:
	if _nearby_publish_wait>0:
		_nearby_publish_wait=maxi(1,_nearby_publish_wait-1)
		if NavigationServer3D.region_get_iteration_id(region)!=_nearby_region_iteration and NavigationServer3D.map_get_iteration_id(map)!=_nearby_iteration:
			mesh=_nearby_mesh;_local_clip=_nearby_clip;_nearby_mesh=null
			_nearby_publish_wait=0;version+=1
	if _deferred_full_publish and _nearby_publish_wait==0:_publish_full_mesh()
	if _publish_wait <= 0: return
	_publish_wait=maxi(1,_publish_wait-1)
	# Keep the previous queryable map while the server builds its replacement.
	# force_update() would join that job here and stall gameplay for seconds.
	if NavigationServer3D.region_get_iteration_id(region)==_publish_region_iteration or NavigationServer3D.map_get_iteration_id(map)==_publish_iteration:return
	_publish_wait=0
	version += 1
	ready_for_queries = true
	fully_ready = _publish_final
	if fully_ready:
		if not _cache_hit and not _cache_key.is_empty():
			# The published NavigationMesh is immutable. Retain it until the
			# worker finishes serializing/checksumming the atomic cache write.
			var snapshot:=mesh;var key:=_cache_key
			_cache_writer=Thread.new()
			if _cache_writer.start(func():preload("res://scripts/world3d/navigation_cache.gd").store_mesh(key,snapshot))!=OK:_cache_writer=null
		source.clear()
		_specs = []
		_faces.clear()
	else:
		_full_mesh = mesh.duplicate()
		_full_mesh.clear()
		_full_mesh.filter_baking_aabb = AABB()
		if _bounds.size.x*_bounds.size.z/(mesh.cell_size*mesh.cell_size)<=25000000:
			source=NavigationMeshSourceGeometryData3D.new();_clip=AABB();_cursor=0;_phase="source"
			return
		# Preserve 10 cm stair precision without rasterizing a kilometre-wide
		# grid in one allocation. These are bake jobs, not render/stream chunks.
		var size:=TILE_SIZE
		for z in range(floori(_bounds.position.z/size),ceili(_bounds.end.z/size)):
			for x in range(floori(_bounds.position.x/size),ceili(_bounds.end.x/size)):
				_tiles.append(AABB(Vector3(x*size,_bounds.position.y-2,z*size),Vector3(size,_bounds.size.y+4,size)))
		_tiles.sort_custom(func(a,b):return a.get_center().distance_squared_to(_origin)<b.get_center().distance_squared_to(_origin))
		loading_profile.tile_count=_tiles.size()
		_next_tile()

func _next_tile()->void:
	if _tiles.is_empty():
		_full_mesh.set_vertices(_tile_vertices)
		_cursor=0;_phase="assemble";return
	var box:AABB=_tiles.pop_front()
	# The border clips away agent erosion at aligned tile edges. Include the
	# adjacent geometry in the source so a seam cannot create a false obstacle.
	# A power-of-two multiple remains exact when stored as float32; decimal
	# 2.0 / 0.1 otherwise trips Recast's border rounding warning on every tile.
	var border:float=_full_mesh.cell_size*16
	_clip=AABB(box.position-Vector3(border,0,border),box.size+Vector3(border*2,0,border*2))
	_tile_mesh=_full_mesh.duplicate();_tile_mesh.clear()
	_tile_mesh.filter_baking_aabb=_clip;_tile_mesh.border_size=border;_tile_mesh.edge_max_error=1.0
	source=NavigationMeshSourceGeometryData3D.new();_cursor=0;_phase="source"

func _tile_baked()->void:
	_merge_offset=_tile_vertices.size();_merge_vertices=_tile_mesh.get_vertices()
	_cursor=0;_phase="tile_vertices"

func _step_merge()->void:
	# Recast runs in the background; its result must not bring a whole tile's
	# vertex/polygon loops back onto one gameplay frame. Preserve the exact
	# snapping, polygon order and indices used by the synchronous assembler.
	var deadline:=Time.get_ticks_usec()+2000
	if _phase=="tile_vertices":
		while _cursor<_merge_vertices.size() and Time.get_ticks_usec()<deadline:
			_merge_vertices[_cursor]=_merge_vertices[_cursor].snappedf(.01);_cursor+=1
		if _cursor<_merge_vertices.size():return
		_tile_vertices.append_array(_merge_vertices);_merge_vertices=PackedVector3Array()
		_cursor=0;_phase="tile_polygons"
	if _phase=="tile_polygons":
		while _cursor<_tile_mesh.get_polygon_count() and Time.get_ticks_usec()<deadline:
			var polygon:=_tile_mesh.get_polygon(_cursor)
			for j in polygon.size():polygon[j]+=_merge_offset
			_tile_polygons.append(polygon);_cursor+=1
		if _cursor<_tile_mesh.get_polygon_count():return
		loading_profile.tiles_remaining=_tiles.size();_next_tile();return
	if _phase=="assemble":
		while _cursor<_tile_polygons.size() and Time.get_ticks_usec()<deadline:
			_full_mesh.add_polygon(_tile_polygons[_cursor]);_cursor+=1
		if _cursor<_tile_polygons.size():return
		_tile_vertices=PackedVector3Array();_tile_polygons.clear();_tile_mesh=null
		_phase="";_full_baked()


func _full_baked() -> void:
	if _full_mesh.get_polygon_count()==0:
		loading_profile.error="Full navigation bake produced no polygons; retaining nearby navigation"
		push_error(loading_profile.error);return
	if _nearby!=null:_discard_source(_nearby.source)
	_final_pending=true;_nearby=null
	_deferred_full_publish=true
	if _nearby_publish_wait==0:_publish_full_mesh()

func _publish_full_mesh()->void:
	_deferred_full_publish=false
	mesh = _full_mesh
	# The previous nearby publication has settled before this submission.
	# Build the much larger region graph off-thread as well as the map graph.
	NavigationServer3D.region_set_use_async_iterations(region,true)
	_publish_region_iteration=NavigationServer3D.region_get_iteration_id(region)
	_publish_iteration=NavigationServer3D.map_get_iteration_id(map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	_publish(true)


func near_surface(point: Vector3, horizontal_tolerance: float = 0.18, vertical_tolerance: float = 0.4) -> bool:
	if not ready_for_queries or mesh.get_polygon_count() == 0 or not point.is_finite():
		return false
	var iteration:=NavigationServer3D.map_get_iteration_id(map)
	# A previously queried point remains a real point on this immutable map.
	# Inside the smaller tolerance sphere, even a closer point must satisfy
	# BOTH original limits. Outside it, retain the exact nearest-point query;
	# a rectangular tolerance check would not provide that guarantee.
	var proven_radius:=minf(horizontal_tolerance,vertical_tolerance)
	if proven_radius>=0 and map==_surface_map and iteration==_surface_iteration and point.distance_squared_to(_surface_point)<=proven_radius*proven_radius:
		surface_cache_hits+=1;return true
	if _surface_index!=null and _surface_index_mesh==mesh and _surface_index_map==map and _surface_index_iteration==iteration:
		var support:Vector3=_surface_index.support(point,proven_radius)
		if support.is_finite():
			_surface_point=support;_surface_iteration=iteration;_surface_map=map
			surface_index_hits+=1;return true
	var started:=Time.get_ticks_usec() if has_meta("profile_frame") else 0
	var nearest := NavigationServer3D.map_get_closest_point(map, point)
	surface_query_count+=1
	if started>0:set_meta("surface_query_timing",{"frame":Engine.get_physics_frames(),"ms":(Time.get_ticks_usec()-started)/1000.0})
	_surface_point=nearest;_surface_iteration=iteration;_surface_map=map
	return Vector2(nearest.x, nearest.z).distance_to(Vector2(point.x, point.z)) <= horizontal_tolerance and absf(nearest.y - point.y) <= vertical_tolerance

func _step_surface_index()->void:
	if _surface_index_worker!=null:
		if _surface_index_worker.is_alive():return
		_surface_index=_surface_index_worker.wait_to_finish();_surface_index_worker=null
	if not fully_ready:return
	var iteration:=NavigationServer3D.map_get_iteration_id(map)
	if _surface_index_mesh==mesh and _surface_index_map==map and _surface_index_iteration==iteration:return
	_surface_index=null;_surface_index_mesh=mesh;_surface_index_map=map;_surface_index_iteration=iteration
	var snapshot:=mesh
	_surface_index_worker=Thread.new()
	if _surface_index_worker.start(func():return preload("res://scripts/world3d/navigation_surface_index.gd").build(snapshot),Thread.PRIORITY_LOW)!=OK:
		_surface_index_worker=null;_surface_index_mesh=null


func find_path(start: Vector3, goal: Vector3, goal_tolerance:float=.18) -> Dictionary:
	if not ready_for_queries:
		return {"ok": false, "reason": "not_ready", "path": PackedVector3Array()}
	# Recast rounds span heights up by a cell. At a rotated low doorstep its
	# simplified surface can be just above the physical climb height; do not
	# strand a grounded actor for that voxel rounding. Still reject other floors.
	var vertical_tolerance:float=maxf(.4,mesh.agent_max_climb+mesh.cell_height+.01)
	if not near_surface(start, 0.35,vertical_tolerance) or not near_surface(goal,goal_tolerance,vertical_tolerance):
		if _staged and not fully_ready and (not _inside_local(start,2) or not _inside_local(goal,2)):
			follow(start,goal)
			return {"ok":false,"reason":"pending","path":PackedVector3Array()}
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
	if _surface_index_worker!=null:_surface_index_worker.wait_to_finish();_surface_index_worker=null
	for job:RefCounted in _source_jobs.values():job.finish()
	for job:RefCounted in _orphan_sources:job.finish()
	_source_jobs.clear();_orphan_sources.clear()
	if _face_worker!=null:_face_worker.wait_to_finish();_face_worker=null
	if _cache_writer!=null:_cache_writer.wait_to_finish();_cache_writer=null
	if region.is_valid():
		NavigationServer3D.free_rid(region)
	if map.is_valid():
		NavigationServer3D.free_rid(map)
