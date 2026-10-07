extends Node3D
## Receivers are scoped to this World3D, including isolated editor playtest worlds.
const Response = preload("res://scripts/world3d/wind_response.gd")
const Materials = preload("res://scripts/world3d/wind_material.gd")
const SharedState = preload("res://scripts/world3d/wind_shared_state.gd")
var camera: Camera3D
var receivers := {}
var scan_left := 0.0
var velocity := Vector3.ZERO
var elapsed := 0.0
var active_rows: Array = []
var range_camera_position := Vector3(INF,INF,INF)
var enabled := true
# One private world-state texel keeps every rendered LOD current without a
# synchronous camera-range sweep. The uniform path remains an A/B reference.
var shared_state_enabled:=true
var _shared_state:RefCounted
const REFRESH_BUDGET_USEC := 2000
var _active_indices:Dictionary={}
var _scan_pending:=false
var _scan_nodes:Array=[]
var _scan_cleanup:Array=[]
var _scan_cursor:=0
var _cleanup_cursor:=0
var _scan_cleaning:=false
var _scan_slices:=0
var _scan_cpu_usec:=0
var _scan_begin_usec:=0
var _last_slice_frame:=-1
var _cancel_nodes_usec:=0
var _cancel_keys_usec:=0
var _cancel_timeline:Dictionary={}

func set_shared_state_enabled(value:bool)->void:
	if shared_state_enabled==value:return
	shared_state_enabled=value
	for id:int in receivers:_configure_shared_row(receivers[id])
	# The retained uniform path is also the same-camera/time A/B reference.
	if not value:_update_active_rows()
	advance(velocity,elapsed)

func _configure_shared_row(row:Dictionary)->void:
	if shared_state_enabled:
		if _shared_state==null:_shared_state=SharedState.new()
		_shared_state.update(velocity,elapsed)
	for material:ShaderMaterial in row.materials:
		material.set_shader_parameter("wind_state_enabled",shared_state_enabled)
		if shared_state_enabled:
			material.set_shader_parameter("wind_state",_shared_state.texture)
			material.set_shader_parameter("wind_exposure",float(row.exposure))
	row.shared_exposure=float(row.exposure)

func set_enabled(value: bool) -> void:
	if enabled==value: return
	enabled=value; set_physics_process(value); scan_left=0
	range_camera_position=Vector3(INF,INF,INF)
	if not enabled:
		_cancel_refresh()
		for row in receivers.values(): _restore(row)
		_clear_active(); receivers.clear()

func _physics_process(delta: float) -> void:
	if not enabled: return
	scan_left -= delta
	if not is_instance_valid(camera): _cancel_refresh(); return
	# Catch-up physics ticks share one render frame; do not spend the budget
	# repeatedly before the player gets another visible frame.
	var frame:=Engine.get_process_frames()
	if _last_slice_frame==frame:return
	if not _scan_pending:
		if scan_left>0:return
		scan_left=.35
		_begin_refresh()
	_last_slice_frame=frame
	_advance_refresh(REFRESH_BUDGET_USEC)

func refresh() -> void:
	_cancel_refresh()
	if not enabled or not is_instance_valid(camera):return
	# Explicit callers (load, editor preview and tests) retain synchronous semantics.
	_begin_refresh()
	_advance_refresh(0)

func _begin_refresh()->void:
	_scan_begin_usec=Time.get_ticks_usec()
	_scan_nodes=get_tree().get_nodes_in_group(Response.GROUP)
	_scan_cursor=0;_cleanup_cursor=0;_scan_cleaning=false
	_scan_slices=0;_scan_cpu_usec=0;_scan_pending=true

func _cancel_refresh()->void:
	var profiling:=has_meta("profile_frame")
	_scan_pending=false
	var mark:=Time.get_ticks_usec() if profiling else 0
	_scan_nodes.clear()
	_cancel_nodes_usec=Time.get_ticks_usec()-mark if profiling else 0
	var nodes_begin:=mark
	mark=Time.get_ticks_usec() if profiling else 0
	_scan_cleanup.clear()
	_cancel_keys_usec=Time.get_ticks_usec()-mark if profiling else 0
	if has_meta("profile_wind_timeline"):
		_cancel_timeline={"nodes_begin_usec":nodes_begin,"nodes_end_usec":nodes_begin+_cancel_nodes_usec,"keys_begin_usec":mark,"keys_end_usec":mark+_cancel_keys_usec}
	_scan_cursor=0;_cleanup_cursor=0;_scan_cleaning=false

func _eligible(node:Variant,world:World3D,camera_position:Vector3)->bool:
	return is_instance_valid(node) and node is MeshInstance3D and not node.is_queued_for_deletion() and node.is_inside_tree() and node.is_in_group(Response.GROUP) and node.get_world_3d()==world and node.is_visible_in_tree() and node.global_position.distance_squared_to(camera_position)<=90*90

func _advance_refresh(budget_usec:int)->void:
	if not _scan_pending:return
	if not enabled or not is_instance_valid(camera):_cancel_refresh();return
	var started:=_scan_begin_usec if _scan_slices==0 else Time.get_ticks_usec()
	var camera_position:=camera.global_position;var world:=get_world_3d()
	var bind_usec:=0;var bound:=0;var scan_usec:=0;var restore_usec:=0;var erase_usec:=0;var advance_usec:=0;var processed:=0;var removed:=0
	var profiling:=has_meta("profile_frame")
	var cleanup_check_usec:=0;var cleanup_keys_usec:=0;var cancel_nodes_usec:=0;var cancel_keys_usec:=0
	while _scan_cursor<_scan_nodes.size():
		var mark:=Time.get_ticks_usec()
		var node:Variant=_scan_nodes[_scan_cursor];_scan_cursor+=1;processed+=1
		if _eligible(node,world,camera_position):
			var id:int=node.get_instance_id()
			if not receivers.has(id):
				var began:=Time.get_ticks_usec();_bind(node)
				bind_usec+=Time.get_ticks_usec()-began;bound+=1
			if receivers.has(id):_refresh_receiver(id,node,camera_position,world)
		scan_usec+=Time.get_ticks_usec()-mark
		if budget_usec>0 and Time.get_ticks_usec()-started>=budget_usec:break
	if _scan_cursor>=_scan_nodes.size() and not _scan_cleaning:
		var mark:=Time.get_ticks_usec() if profiling else 0
		_scan_cleanup=receivers.keys();_scan_cleaning=true
		if profiling:cleanup_keys_usec=Time.get_ticks_usec()-mark
	while _scan_cleaning and _cleanup_cursor<_scan_cleanup.size() and (budget_usec<=0 or processed==0 or Time.get_ticks_usec()-started<budget_usec):
		var checked:=Time.get_ticks_usec() if profiling else 0
		var id:int=_scan_cleanup[_cleanup_cursor];_cleanup_cursor+=1;processed+=1
		if not receivers.has(id):
			if profiling:cleanup_check_usec+=Time.get_ticks_usec()-checked
			continue
		var node:Variant=receivers[id].node.get_ref()
		# Recheck current residency, never an old "alive" set from another frame.
		var eligible:=_eligible(node,world,camera_position)
		if profiling:cleanup_check_usec+=Time.get_ticks_usec()-checked
		if eligible:continue
		var mark:=Time.get_ticks_usec();_restore(receivers[id]);restore_usec+=Time.get_ticks_usec()-mark
		mark=Time.get_ticks_usec();_remove_active(id);receivers.erase(id);erase_usec+=Time.get_ticks_usec()-mark;removed+=1
	var complete:=_scan_cleaning and _cleanup_cursor>=_scan_cleanup.size()
	if complete:
		_cancel_refresh()
		cancel_nodes_usec=_cancel_nodes_usec;cancel_keys_usec=_cancel_keys_usec
		# The synchronous interface historically updates every active uniform.
		# Periodic scans already update visited/new rows and weather advances all
		# active rows each frame; no extra unbudgeted finish pass is needed.
		if budget_usec<=0:
			var mark:=Time.get_ticks_usec();advance(velocity,elapsed);advance_usec=Time.get_ticks_usec()-mark
	_scan_slices+=1
	var used:=Time.get_ticks_usec()-started;_scan_cpu_usec+=used
	if profiling:set_meta("refresh_timing",{"frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"ms":used/1000.0,"cycle_ms":_scan_cpu_usec/1000.0,"slices":_scan_slices,"pending":_scan_pending,"scan_ms":scan_usec/1000.0,"cleanup_check_ms":cleanup_check_usec/1000.0,"cleanup_keys_ms":cleanup_keys_usec/1000.0,"cancel_nodes_ms":cancel_nodes_usec/1000.0,"cancel_keys_ms":cancel_keys_usec/1000.0,"restore_ms":restore_usec/1000.0,"erase_ms":erase_usec/1000.0,"advance_ms":advance_usec/1000.0,"bind_ms":bind_usec/1000.0,"bound":bound,"processed":processed,"removed":removed,"receivers":receivers.size(),"active":active_rows.size()})
	if profiling and has_meta("profile_wind_timeline"):
		var timing:Dictionary=get_meta("refresh_timing")
		timing["begin_usec"]=started;timing["end_usec"]=started+used
		if complete:timing["cancel_timeline"]=_cancel_timeline

func _refresh_receiver(id:int,node:MeshInstance3D,camera_position:Vector3,world:World3D)->void:
	var row:Dictionary=receivers[id]
	if not _in_range(node,camera_position):_remove_active(id);return
	row.exposure=1.0
	if row.config.shelter:
		var bounds:AABB=node.global_transform*node.get_aabb()
		var top:=Vector3(bounds.get_center().x,bounds.end.y+.05,bounds.get_center().z)
		var query:=PhysicsRayQueryParameters3D.create(top,top+Vector3.UP*180,1)
		if not world.direct_space_state.intersect_ray(query).is_empty():row.exposure=0.0
	_append_active(id,row)
	_advance_row(row,velocity,elapsed)

func _append_active(id:int,row:Dictionary)->void:
	if _active_indices.has(id):return
	row.receiver_id=id;_active_indices[id]=active_rows.size();active_rows.append(row)

func _remove_active(id:int)->void:
	if not _active_indices.has(id):return
	var index:int=_active_indices[id];var last:Dictionary=active_rows.back()
	active_rows[index]=last;_active_indices[last.receiver_id]=index
	active_rows.pop_back();_active_indices.erase(id)

func _clear_active()->void:
	active_rows.clear();_active_indices.clear()

func _bind(node: MeshInstance3D) -> void:
	var error := Response.mesh_error(node)
	if not error.is_empty(): node.set_meta("wind_error",error); return
	var config: Dictionary = Response.defaults().merged(node.get_meta("extras").rmmo_wind,true)
	var original := {"override":node.material_override,"surfaces":[],"margin":node.extra_cull_margin}
	var materials: Array[ShaderMaterial] = []
	for slot in node.mesh.get_surface_count():
		original.surfaces.append(node.get_surface_override_material(slot))
		materials.append(Materials.make(node.get_active_material(slot),config,node.get_aabb()))
	node.set_meta("wind_original",original); node.material_override = null
	for slot in materials.size(): node.set_surface_override_material(slot,materials[slot])
	node.extra_cull_margin = maxf(node.extra_cull_margin,config.amplitude*3)
	var row:Dictionary={"node":weakref(node),"original":original,"materials":materials,"config":config,"exposure":1.0}
	receivers[node.get_instance_id()] = row
	_configure_shared_row(row)

func advance(wind: Vector3, time: float) -> void:
	velocity = wind; elapsed = time
	if not enabled: return
	var started:=Time.get_ticks_usec() if has_meta("profile_frame") else 0
	if shared_state_enabled:
		if _shared_state!=null:_shared_state.update(wind,time)
		if started>0:set_meta("advance_timing",{"frame":Engine.get_process_frames(),"range_ms":0.,"uniform_ms":(Time.get_ticks_usec()-started)/1000.,"active":active_rows.size(),"shared_state":true})
		return
	# Periodic refresh may test rows at either side of this camera anchor.
	# Their maximum relative drift is 2 * .45 = .9 m, inside the 1 m guard.
	var range_updated:=false
	if is_instance_valid(camera) and camera.global_position.distance_squared_to(range_camera_position) > .45*.45:
		_update_active_rows();range_updated=true
	var ranged:=Time.get_ticks_usec() if started>0 else 0
	for row: Dictionary in active_rows:
		_advance_row(row,wind,time)
	if started>0:
		var timing:Dictionary={"frame":Engine.get_process_frames(),"range_ms":(ranged-started)/1000.0,"uniform_ms":(Time.get_ticks_usec()-ranged)/1000.0,"active":active_rows.size()}
		if range_updated and has_meta("profile_wind_range_detail"):timing["range_detail"]=get_meta("range_timing",{})
		set_meta("advance_timing",timing)

func _advance_row(row:Dictionary,wind:Vector3,time:float)->void:
	if shared_state_enabled:
		if row.get("shared_exposure",-1.)!=float(row.exposure):
			for material:ShaderMaterial in row.materials:material.set_shader_parameter("wind_exposure",float(row.exposure))
			row.shared_exposure=float(row.exposure)
		return
	var force:=wind*float(row.exposure)
	var force_changed:bool=row.get("last_velocity",Vector3(INF,INF,INF))!=force
	for material:ShaderMaterial in row.materials:
		if force_changed:material.set_shader_parameter("wind_velocity",force)
		material.set_shader_parameter("wind_time",time)
	row.last_velocity=force

func _update_active_rows() -> void:
	# Per-row clocks and dictionary writes are diagnostic overhead, separate
	# from the inexpensive aggregate frame timer used by normal route tests.
	var profiling:=has_meta("profile_wind_range_detail")
	var detail:Dictionary={"clear_ms":0.0,"values_ms":0.0,"resolve_ms":0.0,"resolve_max_ms":0.0,"test_ms":0.0,"test_max_ms":0.0,"append_ms":0.0,"append_max_ms":0.0,"remove_ms":0.0,"membership_removed":0,"scanned":0} if profiling else {}
	var mark:=Time.get_ticks_usec() if profiling else 0
	var has_camera := is_instance_valid(camera)
	if has_camera: range_camera_position = camera.global_position
	# Only active membership changes here. Receiver keys stay stable throughout
	# this synchronous loop, avoiding a temporary values array and full rebuild.
	for id:int in receivers:
		var row:Dictionary=receivers[id]
		if profiling:mark=Time.get_ticks_usec()
		var node: MeshInstance3D = row.node.get_ref()
		if profiling:
			var duration:float=(Time.get_ticks_usec()-mark)/1000.0
			detail.resolve_ms+=duration;detail.resolve_max_ms=maxf(detail.resolve_max_ms,duration);detail.scanned+=1
		if profiling:mark=Time.get_ticks_usec()
		var active:=node!=null and (not has_camera or _in_range(node,range_camera_position))
		if profiling:
			var duration:float=(Time.get_ticks_usec()-mark)/1000.0
			detail.test_ms+=duration;detail.test_max_ms=maxf(detail.test_max_ms,duration)
		if not active:
			if profiling:
				mark=Time.get_ticks_usec()
				if _active_indices.has(id):detail.membership_removed+=1
			_remove_active(id)
			if profiling:detail.remove_ms+=(Time.get_ticks_usec()-mark)/1000.0
			continue
		if profiling:mark=Time.get_ticks_usec()
		_append_active(id,row)
		if profiling:
			var duration:float=(Time.get_ticks_usec()-mark)/1000.0
			detail.append_ms+=duration;detail.append_max_ms=maxf(detail.append_max_ms,duration)
	if profiling:set_meta("range_timing",detail)

func _range_active(node: MeshInstance3D) -> bool:
	if not is_instance_valid(camera): return true
	return _in_range(node,camera.global_position)

func _in_range(node: MeshInstance3D, camera_position: Vector3) -> bool:
	var begin := node.visibility_range_begin
	var end := node.visibility_range_end
	if begin == 0.0 and end == 0.0: return true
	# Same transformed AABB center as renderer range tests. Keep both levels
	# updating within the hysteresis band so a camera crossing never freezes.
	var bounds := node.custom_aabb
	if bounds.size == Vector3.ZERO: bounds = node.get_aabb()
	# Sample camera/world once for a whole scan, but keep each receiver's geometry
	# and transform live. Godot exposes no change signal for the range/custom-AABB
	# setters; retaining these across scans would miss direct edits or mesh swaps.
	var distance_squared := camera_position.distance_squared_to(node.global_transform * bounds.get_center())
	if begin != 0.0:
		var lower := maxf(0.0,begin-node.visibility_range_begin_margin-1.0)
		if distance_squared < lower*lower: return false
	if end != 0.0:
		var upper := end+node.visibility_range_end_margin+1.0
		if distance_squared > upper*upper: return false
	return true

func _restore(row: Dictionary) -> void:
	var node: MeshInstance3D = row.node.get_ref()
	if node == null: return
	node.material_override = row.original.override
	for slot in mini(node.mesh.get_surface_count(),row.original.surfaces.size()): node.set_surface_override_material(slot,row.original.surfaces[slot])
	node.extra_cull_margin = row.original.margin; node.remove_meta("wind_original")

func _exit_tree() -> void:
	_cancel_refresh()
	for row in receivers.values(): _restore(row)
	_clear_active();receivers.clear()
