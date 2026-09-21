extends RefCounted
## Pure helpers for nameplate draw-distance culling (Chebyshev cells).

const GridUtil = preload("res://scripts/util/grid_util.gd")


## Hide when dist > max_dist unless selected (selected always shows).
static func should_show(dist: int, max_dist: int, selected: bool) -> bool:
	if selected:
		return true
	return int(dist) <= int(max_dist)


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return GridUtil.chebyshev(a, b)


static func clamp_distance(v: int) -> int:
	return clampi(int(v), 4, 32)
