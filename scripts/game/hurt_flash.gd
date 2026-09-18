extends RefCounted
## Short red-to-white sprite blink for incoming damage. Retrigger restarts without
## capturing the already-tinted color, and completion always restores the base.

const DEFAULT_DURATION := 0.16
const MIN_DURATION := 0.12
const MAX_DURATION := 0.20
const HIT_COLOR := Color(1.0, 0.22, 0.22, 1.0)

var remaining: float = 0.0
var duration: float = DEFAULT_DURATION
var current_color: Color = Color.WHITE
var _target: CanvasItem = null
var _base_color: Color = Color.WHITE


func is_active() -> bool:
	return remaining > 0.0


func trigger(target: CanvasItem, dur: float = DEFAULT_DURATION) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _target != target or not is_active():
		clear()
		_target = target
		_base_color = target.modulate
	duration = clampf(dur, MIN_DURATION, MAX_DURATION)
	remaining = duration
	current_color = HIT_COLOR
	_target.modulate = current_color


func tick(delta: float) -> Color:
	if not is_active():
		return current_color
	remaining = maxf(0.0, remaining - maxf(delta, 0.0))
	if remaining <= 0.0:
		current_color = _base_color
		_apply_color()
		return current_color
	# Red at impact, quickly easing back to the original (normally white) tint.
	var progress: float = 1.0 - remaining / duration
	current_color = HIT_COLOR.lerp(_base_color, ease(progress, 2.0))
	_apply_color()
	return current_color


func clear() -> void:
	if _target != null and is_instance_valid(_target):
		_target.modulate = _base_color
	remaining = 0.0
	current_color = _base_color
	_target = null


func _apply_color() -> void:
	if _target != null and is_instance_valid(_target):
		_target.modulate = current_color
