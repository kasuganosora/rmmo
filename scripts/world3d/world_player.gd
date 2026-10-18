extends CharacterBody3D
## Local authority for the 3D profile. Feet stay on decimal meters; yaw follows travel, not the camera.

const Motion = preload("res://scripts/world3d/world_motion.gd")
const WorldLocation = preload("res://scripts/world3d/world_location.gd")
## Two millimetres tolerate float32 positions and physical contact recovery at
## town-scale coordinates, without skipping centimetres around a corner.
const WAYPOINT_REACHED_M:=0.002

var map_ref := "p1/yard"
var surface_id := "ground"
var input_locked := true
## Unlike UI input locks, unfinished geometry must also suspend gravity.
var geometry_blocked := false
## Optional world-owned guard also covers passive gravity while UI/combat locks
## input; otherwise that branch would bypass the authority's movement sweep.
var passive_traversal_guard:Callable
var _setting_click_target:=false
var click_target: Variant = null:
	set(value):
		click_target=value
		# Existing combat, transfer and rest callers cancel by assigning null.
		# Cancel deferred clicks too, so a later bake cannot restart movement.
		if value==null:
			if not _setting_click_target:_cancel_navigation_request()
			_pending_click=null
var click_surface := ""
var character: Dictionary = {}
var equipment_parts: Dictionary = {}
var navigation: Node
var _route := PackedVector3Array()
var _pending_click:Variant=null
var _pending_version:=-1
var _pending_navigation_id:=0
var _route_navigation_id:=0
var _route_version:=-1
var _route_goal:Variant=null
var path_status:Dictionary={"ok":false,"reason":"idle"}
var _sequence := 0
var _jump_was_pressed:=false
signal movement_intent
const Net = preload("res://scripts/net/net.gd")
const REST_ACTIONS:=["sit_ground","sit_down_ground","stand_up_ground","sit_chair","sit_chair_hold","stand_up_chair","lie_down","lie","get_up"]

@export var camera_path: NodePath
@onready var _model: Node3D = $CharacterModel3D


func _ready() -> void:
	floor_snap_length = 0.2
	# The shared model is configured from the selected character before entering the tree.


func _physics_process(delta: float) -> void:
	if geometry_blocked:
		velocity=Vector3.ZERO
		return
	if input_locked:
		if passive_traversal_guard.is_valid():
			var bounds:=preload("res://scripts/world3d/physical_traversal.gd").motion_bounds(self,Vector3.ZERO,delta,false)
			var ready:=preload("res://scripts/world3d/physical_traversal.gd").readiness(passive_traversal_guard.call(bounds),Engine.get_physics_frames())
			if not ready.ok:velocity=Vector3.ZERO;return
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= 9.8 * delta
		move_and_slide()
		return
	# move_and_slide uses the engine physics delta; calling it several times
	# with a separate accumulator multiplies displacement at low tick rates.
	_step(delta)


func streaming_intent(allow_geometry_wait:bool=false)->Dictionary:
	var result:={"velocity":Vector3.ZERO,"route":PackedVector3Array()}
	# Keep desired movement when the geometry guard zeroed actual velocity.
	if input_locked and not allow_geometry_wait:return result
	if is_instance_valid(_model) and _model.action in REST_ACTIONS:return result
	var multiplier:=clampf(float(Net.server().player_move_speed_mul()),0.,3.)
	var stick:=_stick()
	if stick.length_squared()>.01:
		result.velocity=Motion.wish_direction(_camera_yaw(),stick)*(Motion.RUN_MPS if Input.is_key_pressed(KEY_SHIFT) else Motion.WALK_MPS)*multiplier
	elif click_target is Vector3 and click_target.is_finite():
		if _route_navigation_id!=0 and (not is_instance_valid(navigation) or navigation.get_instance_id()!=_route_navigation_id or navigation.version!=_route_version or not navigation.ready_for_queries):return result
		result.route.append(click_target)
		# Copy only the bounded prefix, without advancing movement or querying nav.
		for i:int in mini(_route.size(),preload("res://scripts/world3d/approach_preparation.gd").MAX_ROUTE_POINTS-1):result.route.append(_route[i])
		var direction:Vector3=click_target-global_position;direction.y=0
		if direction.length_squared()<.000001:
			for point:Vector3 in result.route:
				direction=point-global_position;direction.y=0
				if direction.length_squared()>=.000001:break
		result.velocity=direction.normalized()*Motion.RUN_MPS*multiplier
	return result


func _step(dt: float) -> void:
	var profiling:=has_meta("profile_frame")
	var profile_started:=Time.get_ticks_usec() if profiling else 0
	var yaw := _camera_yaw()
	var stick := _stick()
	if stick.length_squared()>.01:_cancel_navigation_request();_pending_click=null
	else:_refresh_navigation_request()
	var focus:=get_viewport().gui_get_focus_owner()
	var jump_pressed:=Input.is_key_pressed(KEY_SPACE) and not (focus is LineEdit or focus is TextEdit)
	var jump:=jump_pressed and not _jump_was_pressed
	_jump_was_pressed=jump_pressed
	if stick.length_squared()>.01 or click_target is Vector3:movement_intent.emit()
	if _model.action in REST_ACTIONS:
		if stick.length_squared()>.01 or click_target is Vector3:
			if _model.action in ["sit_down_ground","sit_ground"]:_begin_ground_exit()
			elif _model.action in ["sit_chair","sit_chair_hold"]:_model.play("stand_up_chair","front",true)
			elif _model.action in ["lie_down","lie"]:_model.play("get_up","front",true)
		velocity.x=0;velocity.z=0
		return
	var wish := Vector3.ZERO
	var speed := Motion.WALK_MPS
	if stick.length_squared() > 0.01:
		click_target = null
		_route.clear()
		wish = Motion.wish_direction(yaw, stick)
		if Input.is_key_pressed(KEY_SHIFT):
			speed = Motion.RUN_MPS
	elif click_target is Vector3:
		var multiplier := clampf(float(Net.server().player_move_speed_mul()), 0.0, 3.0)
		# Consume only points already reached by the actual body. An authority
		# rejection or a blocked/partial slide cannot advance the route cursor.
		while click_target is Vector3:
			var target: Vector3 = click_target
			var flat := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
			var length := flat.length()
			if length > WAYPOINT_REACHED_M:
				# One intent follows one straight path segment. Carrying unused
				# distance around the next corner would cut across that corner.
				var distance:=minf(length,Motion.RUN_MPS*multiplier*dt)
				wish=flat.normalized()*distance/maxf(dt*multiplier,0.00001)
				break
			click_target = _route[0] if not _route.is_empty() else null
			if not _route.is_empty():
				_route.remove_at(0)
		speed = 1.0
	var before := global_position
	_sequence += 1
	var desired_speed := wish.length() * speed
	var move_started:=Time.get_ticks_usec() if profiling else 0
	var moved:Dictionary=Net.server().try_move_world(_sequence, wish.normalized(), desired_speed,jump)
	var move_ended:=Time.get_ticks_usec() if profiling else 0
	# Accepted authority movement already senses the surface at the final pose
	# before publishing. Rejected intents still refresh the local surface, as
	# the former pre-move ray did, without doubling successful physics queries.
	if not moved.get("ok",false):_sense_surface()
	var sense_ended:=Time.get_ticks_usec() if profiling else 0
	var actual_speed := Vector2(global_position.x - before.x, global_position.z - before.z).length() / maxf(dt, 0.0001)
	if Vector2(velocity.x, velocity.z).length() > 0.2:
		var facing := atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, facing, 1.0 - exp(-10.0 * dt))
	_model.play("walk" if actual_speed > 0.2 else "idle", "front")
	_model.locomotion_rate = actual_speed / Motion.WALK_MPS
	if profiling:
		var ended:=Time.get_ticks_usec()
		var move_us:=move_ended-move_started;var sense_us:=sense_ended-move_ended;var visual_us:=ended-sense_ended
		set_meta("physics_timing",{"frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"move_ms":move_us/1000.,"sense_ms":sense_us/1000.,"visual_ms":visual_us/1000.,"ms":(ended-profile_started)/1000.})
		# Totals distinguish per-tick work from multiple fixed-step catch-up ticks
		# inside one rendered frame. This diagnostic never changes simulation rate.
		var totals:Dictionary=get_meta("physics_profile",{"ticks":0,"move_us":0,"sense_us":0,"visual_us":0,"total_us":0,"max_us":0})
		totals.ticks+=1;totals.move_us+=move_us;totals.sense_us+=sense_us;totals.visual_us+=visual_us
		totals.total_us+=ended-profile_started;totals.max_us=maxi(totals.max_us,ended-profile_started)
		set_meta("physics_profile",totals)

func request_rest(action:String)->bool:
	if input_locked or not Net.server().combat_stats.player_alive():return false
	if action not in REST_ACTIONS or _model.axis_rig==null or not _model.axis_rig.supports(action):return false
	click_target=null;_pending_click=null;_route.clear();velocity.x=0;velocity.z=0
	if action=="stand_up_ground":_begin_ground_exit()
	else:_model.play(action,"front",true)
	return true

func _begin_ground_exit()->void:
	# The prepared lowering is the exact reverse of rising. Resume at the
	# matching phase on interruption instead of restarting from fully seated.
	var reverse_time:float=_model.action_duration()-_model.elapsed if _model.action=="sit_down_ground" else -1.0
	_model.play("stand_up_ground","front",true)
	if reverse_time>=0:_model.elapsed=clampf(reverse_time,0,_model.action_duration())


func location() -> RefCounted:
	return WorldLocation.make(map_ref, global_position + Vector3(0, -0.9, 0), surface_id)

func _refresh_navigation_request()->void:
	if _pending_click is Vector3:
		if not is_instance_valid(navigation) or navigation.get_instance_id()!=_pending_navigation_id:
			click_target=null;path_status={"ok":false,"reason":"navigation_replaced"}
		elif navigation.version!=_pending_version or navigation.capability_status().state not in ["pending","ready"] or not str(navigation.capability_status().get("geometry_error","")).is_empty() or not str(navigation.capability_status().get("foreground_terminal_reason","")).is_empty():
			set_click_target(_pending_click,click_surface,false)
	if click_target is Vector3 and _route_navigation_id!=0:
		if not is_instance_valid(navigation) or navigation.get_instance_id()!=_route_navigation_id:
			click_target=null;_route.clear();path_status={"ok":false,"reason":"navigation_replaced"}
		elif navigation.version!=_route_version or not navigation.ready_for_queries:
			set_click_target(_route_goal,click_surface,false)


func set_click_target(point: Vector3, target_surface: String,user_request:bool=true) -> Dictionary:
	_setting_click_target=true
	var result:=_set_click_target(point,target_surface,user_request)
	_setting_click_target=false
	return result

func _cancel_navigation_request()->void:
	var expected:Variant=_pending_click if _pending_click is Vector3 else _route_goal
	if expected is Vector3 and is_instance_valid(navigation) and navigation.has_method("cancel_foreground_request"):
		navigation.cancel_foreground_request(expected)

func _set_click_target(point: Vector3, target_surface: String,user_request:bool=true) -> Dictionary:
	_pending_click=null
	click_surface=target_surface
	_route.clear()
	# A solid building component can still have a walkable top (stairs,
	# landings and imported floors). Navigation decides reachability.
	if not is_instance_valid(navigation):
		click_target = null
		path_status={"ok":false,"reason":"navigation_pending"};return path_status
	var start:=global_position-Vector3(0,.9,0)
	var result:Dictionary=navigation.find_foreground_path(start,point,.65,user_request) if navigation.has_method("find_foreground_path") else navigation.find_path(start,point,.65)
	path_status=result.duplicate()
	if not bool(result.get("ok", false)):
		click_target = null
		if result.get("reason")=="pending":
			_pending_click=point;_pending_version=navigation.version;_pending_navigation_id=navigation.get_instance_id()
		elif navigation.has_method("cancel_foreground_request"):
			navigation.cancel_foreground_request(point)
		return path_status
	_route_goal=point;_route_version=navigation.version;_route_navigation_id=navigation.get_instance_id()
	_route = result["path"]
	if not _route.is_empty():
		_route.remove_at(0)
	click_target = _route[0] if not _route.is_empty() else null
	if not _route.is_empty():
		_route.remove_at(0)
	click_surface = target_surface
	if click_target==null and navigation.has_method("cancel_foreground_request"):navigation.cancel_foreground_request(point)
	return path_status


func _sense_surface() -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(0, -2.2, 0))
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var body: Object = hit.collider
	if body is CollisionObject3D and (body as CollisionObject3D).has_meta("surface_id"):
		var uuid:=preload("res://scripts/world3d/fortification_collision_batcher.gd").hit_uuid(hit)
		surface_id = uuid if not uuid.is_empty() else str(body.get_meta("surface_id"))


func _stick() -> Vector2:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return Vector2.ZERO
	var x := 0.0
	var y := 0.0
	if Input.is_key_pressed(KEY_D):
		x += 1.0
	if Input.is_key_pressed(KEY_A):
		x -= 1.0
	if Input.is_key_pressed(KEY_W):
		y += 1.0
	if Input.is_key_pressed(KEY_S):
		y -= 1.0
	return Vector2(x, y)


func _camera_yaw() -> float:
	var cam := get_node_or_null(camera_path)
	if cam == null:
		return 0.0
	return float(cam.yaw)
