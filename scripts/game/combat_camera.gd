extends RefCounted
## Soft combat framing: bias Camera2D toward player↔hostile midpoint (not party follow).

const DEFAULT_FACTOR := 0.25
const DEFAULT_MAX_PX := 64.0
## Approximate approach rate for offset lerp (units/sec toward 1.0).
const LERP_SPEED := 8.0


## Offset from player toward target: (target - player) * factor, clamped to max_px.
static func compute_frame_offset(
	player_pos: Vector2,
	target_pos: Vector2,
	factor: float = DEFAULT_FACTOR,
	max_px: float = DEFAULT_MAX_PX
) -> Vector2:
	factor = maxf(0.0, factor)
	max_px = maxf(0.0, max_px)
	var raw: Vector2 = (target_pos - player_pos) * factor
	if max_px <= 0.0:
		return Vector2.ZERO
	if raw.length_squared() > max_px * max_px:
		return raw.limit_length(max_px)
	return raw


static func lerp_offset(current: Vector2, desired: Vector2, delta: float, speed: float = LERP_SPEED) -> Vector2:
	var t: float = clampf(maxf(0.0, delta) * maxf(0.0, speed), 0.0, 1.0)
	return current.lerp(desired, t)
