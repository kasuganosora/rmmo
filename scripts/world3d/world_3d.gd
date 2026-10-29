extends Node3D
## Meter-space world used by the world3d login profile and editor playtests.

const GltfMapIo = preload("res://scripts/world3d/gltf_map_io.gd")
const WorldMapPaths = preload("res://scripts/world3d/map_paths.gd")
const Travel = preload("res://scripts/world3d/world_travel.gd")
const Stream = preload("res://scripts/world3d/world_stream.gd")
const CrossMapPrefetch=preload("res://scripts/world3d/cross_map_prefetch.gd")
const Net = preload("res://scripts/net/net.gd")
static var navigation_background_enabled:=true
static var wind_background_enabled:=true # Unknown variants recover automatically under a drawn cover.
static var building_readiness_enabled:=false
static var automatic_staged_entry_enabled:=true
var _entry_policy:Dictionary={}
var _preparation_hint:Label
var _preparation_sample_at:=0
var _last_optional_state:Dictionary={}
var _wind_recovery_pending:=false
var _building_entry:RefCounted
var _building_transfer:RefCounted
var _building_traversal:RefCounted
var _building_lease_clock:=0.0
var _approach_clock:=0.
var _approach_preparation=preload("res://scripts/world3d/approach_preparation.gd").new()
var _cross_map_prefetch:CrossMapPrefetch
var _target_scene_prefetch:Node
var _prefetch_fallback_ledger=preload("res://scripts/world3d/resource_admission.gd").new()


var _player: CharacterBody3D
var _transfer_viewport_restore:Variant=null
var _camera: Node3D
var _status: Label
var _travel = null
var _map_path := ""
var _map_root: Node

## Program-controlled doors, glazed casements and shutters. Runtime changes persist
## across chunk residency; authored defaults are changed through editor/MCP tools.
func list_building_components(building_id: String) -> Array:
	return preload("res://scripts/world3d/building_fixtures.gd").list_runtime(_map_root,building_id) if is_instance_valid(_map_root) else []

func set_building_component_state(building_id: String, component_id: String, open: float, duration := .35) -> Dictionary:
	if Net.is_real_server():return Net.server().gameplay.dispatch("fixture",[building_id,component_id,open])
	if not is_instance_valid(_map_root): return {"ok":false,"error":"地图未加载"}
	if building_entry_protocol_enabled() and not building_id.begins_with("fortification:"):
		return _building_authority().set_runtime_fixture(_map_root,_map_ref(),str(_map_root.get_meta("source_map_sha256","")),building_id,component_id,open,duration)
	return preload("res://scripts/world3d/building_fixtures.gd").set_runtime(_map_root,building_id,component_id,open,duration)
var _house_permissions:CanvasLayer
var _sun: DirectionalLight3D
var _env: Environment
var _weather: Node3D
var _outline: CanvasLayer
var _lamps: Array = []
var _house_candles:Node3D
var _night := false
var _check_map := false
var _actor_host: Node3D
var _failed_warp := ""
var _warp_candidates:Array[Node]=[]
var _warp_cache_dirty:=true
var _transfer_pending := false
var _transfer_loader: Node
var _transfer_request_serial := 0
var _local_transfer: Dictionary = {}
var _ready_for_play := false
var _remote_entry_context:Dictionary={}
var _entry_readiness_shadow:RefCounted
var _entry_shadow_waiting_physics:=false
var loading_profile: Dictionary={}
var loading_state: Dictionary={"stage":"准备三维场景","done":0,"total":0}

func loading_progress() -> Dictionary:
	return loading_state

## S0 observation only. Never consult this contract to change the legacy gate.
func entry_readiness_shadow_report()->Dictionary:
	return _entry_readiness_shadow.report() if _entry_readiness_shadow!=null else {"mode":"shadow_only","early_entry_enabled":false,"state":"not_started"}

func note_entry_first_frame(rendered:bool)->bool:
	if _entry_readiness_shadow!=null:_entry_readiness_shadow.first_frame(rendered)
	if not building_entry_protocol_enabled():return true
	if _building_entry==null:return _building_entry_failure("entry_ticket_unavailable")
	var result:Dictionary=_building_entry.activate(rendered,_building_current_position_valid)
	loading_profile.building_entry=_building_entry.report()
	if not result.ok:return _building_entry_failure(str(result.reason))
	_building_entry.retain_residency()
	return true

func _building_authority()->RefCounted:return Net.server().world3d_state.entry_authority
func building_entry_protocol_enabled()->bool:return not Net.is_real_server() and (building_readiness_enabled or _entry_policy.get("mode","")=="staged")

func _choose_entry_policy(map_root:Node,path:String,_centre:Vector3)->Dictionary:
	if Net.is_real_server():return {"mode":"full","reason":"remote_world_ready"}
	if not automatic_staged_entry_enabled:return {"mode":"full","reason":"automatic_disabled"}
	var authored:String=str(GltfMapIo.extras_of(map_root).get("map_ref",""))
	var ref:String=authored if preload("res://scripts/world3d/world_location.gd").map_ref_ok(authored) else "prototype/map_"+path.sha256_text().substr(0,16)
	return preload("res://scripts/world3d/entry_stage_policy.gd").select(_building_authority(),map_root,ref,str(map_root.get_meta("source_map_sha256","")))

func preparation_state()->Dictionary:
	var navigation_ready:bool=is_instance_valid(_navigation) and _navigation.ready_for_queries
	var navigation_error:String=_navigation.geometry_error if is_instance_valid(_navigation) else ""
	var wind:Dictionary=_weather.wind_objects.capability_status() if is_instance_valid(_weather) else {}
	return {"policy":_entry_policy.duplicate(),"playable":_ready_for_play and is_instance_valid(_player) and not _player.input_locked,"navigation":{"ready":navigation_ready,"error":navigation_error,"state":"ready" if navigation_ready else ("failed" if not navigation_error.is_empty() else "preparing")},"wind":wind,"building":_building_entry.report() if _building_entry!=null else {"state":"full_wait"}}

func _update_preparation_hint()->void:
	if not _ready_for_play or not is_instance_valid(_status):return
	if Time.get_ticks_msec()<_preparation_sample_at:return
	_preparation_sample_at=Time.get_ticks_msec()+250
	var pending:bool=is_instance_valid(_navigation) and not _navigation.ready_for_queries
	var wind:Dictionary=_weather.wind_objects.capability_status() if is_instance_valid(_weather) else {}
	var wind_pending:bool=not wind.get("ready",true)
	if wind_background_enabled and int(wind.get("pending_receivers",0))>0 and not _transfer_pending and not _wind_recovery_pending and not get_viewport().disable_3d:
		_wind_recovery_pending=true;_recover_streamed_wind.call_deferred()
	if _preparation_hint==null:
		_preparation_hint=Label.new();_preparation_hint.name="PreparationStatus";_preparation_hint.position=_status.position+Vector2(0,26);_status.get_parent().add_child(_preparation_hint)
	_preparation_hint.visible=(pending or wind_pending) and not _transfer_pending
	var labels:PackedStringArray=[]
	if pending:labels.append("点击寻路准备中" if _navigation.geometry_error.is_empty() else "点击寻路暂不可用："+_navigation.geometry_error)
	if wind_pending:labels.append("风动接入中")
	var can_move:bool=is_instance_valid(_player) and not _player.input_locked and not _player.geometry_blocked
	_preparation_hint.text=("可用键盘移动；" if can_move else "后台准备：")+"；".join(labels)
	if _building_entry!=null and _building_entry.gate!=null:
		var state:Array=["ready" if not pending else _navigation.geometry_error,wind_pending]
		var key:int=_building_entry.get_instance_id()
		if _last_optional_state.get(key)!=state:
			_last_optional_state.clear();_last_optional_state[key]=state
			_building_entry.gate.set_capability("navigation",not pending,_building_entry.gate.token(),_navigation.geometry_error if pending else "")
			_building_entry.gate.set_capability("wind",not wind_pending,_building_entry.gate.token())

func _building_entry_failure(reason:String)->bool:
	if _building_entry!=null:_building_entry.cancel(reason)
	set_meta("entry_loading_error","建筑就绪校验未通过："+reason)
	_loading_stage(str(get_meta("entry_loading_error")))
	if is_instance_valid(_player):_player.input_locked=true
	return false

func _new_building_entry(map_root:Node,path:String,centre:Vector3,reason:String)->RefCounted:
	var attempt:RefCounted=preload("res://scripts/world3d/building_entry_transaction.gd").new()
	var authored:=str(GltfMapIo.extras_of(map_root).get("map_ref",""))
	var map_ref:String=authored if preload("res://scripts/world3d/world_location.gd").map_ref_ok(authored) else "prototype/map_"+path.sha256_text().substr(0,16)
	var result:Dictionary=attempt.begin(_building_authority(),map_root,"local_session_%d"%Net.session().get_instance_id(),"local_world_%d"%get_instance_id(),map_ref,str(map_root.get_meta("source_map_sha256","")),centre-Vector3.UP*.9,reason,true)
	if not result.ok:attempt.set_meta("error",str(result.reason))
	return attempt

func _prepare_initial_building(state:Dictionary)->void:
	state.error=await _building_entry.prepare(self,self,Net.session().world3d_spawn)
	state.done=true

func _building_current_position_valid(snapshot:Dictionary)->bool:
	if not is_instance_valid(_player) or not is_instance_valid(_map_root):return false
	var feet:Vector3=preload("res://scripts/world3d/building_membership.gd")._vector(snapshot.get("position_m"))
	if not feet.is_equal_approx(_player.global_position-Vector3.UP*.9):return false
	if snapshot.get("map_ref")!=_map_ref() or snapshot.get("map_revision")!=_map_root.get_meta("source_map_sha256",""):return false
	var footprint:AABB=preload("res://scripts/world3d/physical_traversal.gd").motion_bounds(_player,Vector3.ZERO,maxf(_player.get_physics_process_delta_time(),.001),false)
	if not _building_authority().footprint_requirements(snapshot.map_ref,snapshot.map_revision,footprint).ok:return false
	return _physical_destination_fits(_map_root,get_world_3d().direct_space_state,feet+Vector3.UP*.9,[_player.get_rid()]) and _same_map_destination_fits(feet+Vector3.UP*.9,_navigation)

func _building_movement_allowed()->bool:
	return _building_entry!=null and _building_entry.gate!=null and _building_entry.gate.can_play() and not _transfer_pending and is_instance_valid(_combat) and _combat.can_move()

func _building_source_snapshot()->Dictionary:
	var result:Dictionary=_building_authority().position_snapshot(_map_ref(),str(_map_root.get_meta("source_map_sha256","")),_player.global_position-Vector3.UP*.9)
	return result.get("snapshot",{})

func _building_recovery_valid(original:Dictionary)->bool:
	if not building_entry_protocol_enabled():return true
	if _building_transfer!=null:_building_transfer.cancel("transfer_failed");_building_transfer=null
	var previous:Dictionary=original.get("building_snapshot",{})
	if previous.is_empty():return false
	var recovered:Dictionary=_building_authority().begin_recovery("local_session_%d"%Net.session().get_instance_id(),"local_world_%d"%get_instance_id(),previous)
	if not recovered.ok:return false
	if not recovered.membership_resolved:
		_building_authority().cancel(recovered.ticket,"recovery_membership_unresolved");return false
	# A fresh ticket is needed even if only the target failed. Existing complete
	# source evidence is rechecked against current source geometry and door state.
	var attempt:RefCounted=preload("res://scripts/world3d/building_entry_transaction.gd").new()
	attempt.authority=_building_authority();attempt.root=weakref(_map_root);attempt.issued=recovered
	attempt.gate=preload("res://scripts/world3d/entry_readiness.gd").new();attempt.gate.begin(recovered.snapshot)
	attempt.gate.mark("metadata",attempt.gate.token())
	var point:Vector3=original.transform.origin
	if not _physical_destination_fits(_map_root,get_world_3d().direct_space_state,point,[_player.get_rid()]):return _reject_building_recovery(attempt)
	if recovered.snapshot.membership=="indoor":
		var state:Dictionary=_building_authority().state_snapshot(recovered.ticket)
		if not state.ok:return _reject_building_recovery(attempt)
		var current:Dictionary=recovered.snapshot.duplicate(true);current.building=state.building
		var receipt:Dictionary=_building_authority().inspect_root(current,_map_root,Engine.get_physics_frames(),Engine.get_physics_frames()-1)
		if not receipt.ok:return _reject_building_recovery(attempt)
		if not attempt.gate.complete_building(receipt,attempt.gate.token()).ok:return _reject_building_recovery(attempt)
	for stage:String in ["geometry","physics","render","base_gameplay"]:attempt.gate.mark(stage,attempt.gate.token())
	# The old visible scene stayed mounted under the cover; no synthetic frame
	# is claimed here. The caller keeps input frozen until its next actual draw.
	attempt.retain_residency()
	if _building_entry!=null:_building_entry.release()
	_building_entry=attempt
	return true

func _reject_building_recovery(attempt:RefCounted)->bool:
	attempt.cancel("recovery_evidence_unavailable");return false

func note_entry_full_gate_released()->void:
	if building_entry_protocol_enabled() and _building_entry!=null and _building_entry.gate.can_play() and is_instance_valid(_player):_player.set_physics_process(true)
	if _entry_readiness_shadow!=null:
		_entry_readiness_shadow.legacy_released()
		loading_profile.entry_readiness_shadow=entry_readiness_shadow_report()

func _begin_entry_readiness_shadow(map_root:Node)->void:
	_entry_readiness_shadow=preload("res://scripts/world3d/entry_readiness_observer.gd").new()
	# These are local observation identities, not a new remote-server protocol.
	_entry_readiness_shadow.begin({"session_id":"local_session_%d"%Net.session().get_instance_id(),
		"world_id":"local_world_%d"%get_instance_id(),"map_ref":_map_ref(),
		"map_revision":str(map_root.get_meta("runtime_geometry_key","")),
		"epoch":get_instance_id(),"position_m":Net.session().world3d_spawn})

func _loading_stage(stage: String, done: int=0, total: int=0) -> void:
	loading_state={"stage":stage,"done":done,"total":total}
var _combat: Node
var _pending_ground_skill := ""
var _revive: Button
var _hud: Control
var _navigation: Node
var _previous_feet := Vector3.ZERO
var _map_data = preload("res://scripts/world3d/world_map_data.gd").new()
var _map_pin_sets:Dictionary={}
var _sit_revision:=0
var _sit_preparing:=false
var furniture=preload("res://scripts/world3d/world_furniture.gd").new(self)
var remote_players=preload("res://scripts/world3d/world_remote_players.gd").new(self)

func facial_expression_catalog()->Array:
	if not is_instance_valid(_player) or _player._model.axis_rig==null:return []
	var catalog=preload("res://scripts/char/character_expressions.gd")
	var rows:Array=[{"id":"neutral","label":"恢复自然","tag":""}]
	for id in catalog.NAMES:rows.append({"id":id,"label":catalog.NAMES[id],"tag":catalog.LABELS[id],"group":catalog.group_for(id)})
	return rows

func facial_expression_state()->Dictionary:
	if not is_instance_valid(_player):return {}
	return _player._model.expression_target()

func request_facial_expression(id:String,combine:bool=false)->bool:
	if not is_instance_valid(_player) or _player.input_locked:return false
	if id=="neutral":return _send_facial_expression({})
	var catalog=preload("res://scripts/char/character_expressions.gd")
	if not catalog.CHANNELS.has(id):return false
	if not combine:return _send_facial_expression({id:1.0})
	# Use the pending target so rapid clicks do not lose a category mid-transition.
	var values:Dictionary=facial_expression_state()
	var selected:bool=values.has(id)
	for peer:String in catalog.GROUPS[catalog.group_for(id)]:values.erase(peer)
	if not selected:values[id]=1.0
	return _send_facial_expression(values)

func request_remote_debug_spawn(display_name:String="")->void:
	var feet:Vector3=_player.global_position-Vector3(0,.9,0)+Vector3(2,0,0)
	var result:Dictionary=Net.server().facial_expressions.spawn_peer(display_name,_map_path,feet)
	apply_actions(result.get("actions",[]))


func _send_facial_expression(weights:Dictionary)->bool:
	var result:Dictionary=Net.server().try_facial_expression(weights)
	apply_actions(result.get("actions",[]))
	return bool(result.get("ok",false))

func _on_identity_shapes_changed()->void:
	call_deferred("_refresh_player_clearance")
	furniture.cancel()
	cancel_sit_preparation()
	if Net.server().sitting:
		apply_actions(Net.server().try_sit(false).get("actions",[]))

func cancel_sit_preparation()->void:
	_sit_revision+=1

func _on_movement_intent()->void:
	if furniture.active():furniture.stand()
	cancel_sit_preparation()
	if Net.server().sitting:apply_actions(Net.server().try_sit(false).get("actions",[]))

func request_sit(on:Variant=null)->void:
	if Net.is_real_server():apply_actions(Net.server()._unsupported("sit").actions);return
	if furniture.active():
		furniture.stand();return
	var want:bool=bool(on) if on is bool else not (Net.server().sitting or _sit_preparing)
	if want and _sit_preparing:return
	cancel_sit_preparation()
	if not want:
		apply_actions(Net.server().try_sit(false).get("actions",[]));return
	if _sit_preparing or _transfer_pending or not is_instance_valid(_player) or _player.input_locked:return
	if not Net.server().combat_stats.player_alive():return
	var model=_player._model
	if model.axis_rig==null:return
	if model.action in _player.REST_ACTIONS:return
	_player.click_target=null;_player._route.clear()
	var revision:int=_sit_revision
	_sit_preparing=true
	var requested_rig=model.axis_rig
	var bundle:AnimationLibrary=await requested_rig.prepare_ground_actions()
	_sit_preparing=false
	if revision!=_sit_revision or not is_instance_valid(_player) or not is_instance_valid(model):return
	if model!=_player._model or model.axis_rig!=requested_rig:return
	if _transfer_pending or _player.input_locked or not Net.server().combat_stats.player_alive():return
	if bundle==null:
		apply_actions([{"type":"system_message","text":"坐下动作准备失败："+model.axis_rig.last_error}]);return
	var library:AnimationLibrary=model.axis_rig.animations.library.duplicate()
	for clip:StringName in bundle.get_animation_list():
		if library.has_animation(clip):library.remove_animation(clip)
		library.add_animation(clip,bundle.get_animation(clip))
	if not model.axis_rig.animations.install(model.skeleton,library):return
	apply_actions(Net.server().try_sit(true).get("actions",[]))

func _refresh_world_map()->void:
	_map_data.build(_map_root)
	_map_data.pins.assign(_map_pin_sets.get(_map_path,[]))
	if is_instance_valid(_hud):
		_hud.bind_world_map_3d(self)
		if is_instance_valid(_hud._map_overview) and _hud._map_overview.has_method("bind_world"):_hud._map_overview.bind_world(self)

func toggle_world_map_pin(point:Vector2)->void:
	if not point.is_finite() or not _map_data.bounds.has_point(point):return
	_map_data.toggle_pin(point)
	_map_pin_sets[_map_path]=_map_data.pins.duplicate()

func clear_world_map_pins()->void:
	_map_data.pins.clear();_map_pin_sets[_map_path]=[]

func request_world_map_move(point:Vector2)->bool:
	if _player.input_locked or not point.is_finite() or not _map_data.bounds.has_point(point):return false
	var desired:=Vector3(point.x,_player.position.y-.9,point.y)
	if not _navigation.fully_ready and not _navigation._inside_local(desired,2):
		var pending:Dictionary=_navigation.find_foreground_path(_player.position-Vector3.UP*.9,desired)
		if pending.get("reason")=="pending":
			_player.set_click_target(desired,"ground")
			_hud.append_system("正在规划路线。")
			return true
	var goal:=NavigationServer3D.map_get_closest_point(_navigation.map,desired)
	if Vector2(goal.x,goal.z).distance_to(point)>1.5:
		_navigation.cancel_foreground_request(desired)
		_hud.append_system("此处暂无可用路径；远处导航可能仍在准备。")
		return false
	var result:Dictionary=_navigation.find_foreground_path(_player.position-Vector3(0,.9,0),goal)
	if result.get("reason")=="pending":
		_player.set_click_target(goal,"ground")
		_hud.append_system("正在规划路线。")
		return true
	if not result.get("ok",false):
		_navigation.cancel_foreground_request(goal)
		_hud.append_system("无法到达此处。")
		return false
	_player.set_click_target(goal,"ground")
	return true


func is_world_ready() -> bool:
	return _ready_for_play


var _geometry_wait_locked:=false

func _bind_deferred_geometry(map_root:Node,navigation:Node)->void:
	var deferred:=map_root.get_node_or_null("DeferredAssets")
	if deferred==null:return
	var streaming:bool=not deferred._reference_index.is_empty()
	if not streaming and deferred.is_complete():return
	var demand_id:="navigation:%d"%navigation.get_instance_id()
	if map_root.has_meta("entry_stream_clip") and not deferred._entry_loading.is_empty():deferred.allow_demand_in_scope(demand_id)
	# Only this transaction's new navigation may extend the temporary scope.
	# Old navigation providers can retain/update their tickets for rollback,
	# but cannot re-enable origin or distant work during destination loading.
	if not _local_transfer.is_empty() and _local_transfer.get("scope_applied",false) and not _local_transfer.get("cancelled",false):
		if _local_transfer.get("request")==_transfer_request_serial and _local_transfer.get("map")==map_root and _local_transfer.get("deferred")==deferred and _local_transfer.get("navigation")==navigation:
			deferred.allow_demand_in_scope(demand_id)
	var base_geometry_key:String=map_root.get_meta("runtime_geometry_key","")
	var provide_geometry:=func(clip:AABB)->Dictionary:
		if not is_instance_valid(deferred):return {"ok":false,"error":"Geometry provider retired"}
		var complete:bool=deferred.ensure_geometry(clip,demand_id)
		return {"ok":complete,"error":deferred.error_for_clip(clip)}
	if streaming:
		navigation.configure_streaming_geometry(provide_geometry,deferred.release_demand.bind(demand_id))
		if map_root.get_node_or_null("AssetResidency")==null:
			var residency:=preload("res://scripts/world3d/asset_residency.gd").new()
			var adoption_complete:bool=int(map_root.get_meta("stream_children",-1))==map_root.get_child_count()
			residency.configure(self,map_root,deferred);map_root.add_child(residency)
			var native:=preload("res://scripts/world3d/native_residency.gd").new();native.configure(self,map_root,deferred);map_root.add_child(native)
			if adoption_complete:map_root.set_meta("stream_children",map_root.get_child_count())
	else:
		navigation.set_geometry_pending(true)
		navigation.configure_geometry_provider(provide_geometry,deferred.release_demand.bind(demand_id))
	var on_published:=func(specs:Array):
		if not is_instance_valid(navigation):return
		var result:Dictionary=navigation.append_specs(specs)
		if not result.ok:navigation.set_geometry_error(str(result.reason))
		# A staged transfer navigation sees the same arrivals but must not append
		# the same objects twice to the live minimap.
		if map_root==_map_root and navigation==_navigation:
			if is_instance_valid(_hud):_map_data.append_resident_specs(specs)
			if is_instance_valid(_house_candles):_house_candles.append_specs(map_root,specs)
			if is_instance_valid(_camera):_camera.append_map_specs(map_root,specs)
	var on_completed:=func():
		if is_instance_valid(navigation):
			var paths:Array=deferred.source_signatures.keys();paths.sort()
			var identities:Array=[]
			for path:String in paths:identities.append([path,deferred.source_signatures[path]])
			navigation.runtime_geometry_key=base_geometry_key+str(identities)
			if navigation==_navigation:map_root.set_meta("runtime_geometry_key",navigation.runtime_geometry_key)
		if is_instance_valid(navigation) and navigation.set_geometry_pending(false):map_root.set_meta("deferred_geometry",false)
	var on_failed:=func(reason:String):
		if is_instance_valid(navigation):navigation.set_geometry_error(reason)
		if map_root==_map_root:_status.text=reason
	deferred.published.connect(on_published)
	deferred.completed.connect(on_completed)
	deferred.failed.connect(on_failed)
	var deferred_ref:WeakRef=weakref(deferred)
	navigation.tree_exiting.connect(func():
		var queue:Node=deferred_ref.get_ref()
		if queue==null:return
		for connection:Array in [[queue.published,on_published],[queue.completed,on_completed],[queue.failed,on_failed]]:
			if connection[0].is_connected(connection[1]):connection[0].disconnect(connection[1])
		queue.release_demand(demand_id)
	)

func _guard_deferred_geometry()->void:
	if _transfer_pending:return
	if building_entry_protocol_enabled() and (_building_entry==null or not _building_entry.gate.can_play()):
		_player.input_locked=true;return
	var deferred:=_map_root.get_node_or_null("DeferredAssets")
	if deferred==null:return
	deferred.prioritize(_player.global_position)
	var origin:Vector3=_player.global_position
	# Prefetch follows the player globally; movement only waits for the local
	# capsule safety footprint, not decorative assets across a 96 m district.
	var clip:=AABB(Vector3(origin.x-2,-100000,origin.z-2),Vector3(4,200000,4))
	var ready:bool=_map_traversal_receipt(_map_root,clip,"player_collision").ok if _collision_first(_map_root) else deferred.ensure_geometry(clip,"player_collision") and Stream.nearby_collision_ready(_map_root,origin)
	_player.geometry_blocked=not ready
	if not ready and not _player.input_locked:
		_geometry_wait_locked=true;_player.input_locked=true;_player.velocity=Vector3.ZERO
	if not ready and _geometry_wait_locked:
		var local_error:String=deferred.error_for_clip(clip)
		if local_error.is_empty():local_error=deferred.error
		_status.text="正在准备附近区块…" if local_error.is_empty() else local_error
	var planned:Vector2i=_map_root.get_meta("stream_target",_map_root.get_meta("stream_chunk",Vector2i(2147483647,2147483647)))
	if _geometry_wait_locked and ready and planned==Stream.chunk_key(origin):
		_geometry_wait_locked=false
		if not _transfer_pending and not Net.session()._world_transition_active and not Net.server().awaiting_respawn and Net.server().combat_stats.player_alive():_player.input_locked=false
		_status.text="WASD 走 · 空格跳跃 · 右键转动 · E 对话"


func _exit_tree() -> void:
	if _transfer_viewport_restore!=null:get_viewport().disable_3d=bool(_transfer_viewport_restore)
	_retire_building_traversal()
	if _building_entry!=null:_building_entry.cancel("world_exited")
	if _building_transfer!=null:_building_transfer.cancel("world_exited")
	if _entry_readiness_shadow!=null:_entry_readiness_shadow.cancelled("world_exited")
	if not _local_transfer.is_empty():
		_local_transfer.cancelled=true
		_release_local_transfer_sources(_local_transfer)
	furniture.cancel()
	cancel_sit_preparation()
	if is_instance_valid(_transfer_loader): _transfer_loader.cancel()
	var server = Net.server()
	if server != null and server.sitting:server.try_sit(false)
	if server != null and server.get("world3d_authority") != null:
		server.world3d_authority.release()
	if server != null and server.has_method("world3d_release_actors"):
		server.world3d_release_actors()


func _ready() -> void:
	if Net.is_real_server():
		_remote_entry_context=Net.server().context()
		Net.server().world_changed.connect(_remote_world_changed)
		Net.server().connection_lost.connect(_remote_connection_lost)
	loading_profile.ready_started=Time.get_ticks_msec()
	child_order_changed.connect(func():_warp_cache_dirty=true)
	_travel = Net.session().world3d_travel()
	_add_light()
	_add_hud()
	if not Net.session().has_active_character():
		_status.text = "缺少角色数据：请登录并选择角色后进入三维世界"
		_ready_for_play = true
		return
	var body_type := str(Net.session().active_character().gender)
	if not preload("res://scripts/char/character_model_3d.gd").source_available(body_type,Net.session().active_character().get("customization",{})):
		_status.text = "角色资源缺失：请检查外部素材包，未使用替代模型"
		_ready_for_play = true
		return
	loading_profile.setup=Time.get_ticks_msec()
	var map_root := _load_or_fail()
	if map_root == null:
		_ready_for_play = true
		return
	add_child(map_root)
	_map_root = map_root
	_entry_policy=_choose_entry_policy(map_root,_map_path,Net.session().world3d_spawn)
	loading_profile.entry_policy=_entry_policy.duplicate()
	_begin_entry_readiness_shadow(map_root)
	if building_entry_protocol_enabled():
		_building_entry=_new_building_entry(map_root,_map_path,Net.session().world3d_spawn,"entry")
		if _building_entry.has_meta("error"):
			_building_entry_failure(str(_building_entry.get_meta("error")));return
	if map_root.has_meta("entry_plan"):
		var entry_error:String=await _prepare_entry_geometry(map_root,self,Net.session().world3d_spawn)
		if not entry_error.is_empty():
			_entry_readiness_shadow.failed(entry_error)
			set_meta("entry_loading_error",entry_error);_loading_stage(entry_error);return
	if Net.session().world3d_loading:
		map_root.set_meta("defer_source_upload",true)
		while not map_root.has_meta("stream_chunk"):
			Stream.sync(map_root, self, Net.session().world3d_spawn, Stream.LOAD_BUDGET)
			_loading_stage("准备附近物件与碰撞",int(map_root.get_meta("stream_cursor",0)),map_root.get_meta("stream_jobs",[]).size())
			await get_tree().process_frame
		map_root.remove_meta("defer_source_upload")
	else:
		_add_collision(map_root)
	var building_preparation:Dictionary={"done":true,"error":""}
	if building_entry_protocol_enabled():
		building_preparation.done=false
		_prepare_initial_building(building_preparation)
	_entry_readiness_shadow.geometry_published(Engine.get_physics_frames())
	_entry_shadow_waiting_physics=true
	loading_profile.stream=Time.get_ticks_msec()
	_loading_stage("准备角色")
	await get_tree().process_frame
	_add_player()
	if building_entry_protocol_enabled():_player.set_physics_process(false)
	if _collision_first(map_root):
		_loading_stage("验证出生点碰撞与支撑")
		await get_tree().physics_frame
		if not _physical_destination_fits(map_root,get_world_3d().direct_space_state,Net.session().world3d_spawn,[_player.get_rid()]):
			var reason:="出生点碰撞或支撑尚未就绪；未放行角色"
			set_meta("entry_loading_error",reason);_loading_stage(reason);return
	_player.movement_intent.connect(_on_movement_intent)
	loading_profile.player=Time.get_ticks_msec()
	_add_town_lamps(map_root)
	_apply_map_environment()
	loading_profile.environment=Time.get_ticks_msec()
	Net.session().prepare_world_first_frame()
	await _prepare_navigation()
	if _navigation.ready_for_queries:_entry_readiness_shadow.navigation_ready()
	loading_profile.navigation=Time.get_ticks_msec()
	_loading_stage("准备环境与交互")
	await get_tree().process_frame
	_mount_events()
	loading_profile.events=Time.get_ticks_msec()
	if not Net.session().active_character().is_empty():
		_add_game_hud()
	_entry_readiness_shadow.base_gameplay_mounted()
	loading_profile.hud=Time.get_ticks_msec()
	_previous_feet = _player.global_position - Vector3(0, 0.9, 0)
	apply_actions(Net.server().world3d_events.runtime.collect_autorun(Net.server().world3d_events.context()))
	await get_tree().process_frame
	var batches:Node=map_root.get_node_or_null("GroundRenderBatches")
	while batches!=null and (not batches.pending.is_empty() or not batches._workers.is_empty()) and (not map_root.has_meta("entry_plan") or not Stream.entry_scope_ready(map_root)):
		_loading_stage("准备建筑渲染")
		await get_tree().process_frame
	if batches!=null:batches.work_budget_usec=2000
	loading_profile.batches=Time.get_ticks_msec()
	while not building_preparation.done:
		_loading_stage("校验建筑完整成员与状态")
		await get_tree().process_frame
	if not str(building_preparation.error).is_empty():_building_entry_failure(str(building_preparation.error));return
	_loading_stage("准备受风材质")
	loading_profile.wind_materials=await _prepare_wind(_map_root)
	if not wind_background_enabled:_entry_readiness_shadow.wind_prepared()
	_loading_stage("准备灯光材质")
	loading_profile.lamp_materials=await _weather.streetlamps.prepare_materials(_entry_specs(_map_root),get_tree())
	# Container layout can resize the radar after its first draw. Finish its
	# budgeted offscreen commands at the final width before movement begins.
	if not is_inside_tree() or is_queued_for_deletion():return
	while is_instance_valid(_hud) and is_instance_valid(_hud._radar) and not _entry_radar_ready():
		var progress:Vector2i=_hud._radar.terrain_preparation_progress()
		_loading_stage("准备地图显示",progress.x,progress.y)
		await get_tree().process_frame
		if not is_inside_tree() or is_queued_for_deletion():return
	loading_profile.radar=Time.get_ticks_msec()
	if Net.is_real_server():
		if not _remote_entry_map_matches():
			set_meta("entry_loading_error","服务器地图在场景准备期间发生变化，请重新进入");return
		Net.server().restore_map_interactions(_map_root)
		var acknowledgement:Dictionary=await Net.server().confirm_world_ready(_map_ref())
		if not acknowledgement.get("ok",false):
			set_meta("entry_loading_error","真实服务器入场确认失败");_loading_stage("真实服务器入场确认失败");return
	_entry_readiness_shadow.render_prepared()
	if building_entry_protocol_enabled():
		_building_entry.gameplay_ready()
		Net.server().world3d_authority.movement_allowed=_building_movement_allowed
	_player.input_locked = Net.session()._world_transition_active or building_entry_protocol_enabled()
	_ready_for_play = true
	if map_root.has_meta("entry_plan"):
		loading_profile.entry_playable_ready_us=Time.get_ticks_usec()
	if not Net.session()._world_transition_active:
		if building_entry_protocol_enabled():
			if DisplayServer.get_name()=="headless":await get_tree().process_frame
			else:await RenderingServer.frame_post_draw
			if not note_entry_first_frame(DisplayServer.get_name()!="headless"):return
			_player.input_locked=false;_player.set_physics_process(true)
		activate_entry_neighbours()
	if _check_map:
		_status.text = "检查用白模，不是正式地图 · WASD 走 · N 切换路灯"
	elif _lamps.is_empty():
		_status.text = "WASD 走 · 空格跳跃 · 右键转动 · E 对话 · 走到北边的垫子会去另一张图"
	else:
		_status.text = "WASD 走 · 空格跳跃 · 右键转动 · N 切换路灯"
	if is_instance_valid(Net.session().editor_playtest): _status.text = "WASD 移动 · 空格跳跃 · 右键转动 · E 交互 · 临时试玩"


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or _player.input_locked:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT and not _camera.captured:
			var hit := _pick(button.position)
			if not hit.is_empty():
				if _pending_ground_skill != "":
					_combat.use_skill(_pending_ground_skill, hit.position)
					_pending_ground_skill = ""
					get_viewport().set_input_as_handled()
					return
				var body: Object = hit.collider
				var id := preload("res://scripts/world3d/fortification_collision_batcher.gd").hit_uuid(hit)
				if _combat.targets.has(id):
					_combat.attack(id)
					get_viewport().set_input_as_handled()
					return
				var surface_id := "ground"
				if body is CollisionObject3D and (body as CollisionObject3D).has_meta("surface_id"):
					surface_id = str((body as CollisionObject3D).get_meta("surface_id"))
				_player.set_click_target(hit.position, surface_id)
				get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			if _pending_ground_skill != "":
				_pending_ground_skill = ""
				_status.text = "已取消地点选择。"
				return
			_leave()
		elif key.pressed and not key.echo and key.keycode == KEY_N and not _lamps.is_empty():
			set_night(not _night)
			get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and key.keycode == KEY_E:
			if not _combat.pickup_nearby(): _talk()


func _process(delta: float) -> void:
	if Net.is_real_server():
		if not is_instance_valid(_player) or _player.input_locked or not _player.is_physics_processing():Net.server().queue_movement(Vector3.ZERO,false)
		apply_actions(Net.server().poll_combat_tick())
		if is_instance_valid(_map_root):Net.server().restore_map_interactions(_map_root)
	_update_preparation_hint()
	var profiling:bool=has_meta("profile_frame")
	var marks:Variant=null
	if profiling:marks=[Time.get_ticks_usec()]
	if is_instance_valid(_player):apply_actions(Net.server().facial_expressions.drain())
	if _player == null or _camera == null or not _ready_for_play:
		return
	if building_entry_protocol_enabled() and _building_entry!=null and not _transfer_pending:
		if _building_traversal!=null:_building_traversal.tick()
		_building_lease_clock+=delta
		if _building_lease_clock>=.1:
			_building_lease_clock=0;_building_entry.release_if_left(_player.global_position-Vector3.UP*.9)
	_guard_deferred_geometry()
	if not _transfer_pending:
		_approach_clock+=delta
		if _approach_clock>=.25:_approach_clock=0.;_update_approach_preparation()
		furniture.tick()
	if profiling:marks.append(Time.get_ticks_usec())
	if _ready_for_play and not _transfer_pending and is_instance_valid(_navigation):
		_navigation.follow(_player.position)
		_navigation.resize_agent(float(_player.get_meta("standing_height",1.9)),_map_root.get_meta("stream_library",[]),_player.position)
	if profiling:marks.append(Time.get_ticks_usec())
	_apply_residency(Stream.FRAME_BUDGET)
	if profiling:marks.append(Time.get_ticks_usec())
	_camera.follow(_player.global_position, delta)
	if is_instance_valid(_outline):_outline.visual_exclusions=_camera.visual_exclusions()
	if profiling:marks.append(Time.get_ticks_usec())
	if not _transfer_pending:_apply_actor_view()
	_poll_warp()
	if profiling:
		marks.append(Time.get_ticks_usec())
		set_meta("frame_timings",{"frame":Engine.get_process_frames(),"actions":(marks[1]-marks[0])/1000.0,"navigation":(marks[2]-marks[1])/1000.0,"stream":(marks[3]-marks[2])/1000.0,"camera":(marks[4]-marks[3])/1000.0,"actors":(marks[5]-marks[4])/1000.0})

func _update_cloth_scene()->void:
	if not is_instance_valid(_map_root):return
	var objects:Array=[]
	var bodies:Dictionary=_map_root.get_meta("stream_bodies",{})
	var meshes:Dictionary=_map_root.get_meta("stream_meshes",{})
	for id in meshes:
		if bodies.has(id) and is_instance_valid(bodies[id]):objects.append(meshes[id])
	var model=_player._model
	if model.axis_rig!=null:model.axis_rig.cloth.set_scene_colliders(objects)
	if is_instance_valid(_combat):
		for actor in _combat.actors.values():
			if is_instance_valid(actor) and actor.model.axis_rig!=null:actor.model.axis_rig.cloth.set_scene_colliders(objects)


func _physics_process(_delta: float) -> void:
	if _entry_shadow_waiting_physics:
		_entry_readiness_shadow.observe_physics_frame(Engine.get_physics_frames())
		_entry_shadow_waiting_physics=_entry_readiness_shadow.needs_physics_frame()
	if _ready_for_play and _map_root!=null and _player!=null:_guard_deferred_geometry()
	if _player == null or _player.input_locked or not _ready_for_play:
		return
	var feet := _player.global_position - Vector3(0, 0.9, 0)
	apply_actions(Net.server().world3d_events.touch_segment(_previous_feet, feet))
	_previous_feet = feet


func activate_entry_neighbours()->void:
	if not _ready_for_play or not is_instance_valid(_map_root) or not is_instance_valid(_player):return
	if loading_profile.has("entry_prefetch_started_us"):return
	if is_instance_valid(_navigation):_navigation.covered_loading=false
	var deferred:=_map_root.get_node_or_null("DeferredAssets")
	if deferred!=null:
		var position_:Vector3=_player.global_position
		var collision_clip:Variant=AABB(Vector3(position_.x-2,-100000,position_.z-2),Vector3(4,200000,4)) if _collision_first(_map_root) else null
		deferred.end_entry_loading(collision_clip);deferred.activate(self);deferred.prioritize(position_)
	Stream.clear_entry_scope(_map_root)
	loading_profile.entry_prefetch_started_us=Time.get_ticks_usec()

func _entry_specs(map_root:Node)->Array:
	var specs:Array=map_root.get_meta("stream_library",[])
	if not map_root.has_meta("entry_stream_clip"):return specs
	var clip:AABB=map_root.get_meta("entry_stream_clip")
	return specs.filter(func(spec):return Stream._in_entry_scope(spec,clip))

func _entry_radar_ready()->bool:
	if not _map_root.has_meta("entry_plan"):return _hud._radar.terrain_is_prepared()
	var origin:Vector3=_map_root.get_meta("entry_plan").origin
	return _hud._radar.region_is_prepared(Vector2(origin.x,origin.z))

static func _collision_first(map_root:Node)->bool:
	return is_instance_valid(map_root) and bool(map_root.get_meta("collision_first_loading",false))

func _navigation_async(map_root:Node)->bool:
	if not building_readiness_enabled and _entry_policy.get("mode","")=="full" and _entry_policy.get("reason")!="automatic_disabled":return false
	return navigation_background_enabled or _collision_first(map_root)

func _entry_dependencies_ready(map_root:Node,deferred:Node,clip:AABB,origin:Vector3,id:String,observation:Dictionary={})->bool:
	if deferred==null:return true
	if not _collision_first(map_root):
		var geometry:bool=deferred.ensure_geometry(clip,id)
		if preload("res://scripts/world3d/load_trace.gd").enabled:observation.full_geometry_ready=geometry
		return geometry
	var collision:bool=deferred.ensure_collision(clip,id)
	# Conservatively retain visible supports/interiors at the landing even for
	# imported models without server-authored building membership.
	var landing:=AABB(Vector3(origin.x-2,-100000,origin.z-2),Vector3(4,200000,4))
	# The safety ticket already requests these records; a read-only query avoids
	# shrinking/regrowing that ticket and invalidating the scheduler every frame.
	var visual:bool=deferred.geometry_published(landing)
	if preload("res://scripts/world3d/load_trace.gd").enabled:
		# Record results already computed above; diagnostics must not run another
		# dependency query, mutate its ticket or scan the whole pending queue.
		observation.collision_dependencies_ready=collision
		observation.landing_visual_ready=visual
	return collision and visual

func _prepare_entry_geometry(map_root:Node,host:Node,origin:Vector3,cover:Node=null)->String:
	var plan:Dictionary=map_root.get_meta("entry_plan",{})
	if plan.is_empty():return ""
	loading_profile.entry_core_resources_ready_us=plan.core_resources_ready_us
	loading_profile.entry_core_cell=[plan.cell.x,plan.cell.y]
	if not Stream.set_entry_scope(map_root,plan.safety_clip):return "入口区块范围无效"
	var deferred:=map_root.get_node_or_null("DeferredAssets")
	if deferred!=null and not deferred.begin_entry_loading(host,plan.safety_clip,cover):return "无法启动入口区块准备"
	map_root.set_meta("defer_source_upload",true)
	if wind_background_enabled:_begin_wind_preparation(map_root,_entry_specs(map_root))
	var deadline:=Time.get_ticks_msec()+180000
	while true:
		var gate_started:=Time.get_ticks_usec()
		var dependency_observation:Dictionary={}
		var ready:bool=_entry_dependencies_ready(map_root,deferred,plan.safety_clip,origin,"entry_safety",dependency_observation)
		if deferred!=null:
			var failure:String=deferred.error_for_clip(plan.safety_clip)
			if failure.is_empty():failure=deferred.error
			if not failure.is_empty():
				_abort_entry_geometry(map_root,deferred);return failure
		var sync_started:=Time.get_ticks_usec()
		Stream.sync(map_root,host,origin,Stream.LOAD_BUDGET)
		var sync_ended:=Time.get_ticks_usec()
		# Preserve short-circuit gate order: monitoring must not scan extra geometry
		# while dependencies or the entry scope are still incomplete.
		var scope_ready:Variant=Stream.entry_scope_ready(map_root) if ready else null
		var collision_ready:Variant=Stream.collision_readiness(map_root,plan.safety_clip).ok if scope_ready is bool and scope_ready and _collision_first(map_root) else (Stream.nearby_collision_ready(map_root,origin) if scope_ready is bool and scope_ready else null)
		if preload("res://scripts/world3d/load_trace.gd").enabled:
			_trace_entry_geometry(map_root,deferred,ready,scope_ready,collision_ready,gate_started,sync_started,sync_ended,dependency_observation)
		if collision_ready is bool and collision_ready:break
		if Time.get_ticks_msec()>deadline:
			_abort_entry_geometry(map_root,deferred);return "入口区块准备超时；未放行角色"
		if cover!=null:cover.update_progress("准备当前区块边界与碰撞")
		else:_loading_stage("准备当前区块边界与碰撞")
		_step_wind_preparation(map_root)
		await get_tree().process_frame
	map_root.remove_meta("defer_source_upload")
	loading_profile.entry_safety_ready_us=Time.get_ticks_usec()
	return ""

static func _trace_entry_geometry(map_root:Node,deferred:Node,dependencies_ready:bool,scope_ready:Variant,collision_ready:Variant,gate_started:int,sync_started:int,sync_ended:int,dependency_observation:Dictionary={})->void:
	# Fixed known services and scalar counters only; never walk the tree, inspect
	# GPU arrays or repeat readiness predicates in a diagnostic callback.
	var jobs:Array=map_root.get_meta("stream_jobs",[])
	var cursor:=int(map_root.get_meta("stream_cursor",0))
	var batcher:=map_root.get_node_or_null("GroundRenderBatches")
	var collision:=map_root.get_node_or_null("StreamCollisionPreparer")
	var details:Dictionary={"dependencies_ready":dependencies_ready,"scope_ready":scope_ready,"nearby_collision_ready":collision_ready,
		"gate_begin_us":gate_started,"dependency_gate_us":sync_started-gate_started,"sync_us":sync_ended-sync_started,"ready_gate_us":Time.get_ticks_usec()-sync_ended,
		"jobs":jobs.size(),"cursor":cursor,"uuid":str(jobs[cursor].uuid) if cursor<jobs.size() else "",
		"append_pending":map_root.get_meta("stream_append_pending",[]).size(),
		"stream_cumulative_us":map_root.get_meta("stream_load_profile_us",{}).duplicate(),
		"deferred_jobs":deferred._jobs.size() if deferred!=null else 0,
		"batch_pending":batcher.pending.size() if batcher!=null else 0,"batch_workers":batcher._workers.size() if batcher!=null else 0,
		"batch_preparing":not batcher._preparation.is_empty() if batcher!=null else false}
	details.merge(dependency_observation)
	if collision!=null:
		details.collision_worker=collision._thread!=null and collision._thread.is_alive()
		details.terrain_worker=collision._terrain._thread!=null and collision._terrain._thread.is_alive()
		details.terrain_uuid=str(collision._terrain._spec.get("uuid",""))
		details.terrain_cursor=collision._terrain._cursor;details.terrain_vertices=collision._terrain._faces.size()
		details.terrain_cached=collision._terrain._cached
		if "prepared_face_hits" in collision:details.prepared_face_hits=collision.prepared_face_hits
		if "prepared_face_hits" in collision._terrain:details.terrain_prepared_face_hits=collision._terrain.prepared_face_hits
		if "_face_prefetch" in collision:details.face_prefetch=collision._face_prefetch.profile.duplicate()
	preload("res://scripts/world3d/load_trace.gd").instant("entry.geometry_gate",details)

func _abort_entry_geometry(map_root:Node,deferred:Node)->void:
	map_root.remove_meta("defer_source_upload")
	_cancel_wind_preparation(map_root)
	if deferred!=null:
		deferred.end_entry_loading();deferred._active=false;deferred.set_process(false)
		for job:Dictionary in deferred._jobs.values():job.token.cancel()

func _prepare_navigation() -> void:
	if is_instance_valid(_combat):
		_combat.free()
	_player.input_locked = true
	if is_instance_valid(_navigation):
		_navigation.free()
	_navigation = preload("res://scripts/world3d/world_navigation.gd").new()
	_navigation.covered_loading=not _navigation_async(_map_root)
	_navigation.agent_height=float(_player.get_meta("standing_height",1.9))
	add_child(_navigation)
	_player.navigation = _navigation
	_navigation.runtime_geometry_key=_map_root.get_meta("runtime_geometry_key","")
	if _map_root.has_meta("entry_plan"):_navigation.initial_geometry_clip=_map_root.get_meta("entry_plan").navigation_clip
	_bind_deferred_geometry(_map_root,_navigation)
	_bind_navigation_lifetime(_navigation,_map_root)
	_navigation.build(_map_root.get_meta("stream_library", []), _player.position)
	while not _navigation.ready_for_queries and not _navigation_async(_map_root):
		# Navigation bakes on the engine worker. Build the unchanged HUD while
		# that worker runs, then bind it once combat/navigation are mounted.
		if _navigation._phase.is_empty() and not is_instance_valid(_hud):_create_game_hud()
		var batches:Node=_map_root.get_node_or_null("GroundRenderBatches")
		if batches!=null and batches.pending.is_empty() and batches._workers.is_empty():Net.session().prepare_world_first_frame()
		var phase_name: String={"bounds":"计算范围","source":"收集通行表面"}.get(_navigation._phase,"烘焙")
		_loading_stage("准备通行导航 · "+phase_name,_navigation._cursor,_navigation._specs.size() if not _navigation._phase.is_empty() else 0)
		await get_tree().process_frame
	Net.server().world3d_authority.mount(_player, _navigation, _map_ref())
	_bind_manual_authority()
	_combat = preload("res://scripts/world3d/world_combat.gd").new()
	add_child(_combat)
	_combat.setup(self)
	remote_players.refresh()
	loading_profile.navigation_background=_navigation_async(_map_root)
	if not Net.session()._world_transition_active:_navigation.covered_loading=false

func _bind_navigation_lifetime(navigation:Node,map_root:Node)->void:
	var target:WeakRef=weakref(map_root)
	navigation.publication_guard=func()->bool:
		var map:Variant=target.get_ref()
		return is_instance_valid(map) and map.is_inside_tree() and not map.is_queued_for_deletion()

func _bind_manual_authority()->void:
	_retire_building_traversal()
	var authority=Net.server().world3d_authority
	if _navigation_async(_map_root) or building_entry_protocol_enabled():
		authority.traversal_guard=_manual_traversal_receipt.bind(weakref(_map_root))
	else:authority.traversal_guard=Callable()
	_player.passive_traversal_guard=_manual_traversal_receipt.bind(weakref(_map_root)) if building_entry_protocol_enabled() or _collision_first(_map_root) else Callable()

func _manual_traversal_receipt(clip:AABB,target:WeakRef)->Dictionary:
	var map:Variant=target.get_ref()
	if not is_instance_valid(map) or map!=_map_root or not is_inside_tree() or _transfer_pending:
		return {"ok":false,"reason":"obsolete_map"}
	if building_entry_protocol_enabled():
		if _building_entry==null or not _building_entry.gate.can_play():return {"ok":false,"reason":"entry_pending"}
		if _building_traversal==null or _building_traversal.anchor!=_building_entry.issued.ticket:
			_retire_building_traversal()
			_building_traversal=preload("res://scripts/world3d/building_traversal_barrier.gd").new()
			_building_traversal.setup(self,map,_building_authority(),_building_entry.issued.ticket)
		var building:Dictionary=_building_traversal.guard(clip,_player.global_position-Vector3.UP*.9)
		if not building.ok:
			_status.text="等待建筑准备完成" if building.reason=="building_pending" else "建筑通行暂不可用："+str(building.reason)
			return building
	return _map_traversal_receipt(map,clip,"manual_traversal")

func _retire_building_traversal()->void:
	if _building_traversal!=null:_building_traversal.dispose();_building_traversal=null

func _map_traversal_receipt(map_root:Node,clip:AABB,demand:String)->Dictionary:
	if not is_instance_valid(map_root) or map_root.is_queued_for_deletion():return {"ok":false,"reason":"obsolete_map"}
	var profiling:=has_meta("profile_frame")
	var began:=Time.get_ticks_usec() if profiling else 0
	var errors_done:=began
	var deferred:Node=map_root.get_node_or_null("DeferredAssets")
	if deferred!=null:
		var failure:String=deferred.error_for_clip(clip)
		if profiling:errors_done=Time.get_ticks_usec()
		if not failure.is_empty():return {"ok":false,"reason":failure}
		var complete:bool=deferred.ensure_collision(clip,demand) if _collision_first(map_root) else deferred.ensure_geometry(clip,demand)
		if not complete:return {"ok":false,"reason":"geometry_pending"}
	var geometry_done:=Time.get_ticks_usec() if profiling else 0
	var result:=Stream.collision_readiness(map_root,clip)
	if profiling:
		var finished:=Time.get_ticks_usec()
		set_meta("traversal_timing",{"frame":Engine.get_physics_frames(),"demand":demand,"errors_ms":(errors_done-began)/1000.,"geometry_ms":(geometry_done-errors_done)/1000.,"collision_ms":(finished-geometry_done)/1000.,"ms":(finished-began)/1000.})
	return result

func _prepare_wind(map_root:Node)->Dictionary:
	if wind_background_enabled:
		_begin_wind_preparation(map_root,_entry_specs(map_root))
		var queue:RefCounted=map_root.get_meta("wind_variant_preparation")
		var report:Dictionary=await queue.finish_covered(get_tree())
		map_root.remove_meta("wind_variant_preparation")
		return report.merged({"mode":"covered_variants_background_receivers"},true)
	return await preload("res://scripts/world3d/wind_material_preparer.gd").prepare(_entry_specs(map_root),get_tree())

func _begin_wind_preparation(map_root:Node,specs:Array)->void:
	if not wind_background_enabled:return
	if not map_root.has_meta("wind_variant_preparation"):
		map_root.set_meta("wind_variant_preparation",preload("res://scripts/world3d/wind_material_preparer.gd").new())
	map_root.get_meta("wind_variant_preparation").enqueue(specs)

func _step_wind_preparation(map_root:Node)->void:
	# Called only inside a drawn loading cover. A cold shader operation cannot
	# be preempted by the time budget; runtime bindings must use ready variants.
	if map_root.has_meta("wind_variant_preparation"):
		map_root.get_meta("wind_variant_preparation").step_covered(true,2000,1)

func _cancel_wind_preparation(map_root:Node)->void:
	if not is_instance_valid(map_root) or not map_root.has_meta("wind_variant_preparation"):return
	map_root.get_meta("wind_variant_preparation").cancel()
	map_root.remove_meta("wind_variant_preparation")


func _load_or_fail() -> Node:
	if is_instance_valid(Net.session().prepared_world3d):
		var prepared: Node = Net.session().prepared_world3d
		Net.session().prepared_world3d = null
		_map_path = Net.session().world3d_map_path
		_note_map(prepared)
		_use_map_spawn(prepared)
		return prepared
	var authored := str(Net.session().world3d_map_path)
	if authored != "":
		var loaded_authored := GltfMapIo.load_scene(authored)
		if loaded_authored == null:
			_status.text = "外部地图读取失败"
			return null
		_map_path = authored
		_note_map(loaded_authored)
		_use_map_spawn(loaded_authored)
		return loaded_authored
	var yard_dir := WorldMapPaths.cache_directory("p4_yard")
	var inn_dir := WorldMapPaths.cache_directory("p4_inn")
	if yard_dir.is_empty() or inn_dir.is_empty():
		_status.text = "没有工程外的 content_root，不能进入 3D 世界"
		return null
	var path := yard_dir.path_join("map.gltf")
	var inn_path := inn_dir.path_join("map.gltf")
	var docs = load("res://scripts/world3d/world_document.gd")
	var err: Error = docs.sample_yard(inn_path).save(path)
	if err != OK:
		_status.text = "外部地图写入失败"
		return null
	err = docs.make_inn(path).save(inn_path)
	if err != OK:
		_status.text = "外部地图写入失败"
		return null
	var loaded := GltfMapIo.load_scene(path)
	if loaded == null:
		_status.text = "外部地图读取失败"
		return null
	_map_path = path
	_use_map_spawn(loaded)
	return loaded


func _note_map(map_root: Node) -> void:
	var extras := GltfMapIo.extras_of(map_root)
	var name := str(extras.get("map_name", ""))
	_check_map = str(extras.get("rmmo_role", "")) == "check" or name.contains("白模")


func _use_map_spawn(map_root: Node) -> void:
	if Net.is_real_server():return
	var spawn: Variant = GltfMapIo.extras_of(map_root).get("spawn", [])
	if typeof(spawn) != TYPE_ARRAY or (spawn as Array).size() < 3:
		return
	var current: Vector3 = Net.session().world3d_spawn
	if current != Vector3(0, 0.9, 4):
		return
	var coords: Array = spawn
	Net.session().world3d_spawn = Vector3(float(coords[0]), float(coords[1]), float(coords[2]))


func _add_collision(map_root: Node) -> void:
	Stream.sync(map_root, self, Net.session().world3d_spawn)


func _add_player() -> void:
	var body := CharacterBody3D.new()
	body.name = "Player"
	body.set_script(load("res://scripts/world3d/world_player.gd"))
	body.map_ref = _map_ref()
	body.character = Net.session().active_character()
	var equipment: Array = Net.session().spawn_data.get("equipment", [])
	body.equipment_parts = preload("res://scripts/char/character_view_3d.gd").equipment_parts(str(body.character.gender), equipment, Net.server().item_catalog)
	body.position = Net.session().world3d_spawn
	var capsule := CollisionShape3D.new()
	capsule.name="CollisionShape3D"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	capsule.shape = shape
	body.add_child(capsule)
	var model:Node3D = Net.session().take_world_actor(str(body.character.gender), body.character.get("customization", {}), body.equipment_parts)
	model.name = "CharacterModel3D"
	model.position = Vector3(0, -0.9, 0)
	body.add_child(model)
	add_child(body)
	_player = body
	model.identity_shapes_changed.connect(_on_identity_shapes_changed)
	var rig := Node3D.new()
	rig.name = "FollowCamera"
	rig.set_script(load("res://scripts/world3d/third_person_camera.gd"))
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.fov = 55.0
	rig.add_child(camera)
	add_child(rig)
	_camera = rig
	_refresh_player_clearance()
	_camera.exclude_body(_player.get_rid())
	_player.camera_path = _camera.get_path()
	_outline = preload("res://scripts/world3d/occlusion_outline.gd").new()
	add_child(_outline)
	_outline.bind(_player, camera)

func _refresh_player_clearance()->void:
	if not is_instance_valid(_player) or not is_instance_valid(_camera):return
	_camera.actor_height=preload("res://scripts/world3d/player_clearance.gd").apply(_player,_player.get_node("CharacterModel3D"))

## Perspective controllers must switch this before taking over camera/head pose.
## First-person/VR controllers own their movement; this does not simulate an HMD.
func set_camera_mode(mode:String)->bool:
	return is_instance_valid(_camera) and _camera.set_view_mode(mode)


func _add_light() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48, 32, 0)
	_sun.light_energy = 1.15
	_sun.light_color = Color(1.0, 0.97, 0.9)
	add_child(_sun)
	_sun.add_to_group("character_key_light")
	var env := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.55, 0.68, 0.78)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.72, 0.76, 0.82)
	_env.ambient_light_energy = 0.42
	env.environment = _env
	add_child(env)


func set_night(on: bool) -> void:
	_request_environment({"preset":"night" if on else "day"})

func _request_environment(changes: Dictionary) -> Dictionary:
	var server = Net.server()
	if not is_instance_valid(_weather) or not server.has_method("try_set_world3d_environment"): return {"ok":false,"error":"环境服务未就绪"}
	var began:=Time.get_ticks_usec() if has_meta("profile_frame") else 0
	var result: Dictionary = server.try_set_world3d_environment(_map_ref(),changes)
	var server_end:=Time.get_ticks_usec() if began>0 else 0
	if result.get("ok",false): _weather.sky_poll = 0; _weather._process(0)
	if began>0:set_meta("environment_timing",{"server_ms":(server_end-began)/1000.0,"weather_ms":(Time.get_ticks_usec()-server_end)/1000.0})
	return result

func _on_server_environment(config: Dictionary) -> void:
	_night = config.preset == "night"; _refresh_lamps()
	if is_instance_valid(_outline): _outline.configure(config)
	if is_instance_valid(_camera): _camera.configure_environment(config)

## Runtime weather changes are transient; editor/MCP author the map's initial weather.
func set_weather(kind: String, intensity := .7) -> Dictionary:
	var changes := {"weather":kind, "weather_intensity":intensity}
	var settings = preload("res://scripts/world3d/environment_settings.gd")
	var invalid: String = settings.Schema.validate(changes, settings.schema())
	if not invalid.is_empty(): return {"ok":false, "error":invalid}
	if not is_instance_valid(_weather): return {"ok":false, "error":"地图天气尚未就绪"}
	return _request_environment(changes)

func _apply_map_environment() -> void:
	var settings = preload("res://scripts/world3d/environment_settings.gd")
	var values: Dictionary = settings.resolve(GltfMapIo.extras_of(_map_root))
	settings.apply(values, _sun, _env)
	if not is_instance_valid(_weather):
		_weather = preload("res://scripts/world3d/weather_controller.gd").new()
		add_child(_weather)
		_weather.bind(_camera.camera, _sun, _env, _player)
		_weather.environment_changed.connect(_on_server_environment)
	_weather.wind_objects.cached_variants_only=wind_background_enabled
	var sky_server = Net.server()
	if sky_server.has_method("mount_world3d_sky"): sky_server.mount_world3d_sky(_map_ref(),_map_path)
	if sky_server.has_method("snapshot_world3d_sky"): _weather.bind_sky(_map_ref(),Callable(sky_server,"snapshot_world3d_sky").bind(_map_ref()))
	_weather.configure(values, true)
	if not is_instance_valid(_house_candles):
		_house_candles=preload("res://scripts/world3d/house_candle_lights.gd").new();add_child(_house_candles)
	_house_candles.bind_map(_map_root,_player,_weather)
	values = _weather.values
	_night = values.preset == "night"
	if is_instance_valid(_outline): _outline.configure(values)
	if is_instance_valid(_camera):_camera.bind_map(_map_root,values)
	_refresh_lamps()

func _refresh_lamps() -> void:
	for lamp in _lamps:
		if lamp is OmniLight3D:
			(lamp as OmniLight3D).light_energy = 1.8 if _night else 0.0
	if _status != null and not _lamps.is_empty():
		var prefix := "检查用白模 · " if _check_map else ""
		_status.text = prefix + ("夜晚 · 路灯亮着" if _night else "白天 · 路灯关掉")


func _add_town_lamps(map_root: Node) -> void:
	var extras := GltfMapIo.extras_of(map_root)
	var raw: Variant = extras.get("lamps", [])
	if typeof(raw) != TYPE_ARRAY:
		return
	var coords: Array = raw
	var i := 0
	while i + 2 < coords.size():
		var lamp := OmniLight3D.new()
		lamp.name = "TownLamp%d" % _lamps.size()
		lamp.position = Vector3(float(coords[i]), float(coords[i + 1]), float(coords[i + 2]))
		lamp.light_color = Color(1.0, 0.78, 0.48)
		lamp.omni_range = 11.0
		lamp.omni_attenuation = 1.35
		lamp.shadow_enabled = false
		lamp.light_energy = 0.0
		add_child(lamp)
		_lamps.append(lamp)
		i += 3


func _add_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_revive = Button.new()
	_revive.text = "返回出生点复活"
	_revive.position = Vector2(530, 80)
	_revive.visible = false
	_revive.pressed.connect(func():
		if building_entry_protocol_enabled():
			if await _combat.request_respawn():_revive.hide()
		elif _combat.respawn():_revive.hide()
	)
	layer.add_child(_revive)
	_status = Label.new()
	_status.position = Vector2(16, 12)
	_status.text = "正在读取外部地图…"
	layer.add_child(_status)
	if is_instance_valid(Net.session().editor_playtest): return
	var back := Button.new()
	back.text = "返回登录"
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.position = Vector2(-110, 12)
	back.pressed.connect(_leave)
	layer.add_child(back)
	if Net.session().editor_return:
		var edit := Button.new()
		edit.text = "返回编辑"
		edit.anchor_left = 0.5
		edit.anchor_right = 0.5
		edit.position = Vector2(0, 12)
		edit.pressed.connect(_back_to_editor)
		layer.add_child(edit)


func _pick(screen: Vector2) -> Dictionary:
	var camera := _camera.get_node("Camera3D") as Camera3D
	var origin := camera.project_ray_origin(screen)
	var end := origin + camera.project_ray_normal(screen) * 80.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = _camera.visual_exclusions()
	return get_world_3d().direct_space_state.intersect_ray(query)


func _apply_actor_view() -> void:
	var server = Net.server()
	if server == null or not server.has_method("try_world3d_chunk"):
		return
	var packet: Dictionary = server.try_world3d_chunk(_player.global_position.x, _player.global_position.z)
	if not bool(packet.get("ok", false)):
		return
	if _actor_host == null:
		_actor_host = Node3D.new()
		_actor_host.name = "ActorView"
		add_child(_actor_host)
	load("res://scripts/world3d/view_actors.gd").apply(_actor_host, packet.get("view", []))


func _apply_residency(budget: int = 0) -> void:
	if _map_root == null or _player == null:
		return
	# The same-map transaction drives target residency while its origin is
	# pinned. A second plan at the frozen player's old position would thrash it.
	if not _local_transfer.is_empty():return
	var started:=Time.get_ticks_usec()
	Stream.sync(_map_root, self, _player.global_position, budget)
	if budget>0 and budget<Stream.LOAD_BUDGET and not has_meta("profile_unshared_stream_budget"):
		var batcher=_map_root.get_node_or_null("GroundRenderBatches")
		if batcher!=null:
			batcher.residency_budget_frame=Engine.get_process_frames()
			batcher.residency_budget_remaining_usec=maxi(0,3000-(Time.get_ticks_usec()-started))


func _poll_warp() -> void:
	if _player == null or _map_path == "" or _player.input_locked:
		return
	if _warp_cache_dirty:
		_warp_candidates.clear()
		for child in get_children():
			if str(child.get_meta("kind", ""))=="warp":_warp_candidates.append(child)
		_warp_cache_dirty=false
	for child in _warp_candidates:
		if not is_instance_valid(child):continue
		var center: Vector3 = child.get_meta("center")
		if not Travel.near(_player.global_position, center, 1.2):
			continue
		var target := str(child.get_meta("target_path", ""))
		if target == _failed_warp:
			return
		var spawn: Array = child.get_meta("spawn", [])
		if spawn.size() != 3: return
		var destination := Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
		if not await transfer_map(target, destination): _failed_warp = target
		return
	_failed_warp = ""


func _map_ref() -> String:
	if Net.is_real_server():return str(Net.server().world_session.get("map_ref",""))
	var authored := str(GltfMapIo.extras_of(_map_root).get("map_ref", ""))
	if preload("res://scripts/world3d/world_location.gd").map_ref_ok(authored):
		return authored
	return "prototype/map_" + _map_path.sha256_text().substr(0, 16)

func _remote_connection_lost(message:String)->void:
	if is_instance_valid(_player):_player.input_locked=true;_player.velocity=Vector3.ZERO;_player.click_target=null
	_ready_for_play=false
	if is_instance_valid(_status):_status.text=message

func _remote_world_changed(_session:Dictionary)->void:
	_remote_connection_lost("正在同步服务器地图")
	if Net.session()._world_transition_active:
		set_meta("entry_loading_error","服务器地图在场景准备期间发生变化，请重新进入");return
	var server=Net.server();var scope:Dictionary=server.context();var connection:int=server._connection_revision
	var prepared:Dictionary=await server.prepare_authoritative_map()
	if not is_inside_tree() or not is_instance_valid(server) or Net.server()!=server or scope!=server.context() or connection!=server._connection_revision:return
	if not prepared.get("ok",false):
		if is_instance_valid(_status):_status.text=str(prepared.get("error","地图不可用"))
		return
	prepared=await server.refresh_world_snapshots()
	if not is_inside_tree() or not is_instance_valid(server) or Net.server()!=server or scope!=server.context() or connection!=server._connection_revision:return
	if not prepared.get("ok",false):
		if is_instance_valid(_status):_status.text="服务器地图快照恢复失败，请重新进入"
		return
	Net.session().loading_mode="world3d_remote"
	Net.session().go_loading()

func _remote_entry_map_matches()->bool:
	var server=Net.server()
	if server==null or not is_instance_valid(_map_root) or _remote_entry_context!=server.context():return false
	if _map_root.get_meta("remote_loaded_context",{})!=_remote_entry_context or _map_root.get_meta("remote_loaded_connection",-1)!=server._connection_revision or _map_root.get_meta("remote_loaded_server",0)!=server.get_instance_id():return false
	return server.prepared_map_matches(str(GltfMapIo.extras_of(_map_root).get("map_ref","")),_map_path)


func _talk() -> void:
	if Net.is_real_server():Net.server().interact_nearest(_player.global_position-Vector3.UP*.9);return
	if furniture.active():
		furniture.stand();return
	if _player == null or _travel == null:
		return
	var bodies: Array = []
	for child in get_children():
		if child.has_meta("seat"):
			bodies.append(child)
	var closest: StaticBody3D
	var distance := 2.0
	for body in bodies:
		var center: Vector3 = body.get_meta("center")
		var flat := Vector2(_player.global_position.x, _player.global_position.z).distance_to(Vector2(center.x, center.z))
		if absf(_player.global_position.y - center.y) <= 1.0 and flat < distance:
			closest = body
			distance = flat
	if closest != null:
		if closest.has_meta("seat"):
			if not furniture.interact(closest):_status.text="无法使用这张椅子。"
			return
	var events = Net.server().world3d_events
	var id: String = events.nearest(_player)
	if not id.is_empty(): apply_actions(events.interact(id, _player))


func _mount_events() -> void:
	Net.server().world3d_events.mount(_map_ref(), _map_root.get_meta("stream_library", []), GltfMapIo.extras_of(_map_root).get("rmmo_records", []))


func _create_game_hud()->void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var path:="res://scenes/ui/game_hud.tscn"
	var status:=ResourceLoader.load_threaded_get_status(path)
	var packed:PackedScene=ResourceLoader.load_threaded_get(path) if status in [ResourceLoader.THREAD_LOAD_LOADED,ResourceLoader.THREAD_LOAD_IN_PROGRESS] else load(path)
	_hud = packed.instantiate()
	loading_profile.hud_instantiated=Time.get_ticks_msec()
	layer.add_child(_hud)
	loading_profile.hud_added=Time.get_ticks_msec()


func _add_game_hud() -> void:
	if not is_instance_valid(_hud):_create_game_hud()
	_hud.bind_character(Net.session().active_character())
	_hud.bind_world_combat(self)
	var data: Dictionary = Net.session().spawn_data
	_hud.apply_combat_stats(data.get("combat", {}))
	_hud.apply_inventory_snapshot(data.get("inventory", []), int(data.get("gold", 0)))
	_hud.apply_equipment_snapshot(data.get("equipment", []), data.get("equipment_bonuses", {}))
	_hud.apply_quest_snapshot(data.get("quests", []))
	_hud.apply_skill_catalog(Net.server().snapshot_skill_catalog())
	_hud.apply_skill_book(data.get("skill_book", {}))
	_hud.apply_guild_update({"guild":Net.server().snapshot_guild()})
	loading_profile.hud_bound=Time.get_ticks_msec()
	_refresh_world_map()
	_status.position.y = 106


func apply_actions(actions: Array) -> void:
	for action in actions:
		match str(action.get("type", "")):
			"house_permissions":
				if not is_instance_valid(_house_permissions):
					_house_permissions=preload("res://scripts/ui/house_permissions.gd").new();add_child(_house_permissions)
				_house_permissions.show_house(action.get("house",{}),Net.server())
			"player_revived":
				_revive.hide()
				_player.input_locked=not is_world_ready()
				_player.get_node("CharacterModel3D").play("idle","front")
			"status_update":
				if _hud!=null:_hud.apply_status_chips(action.get("statuses",[]))
			"remote_entities":
				if _combat!=null:_combat.sync_remote()
			"remote_combat_event":
				if _combat!=null:_combat.apply_remote_event(action.get("event",{}))
			"remote_combat_state":
				Net.session().spawn_data["combat"]=action.get("stats",{})
				if _hud!=null:_hud.apply_combat_stats(action.get("stats",{}))
			"open_shop":
				if _hud != null:
					_hud.show_shop(str(action.get("shop_id", "")), str(action.get("title", "")), action.get("listings", []), int(action.get("gold", 0)), int(action.get("vendor_rep", -1)))
					_hud.apply_shop_buyback(action.get("buyback", []))
			"shop_buyback":
				if _hud != null: _hud.apply_shop_buyback(action.get("buyback", []))
			"facial_expression":remote_players.receive(action)
			"remote_spawn":remote_players.spawn(action.get("player",{}))
			"remote_despawn":remote_players.despawn(str(action.get("id",action.get("player_id",""))))
			"sit":
				if furniture.active():
					if not bool(action.get("on",false)):furniture.stand()
					continue
				if bool(action.get("on",false)):
					if _player._model.action not in ["sit_down_ground","sit_ground"]:_player.request_rest("sit_down_ground")
				elif _player._model.action in ["sit_down_ground","sit_ground"]:
					_player._begin_ground_exit()
			"player_died":
				furniture.cancel(true)
				cancel_sit_preparation()
				Net.server().sitting=false
				Net.server().awaiting_respawn = true
				_player.input_locked = true
				_player.velocity = Vector3.ZERO
				_player.click_target = null
				_player._route.clear()
				_player.get_node("CharacterModel3D").play("death", "front")
				_revive.show()
			"skill_cd":
				if _hud != null: _hud.note_skill_cooldown(str(action.skill_id), float(action.remaining), float(action.get("cooldown", 0)))
			"cast_start":
				if _hud != null and str(action.get("caster", "player")) == "player": _hud.apply_cast_start(action)
			"cast_update":
				if _hud != null and str(action.get("caster", "player")) == "player": _hud.apply_cast_update(action)
			"cast_end":
				if _hud != null and str(action.get("caster", "player")) == "player": _hud.apply_cast_end(action)
			"show_npc_dialogue":
				_status.text = str(action.get("body", ""))
				if _hud != null:
					_hud.show_npc_dialogue(str(action.get("npc_name", "")), str(action.get("body", "")), action.get("options", []))
			"system_message":
				_status.text = str(action.get("text", ""))
				if _hud != null:
					_hud.append_system(_status.text)
			"inventory_update":
				Net.session().spawn_data["inventory"] = action.get("items", [])
				Net.session().spawn_data["gold"] = action.get("gold", 0)
				if _hud != null:
					_hud.apply_inventory_snapshot(action.get("items", []), int(action.get("gold", 0)))
			"equipment_update":
				var equipment: Array = action.get("equipment", [])
				Net.session().spawn_data["equipment"] = equipment
				var gender := str(_player.character.gender)
				_player.get_node("CharacterModel3D").set_equipment(preload("res://scripts/char/character_view_3d.gd").equipment_parts(gender, equipment, Net.server().item_catalog))
				if _hud != null:
					_hud.apply_equipment_snapshot(equipment, action.get("bonuses", {}))
			"quest_update":
				if _hud != null:
					_hud.apply_quest_snapshot(Net.server().snapshot_quest_journal())
			"guild_update":
				if _hud != null:_hud.apply_guild_update(action)
			"guild_invite":
				if _hud != null:_hud.apply_guild_invite(action)
			"world3d_transfer":
				var loc = preload("res://scripts/world3d/world_location.gd").from_dictionary(action["location"])
				var warp := StaticBody3D.new()
				warp.set_meta("kind", "warp")
				warp.set_meta("center", _player.global_position)
				warp.set_meta("target_path", action["path"])
				warp.set_meta("spawn", [loc.position_m.x, loc.position_m.y + 0.9, loc.position_m.z])
				add_child(warp)
				_poll_warp()
				warp.queue_free()


func request_event_choice(option_id: String, option_index: int) -> void:
	apply_actions(Net.server().world3d_events.choice(option_id, option_index))

func request_shop_buy(shop_id: String, item_id: String, quantity: int = 1) -> void:
	apply_actions(Net.server().try_shop_buy(shop_id, item_id, quantity).get("actions", []))

func request_shop_sell(item_id: String, quantity: int = 1) -> void:
	apply_actions(Net.server().try_shop_sell(item_id, quantity).get("actions", []))

func request_shop_sell_junk() -> void:
	apply_actions(Net.server().try_shop_sell_junk().get("actions", []))

func request_shop_buyback(index: int) -> void:
	apply_actions(Net.server().try_shop_buyback(index).get("actions", []))

func request_shop_close() -> void:
	apply_actions(Net.server().try_shop_close().get("actions", []))


func request_equip_item(item_id: String, slot: String = "") -> void:
	apply_actions(Net.server().try_equip_item(item_id, slot).get("actions", []))


func request_unequip_item(slot: String) -> void:
	apply_actions(Net.server().try_unequip_item(slot).get("actions", []))


func _leave() -> void:
	if _camera != null and _camera.has_method("release_capture"):
		_camera.release_capture()
	Net.session().editor_return = false
	Net.session().go_login()


func _back_to_editor() -> void:
	if _camera != null and _camera.has_method("release_capture"):
		_camera.release_capture()
	Net.session().go_world_editor()


func request_use_skill(skill_id: String) -> void:
	var definition: Dictionary = Net.server().skill_catalog.get_skill(skill_id)
	if Net.server().combat_engine.skill_target_mode(definition) == "ground":
		_pending_ground_skill = skill_id
		_status.text = "点击地面选择施法位置。"
		return
	_combat.use_skill(skill_id)


func request_use_item(item_id: String) -> void:
	_combat.use_item(item_id)


func transfer_map(target: String, destination: Vector3, before_commit: Callable = Callable()) -> bool:
	if Net.is_real_server():apply_actions(Net.server()._unsupported("transfer_map").actions);return false
	if is_instance_valid(Net.session().editor_playtest): target = Net.session().editor_playtest.resolve_map(target)
	if not destination.is_finite() or target.is_empty(): return false
	if not Net.server().combat_stats.player_alive(): return false
	if _transfer_pending and _local_transfer.is_empty():return false
	_transfer_request_serial+=1
	var request:=_transfer_request_serial
	if _transfer_pending:
		# Latest valid request wins before commit. A committed handoff finishes
		# its first rendered frame before the next transaction may start.
		if not _local_transfer.get("committed",false):_local_transfer.cancelled=true
		while _transfer_pending:await get_tree().process_frame
		if request!=_transfer_request_serial:return false
	_approach_preparation.release(_map_root.get_node_or_null("DeferredAssets"))
	if _same_map_target(target):
		if is_instance_valid(_cross_map_prefetch):_cross_map_prefetch.cancel()
		if is_instance_valid(_target_scene_prefetch):_target_scene_prefetch.cancel()
		return await _transfer_within_map(target,destination,before_commit,request)
	_transfer_pending = true
	var original:Dictionary={"combat_processing":_combat.is_physics_processing(),"locked":_player.input_locked,"physics":_player.is_physics_processing(),"velocity":_player.velocity,"geometry_blocked":_player.geometry_blocked,"geometry_wait_locked":_geometry_wait_locked,"transform":_player.global_transform,"disable_3d":get_viewport().disable_3d,"entry_policy":_entry_policy.duplicate()}
	_transfer_viewport_restore=original.disable_3d
	if building_entry_protocol_enabled():original.building_snapshot=_building_source_snapshot()
	original.navigation_processing=_navigation.is_processing()
	_navigation.set_process(false)
	var outgoing_deferred:=_map_root.get_node_or_null("DeferredAssets")
	if outgoing_deferred!=null:
		original.deferred=outgoing_deferred;original.deferred_processing=outgoing_deferred.is_processing()
		original.deferred_active=outgoing_deferred._active
		outgoing_deferred.set_process(false)
	_combat.set_physics_process(false)
	_player.input_locked = true
	_player.set_physics_process(false);_player.velocity=Vector3.ZERO
	var cover:=preload("res://scripts/world3d/transfer_loading.gd").new();add_child(cover)
	if is_instance_valid(_camera):_camera.release_capture()
	if not await cover.wait_until_drawn():return _hold_transfer_presentation(cover)
	get_viewport().disable_3d=true
	cover.update_progress("等待当前导航调整结束")
	await _navigation.cancel_resize()
	if outgoing_deferred!=null:
		cover.update_progress("等待当前区域素材任务结束")
		await outgoing_deferred.quiesce()
	_combat._save_map_state()
	_status.text = "读取目标地图…"
	cover.update_progress("读取目标地图与附近素材（后台）")
	var prepared:Node
	if is_instance_valid(_target_scene_prefetch):
		prepared=_target_scene_prefetch.take(target,destination)
		await _target_scene_prefetch.drain()
	if prepared==null:
		var prefetched:CrossMapPrefetch.Packet
		if is_instance_valid(_cross_map_prefetch):
			prefetched=_cross_map_prefetch.take(target,destination)
			await _cross_map_prefetch.drain()
		var loader = preload("res://scripts/world3d/map_loader.gd").new()
		loader.source_prefetch=prefetched;loader.near_first=true;_transfer_loader=loader
		loader.progress.connect(func(stage: String, done: int, total: int):
			_status.text = "%s %d/%d" % [stage, done, total]
			if is_instance_valid(cover):cover.update_progress(stage,done,total)
		)
		Net.session().add_child(loader);loader.start(target,destination)
		var result:Array=await loader.finished;_transfer_loader=null;prepared=result[0]
		if prepared==null:return await _transfer_failed(original,cover,str(result[2]))
	# The local lease keeps warmed buffers alive through target draw/adoption,
	# then releases them. It cannot pin all resources for the map's lifetime.
	var gpu_owners:Array=prepared.get_meta("prefetched_gpu_owners",[])
	if prepared.has_meta("prefetched_gpu_owners"):prepared.remove_meta("prefetched_gpu_owners")
	# Prepare and validate in an isolated physics world. The current map and
	# inventory stay intact until navigation and the destination capsule fit.
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.disable_3d = true
	add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	stage.add_child(prepared)
	_entry_policy=_choose_entry_policy(prepared,target,destination)
	if building_entry_protocol_enabled():
		_building_transfer=_new_building_entry(prepared,target,destination,"cross_map_transfer")
		if _building_transfer.has_meta("error"):return await _transfer_failed(original,cover,str(_building_transfer.get_meta("error")),null,viewport)
	if prepared.has_meta("entry_plan"):
		var entry_error:String=await _prepare_entry_geometry(prepared,stage,destination,cover)
		if not entry_error.is_empty():return await _transfer_failed(original,cover,entry_error,null,viewport)
	if building_entry_protocol_enabled():
		var building_error:String=await _building_transfer.prepare(self,stage,destination,cover)
		if not building_error.is_empty():return await _transfer_failed(original,cover,building_error,null,viewport)
	var target_deferred:=prepared.get_node_or_null("DeferredAssets")
	var initial_clip:AABB=prepared.get_meta("entry_plan",{}).get("navigation_clip",AABB(Vector3(destination.x-80,-100000,destination.z-80),Vector3(160,200000,160)))
	if not _entry_dependencies_ready(prepared,target_deferred,initial_clip,destination,"entry_safety"):
		return await _transfer_failed(original,cover,"目标附近物件尚未完整准备；保留当前地图。",null,viewport)
	cover.update_progress("准备目标附近物件与碰撞")
	var deadline:=Time.get_ticks_msec()+180000
	while not prepared.has_meta("stream_chunk") or not Stream.nearby_collision_ready(prepared,destination):
		if Time.get_ticks_msec()>deadline:return await _transfer_failed(original,cover,"目标附近碰撞准备超时；保留当前地图。",null,viewport)
		Stream.sync(prepared, stage, destination, Stream.LOAD_BUDGET)
		await get_tree().process_frame
	var navigation = preload("res://scripts/world3d/world_navigation.gd").new()
	navigation.covered_loading=not _navigation_async(prepared)
	navigation.agent_height=float(_player.get_meta("standing_height",1.9))
	add_child(navigation)
	navigation.runtime_geometry_key=prepared.get_meta("runtime_geometry_key","")
	if prepared.has_meta("entry_plan"):navigation.initial_geometry_clip=prepared.get_meta("entry_plan").navigation_clip
	_bind_deferred_geometry(prepared,navigation)
	_bind_navigation_lifetime(navigation,prepared)
	navigation.build(prepared.get_meta("stream_library", []), destination)
	deadline=Time.get_ticks_msec()+180000
	while not navigation.ready_for_queries and not _navigation_async(prepared):
		var navigation_error:=_transfer_navigation_error(navigation)
		if not navigation_error.is_empty():return await _transfer_failed(original,cover,navigation_error,navigation,viewport)
		if Time.get_ticks_msec()>deadline:return await _transfer_failed(original,cover,"目标附近导航准备超时；保留当前地图。",navigation,viewport)
		cover.update_progress("准备目标附近通行导航",navigation._cursor,navigation._specs.size())
		await get_tree().process_frame
	cover.update_progress("准备目标区域材质与灯光")
	await _prepare_wind(prepared)
	await _weather.streetlamps.prepare_materials(_entry_specs(prepared),get_tree())
	var batches:=prepared.get_node_or_null("GroundRenderBatches")
	deadline=Time.get_ticks_msec()+180000
	while batches!=null and (not batches.pending.is_empty() or not batches._workers.is_empty()) and (not prepared.has_meta("entry_plan") or not Stream.entry_scope_ready(prepared)):
		if Time.get_ticks_msec()>deadline:return await _transfer_failed(original,cover,"目标区域绘制准备超时；保留当前地图。",navigation,viewport)
		cover.update_progress("准备目标区域绘制")
		await get_tree().process_frame
	if target_deferred!=null:await target_deferred.quiesce()
	await get_tree().physics_frame
	await get_tree().process_frame
	var feet := destination - Vector3(0, 0.9, 0)
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.29
	capsule.height = float(_player.get_meta("standing_height",1.9))-.02
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, capsule.height/2+.02, 0))
	var fits:bool
	if _navigation_async(prepared):
		fits=_physical_destination_fits(prepared,stage.get_world_3d().direct_space_state,destination,[])
	else:fits=navigation.near_surface(feet, 0.35, 0.4) and stage.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	# Dynamic actors are deliberately absent from static navigation/collision.
	# Check their authored occupancy before committing, including cached poses.
	var saved: Dictionary = Net.server().world3d_state.read_map(target.simplify_path())
	for spec in prepared.get_meta("stream_library", []):
		var data: Dictionary = spec.get("extras", {})
		if not bool(data.get("hostile", false)) and not bool(data.get("ally", false)): continue
		var bounds: AABB = spec.transform * spec.mesh.get_aabb()
		var actor_feet := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
		var cached: Dictionary = saved.get("actors", {}).get(str(spec.uuid), {})
		if not cached.is_empty() and cached.get("signature", "") == _combat._signature(spec):
			if cached.get("stats", {}).is_empty() or int(cached.stats.get("hp", 0)) <= 0: continue
			actor_feet = cached.position - Vector3(0, 0.9, 0)
		if absf(actor_feet.y - feet.y) < 1.8 and Vector2(actor_feet.x - feet.x, actor_feet.z - feet.z).length() < 0.6: fits = false
	if not fits or (before_commit.is_valid() and not before_commit.call()):
		return await _transfer_failed(original,cover,"目标出生点不可用，或操作条件已变化；保留当前地图。",navigation,viewport)
	if building_entry_protocol_enabled():
		var current_ticket:Dictionary=_building_authority().validate(_building_transfer.issued.ticket)
		if not current_ticket.ok:return await _transfer_failed(original,cover,str(current_ticket.reason),navigation,viewport)
		if not _physical_destination_fits(prepared,stage.get_world_3d().direct_space_state,destination,[]):return await _transfer_failed(original,cover,"权威落点无有效支撑",navigation,viewport)
	if target_deferred!=null and not target_deferred.begin_scene_handoff():
		return await _transfer_failed(original,cover,"目标区块队列尚未安全停止；保留当前地图。",navigation,viewport)
	# Commit after preparation. Save the outgoing mock map state before freeing it.
	cover.update_progress("进入目标区域")
	cancel_sit_preparation()
	if Net.server().sitting:apply_actions(Net.server().try_sit(false).get("actions",[]))
	furniture.cancel()
	_combat.free()
	# Detached CPU workers retain their immutable inputs in the shared drainer;
	# freeing the outgoing map must not synchronously join unfinished geometry.
	for service:String in ["GroundRenderBatches","StreamCollisionPreparer"]:
		var outgoing:Node=_map_root.get_node_or_null(service)
		if outgoing!=null:outgoing.retire_workers(get_tree())
	for body in _map_root.get_meta("stream_bodies", {}).values():
		if is_instance_valid(body): body.free()
	# Clear presentation observers while outgoing meshes still have valid owners.
	if is_instance_valid(_house_candles):_house_candles.bind_map(null)
	if is_instance_valid(_camera):_camera.cutaway.bind(null)
	if not building_entry_protocol_enabled() and _building_entry!=null:_building_entry.cancel("full_wait_handoff");_building_entry=null
	_map_root.free()
	if not _navigation.retire_background("map_replaced"):_navigation.free()
	for lamp in _lamps: lamp.free()
	_lamps.clear()
	Net.server().world3d_release_actors()
	if is_instance_valid(_actor_host): _actor_host.free()
	_actor_host = null
	_map_root = prepared
	_geometry_wait_locked=false
	_player.geometry_blocked=false
	prepared.reparent(self)
	if target_deferred!=null:target_deferred.end_scene_handoff(self)
	for body in prepared.get_meta("stream_bodies", {}).values():
		if is_instance_valid(body): body.reparent(self)
	_navigation = navigation
	viewport.queue_free()
	_map_path = target
	Net.session().world3d_map_path = target
	Net.session().world3d_spawn = destination
	_player.global_position = destination
	_player.velocity = Vector3.ZERO
	_player.click_target = null
	_player._route.clear()
	_previous_feet = feet
	_player.map_ref = _map_ref()
	_player.navigation = navigation
	Net.server().world3d_authority.mount(_player, navigation, _map_ref())
	_bind_manual_authority()
	_combat = preload("res://scripts/world3d/world_combat.gd").new()
	add_child(_combat)
	_combat.setup(self)
	_combat.set_physics_process(false)
	remote_players.refresh()
	_add_town_lamps(prepared)
	_note_map(prepared)
	_mount_events()
	_refresh_world_map()
	_apply_map_environment()
	while is_instance_valid(_hud) and is_instance_valid(_hud._radar) and not _hud._radar.region_is_prepared(Vector2(destination.x,destination.z)):
		var radar_progress:Vector2i=_hud._radar.terrain_preparation_progress()
		cover.update_progress("准备目标区域地图显示",radar_progress.x,radar_progress.y)
		await get_tree().process_frame
	await get_tree().physics_frame
	get_viewport().disable_3d=bool(original.disable_3d)
	_camera.snap_to(_player.global_position)
	if not await cover.finish(_camera.camera):return _hold_transfer_presentation(cover)
	gpu_owners.clear() # Target instances now own the exact buffers used in its drawn frame.
	if building_entry_protocol_enabled() and not _activate_building_transfer(cover):return false
	if not await cover.reveal():return _hold_transfer_presentation(cover)
	cover.retire()
	_combat.set_physics_process(bool(original.combat_processing))
	_player.set_physics_process(bool(original.physics))
	_player.input_locked = false
	_record_transfer_presentation(cover,{"target":target,"ok":true,"committed":true})
	_transfer_pending = false
	navigation.covered_loading=false
	var deferred:=prepared.get_node_or_null("DeferredAssets")
	if deferred!=null:
		var collision_clip:Variant=AABB(Vector3(destination.x-2,-100000,destination.z-2),Vector3(4,200000,4)) if _collision_first(prepared) else null
		deferred.end_entry_loading(collision_clip);deferred.activate(self);deferred.prioritize(destination)
	if prepared.has_meta("entry_plan"):Stream.clear_entry_scope(prepared)
	_status.text = "已进入目标地图。"
	return true

func _hold_transfer_presentation(cover:CanvasLayer)->bool:
	if not is_inside_tree() or not is_instance_valid(cover) or not cover.is_inside_tree():return false
	_player.input_locked=true;_player.set_physics_process(false)
	var reason:="目标画面未能完成显示，请返回角色选择。"
	cover.show_failure(reason,func():Net.session().go_character_select())
	set_meta("transfer_loading_profile",{"ok":false,"error":reason,"presentation_blocked":true})
	return false


func _record_transfer_presentation(cover:CanvasLayer,result:Dictionary)->void:
	var profile:Dictionary=cover.profile()
	profile.merge(result,true)
	profile.input_restored_ms=Time.get_ticks_msec()
	profile.input_locked_at_return=_player.input_locked
	_transfer_viewport_restore=null
	set_meta("transfer_loading_profile",profile)


func _same_map_target(target:String)->bool:
	var left:=target.replace("\\","/").simplify_path()
	var right:=_map_path.replace("\\","/").simplify_path()
	return left.to_lower()==right.to_lower() if OS.get_name()=="Windows" else left==right

func _local_transfer_error(context:Dictionary)->String:
	if context.get("cancelled",false) or context.request!=_transfer_request_serial:return "已取消先前的传送，保留原位置。"
	if not is_instance_valid(context.map) or context.map!=_map_root:return "当前地图已变化，传送已取消。"
	var deferred:Node=context.get("deferred")
	if is_instance_valid(deferred):
		var local_error:String=deferred.error_for_clip(context.clip)
		if local_error.is_empty():local_error=deferred.error
		if not local_error.is_empty():return "目标附近素材准备失败："+local_error
	return ""

## Dedicated dead-player path. Ordinary transfer_map still rejects dead actors;
## health changes only after destination first-frame authority activation.
func prepare_respawn(destination:Vector3,still_dead:Callable,activation_commit:Callable)->bool:
	if not building_entry_protocol_enabled() or _transfer_pending or not destination.is_finite():return false
	if not still_dead.is_valid() or not activation_commit.is_valid() or Net.server().combat_stats.player_alive() or not still_dead.call():return false
	_transfer_request_serial+=1
	return await _transfer_within_map(_map_path,destination,still_dead,_transfer_request_serial,activation_commit)

func cancel_respawn_preparation()->bool:
	if _local_transfer.is_empty() or not _local_transfer.get("respawn",false) or _local_transfer.get("committed",false):return false
	_local_transfer.cancelled=true
	return true

func _transfer_within_map(target:String,destination:Vector3,before_commit:Callable,request:int,activation_commit:Callable=Callable())->bool:
	if not is_instance_valid(_map_root) or not is_instance_valid(_navigation) or not is_instance_valid(_combat):return false
	_transfer_pending=true
	var original:Dictionary={"combat_processing":_combat.is_physics_processing(),"locked":_player.input_locked,"physics":_player.is_physics_processing(),"velocity":_player.velocity,"geometry_blocked":_player.geometry_blocked,"geometry_wait_locked":_geometry_wait_locked,"transform":_player.global_transform,"disable_3d":get_viewport().disable_3d,"navigation_processing":_navigation.is_processing()}
	_transfer_viewport_restore=original.disable_3d
	if building_entry_protocol_enabled():original.building_snapshot=_building_source_snapshot()
	var deferred:=_map_root.get_node_or_null("DeferredAssets")
	if deferred!=null:
		original.deferred=deferred;original.deferred_processing=deferred.is_processing()
		original.deferred_active=deferred._active
	var cover:=preload("res://scripts/world3d/transfer_loading.gd").new()
	var entry_plan:Dictionary=preload("res://scripts/world3d/entry_plan.gd").create(destination)
	var clip:AABB=entry_plan.core_clip
	var context:Dictionary={"request":request,"map":_map_root,"deferred":deferred,"original":original,"cover":cover,"navigation":null,"cancelled":false,"committed":false,
		"origin_id":"transfer_origin:%d"%request,"target_id":"transfer_target:%d"%request,"demand_id":"transfer:%d"%request,"destination":destination,"clip":clip}
	context.respawn=activation_commit.is_valid()
	context.entry_plan=entry_plan
	original.entry_stream_clip=_map_root.get_meta("entry_stream_clip") if _map_root.has_meta("entry_stream_clip") else null
	_local_transfer=context
	_combat.set_physics_process(false);_navigation.set_process(false)
	_player.input_locked=true;_player.set_physics_process(false);_player.velocity=Vector3.ZERO
	Stream.pin_source(_map_root,context.origin_id,_player.global_position)
	add_child(cover)
	if is_instance_valid(_camera):_camera.release_capture()
	if not await cover.wait_until_drawn():return _hold_transfer_presentation(cover)
	get_viewport().disable_3d=true
	Stream.pin_source(_map_root,context.target_id,destination)
	context.stream_scope_applied=Stream.set_entry_scope(_map_root,entry_plan.safety_clip)
	if wind_background_enabled:_begin_wind_preparation(_map_root,_entry_specs(_map_root))
	cover.update_progress("等待当前导航调整结束")
	await _navigation.cancel_resize()
	if context.get("cancelled",false) or request!=_transfer_request_serial:
		return await _local_transfer_failed(context,"已取消先前的传送，保留原位置。")
	if building_entry_protocol_enabled():
		_building_transfer=_new_building_entry(_map_root,_map_path,destination,"same_map_transfer")
		if _building_transfer.has_meta("error"):return await _local_transfer_failed(context,str(_building_transfer.get_meta("error")))
	if deferred!=null:
		deferred.retry_failed(clip)
		deferred.activate(self);deferred.set_demand(context.demand_id,clip,-2)
		_begin_local_transfer_scope(context)
	cover.update_progress("准备目标区块素材")
	var deadline:=Time.get_ticks_msec()+180000
	while true:
		var error:=_local_transfer_error(context)
		if not error.is_empty():return await _local_transfer_failed(context,error)
		var complete:bool=_entry_dependencies_ready(_map_root,deferred,clip,destination,context.demand_id)
		if deferred!=null:deferred.set_demand(context.demand_id,clip,-2)
		if complete:
			if not context.has("core_resources_ready_us"):
				context.core_resources_ready_us=Time.get_ticks_usec()
				clip=entry_plan.safety_clip;context.clip=clip
				if deferred!=null:deferred.retry_failed(clip);deferred.set_demand(context.demand_id,clip,-2)
				cover.update_progress("准备目标区块边界依赖")
				continue
			break
		if Time.get_ticks_msec()>deadline:return await _local_transfer_failed(context,"目标区块素材准备超时；保留原位置。")
		_step_wind_preparation(_map_root)
		await get_tree().process_frame
	cover.update_progress("准备目标区块碰撞")
	if building_entry_protocol_enabled():
		var building_error:String=await _building_transfer.prepare(self,self,destination,cover,func():return context.get("cancelled",false) or request!=_transfer_request_serial)
		if not building_error.is_empty():return await _local_transfer_failed(context,building_error)
	deadline=Time.get_ticks_msec()+180000
	while true:
		var error:=_local_transfer_error(context)
		if not error.is_empty():return await _local_transfer_failed(context,error)
		Stream.sync(_map_root,self,destination,Stream.LOAD_BUDGET)
		if _transfer_residency_ready(destination):break
		if Time.get_ticks_msec()>deadline:return await _local_transfer_failed(context,"目标区块碰撞准备超时；保留原位置。")
		_step_wind_preparation(_map_root)
		await get_tree().process_frame
	var navigation:=preload("res://scripts/world3d/world_navigation.gd").new()
	navigation.covered_loading=not _navigation_async(_map_root)
	navigation.agent_height=float(_player.get_meta("standing_height",1.9))
	context.navigation=navigation;add_child(navigation)
	navigation.initial_geometry_clip=entry_plan.navigation_clip
	navigation.runtime_geometry_key=_map_root.get_meta("runtime_geometry_key","")
	_bind_deferred_geometry(_map_root,navigation)
	_bind_navigation_lifetime(navigation,_map_root)
	navigation.build(_map_root.get_meta("stream_library",[]),destination)
	deadline=Time.get_ticks_msec()+180000
	while not navigation.ready_for_queries and not _navigation_async(_map_root):
		var error:=_local_transfer_error(context)
		if error.is_empty():error=_transfer_navigation_error(navigation)
		if not error.is_empty():return await _local_transfer_failed(context,error)
		if Time.get_ticks_msec()>deadline:return await _local_transfer_failed(context,"目标附近导航准备超时；保留原位置。")
		cover.update_progress("准备目标附近通行导航",navigation._cursor,navigation._specs.size())
		Stream.sync(_map_root,self,destination,Stream.LOAD_BUDGET)
		await get_tree().process_frame
	cover.update_progress("准备目标区域材质与灯光")
	var nearby_specs:Array=[]
	for spec:Dictionary in _map_root.get_meta("stream_library",[]):
		var bounds:AABB=spec.transform*spec.mesh.get_aabb()
		if bounds.intersects(clip):nearby_specs.append(spec)
	if wind_background_enabled:
		_begin_wind_preparation(_map_root,nearby_specs)
		var wind_queue:RefCounted=_map_root.get_meta("wind_variant_preparation")
		context.wind_materials=await wind_queue.finish_covered(get_tree())
		_map_root.remove_meta("wind_variant_preparation")
	else:await preload("res://scripts/world3d/wind_material_preparer.gd").prepare(nearby_specs,get_tree())
	await _weather.streetlamps.prepare_materials(nearby_specs,get_tree())
	var batches:=_map_root.get_node_or_null("GroundRenderBatches")
	deadline=Time.get_ticks_msec()+180000
	while batches!=null and (not batches.pending.is_empty() or not batches._workers.is_empty()) and not Stream.entry_scope_ready(_map_root):
		var error:=_local_transfer_error(context)
		if not error.is_empty():return await _local_transfer_failed(context,error)
		if Time.get_ticks_msec()>deadline:return await _local_transfer_failed(context,"目标区域绘制准备超时；保留原位置。")
		cover.update_progress("准备目标区域绘制")
		await get_tree().process_frame
	# Required target geometry is already complete. Hold unrelated publications
	# through the first destination frame so they cannot restart the incremental
	# radar preparation between this readiness check and cover retirement.
	if deferred!=null:deferred._active=false;deferred.set_process(false)
	deadline=Time.get_ticks_msec()+180000
	while is_instance_valid(_hud) and is_instance_valid(_hud._radar) and not _hud._radar.region_is_prepared(Vector2(destination.x,destination.z)):
		var radar_error:=_local_transfer_error(context)
		if not radar_error.is_empty():return await _local_transfer_failed(context,radar_error)
		if Time.get_ticks_msec()>deadline:return await _local_transfer_failed(context,"目标区域地图显示准备超时；保留原位置。")
		var radar_progress:Vector2i=_hud._radar.terrain_preparation_progress()
		cover.update_progress("准备目标区域地图显示",radar_progress.x,radar_progress.y)
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var error:=_local_transfer_error(context)
	if not error.is_empty():return await _local_transfer_failed(context,error)
	if not _same_map_destination_fits(destination,navigation):return await _local_transfer_failed(context,"目标出生点不可用；保留原位置。")
	if before_commit.is_valid() and not before_commit.call():return await _local_transfer_failed(context,"操作条件已变化；保留原位置。")
	error=_local_transfer_error(context)
	if not error.is_empty():return await _local_transfer_failed(context,error)
	if building_entry_protocol_enabled():
		var current_ticket:Dictionary=_building_authority().validate(_building_transfer.issued.ticket)
		if not current_ticket.ok:return await _local_transfer_failed(context,str(current_ticket.reason))
		if not _physical_destination_fits(_map_root,get_world_3d().direct_space_state,destination,[_player.get_rid()]):return await _local_transfer_failed(context,"权威落点无有效支撑")
	# Atomic logical handoff: live map, combat, NPCs, drops, HUD and authored
	# state retain identity. Only the ready navigation and player's pose change.
	context.committed=true;cover.update_progress("进入目标区域")
	cancel_sit_preparation()
	if Net.server().sitting:apply_actions(Net.server().try_sit(false).get("actions",[]))
	furniture.cancel()
	var old_navigation:=_navigation
	_navigation=navigation;_player.navigation=navigation
	_player.global_position=destination;_player.velocity=Vector3.ZERO;_player.click_target=null;_player._route.clear()
	_player.geometry_blocked=false;_geometry_wait_locked=false
	_previous_feet=destination-Vector3.UP*.9;_combat._previous=destination
	Net.session().world3d_spawn=destination
	_player._sense_surface()
	Net.server().world3d_authority.mount(_player,navigation,_map_ref())
	_bind_manual_authority()
	for actor:Node in _combat.actors.values():
		if is_instance_valid(actor):actor.authority.mount(actor,navigation,_map_ref())
	if not old_navigation.retire_background("local_transfer_replaced"):old_navigation.free()
	await get_tree().physics_frame
	# The radar's usual 10 Hz follow tick may still point at the departure.
	# Submit the destination view before its first rendered frame under cover.
	if is_instance_valid(_hud) and is_instance_valid(_hud._radar):
		_hud._radar.center=Vector2(destination.x,destination.z);_hud._radar.queue_redraw()
	get_viewport().disable_3d=bool(original.disable_3d)
	_camera.snap_to(_player.global_position)
	if not await cover.finish(_camera.camera):return _hold_transfer_presentation(cover)
	if building_entry_protocol_enabled() and not _activate_building_transfer(cover):return false
	if activation_commit.is_valid():
		if not activation_commit.call():return _hold_building_transfer(cover,"复活条件已变化")
		original.locked=false;original.geometry_wait_locked=false
	if not await cover.reveal():return _hold_transfer_presentation(cover)
	var radar_ready:bool=not is_instance_valid(_hud) or not is_instance_valid(_hud._radar) or _hud._radar.terrain_is_prepared()
	var radar_region_ready:bool=not is_instance_valid(_hud) or not is_instance_valid(_hud._radar) or _hud._radar.region_is_prepared(Vector2(destination.x,destination.z))
	_release_local_transfer_sources(context)
	if deferred!=null:deferred.activate(self);deferred.prioritize(destination)
	cover.retire();_local_transfer={}
	_combat.set_physics_process(bool(original.combat_processing))
	_player.set_physics_process(bool(original.physics));_player.input_locked=bool(original.locked) and not bool(original.geometry_wait_locked)
	_record_transfer_presentation(cover,{"target":target,"ok":true,"same_map":true,"map_reused":true,"committed":true,"radar_ready_at_retire":radar_ready,"radar_region_ready_at_retire":radar_region_ready})
	_transfer_pending=false;_status.text="已到达目标区域。"
	navigation.covered_loading=false
	return true

func _activate_building_transfer(cover:CanvasLayer)->bool:
	if _building_transfer==null:return _hold_building_transfer(cover,"entry_ticket_unavailable")
	_building_transfer.gameplay_ready()
	var approval:Dictionary=_building_transfer.activate(DisplayServer.get_name()!="headless",_building_current_position_valid)
	if not approval.ok:return _hold_building_transfer(cover,str(approval.reason))
	_building_transfer.retain_residency()
	if _building_entry!=null:_building_entry.release()
	_building_entry=_building_transfer;_building_transfer=null
	Net.server().world3d_authority.movement_allowed=_building_movement_allowed
	set_meta("building_transfer_report",_building_entry.report())
	return true

func _hold_building_transfer(cover:CanvasLayer,reason:String)->bool:
	if _building_transfer!=null:_building_transfer.cancel(reason);_building_transfer=null
	if _building_entry!=null:_building_entry.cancel(reason)
	_player.input_locked=true;_player.set_physics_process(false)
	cover.show_failure("建筑就绪校验未通过："+reason,func():Net.session().go_character_select())
	set_meta("transfer_loading_profile",{"ok":false,"committed":true,"error":reason,"authority_blocked":true})
	return false

func _transfer_residency_ready(origin:Vector3)->bool:
	return _map_root.get_meta("stream_chunk",Vector2i(2147483647,2147483647))==Stream.chunk_key(origin) and _map_root.get_meta("stream_append_pending",[]).is_empty() and Stream.nearby_collision_ready(_map_root,origin)

func _same_map_destination_fits(destination:Vector3,navigation:Node)->bool:
	var feet:=destination-Vector3.UP*.9
	if _navigation_async(_map_root):
		if not _physical_destination_fits(_map_root,get_world_3d().direct_space_state,destination,[_player.get_rid()]):return false
	elif not navigation.near_surface(feet,.35,.4):return false
	var collider:=_player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider==null or not collider.shape is CapsuleShape3D:return false
	var capsule:=CapsuleShape3D.new()
	capsule.radius=maxf(.01,collider.shape.radius-.01)
	capsule.height=maxf(capsule.radius*2,collider.shape.height-.02)
	var pose:=_player.global_transform;pose.origin=destination
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=capsule;query.transform=pose*collider.transform;query.transform.origin.y+=.01
	query.exclude=[_player.get_rid()];query.collision_mask=_player.collision_mask;query.collide_with_areas=false
	# Keep live NPC/pet bodies in this query: their current poses, not authored
	# or saved spawn locations, decide whether the landing point is occupied.
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return false
	# Remote peer visuals currently have no PhysicsBody. Their roots are feet.
	for model:Node3D in remote_players.models.values():
		if not is_instance_valid(model) or not model.is_visible_in_tree():continue
		var peer_feet:=model.global_position
		if peer_feet.y+2.1>feet.y and feet.y+capsule.height>peer_feet.y and Vector2(peer_feet.x-feet.x,peer_feet.z-feet.z).length()<capsule.radius+.3:return false
	return true

func _physical_destination_fits(map_root:Node,space:PhysicsDirectSpaceState3D,destination:Vector3,exclude:Array[RID])->bool:
	var collider:=_player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider==null or not collider.shape is CapsuleShape3D:return false
	var capsule:CapsuleShape3D=collider.shape
	var pose:=_player.global_transform;pose.origin=destination;pose=pose*collider.transform
	var size:=Vector3(capsule.radius*2,capsule.height,capsule.radius*2)
	var clip:AABB=(pose*AABB(-size*.5,size)).grow(.4)
	var receipt:=_map_traversal_receipt(map_root,clip,"transfer_landing")
	var result:Dictionary=preload("res://scripts/world3d/physical_traversal.gd").landing(space,destination-Vector3.UP*.9,capsule,pose,_player.collision_mask,exclude,receipt)
	var deferred:Node=map_root.get_node_or_null("DeferredAssets")
	if deferred!=null:deferred.release_demand("transfer_landing")
	return result.ok

func _begin_local_transfer_scope(context:Dictionary)->void:
	var deferred:Node=context.get("deferred")
	if not is_instance_valid(deferred):return
	context.original.deferred_scope=deferred.get_demand_scope();context.scope_applied=true
	var retained:Array=[]
	if _collision_first(context.get("map")):
		# Stream pins do not own collision-only bodies. Preserve the actual old
		# movement/camera leases without reopening their visual dispatch scope.
		for id:String in ["player_collision","manual_traversal"]:
			if deferred._collision_request_ids.has(id):retained.append(id)
	context.original.collision_tickets=retained
	deferred.set_demand_scope([context.demand_id],retained)

func _restore_local_transfer_demand_scope(context:Dictionary)->void:
	var deferred:Node=context.get("deferred")
	if not is_instance_valid(deferred):return
	if context.get("scope_applied",false):
		var retained:Array=context.original.get("collision_tickets",[]).duplicate()
		retained.append(context.demand_id)
		# Keep both sides until the player takes its final location's lease.
		deferred.set_demand_scope(context.original.deferred_scope,retained)
		context.scope_applied=false
	if _collision_first(context.get("map")):deferred.allow_demand_in_scope("player_collision")

func _local_transfer_origin_ready(context:Dictionary,origin:Vector3)->bool:
	if not is_instance_valid(context.get("map")) or context.map!=_map_root:return false
	if not _transfer_residency_ready(origin):return false
	if not _collision_first(_map_root):return true
	var clip:=AABB(Vector3(origin.x-2,-100000,origin.z-2),Vector3(4,200000,4))
	# Ordinary Stream metadata does not include still-unpublished GLBs. Require
	# their exact per-instance proof AND the live ordinary-body physics watermark.
	return _map_traversal_receipt(_map_root,clip,"player_collision").ok

func _release_local_transfer_sources(context:Dictionary)->void:
	var map_root:Node=context.get("map")
	if is_instance_valid(map_root):
		Stream.release_source(map_root,context.origin_id);Stream.release_source(map_root,context.target_id)
		_restore_local_stream_scope(context)
	var deferred:Node=context.get("deferred")
	if is_instance_valid(deferred):
		_restore_local_transfer_demand_scope(context)
		if _collision_first(map_root) and is_instance_valid(_player):
			var position_:Vector3=_player.global_position
			deferred.ensure_collision(AABB(Vector3(position_.x-2,-100000,position_.z-2),Vector3(4,200000,4)),"player_collision")
			# This short-lived sweep belongs to the departure. Future movement
			# acquires a fresh sweep; the camera/player margin is already held.
			if context.get("committed",false):deferred.release_demand("manual_traversal")
		deferred.release_demand(context.demand_id)

func _restore_local_stream_scope(context:Dictionary)->void:
	if not context.get("stream_scope_applied",false):return
	context.stream_scope_applied=false
	var map_root:Node=context.get("map")
	if not is_instance_valid(map_root):return
	var previous:Variant=context.get("original",{}).get("entry_stream_clip")
	if previous is AABB:Stream.set_entry_scope(map_root,previous)
	else:Stream.clear_entry_scope(map_root)

func _local_transfer_failed(context:Dictionary,reason:String)->bool:
	_cancel_wind_preparation(context.get("map"))
	if _building_transfer!=null:_building_transfer.cancel("transfer_failed");_building_transfer=null
	var original:Dictionary=context.original
	var navigation:Node=context.get("navigation")
	if is_instance_valid(navigation) and not navigation.retire_background("transfer_cancelled"):navigation.free()
	var deferred:Node=context.get("deferred")
	if is_instance_valid(deferred):deferred.release_demand(context.demand_id)
	Stream.release_source(_map_root,context.target_id)
	_restore_local_stream_scope(context)
	if _collision_first(_map_root):
		_restore_local_transfer_demand_scope(context)
		# Cancellation can occur after publication was suspended for the first
		# target frame. Recovery must be allowed to finish missing source work.
		if is_instance_valid(deferred):deferred.activate(self)
	# The old source remained pinned throughout. Settle its plan before input
	# resumes, including after cancellation halfway through a target plan.
	var origin:Vector3=original.transform.origin
	var deadline:=Time.get_ticks_msec()+180000
	while true:
		Stream.sync(_map_root,self,origin,Stream.LOAD_BUDGET)
		if _local_transfer_origin_ready(context,origin):break
		if Time.get_ticks_msec()>deadline:
			reason+=" 原区域驻留恢复超时。"
			if _collision_first(_map_root):return _hold_local_transfer_recovery(context,reason)
			original.geometry_blocked=true;original.geometry_wait_locked=true;original.locked=true
			break
		await get_tree().process_frame
	_release_local_transfer_sources(context)
	_navigation.set_process(bool(original.navigation_processing))
	_local_transfer={}
	var result:=await _transfer_failed(original,context.cover,reason)
	var profile:Dictionary=get_meta("transfer_loading_profile",{})
	profile.merge({"same_map":true,"map_reused":true,"committed":false},true);set_meta("transfer_loading_profile",profile)
	return result

func _hold_local_transfer_recovery(context:Dictionary,reason:String)->bool:
	# A failed fallback has no safe playable location. Keep the original leases
	# and drawn cover until leaving the world rather than restoring physics.
	_player.input_locked=true;_player.set_physics_process(false);_player.velocity=Vector3.ZERO
	context.recovery_failed=true
	context.cover.show_failure(reason,func():Net.session().go_character_select())
	set_meta("transfer_loading_profile",{"same_map":true,"ok":false,"committed":false,"recovery_failed":true,"error":reason})
	return false

func _transfer_navigation_error(navigation:Node)->String:
	if not navigation.geometry_error.is_empty():return "目标导航准备失败："+navigation.geometry_error
	var error:String=str(navigation.loading_profile.get("error",""))
	if not error.is_empty():return "目标导航准备失败："+error
	if navigation.region.is_valid() and navigation._bake_pending.is_empty() and navigation.mesh.get_polygon_count()==0:return "目标附近没有可用通行表面；保留当前地图。"
	return ""

func _transfer_failed(original:Dictionary,cover:CanvasLayer,reason:String,navigation:Node=null,viewport:Node=null)->bool:
	if _building_transfer!=null:_building_transfer.cancel("transfer_failed");_building_transfer=null
	if original.has("entry_policy"):_entry_policy=original.entry_policy
	if is_instance_valid(navigation) and not navigation.retire_background("transfer_failed"):navigation.free()
	if is_instance_valid(viewport):viewport.queue_free()
	get_viewport().disable_3d=bool(original.disable_3d)
	_player.global_transform=original.transform;_player.velocity=Vector3.ZERO
	if building_entry_protocol_enabled():
		# Target failure never licenses blindly restoring an old transform.
		await get_tree().physics_frame
		await get_tree().process_frame
		if not _building_recovery_valid(original):return _hold_building_transfer(cover,reason+"；原位置已无法安全恢复")
		_player.global_transform=original.transform;_player.velocity=Vector3.ZERO
	_camera.snap_to(_player.global_position)
	if not await cover.finish(_camera.camera):return _hold_transfer_presentation(cover)
	if building_entry_protocol_enabled():
		var approval:Dictionary=_building_entry.activate(DisplayServer.get_name()!="headless",_building_current_position_valid)
		if not approval.ok:return _hold_building_transfer(cover,reason+"；"+str(approval.reason))
		Net.server().world3d_authority.movement_allowed=_building_movement_allowed
	if not await cover.reveal():return _hold_transfer_presentation(cover)
	_combat.set_physics_process(bool(original.combat_processing))
	_player.global_transform=original.transform;_player.velocity=original.velocity
	_player.geometry_blocked=original.geometry_blocked;_geometry_wait_locked=original.geometry_wait_locked
	_player.set_physics_process(bool(original.physics));_player.input_locked=original.locked
	if original.has("navigation_processing"):_navigation.set_process(bool(original.navigation_processing))
	if is_instance_valid(original.get("deferred")):
		if original.has("deferred_active"):original.deferred._active=bool(original.deferred_active)
		original.deferred.set_process(bool(original.deferred_processing))
	_transfer_pending=false;_status.text=reason
	if is_instance_valid(cover):
		_record_transfer_presentation(cover,{"ok":false,"error":reason,"committed":false})
		cover.retire()
	return false


func request_pet_summon(id: String = "default") -> void:
	if Net.is_real_server():apply_actions(Net.server()._unsupported("pet_summon").actions);return
	_combat.summons.pet_summon(id)

func request_pet_dismiss() -> void:
	if Net.is_real_server():apply_actions(Net.server()._unsupported("pet_dismiss").actions);return
	_combat.summons.pet_dismiss()

func _update_approach_preparation()->void:
	if not is_instance_valid(_map_root) or not is_instance_valid(_player):return
	if is_instance_valid(_camera):preload("res://scripts/world3d/terrain_render_lod.gd").update(_map_root,_camera.camera.global_position)
	if _map_root.get_node_or_null("DistantBuildingProxy")==null:
		var adopted:bool=int(_map_root.get_meta("stream_children",-1))==_map_root.get_child_count()
		var proxy:=preload("res://scripts/world3d/distant_building_proxy.gd").new();proxy.name="DistantBuildingProxy";_map_root.add_child(proxy)
		if adopted:_map_root.set_meta("stream_children",_map_root.get_child_count())
	var deferred:Node=_map_root.get_node_or_null("DeferredAssets")
	_approach_preparation.update(deferred,_player.global_position,_player.velocity)
	preload("res://scripts/world3d/surface_materials.gd").trim_cached_resources()
	if not CrossMapPrefetch.enabled:return
	if not is_instance_valid(_cross_map_prefetch):
		_cross_map_prefetch=CrossMapPrefetch.new();_cross_map_prefetch.name="CrossMapPrefetch";add_child(_cross_map_prefetch)
	if not is_instance_valid(_target_scene_prefetch):
		_target_scene_prefetch=preload("res://scripts/world3d/target_scene_prefetch.gd").new();_target_scene_prefetch.name="TargetScenePrefetch";add_child(_target_scene_prefetch)
	var chosen:="";var destination:=Vector3.ZERO;var distance:=24.
	for body:Node in _warp_candidates:
		if not is_instance_valid(body):continue
		var centre:Vector3=body.get_meta("center",Vector3.INF);var d:=_player.global_position.distance_to(centre)
		var target:String=_approach_map_target(body.get_meta("target_path",""));var spawn:Variant=body.get_meta("spawn",[])
		if d>=distance or target.is_empty() or not spawn is Array or spawn.size()!=3:continue
		chosen=target;destination=Vector3(spawn[0],spawn[1],spawn[2]);distance=d
	for spec:Dictionary in Net.server().world3d_events.targets.values():
		var template:Dictionary=spec.get("template",{})
		if template.get("template","")!="transfer":continue
		var d:float=_player.global_position.distance_to(spec.position);var params:Dictionary=template.parameters
		var target:String=_approach_map_target(params.map_path)
		if d>=distance or target.is_empty():continue
		chosen=target;destination=Vector3(params.spawn[0],params.spawn[1]+.9,params.spawn[2]);distance=d
	if chosen.is_empty():_cross_map_prefetch.cancel();_target_scene_prefetch.cancel();return
	var ledger:RefCounted=deferred._admission if deferred!=null else _prefetch_fallback_ledger
	if deferred==null:ledger.byte_limit=preload("res://scripts/world3d/target_scene_prefetch.gd").LEASE_BYTES+CrossMapPrefetch.LEASE_BYTES
	if not _target_scene_prefetch.matches(chosen,destination):_cross_map_prefetch.request(chosen,destination,ledger)
	_target_scene_prefetch.request(chosen,destination,ledger,_cross_map_prefetch)

func _approach_map_target(target:String)->String:
	if target.is_empty():return ""
	if is_instance_valid(Net.session().editor_playtest):target=Net.session().editor_playtest.resolve_map(target)
	return "" if _same_map_target(target) else target

func _recover_streamed_wind()->void:
	# Shader reflection still serializes on the renderer. Unknown variants get
	# an explicit automatic cover; cache-only receiver work remains background.
	if not _ready_for_play or _transfer_pending or not is_instance_valid(_weather) or not is_instance_valid(_player):
		_wind_recovery_pending=false;return
	var runtime:Node3D=_weather.wind_objects
	if runtime.pending_specs().is_empty():_wind_recovery_pending=false;return
	var original_map:=_map_root;var viewport:=get_viewport()
	var original:Dictionary={"locked":_player.input_locked,"physics":_player.is_physics_processing(),"combat":_combat.is_physics_processing(),"disable_3d":viewport.disable_3d}
	_transfer_pending=true;_transfer_viewport_restore=original.disable_3d
	_player.input_locked=true;_player.set_physics_process(false);_player.velocity=Vector3.ZERO;_combat.set_physics_process(false)
	var cover:=preload("res://scripts/world3d/transfer_loading.gd").new()
	cover.title_text="正在准备附近风动材质";cover.ready_text="风动材质已准备好"
	add_child(cover);cover.update_progress("准备风动材质")
	var covered:bool=await cover.wait_until_drawn()
	if not is_instance_valid(self) or not is_inside_tree():return
	var result:Dictionary={"ok":false,"reason":"cover_unavailable"}
	if covered and is_instance_valid(runtime) and _map_root==original_map:
		viewport.disable_3d=true
		result=await runtime.prepare_pending_covered(cover)
	if not is_instance_valid(self) or not is_inside_tree():return
	viewport.disable_3d=original.disable_3d
	if result.ok and is_instance_valid(cover) and await cover.finish(_camera.camera):await cover.reveal()
	if not is_instance_valid(self) or not is_inside_tree():return
	if is_instance_valid(cover):
		set_meta("wind_recovery_profile",cover.profile().merged(result));cover.retire()
	_player.set_physics_process(original.physics);_player.input_locked=original.locked;_combat.set_physics_process(original.combat)
	_transfer_pending=false;_transfer_viewport_restore=null;_wind_recovery_pending=false
	_preparation_sample_at=0
