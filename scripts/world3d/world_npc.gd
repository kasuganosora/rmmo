extends CharacterBody3D
## Physical NPC locomotion uses the same capsule sweep / step rules as players.
var surface_id := ""
var authority = preload("res://scripts/world3d/world_authority.gd").new()
var route := PackedVector3Array()
var sequence := 0
var home := Vector3.ZERO
var spec: Dictionary
var model: Node3D
var repath := 0.0
var respawn_remaining := -1.0
var attack_remaining := 0.0
var engaged := false
var returning := false
var cast_label: Label3D

func configure(definition: Dictionary) -> void:
	spec = definition
	var bounds: AABB = spec.transform * spec.mesh.get_aabb()
	home = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	position = home + Vector3(0, 0.9, 0)
	set_meta("uuid", str(spec.uuid))
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	add_child(shape)
	floor_snap_length = 0.2
	model = preload("res://scripts/char/character_model_3d.gd").create_npc(spec.extras.get("appearance", {}))
	model.position.y = -0.9
	add_child(model)
	cast_label = preload("res://scripts/char/character_overhead_label.gd").new()
	cast_label.model=model
	cast_label.clearance=.24
	cast_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cast_label.font_size = 32
	cast_label.pixel_size = 0.008
	cast_label.modulate = Color("ffd480")
	cast_label.visible = false
	add_child(cast_label)

func feet() -> Vector3:
	return global_position - Vector3(0, 0.9, 0)

func follow_path(delta: float, speed_multiplier: float = 1.0) -> void:
	while not route.is_empty() and Vector2(feet().x - route[0].x, feet().z - route[0].z).length() < 0.12:
		route.remove_at(0)
	var wish := Vector3.ZERO
	var speed := 0.0
	if not route.is_empty():
		wish = Vector3(route[0].x - feet().x, 0, route[0].z - feet().z)
		speed = minf(2.5 * clampf(speed_multiplier, 0, 1.6), wish.length() / maxf(delta, 0.00001))
	var before := global_position
	sequence += 1
	authority.move_intent(sequence, wish.normalized(), speed)
	var actual := (global_position - before).length() / maxf(delta, 0.00001)
	if actual > 0.1 and wish.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(wish.x, wish.z), 1 - exp(-10 * delta))
	model.play("walk" if actual > 0.1 else "idle", "front")
	model.locomotion_rate = actual / 2.5

func _sense_surface() -> void:
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position - Vector3(0, 1.4, 0))
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	surface_id = "" if hit.is_empty() else str(hit.collider.get_meta("uuid", ""))
