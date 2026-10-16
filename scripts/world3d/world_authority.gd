extends RefCounted
## In-process authority. Accepts direction intents, never a client-authored position.
const Location = preload("res://scripts/world3d/world_location.gd")
const Motion = preload("res://scripts/world3d/world_motion.gd")
const Traversal=preload("res://scripts/world3d/physical_traversal.gd")
var _body: WeakRef
var _navigation: WeakRef
var _sequence := -1
var _map_ref := ""
var _last_tick := -1
var snapshot: Dictionary = {}
var movement_allowed: Callable = Callable()
var speed_multiplier: Callable = Callable()
## World-owned map/epoch/residency proof for a swept physical footprint. When
## configured this applies before AND after navigation becomes ready.
var traversal_guard:Callable=Callable()
## Reuse the already-required forward test's result; flat walking performs no
## additional collision query or per-tick KinematicCollision allocation.
var _step_contact:=KinematicCollision3D.new()
var _descent=preload("res://scripts/world3d/step_descent.gd").new()


func release() -> void:
	_descent.clear()
	_body = null
	_navigation = null
	snapshot.clear()
	movement_allowed = Callable()
	speed_multiplier = Callable()
	traversal_guard=Callable()


func mount(body: CharacterBody3D, navigation: Node, map_ref: String) -> void:
	_descent.clear()
	_body = weakref(body)
	_navigation = weakref(navigation) if is_instance_valid(navigation) else null
	_map_ref = map_ref
	_sequence = -1
	_last_tick = -1
	_publish(body)


func move_intent(sequence: int, direction: Vector3, speed: float, jump:bool=false) -> Dictionary:
	var body = _body.get_ref() if _body != null else null
	var navigation = _navigation.get_ref() if _navigation != null else null
	var profiling:bool=is_instance_valid(body) and body.has_meta("profile_frame")
	var intent_started:=Time.get_ticks_usec() if profiling else 0
	if body == null or (not traversal_guard.is_valid() and (navigation == null or not navigation.ready_for_queries)):
		return {"ok": false, "reason": "not_ready"}
	if movement_allowed.is_valid() and not movement_allowed.call():
		return {"ok": false, "reason": "movement_locked"}
	if sequence <= _sequence or not direction.is_finite() or not is_finite(speed):
		return {"ok": false, "reason": "invalid_intent"}
	if _last_tick == Engine.get_physics_frames():
		return {"ok": false, "reason": "duplicate_tick"}
	var dt: float = body.get_physics_process_delta_time()
	var multiplier := clampf(float(speed_multiplier.call()), 0.0, 3.0) if speed_multiplier.is_valid() else 1.0
	var wish := Vector3(direction.x, 0, direction.z).limit_length(1.0) * clampf(speed, 0, Motion.RUN_MPS) * multiplier
	var guard_started:=Time.get_ticks_usec() if profiling else 0
	if traversal_guard.is_valid():
		var bounds:=Traversal.motion_bounds(body,wish,dt,jump)
		if not bounds.has_volume():return {"ok":false,"reason":"invalid_capsule"}
		var ready:=Traversal.readiness(traversal_guard.call(bounds),Engine.get_physics_frames())
		if not ready.ok:return ready
	_last_tick = Engine.get_physics_frames();_sequence = sequence
	var requested_wish:Vector3=wish if profiling else Vector3.ZERO
	var support_block:=""
	var started:=Time.get_ticks_usec() if profiling else 0
	var landing_done:=started
	var actor_rotation:Variant=null
	if not body.has_meta("profile_legacy_capsule_yaw"):actor_rotation=preload("res://scripts/world3d/player_clearance.gd").begin_capsule_motion(body)
	if jump or not wish.is_zero_approx():preload("res://scripts/world3d/floor_contact_recovery.gd").recover(body)
	var feet: Vector3 = body.global_position - Vector3(0, 0.9, 0)
	# Walking off an internal ledge is valid even though there is no navigation
	# polygon at the character's current height. Check the landing below instead.
	# Looking beyond the leading hemisphere also crosses the navmesh's eroded rim.
	if wish.length_squared()>0:
		var next:=feet+wish*dt
		var landing:=_landing_below(body,next+wish.normalized()*.32,wish.normalized())
		if profiling:landing_done=Time.get_ticks_usec()
		if landing.is_empty():
			support_block="no_support"
			wish=Vector3.ZERO # No supporting map surface below: retain edge protection.
		# Navigation decides click-to-move routes, not manual physical movement.
		# A supported roof, narrow post or prop needs no nav polygon/asset allowlist.
	var support_done:=Time.get_ticks_usec() if profiling else 0
	var was_supported:bool=body.is_on_floor() or _descent.supported(body)
	var jumped:bool=jump and was_supported
	if jumped:body.velocity.y=4.8
	if body.velocity.y<=0 and wish.length_squared() > 0.0 and body.test_move(body.global_transform, wish * dt,_step_contact):
		_step_up(body, feet, wish, dt,_step_contact)
		feet = body.global_position - Vector3(0, 0.9, 0)
	var step_done:=Time.get_ticks_usec() if profiling else 0
	body.velocity.x = wish.x
	body.velocity.z = wish.z
	body.velocity.y -= 9.8 * dt
	var move_from:Transform3D=body.global_transform if profiling else Transform3D.IDENTITY
	var move_velocity:Vector3=body.velocity if profiling else Vector3.ZERO
	body.move_and_slide()
	_descent.follow(body,was_supported,jumped)
	var move_done:=Time.get_ticks_usec() if profiling else 0
	body._sense_surface()
	preload("res://scripts/world3d/player_clearance.gd").end_capsule_motion(body,actor_rotation)
	_publish(body)
	if profiling:
		var timing:={"frame":Engine.get_physics_frames(),"ms":(Time.get_ticks_usec()-started)/1000.0,"support_ms":(support_done-started)/1000.0,"landing_ms":(landing_done-started)/1000.0,"navigation_ms":(support_done-landing_done)/1000.0,"step_ms":(step_done-support_done)/1000.0,"move_ms":(move_done-step_done)/1000.0,"sense_ms":(Time.get_ticks_usec()-move_done)/1000.0}
		# Keep historical motion-only timing comparable. The scoped readiness
		# check precedes it and must be measured separately, not blamed on physics.
		timing.guard_ms=(started-guard_started)/1000.0
		timing.intent_precheck_ms=(guard_started-intent_started)/1000.0
		timing.capsule_query_aligned=move_from.basis==Basis.IDENTITY
		timing.requested_wish=requested_wish;timing.effective_wish=wish;timing.support_block=support_block
		if timing.ms>2.0:
			timing.move_from=[move_from.origin.x,move_from.origin.y,move_from.origin.z]
			timing.move_rotation=move_from.basis.get_euler()
			timing.move_velocity=move_velocity
			timing.contacts=[]
			for i in body.get_slide_collision_count():
				var hit:KinematicCollision3D=body.get_slide_collision(i)
				var collider:Object=hit.get_collider()
				timing.contacts.append({"uuid":collider.get_meta("uuid","") if is_instance_valid(collider) else "","normal":hit.get_normal(),"position":hit.get_position(),"shape":str(hit.get_collider_shape()),"shape_type":hit.get_collider_shape().shape.get_class() if hit.get_collider_shape() is CollisionShape3D else ""})
		body.set_meta("motion_timing",timing)
	return {"ok": true, "sequence": sequence, "location": snapshot.duplicate(true)}


func _landing_below(body:CharacterBody3D,point:Vector3,direction:Vector3)->Dictionary:
	return Traversal.support(body.get_world_3d().direct_space_state,point,direction,body.global_position.y-.9,body.collision_mask,[body.get_rid()],cos(body.floor_max_angle))


func _publish(body: CharacterBody3D) -> void:
	snapshot = Location.make(_map_ref, body.global_position - Vector3(0, 0.9, 0), body.surface_id).to_dictionary()


func _step_up(body: CharacterBody3D, feet: Vector3, wish: Vector3, dt: float,contact:KinematicCollision3D=null) -> void:
	var support := PhysicsRayQueryParameters3D.create(feet + Vector3(0, 0.05, 0), feet - Vector3(0, 0.4, 0))
	support.exclude = [body.get_rid()]
	support.collision_mask=body.collision_mask
	if body.get_world_3d().direct_space_state.intersect_ray(support).is_empty():
		return
	var rise:=preload("res://scripts/world3d/step_support.gd").rise(body,feet,wish,dt,.32,body.collision_mask,cos(body.floor_max_angle),.005,contact)
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
