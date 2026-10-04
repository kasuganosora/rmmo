extends RefCounted
## In-process authority. Accepts direction intents, never a client-authored position.
const Location = preload("res://scripts/world3d/world_location.gd")
const Motion = preload("res://scripts/world3d/world_motion.gd")
var _body: WeakRef
var _navigation: WeakRef
var _sequence := -1
var _map_ref := ""
var _last_tick := -1
var snapshot: Dictionary = {}
var movement_allowed: Callable = Callable()
var speed_multiplier: Callable = Callable()


func release() -> void:
	_body = null
	_navigation = null
	snapshot.clear()
	movement_allowed = Callable()
	speed_multiplier = Callable()


func mount(body: CharacterBody3D, navigation: Node, map_ref: String) -> void:
	_body = weakref(body)
	_navigation = weakref(navigation)
	_map_ref = map_ref
	_sequence = -1
	_last_tick = -1
	_publish(body)


func move_intent(sequence: int, direction: Vector3, speed: float, jump:bool=false) -> Dictionary:
	var body = _body.get_ref() if _body != null else null
	var navigation = _navigation.get_ref() if _navigation != null else null
	if body == null or navigation == null or not navigation.ready_for_queries:
		return {"ok": false, "reason": "not_ready"}
	if movement_allowed.is_valid() and not movement_allowed.call():
		return {"ok": false, "reason": "movement_locked"}
	if sequence <= _sequence or not direction.is_finite() or not is_finite(speed):
		return {"ok": false, "reason": "invalid_intent"}
	if _last_tick == Engine.get_physics_frames():
		return {"ok": false, "reason": "duplicate_tick"}
	_last_tick = Engine.get_physics_frames()
	_sequence = sequence
	var dt: float = body.get_physics_process_delta_time()
	var multiplier := clampf(float(speed_multiplier.call()), 0.0, 3.0) if speed_multiplier.is_valid() else 1.0
	var wish := Vector3(direction.x, 0, direction.z).limit_length(1.0) * clampf(speed, 0, Motion.RUN_MPS) * multiplier
	var feet: Vector3 = body.global_position - Vector3(0, 0.9, 0)
	# Walking off an internal ledge is valid even though there is no navigation
	# polygon at the character's current height. Check the landing below instead.
	# Looking beyond the leading hemisphere also crosses the navmesh's eroded rim.
	if wish.length_squared()>0:
		var next:=feet+wish*dt
		var landing:=_landing_below(body,next+wish.normalized()*.32)
		if landing.is_empty():
			wish=Vector3.ZERO # No supporting map surface below: retain edge protection.
		elif not navigation.near_surface(next,.35,.65) and not navigation.near_surface(landing.position,.55,.65):
			wish=Vector3.ZERO
	if jump and body.is_on_floor():body.velocity.y=4.8
	if body.velocity.y<=0 and wish.length_squared() > 0.0 and body.test_move(body.global_transform, wish * dt):
		_step_up(body, feet, wish, dt)
		feet = body.global_position - Vector3(0, 0.9, 0)
	body.velocity.x = wish.x
	body.velocity.z = wish.z
	body.velocity.y -= 9.8 * dt
	body.move_and_slide()
	body._sense_surface()
	_publish(body)
	return {"ok": true, "sequence": sequence, "location": snapshot.duplicate(true)}


func _landing_below(body:CharacterBody3D,point:Vector3)->Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.4,point-Vector3.UP*4096)
	query.exclude=[body.get_rid()];query.collide_with_areas=false
	var hit:=body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).y<cos(deg_to_rad(40.0)):return {}
	return hit


func _publish(body: CharacterBody3D) -> void:
	snapshot = Location.make(_map_ref, body.global_position - Vector3(0, 0.9, 0), body.surface_id).to_dictionary()


func _step_up(body: CharacterBody3D, feet: Vector3, wish: Vector3, dt: float) -> void:
	var support := PhysicsRayQueryParameters3D.create(feet + Vector3(0, 0.05, 0), feet - Vector3(0, 0.4, 0))
	support.exclude = [body.get_rid()]
	if body.get_world_3d().direct_space_state.intersect_ray(support).is_empty():
		return
	var ahead := feet + wish.normalized() * (0.32 + wish.length() * dt)
	var query := PhysicsRayQueryParameters3D.create(ahead + Vector3(0, 0.4, 0), ahead - Vector3(0, 0.02, 0))
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < cos(deg_to_rad(40.0)):
		return
	var rise := float(hit["position"].y) - feet.y + 0.005
	if rise <= 0.01 or rise > 0.4:
		return
	var up := Vector3(0, rise, 0)
	if body.test_move(body.global_transform, up):
		return
	var raised := body.global_transform
	raised.origin += up
	if body.test_move(raised, wish * dt):
		return
	body.global_transform = raised
