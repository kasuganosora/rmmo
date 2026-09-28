extends CharacterBody3D
## Local authority for the 3D profile. Feet stay on decimal meters; yaw follows travel, not the camera.

const Motion = preload("res://scripts/world3d/world_motion.gd")
const WorldLocation = preload("res://scripts/world3d/world_location.gd")

var map_ref := "p1/yard"
var surface_id := "ground"
var input_locked := true
var click_target: Variant = null
var click_surface := ""
var character: Dictionary = {}
var equipment_parts: Dictionary = {}
var navigation: Node
var _route := PackedVector3Array()
var _sequence := 0
signal movement_intent
const Net = preload("res://scripts/net/net.gd")
const REST_ACTIONS:=["sit_ground","sit_down_ground","stand_up_ground","sit_chair","sit_chair_hold","stand_up_chair","lie_down","lie","get_up"]

@export var camera_path: NodePath
@onready var _model: Node3D = $CharacterModel3D


func _ready() -> void:
	floor_snap_length = 0.2
	# The shared model is configured from the selected character before entering the tree.


func _physics_process(delta: float) -> void:
	if input_locked:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= 9.8 * delta
		move_and_slide()
		return
	# move_and_slide uses the engine physics delta; calling it several times
	# with a separate accumulator multiplies displacement at low tick rates.
	_step(delta)


func _step(dt: float) -> void:
	var yaw := _camera_yaw()
	var stick := _stick()
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
	_sense_surface()
	if stick.length_squared() > 0.01:
		click_target = null
		_route.clear()
		wish = Motion.wish_direction(yaw, stick)
		if Input.is_key_pressed(KEY_SHIFT):
			speed = Motion.RUN_MPS
	elif click_target is Vector3:
		var cursor := global_position
		var multiplier := clampf(float(Net.server().player_move_speed_mul()), 0.0, 3.0)
		var remaining := Motion.RUN_MPS * multiplier * dt
		while click_target is Vector3 and remaining > 0.00001:
			var target: Vector3 = click_target
			var flat := Vector3(target.x - cursor.x, 0, target.z - cursor.z)
			var length := flat.length()
			if length > remaining:
				cursor += flat.normalized() * remaining
				remaining = 0.0
			else:
				cursor += flat
				remaining -= length
				click_target = _route[0] if not _route.is_empty() else null
				if not _route.is_empty():
					_route.remove_at(0)
		wish = (cursor - global_position) / maxf(dt * multiplier, 0.00001)
		speed = 1.0
	var before := global_position
	_sequence += 1
	var desired_speed := wish.length() * speed
	Net.server().try_move_world(_sequence, wish.normalized(), desired_speed)
	var actual_speed := Vector2(global_position.x - before.x, global_position.z - before.z).length() / maxf(dt, 0.0001)
	if Vector2(velocity.x, velocity.z).length() > 0.2:
		var facing := atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, facing, 1.0 - exp(-10.0 * dt))
	_model.play("walk" if actual_speed > 0.2 else "idle", "front")
	_model.locomotion_rate = actual_speed / Motion.WALK_MPS

func request_rest(action:String)->bool:
	if input_locked or not Net.server().combat_stats.player_alive():return false
	if action not in REST_ACTIONS or _model.axis_rig==null or not _model.axis_rig.supports(action):return false
	click_target=null;_route.clear();velocity.x=0;velocity.z=0
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


func set_click_target(point: Vector3, target_surface: String) -> void:
	_route.clear()
	if target_surface == "block" or navigation == null:
		click_target = null
		return
	var result: Dictionary = navigation.find_path(global_position - Vector3(0, 0.9, 0), point)
	if not bool(result.get("ok", false)):
		click_target = null
		return
	_route = result["path"]
	if not _route.is_empty():
		_route.remove_at(0)
	click_target = _route[0] if not _route.is_empty() else null
	if not _route.is_empty():
		_route.remove_at(0)
	click_surface = target_surface


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
		surface_id = str((body as CollisionObject3D).get_meta("uuid", body.get_meta("surface_id")))


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
