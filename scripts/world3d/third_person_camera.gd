extends Node3D
## Orbit follow camera. Yaw 0 looks north (-Z). Right mouse orbits, wheel changes distance.

const MIN_DISTANCE := 2.0
const MAX_DISTANCE := 12.0
const MIN_PITCH := deg_to_rad(-10.0)
const MAX_PITCH := deg_to_rad(55.0)
const LOOK_SENS := 0.005

var yaw := 0.0
var pitch := deg_to_rad(18.0)
var distance := 6.0
var _want_distance := 6.0
var pivot_height := 1.2
var captured := false
var occluder_exclude: Array[RID] = []

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_want_distance = distance


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			captured = button.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_want_distance = maxf(MIN_DISTANCE, _want_distance - 0.6)
			get_viewport().set_input_as_handled()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_want_distance = minf(MAX_DISTANCE, _want_distance + 0.6)
			get_viewport().set_input_as_handled()
	elif captured and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * LOOK_SENS
		pitch = clampf(pitch - motion.relative.y * LOOK_SENS, MIN_PITCH, MAX_PITCH)
		get_viewport().set_input_as_handled()


func follow(pivot: Vector3, delta: float) -> void:
	distance = lerpf(distance, _want_distance, 1.0 - exp(-8.0 * delta))
	var arm := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var focus := pivot + Vector3(0.0, pivot_height, 0.0)
	var wanted := focus + arm
	wanted = _shorten(focus, wanted)
	global_position = wanted
	camera.look_at(focus, Vector3.UP)


func exclude_body(rid: RID) -> void:
	occluder_exclude = [rid]


func release_capture() -> void:
	captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _shorten(focus: Vector3, wanted: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return wanted
	var query := PhysicsRayQueryParameters3D.create(focus, wanted)
	query.collide_with_areas = false
	query.exclude = occluder_exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return wanted
	var normal: Vector3 = hit.normal
	return (hit.position as Vector3) + normal * 0.2
