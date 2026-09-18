extends RefCounted
## Thin Camera2D offset shake for crit hits. New trigger restarts; amplitude does not stack.

const DEFAULT_DURATION := 0.2
const DEFAULT_AMPLITUDE := 3.0
const MAX_AMPLITUDE := 4.0
const MIN_DURATION := 0.15
const MAX_DURATION := 0.25
## Radians per second — fast jitter within the short window.
const PHASE_SPEED := 55.0


var remaining: float = 0.0
var duration: float = DEFAULT_DURATION
var amplitude: float = DEFAULT_AMPLITUDE
var offset: Vector2 = Vector2.ZERO
var _phase: float = 0.0
## When false, trigger() uses phase 0 (deterministic headless tests).
var randomize_phase: bool = true


func is_active() -> bool:
	return remaining > 0.0


func clear() -> void:
	remaining = 0.0
	offset = Vector2.ZERO


## Restart shake. Duration clamped to ~0.15–0.25s; amplitude to 2–4 px.
## Optional fixed_phase (>= 0) skips RNG for tests.
func trigger(
	dur: float = DEFAULT_DURATION,
	amp: float = DEFAULT_AMPLITUDE,
	fixed_phase: float = -1.0
) -> void:
	duration = clampf(dur, MIN_DURATION, MAX_DURATION)
	amplitude = clampf(amp, 2.0, MAX_AMPLITUDE)
	remaining = duration
	if fixed_phase >= 0.0:
		_phase = fixed_phase
	elif randomize_phase:
		_phase = randf() * TAU
	else:
		_phase = 0.0
	# Seed first sample immediately so apply_to works before first tick.
	_sample(1.0)


func tick(delta: float) -> Vector2:
	if remaining <= 0.0:
		offset = Vector2.ZERO
		return offset
	delta = maxf(0.0, delta)
	remaining = maxf(0.0, remaining - delta)
	if remaining <= 0.0:
		offset = Vector2.ZERO
		return offset
	_phase += delta * PHASE_SPEED
	var t: float = remaining / duration  ## 1 → 0 linear decay
	_sample(t)
	return offset


func _sample(decay: float) -> void:
	var mag: float = amplitude * clampf(decay, 0.0, 1.0)
	offset = Vector2(cos(_phase), sin(_phase * 1.31)) * mag


func apply_to(cam: Camera2D, base: Vector2 = Vector2.ZERO) -> void:
	if cam == null or not is_instance_valid(cam):
		return
	cam.offset = base + offset
