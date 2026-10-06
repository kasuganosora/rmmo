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
var pivot_height := .65
var actor_height:=1.9
var indoor_distance:=3.2
var cutaway=preload("res://scripts/world3d/building_cutaway.gd").new()
var _focus:=Vector3.ZERO
var _initialized:=false
var _arm_length:=0.0
var last_focus:=Vector3.ZERO
var last_desired:=Vector3.ZERO
var view_mode:="third_person"
var captured := false
var occluder_exclude: Array[RID] = []

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_want_distance = distance


func _unhandled_input(event: InputEvent) -> void:
	if view_mode!="third_person":return
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
	if view_mode!="third_person":
		cutaway.restore();_initialized=false;return
	var feet:=pivot-Vector3.UP*.9
	var room:Dictionary=cutaway.locate(feet)
	var target_distance:=minf(_want_distance,indoor_distance) if not room.is_empty() else _want_distance
	distance = lerpf(distance, target_distance, 1.0 - exp(-8.0 * delta))
	var arm := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * minf(distance,target_distance)
	pivot_height=clampf(actor_height*.84,1.4,1.7)-.9
	var focus := pivot + Vector3(0.0, pivot_height, 0.0)
	if not _initialized or _focus.distance_to(focus)>4:
		_focus=focus;_arm_length=distance;_initialized=true
	else:
		_focus.x=focus.x;_focus.z=focus.z
		_focus.y=lerpf(_focus.y,focus.y,1-exp(-12*delta))
	focus=_focus
	var wanted := focus + arm
	last_focus=focus;last_desired=wanted
	var probe:=focus+arm.normalized()*minf(arm.length(),_arm_length)
	cutaway.update(room,focus,probe,get_world_3d().direct_space_state,occluder_exclude,delta)
	wanted = _shorten(focus, wanted)
	var safe_length:=focus.distance_to(wanted)
	_arm_length=safe_length if safe_length<_arm_length else lerpf(_arm_length,safe_length,1-exp(-6*delta))
	global_position = focus+arm.normalized()*maxf(.05,_arm_length)
	# Validate the actual shortened camera segment; a distant ideal orbit is not visibility.
	cutaway.update(room,focus,global_position,get_world_3d().direct_space_state,occluder_exclude,delta)
	camera.look_at(focus, Vector3.UP)

func bind_map(map_root:Node,settings:Dictionary)->void:
	cutaway.bind(map_root)
	configure_environment(settings)
	_initialized=false

func configure_environment(settings:Dictionary)->void:
	# Time/weather changes do not change building topology or camera focus.
	var enabled:=bool(settings.get("interior_cutaway",false))
	if cutaway.enabled and not enabled:cutaway.restore()
	cutaway.enabled=enabled
	indoor_distance=float(settings.get("indoor_camera_distance",3.2))

func visual_exclusions()->Array[RID]:
	var result:Array[RID]=occluder_exclude.duplicate()
	result.append_array(cutaway.excluded)
	return result

func set_view_mode(mode:String)->bool:
	if mode not in ["third_person","first_person","vr"]:return false
	view_mode=mode;_initialized=false
	if mode!="third_person":
		cutaway.restore()
		if captured:release_capture()
	return true

func _exit_tree()->void:cutaway.restore()


func exclude_body(rid: RID) -> void:
	occluder_exclude = [rid]


func release_capture() -> void:
	captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _shorten(focus: Vector3, wanted: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return wanted
	var query:=PhysicsShapeQueryParameters3D.new()
	var sphere:=SphereShape3D.new();sphere.radius=.2
	query.shape=sphere;query.transform=Transform3D(Basis.IDENTITY,focus)
	query.motion=wanted-focus;query.margin=.015
	query.collide_with_areas=false;query.exclude=visual_exclusions()
	var fractions:=space.cast_motion(query)
	var length:=query.motion.length()
	var safe:=maxf(.05,length*fractions[0]-.03) if fractions[0]<1 else length
	return focus+query.motion.normalized()*safe
