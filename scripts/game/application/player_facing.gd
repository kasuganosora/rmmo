extends RefCounted
## Application layer: facing direction, idle/walk animation, facing angle.

static func set_facing_dir(ctrl, d: int) -> void:
	ctrl._set_facing_from_dir(d)
	ctrl._play_idle()

static func _set_facing_from_dir(ctrl, d: int) -> void:
	match d:
		4:
			ctrl._facing = "left"
		6:
			ctrl._facing = "right"
		7, 8, 9:
			ctrl._facing = "back"
		_:
			ctrl._facing = "front"
	ctrl._place_weapon_overlay()

static func _play_walk(ctrl) -> void:
	if ctrl.anim == null or ctrl.anim.sprite_frames == null:
		return
	var walk = "walk_%s" % ctrl._facing
	if ctrl.anim.animation != walk:
		ctrl.anim.play(walk)

static func _play_idle(ctrl) -> void:
	if ctrl.anim == null or ctrl.anim.sprite_frames == null:
		return
	var idle = "idle_%s" % ctrl._facing
	if ctrl.anim.sprite_frames.has_animation(idle) and ctrl.anim.animation != idle:
		ctrl.anim.play(idle)

static func facing_angle(ctrl) -> float:
	# Screen/world angles: +x right, +y down.
	match ctrl._facing:
		"front":
			return PI * 0.5
		"back":
			return -PI * 0.5
		"left":
			return PI
		"right":
			return 0.0
		_:
			return PI * 0.5

