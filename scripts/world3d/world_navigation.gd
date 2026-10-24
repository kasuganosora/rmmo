extends Node
const CpuMesh=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const FrameBudget=preload("res://scripts/world3d/frame_work_budget.gd")
const EMPTY_APPEND_RECORD:Dictionary={}
static var ordered_retirement_catalog_enabled:=true
static var lazy_retirement_snapshot_enabled:=true
var covered_loading:=false
var publication_guard:Callable=Callable() # Optional map/transaction lifetime validator.
var preparation_timeout_msec:=180000
var _preparation_started_msec:=-1
var _terminal_state:=""
var _terminal_reason:=""
var _work_deadline_usec:=0
var _budget_slice_active:=false
var _retiring:=false
var _retire_reparenting:=false
# Bound Recast's temporary voxel allocation while gameplay is already running.
# 350 m tiles at 10 cm precision created 12.25 million cells in one bake.
const TILE_SIZE:=128.0
## Recast detail heights sample an already quantized 10 cm heightfield. A
## one-voxel tolerance creates overlapping detail triangles on broad, nearly
## flat terrain. Two voxels preserve contours/obstacles and stair voxelization;
## the physical controller still follows the actual collision surface.
const DETAIL_HEIGHT_ERROR:=.2
## A separate meter-space navigation map; bridges and ground remain separate polygons.
var loading_profile:Dictionary={}
var runtime_geometry_key:=""
var _cache_key:=""
var _cache_hit:=false
var _initial_cache_key:=""
var _initial_cache_hit:=false
## Optional entry-plan X/Z footprint, configured before build. Its Y extent is
## a dependency-query sentinel, not a Recast voxel allocation height.
var initial_geometry_clip:Variant=null
var follow_guard_margin:=2.0
var _initial_geometry_clip_active:=false
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
var _spec_snapshot:Array=[]
var _spec_snapshot_dirty:=false
var _specs:Array:
	get:
		if _spec_snapshot_dirty:
			_spec_snapshot=_spec_ids.values();_spec_snapshot_dirty=false
			loading_profile.retirement_snapshot_rows=int(loading_profile.get("retirement_snapshot_rows",0))+_spec_snapshot.size()
		return _spec_snapshot
	set(value):
		_spec_snapshot=value;_spec_snapshot_dirty=false
var _faces := {}
var _box_faces := PackedVector3Array()
var nearby_source_count := 0
var full_source_count := 0
var face_extractions := 0
var prepared_face_hits := 0
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
var _resize_replacement:Node
var _resize_cancelled:=false
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
var _surface_profile_samples:Array=[]
var _surface_profile_dropped:=0
var _surface_index:RefCounted
var _surface_index_worker:Thread
var _surface_index_mesh:NavigationMesh
var _surface_index_map:=RID()
var _surface_index_iteration:=-1
var _face_worker:Thread
var _face_worker_key:=0
var _source_jobs:Dictionary={}
var _orphan_sources:Array=[]
var geometry_pending:=false
var geometry_error:=""
var _geometry_was_pending:=false
var _geometry_provider:Callable
var _spec_ids:Dictionary={}
var _spec_geometry:Dictionary={} # Scalar ownership, no second mesh/resource owner.
var _geometry_users:Dictionary={}
static var legacy_retirement_geometry_scan_enabled:=false
static var coalesced_retirement_owners_enabled:=true
var _nearby_request:Variant=null
var _full_started:=false
var streaming_geometry:=false
const FOREGROUND_PADDING:=[16.0,32.0,64.0,96.0]
const FOREGROUND_MAX_DISTANCE:=160.0
var _geometry_release:Callable
var _request_generation:=0
var _nearby_generation:=-1
var _nearby_publish_generation:=-1
var _foreground_goal:Variant=null
var _foreground_start:=Vector3.ZERO
var _foreground_level:=-1
var _foreground_clip:Variant=null
var _foreground_waiting:=false
var _foreground_no_path:=false
var _request_geometry_error:=""
var foreground_timeout_msec:=180000
var _foreground_deadline_msec:=-1
var _foreground_timed_out:=false

func capability_status()->Dictionary:
	var state:=_terminal_state;var reason:=_terminal_reason
	if _disposed:state="cancelled";reason="disposed"
	elif state.is_empty():
		if ready_for_queries:state="ready"
		elif not geometry_error.is_empty():state="failed";reason=geometry_error
		elif not str(loading_profile.get("error","")).is_empty():state="failed";reason=str(loading_profile.error)
		else:state="pending";reason="navigation_pending"
	return {"ok":state=="ready","state":state,"reason":reason,"version":version,"instance_id":get_instance_id(),"geometry_key":runtime_geometry_key,"phase":_phase,
		"foreground_generation":_request_generation,"foreground_level":_foreground_level,"foreground_pending":_foreground_waiting,"foreground_no_path":_foreground_no_path,"foreground_clip":_foreground_clip,"foreground_goal":_foreground_goal,"foreground_deadline_msec":_foreground_deadline_msec,"foreground_terminal_reason":"navigation_timeout" if _foreground_timed_out else "","geometry_error":_query_geometry_error(),"geometry_wait_reason":loading_profile.get("geometry_wait_reason","")}

func cancel_background(reason:String="cancelled")->void:
	_stop_background("cancelled",reason)

## Keep the Node and its immutable worker/server snapshots alive outside the
## retiring world. Ordinary transfers never join a live worker on this call.
## Application shutdown still uses _exit_tree's final cleanup.
func retire_background(reason:String="retired")->bool:
	if _retiring:return true
	if not is_inside_tree() or is_queued_for_deletion():return false
	cancel_background(reason);_retiring=true
	loading_profile.retire_started_us=Time.get_ticks_usec()
	var destination:=get_tree().root
	if get_parent()!=destination:
		_set_retire_reparenting(true);reparent(destination);_set_retire_reparenting(false)
	set_process(true);set_physics_process(false)
	return true

func _set_retire_reparenting(value:bool)->void:
	_retire_reparenting=value
	# A resize candidate is also retaining its own source/server jobs. Moving
	# its parent must not run the child's final destructor halfway through.
	if is_instance_valid(_resize_replacement):_resize_replacement._set_retire_reparenting(value)

func _stop_background(state:String,reason:String)->void:
	if not _terminal_state.is_empty():return
	cancel_foreground_request()
	_terminal_state=state;_terminal_reason=reason;ready_for_queries=false;fully_ready=false
	_resize_cancelled=true;_publish_wait=0;_nearby_publish_wait=0;_deferred_full_publish=false;_final_pending=false
	if is_instance_valid(_resize_replacement):_resize_replacement.cancel_background(reason)
	loading_profile.capability_state=state;loading_profile.capability_reason=reason

func _publication_current()->bool:
	if _disposed or not _terminal_state.is_empty():return false
	if publication_guard.is_valid() and not publication_guard.call():
		cancel_background("obsolete");return false
	return true

## A resident map never promises that all geometry will remain loaded forever.
## Configure before build; the provider completes one requested footprint.
func configure_streaming_geometry(provider:Callable,release_request:Callable=Callable())->bool:
	if map.is_valid() or not provider.is_valid():return false
	streaming_geometry=true;_geometry_provider=provider;_geometry_release=release_request
	geometry_pending=true;_geometry_was_pending=true;fully_ready=false
	loading_profile.geometry_pending=true;loading_profile.streaming_geometry=true
	return true

## This releases navigation's references only. The residency owner must first
## protect live render/collision cells, navigation clips, and transfer pins.
## No await or mutation precedes complete validation, so a busy retry is safe.
func try_retire_specs(ids:Array)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_navigation.try_retire_specs") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not streaming_geometry:return {"ok":false,"reason":"not_streaming","removed":0}
	var requested:Dictionary={}
	for id:Variant in ids:
		if not id is String or id.is_empty():return {"ok":false,"reason":"invalid_uuid","removed":0}
		if not _spec_ids.has(id):return {"ok":false,"reason":"unknown_uuid","removed":0}
		requested[id]=true
	loading_profile.retirement_selection_entries=int(loading_profile.get("retirement_selection_entries",0))+requested.size()
	return _retire_selected(requested)

## The stream index has already validated and deduplicated this selection in
## the same synchronous transaction. Borrow it; navigation still checks its
## own membership and every active consumer before releasing any source.
func _try_retire_index_selection(requested:Dictionary)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_navigation.try_retire_specs") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not streaming_geometry:return {"ok":false,"reason":"not_streaming","removed":0}
	if not _spec_ids.has_all(requested.keys()):return {"ok":false,"reason":"unknown_uuid","removed":0}
	return _retire_selected(requested)

func _retire_selected(requested:Dictionary)->Dictionary:
	if requested.is_empty():return {"ok":true,"reason":"","removed":0}
	# nearby_navigation scans owner._specs by cursor. Even removal of an
	# unrelated item would change the meaning of its next index mid-build.
	if not ready_for_queries or _resizing or _phase not in ["","waiting_geometry"] or _nearby!=null or _nearby_request!=null:
		return {"ok":false,"reason":"source_in_use","removed":0}
	if _face_worker!=null or not _source_jobs.is_empty() or not _orphan_sources.is_empty() or _surface_index_worker!=null or _cache_writer!=null:
		return {"ok":false,"reason":"worker_in_use","removed":0}
	if source.has_meta("pending_faces") or not _bake_pending.is_empty() or _baking_mesh!=null or NavigationServer3D.is_baking_navigation_mesh(mesh):
		return {"ok":false,"reason":"bake_in_use","removed":0}
	if _publish_wait>0 or _nearby_publish_wait>0 or _deferred_full_publish or _final_pending:
		return {"ok":false,"reason":"publication_in_use","removed":0}
	var survivors:Array=[];var doors:Array=[];var retained_geometry:Dictionary={}
	var ordered:=ordered_retirement_catalog_enabled and not legacy_retirement_geometry_scan_enabled
	var sparse:=false
	if ordered:
		# Streaming IDs own the same immutable specs in append order. Removing
		# IDs then materializing values avoids a GDScript scan of every survivor.
		if coalesced_retirement_owners_enabled:
			# Identity, source and geometry are the same ownership transaction.
			# Visit each removed UUID once; shared geometry counts are updated once
			# per distinct owner instead of once per repeated house instance.
			var counts:Dictionary={}
			for id:String in requested:
				_spec_ids.erase(id)
				var key:Variant=_spec_geometry.get(id)
				if key==null:continue
				_spec_geometry.erase(id);counts[key]=int(counts.get(key,0))+1
			for key:int in counts:
				var users:=int(_geometry_users.get(key,0))-int(counts[key])
				if users<=0:_geometry_users.erase(key);_faces.erase(key)
				else:_geometry_users[key]=users
			loading_profile.retirement_geometry_updates=int(loading_profile.get("retirement_geometry_updates",0))+counts.size()
		else:
			for id:String in requested:_spec_ids.erase(id)
		if not lazy_retirement_snapshot_enabled:
			survivors=_spec_ids.values()
			loading_profile.retirement_snapshot_rows=int(loading_profile.get("retirement_snapshot_rows",0))+survivors.size()
	elif not legacy_retirement_geometry_scan_enabled and requested.size()<=16:
		survivors=_specs.duplicate()
		sparse=preload("res://scripts/world3d/source_list_retirement.gd").erase_small(survivors,_spec_ids,requested)
	if not ordered and not sparse:
		survivors.clear()
		for spec:Dictionary in _specs:
			if requested.has(spec.get("uuid","")):continue
			survivors.append(spec)
			if legacy_retirement_geometry_scan_enabled:
				var geometry:Resource=_source_geometry(spec)
				if geometry!=null:retained_geometry[geometry.get_instance_id()]=true
	for door:Dictionary in _doors:
		if not requested.has(door.get("uuid","")):doors.append(door)
	if ordered and lazy_retirement_snapshot_enabled:
		# No source cursor/worker is live past the guards above. Release this
		# snapshot immediately; only a later traversal needs ordered survivors.
		_spec_snapshot=[];_spec_snapshot_dirty=true
	else:_specs=survivors
	_doors=doors;_cursor=0
	if not ordered or not coalesced_retirement_owners_enabled:
		for id:String in requested:
			_spec_ids.erase(id);_forget_source_geometry(id)
		loading_profile.retirement_geometry_updates=int(loading_profile.get("retirement_geometry_updates",0))+requested.size()
	if legacy_retirement_geometry_scan_enabled:
		for key:Variant in _faces.keys():
			if not retained_geometry.has(key):_faces.erase(key)
	# The published mesh owns baked polygons, not this completed source soup.
	# Future nearby work creates a separate source from freshly admitted specs.
	source.clear()
	loading_profile.retired_specs=int(loading_profile.get("retired_specs",0))+requested.size()
	return {"ok":true,"reason":"","removed":requested.size()}

## Configure before build. A true provider result promises the complete,
## immutable geometry across clip's X/Z footprint (all heights) has already
## been appended on this thread.
func configure_geometry_provider(provider:Callable,release_request:Callable=Callable())->void:
	_geometry_provider=provider;_geometry_release=release_request

func set_geometry_pending(value:bool)->bool:
	# A momentarily empty queue is not global completeness in a resident map.
	if streaming_geometry and not value:return false
	if value and not geometry_pending and map.is_valid():return false
	if not value and not geometry_error.is_empty():return false
	geometry_pending=value
	_geometry_was_pending=_geometry_was_pending or value
	loading_profile.geometry_pending=value
	if value:fully_ready=false
	elif ready_for_queries and _phase=="waiting_geometry":_start_full_bake()
	return true

func set_geometry_error(reason:String)->void:
	geometry_error=reason;loading_profile.geometry_error=reason

func _ensure_geometry(clip:AABB)->bool:
	if not geometry_pending and not streaming_geometry:return true
	if not geometry_error.is_empty():return false
	if not _geometry_provider.is_valid():
		loading_profile.geometry_wait_reason="provider_missing";return false
	var result:Variant=_geometry_provider.call(clip)
	var complete:bool=result is bool and result
	_request_geometry_error=""
	if result is Dictionary:
		_request_geometry_error=str(result.get("error",""))
		complete=result.get("ok",false)==true and _request_geometry_error.is_empty()
		# An initial failure has no prior usable map to preserve. Once resident,
		# failures belong to the current requested clip, not the whole map.
		if not ready_for_queries and not _request_geometry_error.is_empty():set_geometry_error(_request_geometry_error)
	loading_profile.geometry_wait_reason=_request_geometry_error if not _request_geometry_error.is_empty() else ("" if complete else "geometry_pending")
	return complete

func _query_geometry_error()->String:
	return geometry_error if not geometry_error.is_empty() else _request_geometry_error

func _expanded_geometry_height(clip:AABB)->AABB:
	# The provider completes the entire X/Z footprint, including all storeys.
	# Its append may have raised/lowered bounds while this request was waiting.
	# Preserve X/Z and only widen Y, so newly available upper floors are baked.
	if not _has_bounds:return clip
	var low:float=minf(clip.position.y,_bounds.position.y-2)
	var high:float=maxf(clip.end.y,_bounds.end.y+2)
	if not is_finite(low) or not is_finite(high):
		set_geometry_error("Nonfinite deferred navigation bounds");return clip
	return AABB(Vector3(clip.position.x,low,clip.position.z),Vector3(clip.size.x,high-low,clip.size.z))

func _complete_initial_geometry()->bool:
	if not _ensure_geometry(_clip):return false
	if _geometry_was_pending:
		_clip=_expanded_geometry_height(_clip)
		if not geometry_error.is_empty():return false
		mesh.filter_baking_aabb=_clip;_local_clip=_clip
	return true

func append_specs(additions:Array,prepared:RefCounted=null)->Dictionary:
	if not streaming_geometry and (not geometry_pending or fully_ready):return {"ok":false,"reason":"geometry_not_pending","added":0}
	if not map.is_valid():return {"ok":false,"reason":"navigation_not_built","added":0}
	if prepared!=null:return _append_prepared_specs(additions,prepared)
	var ids:Dictionary={};var doors:Array=[];var geometry_ids:Dictionary={};var geometry_counts:Dictionary={};var aliases:=false
	var bounds_after:=_bounds;var has_bounds_after:=_has_bounds
	for value:Variant in additions:
		if not value is Dictionary:return {"ok":false,"reason":"invalid_spec","added":0}
		var raw_id:Variant=value.get("uuid");var raw_mesh:Variant=value.get("mesh");var raw_pose:Variant=value.get("transform")
		if not raw_id is String or raw_id.is_empty() or not raw_mesh is Mesh or not raw_pose is Transform3D:return {"ok":false,"reason":"invalid_spec","added":0}
		var id:String=raw_id;var source_mesh:Mesh=raw_mesh;var pose:Transform3D=raw_pose
		if not pose.is_finite():return {"ok":false,"reason":"invalid_spec","added":0}
		var extra:Variant=value.get("extras",EMPTY_APPEND_RECORD)
		if not extra is Dictionary or not extra.get("fixture",EMPTY_APPEND_RECORD) is Dictionary:return {"ok":false,"reason":"invalid_spec","added":0}
		var shape:Variant=value.get("shape");var collision:Variant=value.get("collision_mesh")
		if shape!=null and not shape is Shape3D:return {"ok":false,"reason":"invalid_spec","added":0}
		if collision!=null and not collision is Mesh:return {"ok":false,"reason":"invalid_spec","added":0}
		var bounds:AABB=pose*source_mesh.get_aabb()
		if not bounds.position.is_finite() or not bounds.size.is_finite():return {"ok":false,"reason":"invalid_spec","added":0}
		if ids.has(id) or _spec_ids.has(id):return {"ok":false,"reason":"duplicate_uuid","added":0}
		ids[id]=value if streaming_geometry else true
		var geometry:Resource=shape if shape is ConcavePolygonShape3D else value.get("collision_mesh",source_mesh)
		var geometry_id:int=geometry.get_instance_id() if geometry!=null else 0
		geometry_ids[id]=geometry_id;geometry_counts[geometry_id]=int(geometry_counts.get(geometry_id,0))+1
		aliases=aliases or _spec_geometry.has(id)
		var door:bool=extra.get("fixture",EMPTY_APPEND_RECORD).get("kind")=="door"
		if door and extra.get("rmmo_collision","")!="none":doors.append(value)
		# Reuse the checked extras and role instead of looking them up again for
		# every part. Keep _collides' conversions and the original merge order.
		if not door and str(extra.get("rmmo_collision",""))!="none" and not bool(extra.get("hostile",false)) and not bool(extra.get("ally",false)):
			bounds_after=bounds_after.merge(bounds) if has_bounds_after else bounds;has_bounds_after=true
	# All source checks finished. Reuse those exact bounds and keep the source
	# geometry-user lifecycle operation unchanged, including any old aliases.
	if not _spec_snapshot_dirty:_spec_snapshot.append_array(additions)
	_spec_ids.merge(ids,true);_doors.append_array(doors)
	if aliases:
		# Preserve per-source alias rebinding order, including transient face
		# cache ownership. Ordinary new UUIDs use the validated bulk metadata.
		for spec:Dictionary in additions:_remember_source_geometry(spec)
	else:
		_spec_geometry.merge(geometry_ids,true)
		for key:int in geometry_counts:_geometry_users[key]=int(_geometry_users.get(key,0))+int(geometry_counts[key])
	_bounds=bounds_after;_has_bounds=has_bounds_after
	loading_profile.appended_specs=int(loading_profile.get("appended_specs",0))+additions.size()
	if is_instance_valid(_resize_replacement):
		var forwarded:Dictionary=_resize_replacement.append_specs(additions)
		if not forwarded.ok:_resize_replacement.set_geometry_error(str(forwarded.reason))
	return {"ok":true,"reason":"","added":additions.size()}

func _append_prepared_specs(additions:Array,packet:RefCounted)->Dictionary:
	if packet.get_script()!=preload("res://scripts/world3d/publication_metadata.gd") or not packet.ready(additions):return {"ok":false,"reason":"stale_publication_packet","added":0}
	var aliases:=false
	# A separate navigation can retire or receive other publications while the
	# private packet prepares. Check its current membership at the actual commit.
	for id:String in packet.ids:
		if _spec_ids.has(id):return {"ok":false,"reason":"duplicate_uuid","added":0}
		aliases=aliases or _spec_geometry.has(id)
	if not _spec_snapshot_dirty:_spec_snapshot.append_array(additions)
	if streaming_geometry:_spec_ids.merge(packet.ids,true)
	else:
		# Full-map navigation releases source specs after baking. Its identity
		# set must not become a second persistent resource owner.
		for id:String in packet.ids:_spec_ids[id]=true
	_doors.append_array(packet.doors)
	if aliases:
		for spec:Dictionary in additions:_remember_source_geometry(spec)
	else:
		_spec_geometry.merge(packet.geometry_ids,true)
		for key:int in packet.geometry_counts:_geometry_users[key]=int(_geometry_users.get(key,0))+int(packet.geometry_counts[key])
	for bounds:AABB in packet.bounds:
		_bounds=_bounds.merge(bounds) if _has_bounds else bounds;_has_bounds=true
	loading_profile.appended_specs=int(loading_profile.get("appended_specs",0))+additions.size()
	if is_instance_valid(_resize_replacement):
		var forwarded:Dictionary=_resize_replacement.append_specs(additions,packet)
		if not forwarded.ok:_resize_replacement.set_geometry_error(str(forwarded.reason))
	return {"ok":true,"reason":"","added":additions.size()}

func _navigation_cache_key()->String:
	if runtime_geometry_key.is_empty():return ""
	return runtime_geometry_key+str(mesh.agent_height)+FileAccess.get_sha256(get_script().resource_path)+FileAccess.get_sha256("res://scripts/world3d/navigation_cache.gd")

func follow(position:Vector3,goal:Variant=null)->void:
	if _resizing:return
	if not ready_for_queries or fully_ready or _final_pending or not _staged:return
	if _compact_follow():
		if goal is Vector3 and _within_foreground_range(position,goal):
			_begin_foreground(position,goal)
			if _foreground_timed_out:return
			if _foreground_waiting:_try_nearby_request();return
			if _inside_local(position,2) and _inside_local(goal,2):return
			_queue_foreground(0);return
		# Normal per-frame following must not replace a pending explicit click.
		if goal==null and _foreground_goal is Vector3:return
	if _nearby!=null or _nearby_publish_wait>0:return
	var margin:=follow_guard_margin if _compact_follow() or _initial_geometry_clip_active else 48.0
	if goal==null and _inside_local(position,margin):return
	if goal is Vector3 and _inside_local(position,2) and _inside_local(goal,2):return
	if goal is Vector3 and not _within_foreground_range(position,goal) and _inside_local(position,margin):return
	var area:=_legacy_follow_area(position,goal)
	if _compact_follow() and goal==null:
		area=_corridor_area(position,position,16.)
		# Freeze an outstanding manual request until the actor leaves its safe
		# interior, rather than invalidating its provider ticket every centimetre.
		if _nearby_request is AABB and _contains_xz(_nearby_request,position,2):_try_nearby_request();return
	_request_generation+=1
	_request_geometry_error=""
	_nearby_request=area
	_try_nearby_request()

func _compact_follow()->bool:
	return streaming_geometry and initial_geometry_clip is AABB

func _within_foreground_range(start:Vector3,goal:Vector3)->bool:
	return Vector2(goal.x-start.x,goal.z-start.z).length()<=FOREGROUND_MAX_DISTANCE

func _legacy_follow_area(position:Vector3,goal:Variant=null)->AABB:
	var area:=AABB(Vector3(position.x-96,_bounds.position.y-2,position.z-96),Vector3(192,_bounds.size.y+4,192))
	if goal is Vector3 and _within_foreground_range(position,goal):
		area=area.expand(Vector3(goal.x-16,area.position.y,goal.z-16)).expand(Vector3(goal.x+16,area.end.y,goal.z+16))
	return area

func _corridor_area(start:Vector3,goal:Vector3,padding:float)->AABB:
	var low:=Vector3(minf(start.x,goal.x)-padding,_bounds.position.y-2,minf(start.z,goal.z)-padding)
	var high:=Vector3(maxf(start.x,goal.x)+padding,_bounds.end.y+2,maxf(start.z,goal.z)+padding)
	return AABB(low,high-low).intersection(_legacy_follow_area(start,goal))

func _contains_xz(area:AABB,point:Vector3,margin:float)->bool:
	return point.x>=area.position.x+margin and point.x<=area.end.x-margin and point.z>=area.position.z+margin and point.z<=area.end.z-margin

func _follow_passive(start:Vector3,goal:Vector3)->void:
	# NPC/summon/skill queries share this navigator. They may inspect the
	# resident mesh but never replace the player's foreground dependency lease.
	if _foreground_goal is Vector3 or _resizing or not ready_for_queries or fully_ready or not _staged or _final_pending:return
	if _nearby!=null or _nearby_publish_wait>0:return
	if not _within_foreground_range(start,goal):follow(start);return
	if _nearby_request is AABB and _contains_xz(_nearby_request,start,2) and _contains_xz(_nearby_request,goal,2):_try_nearby_request();return
	_request_generation+=1
	_request_geometry_error=""
	# Passive actors have no foreground expansion state. Retain their original
	# complete detour window rather than falsely declaring a narrow corridor
	# unreachable; an explicit player request can supersede this preparation.
	_nearby_request=_legacy_follow_area(start,goal)
	_try_nearby_request()

func _begin_foreground(start:Vector3,goal:Vector3)->void:
	if _foreground_goal is Vector3 and _foreground_goal.distance_squared_to(goal)<.000001:return
	cancel_foreground_request()
	_foreground_goal=goal;_foreground_start=start
	_foreground_deadline_msec=Time.get_ticks_msec()+maxi(1,foreground_timeout_msec)

func _poll_foreground_deadline(now_msec:int=-1)->void:
	if _foreground_timed_out or _foreground_deadline_msec<0 or not _foreground_goal is Vector3:return
	if now_msec<0:now_msec=Time.get_ticks_msec()
	if now_msec<_foreground_deadline_msec:return
	# Retain a terminal receipt for automatic polls, but immediately stop the
	# dependency lease and invalidate unfinished source/bake work. A submitted
	# server update may still settle to its factual clip; it cannot clear this.
	_foreground_timed_out=true;_foreground_waiting=false
	_request_generation+=1;_nearby_request=null;_request_geometry_error=""
	if _geometry_release.is_valid():_geometry_release.call()

## An expected goal prevents one actor from cancelling another actor's request.
## An already submitted server update still settles to its factual clip; its
## generation can never complete a replacement foreground request.
func cancel_foreground_request(expected_goal:Variant=null)->bool:
	if expected_goal is Vector3 and (not _foreground_goal is Vector3 or _foreground_goal.distance_squared_to(expected_goal)>=.000001):return false
	_request_generation+=1;_nearby_request=null
	_foreground_goal=null;_foreground_clip=null;_foreground_level=-1
	_foreground_waiting=false;_foreground_no_path=false
	_request_geometry_error=""
	_foreground_deadline_msec=-1;_foreground_timed_out=false
	if _geometry_release.is_valid():_geometry_release.call()
	return true

func _queue_foreground(level:int)->void:
	_request_generation+=1;_foreground_level=level
	# A route already delivered may later require revalidation after a genuine
	# map revision. Only that new preparation gets a new deadline; expansion
	# and repeated polls of an unfinished attempt retain the original one.
	if _foreground_deadline_msec<0:_foreground_deadline_msec=Time.get_ticks_msec()+maxi(1,foreground_timeout_msec)
	_request_geometry_error=""
	_foreground_clip=_corridor_area(_foreground_start,_foreground_goal,FOREGROUND_PADDING[level])
	_foreground_waiting=true;_foreground_no_path=false;_nearby_request=_foreground_clip
	_try_nearby_request()

func _foreground_unreachable()->Dictionary:
	# Only a complete, synchronized query/bake can request a larger closure.
	# Repeated queries while any stage is pending never spend another level.
	if _foreground_waiting:return {"ok":false,"reason":"pending","path":PackedVector3Array()}
	if _foreground_level+1<FOREGROUND_PADDING.size():
		_queue_foreground(_foreground_level+1)
		return {"ok":false,"reason":"pending","path":PackedVector3Array()}
	_foreground_no_path=true
	_foreground_deadline_msec=-1
	return {"ok":false,"reason":"unreachable","path":PackedVector3Array()}

func _try_nearby_request()->void:
	if not ready_for_queries or not _staged or _nearby_request==null or _nearby!=null or _nearby_publish_wait>0 or fully_ready or _final_pending:return
	if not _ensure_geometry(_nearby_request):return
	if _geometry_was_pending:
		_nearby_request=_expanded_geometry_height(_nearby_request)
		if not geometry_error.is_empty():return
	_nearby=preload("res://scripts/world3d/nearby_navigation.gd").new(mesh,_nearby_request)
	_nearby_generation=_request_generation
	_nearby_request=null

func _inside_local(point:Vector3,margin:float)->bool:
	return point.x>=_local_clip.position.x+margin and point.x<=_local_clip.end.x-margin and point.z>=_local_clip.position.z+margin and point.z<=_local_clip.end.z-margin

func _step_nearby()->bool:
	if _nearby!=null and _nearby_generation!=_request_generation:
		# Recast owns the mesh and source until its async bake has ended. Do not
		# join, free them early, or keep advancing an obsolete CPU source scan.
		if _nearby.baking and NavigationServer3D.is_baking_navigation_mesh(_nearby.mesh):return true
		_discard_source(_nearby.source);_nearby=null
	_try_nearby_request()
	if _nearby==null:return false
	if fully_ready or _final_pending:_discard_source(_nearby.source);_nearby=null;return true
	_nearby.step(self,mini(2000,maxi(1,_work_deadline_usec-Time.get_ticks_usec())))
	if not _nearby.complete:return true
	if _nearby.mesh.get_polygon_count()>0:
		_nearby_mesh=_nearby.mesh;_nearby_clip=_nearby.clip
		_nearby_publish_generation=_nearby_generation
		NavigationServer3D.region_set_use_async_iterations(region,true)
		_nearby_iteration=NavigationServer3D.map_get_iteration_id(map)
		_nearby_region_iteration=NavigationServer3D.region_get_iteration_id(region)
		NavigationServer3D.region_set_navigation_mesh(region,_nearby_mesh)
		_nearby_publish_wait=2
		loading_profile.nearby_refreshes=int(loading_profile.get("nearby_refreshes",0))+1
		loading_profile.nearby_last_ms=Time.get_ticks_msec()-_nearby.started_ms
	elif _foreground_waiting and _foreground_goal is Vector3:
		# A completed empty bake is a no-route result, not a pending server
		# iteration. Preserve the last usable map while bounded expansion runs.
		_foreground_waiting=false
		_nearby=null
		_foreground_unreachable();version+=1
		return true
	_nearby=null
	return true


func resize_agent(height:float,specs:Array,origin:Vector3)->void:
	if not _publication_current():return
	# Keep this Node stable: player, NPC and summon authorities hold weak refs.
	# Bake in a child map and swap only a complete result; never reset combat.
	if streaming_geometry:
		await _resize_streaming_agent(height,specs,origin)
		return
	if _resizing or not fully_ready or is_equal_approx(height,agent_height):return
	_resizing=true;_resize_cancelled=false
	var replacement=get_script().new();replacement.agent_height=height;add_child(replacement)
	_resize_replacement=replacement
	replacement.runtime_geometry_key=runtime_geometry_key
	replacement.build(specs,origin)
	while not replacement.fully_ready and not _resize_cancelled:
		if replacement.capability_status().state in ["failed","cancelled"]:break
		await get_tree().process_frame
	replacement.set_process(false);replacement.set_physics_process(false)
	while true:
		var old_idle:=_poll_resize_drain()
		var next_idle:bool=replacement._poll_resize_drain()
		if old_idle and next_idle:break
		await get_tree().process_frame
	_resize_replacement=null
	if _resize_cancelled or not replacement.fully_ready:
		replacement.free();_resizing=false;return
	NavigationServer3D.free_rid(region);NavigationServer3D.free_rid(map)
	map=replacement.map;region=replacement.region;mesh=replacement.mesh
	replacement.map=RID();replacement.region=RID()
	_doors=replacement._doors;agent_height=height;version+=1
	replacement.queue_free();_resizing=false

func cancel_resize()->void:
	# set_process(false) does not stop an already-awaiting resize coroutine or
	# its child navigator. The transaction owner waits for explicit retirement.
	if not _resizing:return
	_resize_cancelled=true
	while _resizing:await get_tree().process_frame

func _resize_streaming_agent(height:float,specs:Array,origin:Vector3)->void:
	if _resizing or not ready_for_queries or not is_finite(height) or height<=0 or not origin.is_finite() or is_equal_approx(height,agent_height):return
	# Do not interrupt a server handoff already submitted by the old navigator.
	# The regular caller retries after that publication has settled.
	if _publish_wait>0 or _nearby_publish_wait>0 or _final_pending:return
	_resizing=true;_resize_cancelled=false
	loading_profile.erase("resize_cancelled")
	var previous_request:Variant=_nearby.clip if _nearby!=null else _nearby_request
	var replacement=get_script().new();replacement.agent_height=height
	if _initial_geometry_clip_active and _inside_local(origin,follow_guard_margin):
		replacement.initial_geometry_clip=_local_clip;replacement.follow_guard_margin=follow_guard_margin
	if not replacement.configure_streaming_geometry(_geometry_provider):_resizing=false;replacement.free();return
	add_child(replacement);_resize_replacement=replacement
	replacement.runtime_geometry_key=runtime_geometry_key
	replacement.build(specs,origin)
	var deadline:=Time.get_ticks_msec()+180000
	var failure:=""
	while not replacement.ready_for_queries:
		if _resize_cancelled:break
		# Retire old in-flight snapshots while its published map remains usable.
		# No thread join happens until is_alive() is false.
		_poll_resize_drain()
		failure=str(replacement.geometry_error)
		if failure.is_empty():failure=str(replacement.loading_profile.get("error",""))
		if not failure.is_empty():break
		if Time.get_ticks_msec()>deadline:failure="Local navigation resize timed out";break
		await get_tree().process_frame
	replacement.set_process(false);replacement.set_physics_process(false)
	# Both CPU source builders and server bakes own snapshots beyond their Node
	# call sites. Keep old and candidate resources until their leases have ended.
	while true:
		var old_idle:=_poll_resize_drain()
		var next_idle:bool=replacement._poll_resize_drain()
		if old_idle and next_idle:break
		await get_tree().process_frame
	_resize_replacement=null
	if _resize_cancelled or not failure.is_empty() or not replacement.ready_for_queries:
		if _resize_cancelled:loading_profile.resize_cancelled=true
		else:loading_profile.resize_error=failure
		replacement.free();_nearby_request=previous_request;_resizing=false
		return
	var old_map:=map;var old_region:=region
	map=replacement.map;region=replacement.region;mesh=replacement.mesh;source=replacement.source
	replacement.map=RID();replacement.region=RID()
	_specs=replacement._specs;_spec_ids=replacement._spec_ids;_doors=replacement._doors
	_spec_geometry=replacement._spec_geometry;_geometry_users=replacement._geometry_users
	_faces=replacement._faces;_box_faces=replacement._box_faces
	_bounds=replacement._bounds;_has_bounds=replacement._has_bounds
	_clip=replacement._clip;_local_clip=replacement._local_clip;_origin=origin;_staged=true
	_initial_geometry_clip_active=replacement._initial_geometry_clip_active
	_phase="waiting_geometry";_cursor=0;_nearby_request=null
	_foreground_waiting=false;_foreground_level=-1;_foreground_clip=null;_foreground_no_path=false
	_surface_index=null;_surface_index_mesh=null;_surface_index_map=RID();_surface_index_iteration=-1
	_surface_point=Vector3.INF;_surface_map=RID();_surface_iteration=-1
	agent_height=height;version+=1;fully_ready=false
	loading_profile.erase("resize_error")
	loading_profile.resize_count=int(loading_profile.get("resize_count",0))+1
	loading_profile.resize_height=height
	if old_region.is_valid():NavigationServer3D.free_rid(old_region)
	if old_map.is_valid():NavigationServer3D.free_rid(old_map)
	replacement.free();_resizing=false

func _poll_resize_drain()->bool:
	var ready:=true
	if _face_worker!=null:
		if _face_worker.is_alive():ready=false
		else:_face_worker.wait_to_finish();_face_worker=null
	if _surface_index_worker!=null:
		if _surface_index_worker.is_alive():ready=false
		else:_surface_index_worker.wait_to_finish();_surface_index_worker=null
	if _cache_writer!=null:
		if _cache_writer.is_alive():ready=false
		else:_cache_writer.wait_to_finish();_cache_writer=null
	for target:Variant in _source_jobs.keys():
		if _source_jobs[target].poll():_source_jobs.erase(target)
		else:ready=false
	for i in range(_orphan_sources.size()-1,-1,-1):
		if _orphan_sources[i].poll():_orphan_sources.remove_at(i)
		else:ready=false
	if _nearby!=null:
		if _nearby.baking and NavigationServer3D.is_baking_navigation_mesh(_nearby.mesh):ready=false
		else:_nearby=null
	if _baking_mesh!=null:
		if NavigationServer3D.is_baking_navigation_mesh(_baking_mesh):ready=false
		else:_baking_mesh=null;_bake_pending=""
	return ready


func build(specs: Array, origin: Variant = null) -> void:
	if not _publication_current():return
	if map.is_valid():set_geometry_error("Navigation instance cannot be built twice");return
	_preparation_started_msec=Time.get_ticks_msec()
	if initial_geometry_clip!=null:
		if not _valid_initial_geometry_clip(origin):
			set_geometry_error("Initial navigation clip requires finite bounds, a contained origin and a safe follow margin");return
		_initial_geometry_clip_active=true
	if geometry_pending and (not origin is Vector3 or not origin.is_finite()):
		set_geometry_error("Deferred navigation requires a finite spawn origin");return
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_use_async_iterations(map, true)
	NavigationServer3D.map_set_active(map, true)
	# Bake voxels remain 10 cm; connecting already-baked polygon edges needs
	# the 1 cm precision used by tile assembly. At voxel precision, distinct
	# cliff/riverbed edges can collapse into a non-manifold four-edge bucket.
	NavigationServer3D.map_set_cell_size(map, 0.01)
	NavigationServer3D.map_set_cell_height(map, 0.01)
	# A 28cm tread needs at least two horizontal cells at every grid phase;
	# 15cm voxels can collapse a tread and disconnect an otherwise valid stair.
	mesh.cell_size = 0.1
	mesh.cell_height = 0.1
	# Use the same contour tolerance for nearby and tiled bakes. The default
	# 1.3-cell simplification can overlap riverbed triangles at clipped banks.
	mesh.edge_max_error = 1.0
	mesh.detail_sample_max_error = DETAIL_HEIGHT_ERROR / mesh.cell_height
	# Extra clearance beyond the capsule avoids polygon simplification
	# placing ramp corner waypoints on the rounded capsule's contact boundary.
	mesh.agent_radius = 0.5
	mesh.agent_height = ceilf(agent_height/mesh.cell_height)*mesh.cell_height
	mesh.agent_max_climb = 0.4
	mesh.agent_max_slope = 40.0
	mesh.filter_walkable_low_height_spans = true
	_specs = specs.duplicate()
	_spec_ids.clear()
	_spec_geometry.clear();_geometry_users.clear()
	for spec:Dictionary in _specs:
		if spec.get("uuid") is String and not spec.uuid.is_empty():
			_spec_ids[spec.uuid]=spec if streaming_geometry else true;_remember_source_geometry(spec)
	# Hinges and handles follow the door but are not navigation obstacles.
	_doors=specs.filter(func(spec):return spec.get("extras",{}).get("fixture",{}).get("kind")=="door" and spec.extras.get("rmmo_collision","")!="none")
	_origin = origin
	_phase = "bounds"
	if not geometry_pending and not runtime_geometry_key.is_empty():
		_cache_key=_navigation_cache_key()
		# An explicit first footprint has its own cache below. A full-map cache
		# must not silently replace this local preparation with a global load.
		_cache_hit=not _initial_geometry_clip_active and preload("res://scripts/world3d/navigation_cache.gd").restore(_cache_key,mesh)
		loading_profile.cache_hit=_cache_hit
		if _cache_hit:_phase="";_baked()

func _valid_initial_geometry_clip(origin:Variant)->bool:
	if not initial_geometry_clip is AABB or not origin is Vector3 or not origin.is_finite():return false
	var clip:AABB=initial_geometry_clip
	if not clip.position.is_finite() or not clip.size.is_finite() or not clip.end.is_finite() or clip.size.x<=0 or clip.size.z<=0 or clip.size.y<0:return false
	if not is_finite(follow_guard_margin) or follow_guard_margin<2.0 or follow_guard_margin*2>=minf(clip.size.x,clip.size.z):return false
	return origin.x>=clip.position.x+follow_guard_margin and origin.x<=clip.end.x-follow_guard_margin and origin.z>=clip.position.z+follow_guard_margin and origin.z<=clip.end.z-follow_guard_margin

func _process(_delta: float) -> void:
	if not _publication_current():
		var budget:=FrameBudget.allowance("retire",500,covered_loading)
		if budget<=0:return
		var started:=Time.get_ticks_usec()
		var drained:=_poll_resize_drain() and not _resizing
		FrameBudget.charge("retire",started)
		if drained:
			set_process(false)
			if _retiring:
				loading_profile.retire_done_us=Time.get_ticks_usec();queue_free()
		return
	# Deadline observation does not need a production-work budget. Exhausted
	# lanes must not hide the terminal result from the player's physics poll.
	_poll_foreground_deadline()
	if not ready_for_queries and _preparation_started_msec>=0 and Time.get_ticks_msec()-_preparation_started_msec>preparation_timeout_msec:
		_stop_background("failed","navigation_timeout");return
	var budget:=FrameBudget.allowance("navigation",12000 if not ready_for_queries else 3000,covered_loading)
	if budget<=0:return
	var started:=Time.get_ticks_usec();var phase:=_phase
	_work_deadline_usec=started+budget
	_budget_slice_active=true
	_step_background()
	_budget_slice_active=false
	FrameBudget.charge("navigation",started)
	if has_meta("profile_frame"):set_meta("background_timing",{"frame":Engine.get_process_frames(),"phase":phase,"ms":(Time.get_ticks_usec()-started)/1000.0})

func _step_background()->void:
	# Direct CPU fixtures may step explicitly without the _process wrapper.
	if not _budget_slice_active:_work_deadline_usec=Time.get_ticks_usec()+(12000 if not ready_for_queries else 3000)
	if _resizing:return
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
	var nearby_work:=_step_nearby()
	if nearby_work and Time.get_ticks_usec()>=_work_deadline_usec:return
	if _phase.is_empty(): return
	if _phase=="waiting_initial_geometry":
		if not _complete_initial_geometry():return
		_phase="source";_cursor=0
	if _phase=="waiting_geometry":
		if not geometry_pending:_start_full_bake()
		return
	if ready_for_queries and geometry_pending:
		_phase="waiting_geometry";return
	if _phase=="prepare_source":
		var prepared:=_prepare_source(source)
		if prepared==null:return
		source=prepared;_phase="";_submit_bake();return
	if _phase in ["tile_vertices","tile_polygons","assemble"]:
		_step_merge();return
	var started := Time.get_ticks_usec()
	var initial_cursor:=_cursor
	var source_specs:Array=_specs
	while _cursor < source_specs.size() and (_cursor==initial_cursor or (Time.get_ticks_usec() - started < (12000 if not ready_for_queries else 3000) and Time.get_ticks_usec()<_work_deadline_usec)):
		var spec: Dictionary = source_specs[_cursor]
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
	if _cursor < source_specs.size(): return
	_cursor = 0
	if _phase == "bounds":
		if _initial_geometry_clip_active:
			_staged=true
			var area:AABB=initial_geometry_clip
			_clip=AABB(Vector3(area.position.x,_bounds.position.y-2,area.position.z),Vector3(area.size.x,_bounds.size.y+4,area.size.z))
			mesh.filter_baking_aabb=_clip;_local_clip=_clip
			loading_profile.initial_geometry_clip=_clip;loading_profile.initial_follow_guard_margin=follow_guard_margin
		elif _origin is Vector3 and (geometry_pending or _bounds.size.x > 192 or _bounds.size.z > 192):
			_staged = true
			_clip = AABB(Vector3(_origin.x - 80, _bounds.position.y - 2, _origin.z - 80), Vector3(160, _bounds.size.y + 4, 160))
			mesh.filter_baking_aabb = _clip
			_local_clip=_clip
		loading_profile.bounds=Time.get_ticks_msec()
		if not geometry_pending and _staged and not _cache_key.is_empty():
			# The small spawn mesh is useful even when the player leaves before
			# the full-town bake finishes. Its exact clip is part of its identity.
			_initial_cache_key=_cache_key+"|initial|"+preload("res://scripts/world3d/map_metadata_cache.gd").checksum(var_to_bytes(_clip)).hex_encode()
			_initial_cache_hit=preload("res://scripts/world3d/navigation_cache.gd").restore(_initial_cache_key,mesh)
			loading_profile.initial_cache_hit=_initial_cache_hit
			if _initial_cache_hit:
				_phase="";_baked();return
		_phase = "source" if _complete_initial_geometry() else "waiting_initial_geometry"
		return
	loading_profile.source=Time.get_ticks_msec()
	if ready_for_queries or source.has_meta("pending_faces"):
		_phase="prepare_source";return
	_phase = ""
	_submit_bake()

func _submit_bake()->void:
	if ready_for_queries and geometry_pending:_phase="waiting_geometry";return
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
	if not ready_for_queries and covered_loading:target.add_faces(faces,pose);return
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


static func _source_geometry(spec:Dictionary)->Resource:
	var shape: Shape3D = spec.get("shape")
	return shape if shape is ConcavePolygonShape3D else spec.get("collision_mesh", spec["mesh"])

func _forget_source_geometry(id:String)->void:
	if not _spec_geometry.has(id):return
	var key:int=_spec_geometry[id];_spec_geometry.erase(id)
	var users:=int(_geometry_users.get(key,0))-1
	if users<=0:_geometry_users.erase(key);_faces.erase(key)
	else:_geometry_users[key]=users

func _remember_source_geometry(spec:Dictionary)->void:
	var id:String=spec.get("uuid","")
	if id.is_empty():return
	var geometry:Resource=_source_geometry(spec)
	var key:int=geometry.get_instance_id() if geometry!=null else 0
	if _spec_geometry.get(id,-1)==key:return
	_forget_source_geometry(id)
	_spec_geometry[id]=key;_geometry_users[key]=int(_geometry_users.get(key,0))+1

func _add_source(target:NavigationMeshSourceGeometryData3D,spec:Dictionary)->bool:
	# A prepared ConcavePolygonShape may replace the original mesh after append.
	# Rebind when navigation consumes it; unconsumed old identities remain only
	# conservative face-cache users until the next consumption or retirement.
	_remember_source_geometry(spec)
	var started:=Time.get_ticks_usec() if has_meta("profile_frame") else 0
	var geometry:Resource=_source_geometry(spec)
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
		if not _faces.has(key) and geometry is CpuMesh and not geometry._collision_faces.is_empty():
			# Completed local-space faces come from this exact immutable capture.
			# Keep their PackedArray value and the original per-instance transform;
			# _queue_faces still owns bounded background source preparation. A
			# prepared soup needs neither index expansion nor another face worker.
			_faces[key]=geometry._collision_faces;prepared_face_hits+=1
		if not _faces.has(key):
			var large_cpu:=false
			if geometry is CpuMesh:
				var count:=0
				for surface:Array in geometry.surfaces:
					var indices:Variant=surface[Mesh.ARRAY_INDEX]
					count+=indices.size() if indices!=null and not indices.is_empty() else surface[Mesh.ARRAY_VERTEX].size()
				large_cpu=count>1536
			if (ready_for_queries or not covered_loading) and large_cpu:
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
	if not _publication_current():return
	if mesh.get_polygon_count()==0:
		_stop_background("failed","navigation_empty");loading_profile.error="Initial navigation bake produced no polygons";return
	loading_profile.baked=Time.get_ticks_msec()
	if not geometry_pending and _staged and not _initial_cache_hit:
		preload("res://scripts/world3d/navigation_cache.gd").store_mesh(_initial_cache_key,mesh)
	region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_use_async_iterations(region, false)
	_publish_region_iteration=NavigationServer3D.region_get_iteration_id(region)
	_publish_iteration=NavigationServer3D.map_get_iteration_id(map)
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	call_deferred("_publish", not _staged)


func _publish(final: bool = true) -> void:
	if not _publication_current():return
	_publish_wait = 2
	_publish_final = final and not geometry_pending and not streaming_geometry

func _physics_process(_delta: float) -> void:
	if not has_meta("profile_frame"):
		_step_publication();return
	var started:=Time.get_ticks_usec()
	_step_publication()
	set_meta("publication_timing",{"frame":Engine.get_process_frames(),"ms":(Time.get_ticks_usec()-started)/1000.0})

func _step_publication()->void:
	if not _publication_current():return
	if _resizing:return
	if _nearby_publish_wait>0:
		_nearby_publish_wait=maxi(1,_nearby_publish_wait-1)
		if NavigationServer3D.region_get_iteration_id(region)!=_nearby_region_iteration and NavigationServer3D.map_get_iteration_id(map)!=_nearby_iteration:
			mesh=_nearby_mesh;_local_clip=_nearby_clip;_nearby_mesh=null
			_initial_geometry_clip_active=false
			if _nearby_publish_generation==_request_generation:_foreground_waiting=false
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
	fully_ready = _publish_final and not geometry_pending and not streaming_geometry
	if fully_ready:
		if not _cache_hit and not _cache_key.is_empty():
			# The published NavigationMesh is immutable. Retain it until the
			# worker finishes serializing/checksumming the atomic cache write.
			var snapshot:=mesh;var key:=_cache_key
			_cache_writer=Thread.new()
			if _cache_writer.start(func():preload("res://scripts/world3d/navigation_cache.gd").store_mesh(key,snapshot))!=OK:_cache_writer=null
		source.clear()
		_specs = []
		_spec_geometry.clear();_geometry_users.clear()
		_faces.clear()
	else:_start_full_bake()

func _start_full_bake()->void:
	if geometry_pending or streaming_geometry:_phase="waiting_geometry";return
	if _full_started or not ready_for_queries:return
	_full_started=true
	_full_mesh = mesh.duplicate()
	_full_mesh.clear()
	_full_mesh.filter_baking_aabb = AABB()
	if _geometry_was_pending:
		_cache_key=_navigation_cache_key()
		if not _cache_key.is_empty():
			_cache_hit=preload("res://scripts/world3d/navigation_cache.gd").restore(_cache_key,_full_mesh)
			loading_profile.cache_hit=_cache_hit
			if _cache_hit:_phase="";_full_baked();return
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
	if geometry_pending:_phase="waiting_geometry";return
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
	var deadline:=mini(Time.get_ticks_usec()+2000,_work_deadline_usec)
	var advanced:=false
	if _phase=="tile_vertices":
		while _cursor<_merge_vertices.size() and (not advanced or Time.get_ticks_usec()<deadline):
			_merge_vertices[_cursor]=_merge_vertices[_cursor].snappedf(.01);_cursor+=1;advanced=true
		if _cursor<_merge_vertices.size():return
		_tile_vertices.append_array(_merge_vertices);_merge_vertices=PackedVector3Array()
		_cursor=0;_phase="tile_polygons"
	if _phase=="tile_polygons":
		while _cursor<_tile_mesh.get_polygon_count() and (not advanced or Time.get_ticks_usec()<deadline):
			var polygon:=_tile_mesh.get_polygon(_cursor)
			for j in polygon.size():polygon[j]+=_merge_offset
			# Centimetre seam snapping may collapse a tiny detail triangle. It
			# encloses no walkable area and must not add repeated graph edges.
			if projected_polygon_valid(polygon,_tile_vertices):_tile_polygons.append(polygon)
			else:loading_profile.degenerate_tile_polygons=int(loading_profile.get("degenerate_tile_polygons",0))+1
			_cursor+=1;advanced=true
		if _cursor<_tile_mesh.get_polygon_count():return
		loading_profile.tiles_remaining=_tiles.size();_next_tile();return
	if _phase=="assemble":
		while _cursor<_tile_polygons.size() and (not advanced or Time.get_ticks_usec()<deadline):
			_full_mesh.add_polygon(_tile_polygons[_cursor]);_cursor+=1;advanced=true
		if _cursor<_tile_polygons.size():return
		_tile_vertices=PackedVector3Array();_tile_polygons.clear();_tile_mesh=null
		_phase="";_full_baked()

static func projected_polygon_valid(polygon:PackedInt32Array,vertices:PackedVector3Array)->bool:
	if polygon.size()<3:return false
	var origin:=vertices[polygon[0]];var twice_area:=0.
	for i in polygon.size():
		var a:=vertices[polygon[i]]-origin;var b:=vertices[polygon[(i+1)%polygon.size()]]-origin
		if a==b:return false
		twice_area+=a.x*b.z-b.x*a.z
	return absf(twice_area)>.00000001

func _full_baked() -> void:
	if not _publication_current():return
	if geometry_pending:_phase="waiting_geometry";return
	if _full_mesh.get_polygon_count()==0:
		loading_profile.error="Full navigation bake produced no polygons; retaining nearby navigation"
		push_error(loading_profile.error);return
	if _nearby!=null:_discard_source(_nearby.source)
	_final_pending=true;_nearby=null
	_deferred_full_publish=true
	if _nearby_publish_wait==0:_publish_full_mesh()

func _publish_full_mesh()->void:
	if not _publication_current():return
	if geometry_pending:_phase="waiting_geometry";return
	_deferred_full_publish=false
	mesh = _full_mesh
	# The previous nearby publication has settled before this submission.
	# Build the much larger region graph off-thread as well as the map graph.
	NavigationServer3D.region_set_use_async_iterations(region,true)
	_publish_region_iteration=NavigationServer3D.region_get_iteration_id(region)
	_publish_iteration=NavigationServer3D.map_get_iteration_id(map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	_publish(true)


func take_surface_profile() -> Dictionary:
	var result:={"queries":_surface_profile_samples,"dropped":_surface_profile_dropped}
	_surface_profile_samples=[];_surface_profile_dropped=0
	return result

func _record_surface_profile(point:Vector3, stamps:Array, route:String, accepted:bool)->void:
	# Explicit diagnostic only. Keep every query (including the first failed
	# support test), bounded between render samples, with absolute intervals.
	if _surface_profile_samples.size()>=64:
		_surface_profile_dropped+=1;return
	_surface_profile_samples.append({"frame":Engine.get_physics_frames(),"point":point,"route":route,"accepted":accepted,"begin_us":stamps[0],"iteration_us":stamps[1],"index_us":stamps[2],"end_us":Time.get_ticks_usec()})

func near_surface(point: Vector3, horizontal_tolerance: float = 0.18, vertical_tolerance: float = 0.4) -> bool:
	if not _publication_current():return false
	var detailed:=has_meta("profile_surface_details")
	var stamps:Array=[Time.get_ticks_usec(),0,0] if detailed else []
	if not ready_for_queries or mesh.get_polygon_count() == 0 or not point.is_finite():
		if detailed:
			stamps[1]=Time.get_ticks_usec();stamps[2]=stamps[1]
			_record_surface_profile(point,stamps,"rejected",false)
		return false
	var iteration:=NavigationServer3D.map_get_iteration_id(map)
	if detailed:stamps[1]=Time.get_ticks_usec();stamps[2]=stamps[1]
	# A previously queried point remains a real point on this immutable map.
	# Inside the smaller tolerance sphere, even a closer point must satisfy
	# BOTH original limits. Outside it, retain the exact nearest-point query;
	# a rectangular tolerance check would not provide that guarantee.
	var proven_radius:=minf(horizontal_tolerance,vertical_tolerance)
	if proven_radius>=0 and map==_surface_map and iteration==_surface_iteration and point.distance_squared_to(_surface_point)<=proven_radius*proven_radius:
		if detailed:_record_surface_profile(point,stamps,"point_cache",true)
		surface_cache_hits+=1;return true
	if _surface_index!=null and _surface_index_mesh==mesh and _surface_index_map==map and _surface_index_iteration==iteration:
		var support:Vector3=_surface_index.support(point,proven_radius)
		if detailed:stamps[2]=Time.get_ticks_usec()
		if support.is_finite():
			_surface_point=support;_surface_iteration=iteration;_surface_map=map
			if detailed:_record_surface_profile(point,stamps,"triangle_index",true)
			surface_index_hits+=1;return true
	var started:=Time.get_ticks_usec() if has_meta("profile_frame") else 0
	var nearest := NavigationServer3D.map_get_closest_point(map, point)
	surface_query_count+=1
	if started>0:set_meta("surface_query_timing",{"frame":Engine.get_physics_frames(),"ms":(Time.get_ticks_usec()-started)/1000.0})
	_surface_point=nearest;_surface_iteration=iteration;_surface_map=map
	var accepted:=Vector2(nearest.x, nearest.z).distance_to(Vector2(point.x, point.z)) <= horizontal_tolerance and absf(nearest.y - point.y) <= vertical_tolerance
	if detailed:_record_surface_profile(point,stamps,"nearest",accepted)
	return accepted

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


func find_foreground_path(start:Vector3,goal:Vector3,goal_tolerance:float=.18,retry_timeout:bool=true)->Dictionary:
	return find_path(start,goal,goal_tolerance,true,retry_timeout)

func find_path(start: Vector3, goal: Vector3, goal_tolerance:float=.18,foreground_request:bool=false,retry_timeout:bool=false) -> Dictionary:
	_publication_current()
	if not start.is_finite() or not goal.is_finite() or not is_finite(goal_tolerance) or goal_tolerance<0:return {"ok":false,"reason":"invalid_query","path":PackedVector3Array()}
	if foreground_request and _terminal_state.is_empty() and not _disposed:
		_poll_foreground_deadline()
		if _foreground_timed_out and _foreground_goal is Vector3 and _foreground_goal.distance_squared_to(goal)<.000001:
			if retry_timeout:cancel_foreground_request(goal)
			else:return {"ok":false,"reason":"navigation_timeout","path":PackedVector3Array()}
		_begin_foreground(start,goal)
	var capability:=capability_status()
	if not capability.ok:
		var reason:String="pending" if capability.state=="pending" else "navigation_"+str(capability.state)
		if capability.state=="failed" and not geometry_error.is_empty():reason="geometry_error"
		return {"ok":false,"reason":reason,"error":capability.reason,"capability":capability,"path":PackedVector3Array()}
	var compact_query:=foreground_request and _compact_follow() and _within_foreground_range(start,goal)
	if compact_query:
		if _foreground_no_path:return {"ok":false,"reason":"unreachable","path":PackedVector3Array()}
		if _nearby_publish_wait>0 and not _foreground_waiting:_queue_foreground(0)
		if _foreground_waiting or _nearby_publish_wait>0:
			_try_nearby_request()
			return {"ok":false,"reason":"pending" if _query_geometry_error().is_empty() else "geometry_error","error":_query_geometry_error(),"path":PackedVector3Array()}
	# Distant foreground queries retain their original bounded preparation
	# behavior, while sharing the same finite request lifetime as near clicks.
	if _nearby_publish_wait>0:return {"ok":false,"reason":"pending","path":PackedVector3Array()}
	# A nearest-point projection on the old local mesh cannot prove geometry
	# beyond its complete published clip. Request that closure before querying.
	if geometry_pending and (not _inside_local(start,2) or not _inside_local(goal,2)):
		if foreground_request:follow(start,goal)
		else:_follow_passive(start,goal)
		return {"ok":false,"reason":"pending" if _query_geometry_error().is_empty() else "geometry_error","error":_query_geometry_error(),"path":PackedVector3Array()}
	# Recast rounds span heights up by a cell. At a rotated low doorstep its
	# simplified surface can be just above the physical climb height; do not
	# strand a grounded actor for that voxel rounding. Still reject other floors.
	var vertical_tolerance:float=maxf(.4,mesh.agent_max_climb+mesh.cell_height+.01)
	if not near_surface(start, 0.35,vertical_tolerance) or not near_surface(goal,goal_tolerance,vertical_tolerance):
		if _staged and not fully_ready and (not _inside_local(start,2) or not _inside_local(goal,2)):
			if foreground_request:follow(start,goal)
			else:_follow_passive(start,goal)
			return {"ok":false,"reason":"pending","path":PackedVector3Array()}
		if compact_query:return _foreground_unreachable()
		return {"ok": false, "reason": "unreachable", "path": PackedVector3Array()}
	# Recast erodes polygons by the agent radius. Visible floor beside a wall
	# remains a valid click; stop on the nearby walkable point, on this storey.
	if not near_surface(goal):goal=NavigationServer3D.map_get_closest_point(map,goal)
	var points := NavigationServer3D.map_get_path(map, start, goal, true)
	if points.is_empty() or points[-1].distance_to(goal) > 0.4:
		if compact_query:return _foreground_unreachable()
		return {"ok": false, "reason": "unreachable", "path": PackedVector3Array()}
	points[0] = start
	points[-1] = goal
	for attempt in 8:
		var obstruction:=_door_obstruction(points)
		if obstruction.is_empty():
			if foreground_request:_foreground_deadline_msec=-1
			return {"ok":true,"reason":"","path":points,"version":version}
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
	if _retire_reparenting:return
	if _geometry_release.is_valid():_geometry_release.call()
	_disposed = true
	ready_for_queries=false;fully_ready=false;_resize_cancelled=true
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
