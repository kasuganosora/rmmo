extends RefCounted
## Aggressive / enraged mob vision cone + chase / return-home / idle wander helpers (MockServer AI).
## Vision: 120° cone, length 6 cells (1 tile ≈ 1 m; project uses 48px RM tiles).

const GridPath = preload("res://scripts/map/grid_path.gd")
const TileId = preload("res://scripts/map/tile_id.gd")
const GridUtil = preload("res://scripts/util/grid_util.gd")

## 6 meters → 6 cells (documented in COMBAT.md).
const VISION_RANGE_CELLS := 6.0
## Full cone 120° → half-angle 60°.
const VISION_HALF_ANGLE_DEG := 60.0
const LOSE_SIGHT_SEC := 5.0
## While chasing: no engageable target within engage range for this long → clear_chase / return_home.
const NO_VALID_TARGET_SEC := 5.0
## Engage radius fallback when leash_radius disabled (<0): Chebyshev cells from NPC to target.
const DEFAULT_ENGAGE_RANGE := 15
## Return-home: after this many blocked/failed steps, teleport snap to home_cell.
const RETURN_STUCK_TICKS := 8
## Home leash: Chebyshev cells from home_cell; chase beyond this → clear_chase / return_home.
## Configurable per-NPC via npcs.json `leash_radius` (default 12).
const DEFAULT_LEASH_RADIUS := 12
## Dead hostile respawn delay (seconds); overridable via `respawn_sec` on npc / AI blob.
const DEFAULT_RESPAWN_SEC := 30.0
## Idle wander: accumulate this many seconds between optional steps (low frequency).
const IDLE_WANDER_INTERVAL_SEC := 2.2

const AI_IDLE := "idle"
const AI_CHASE := "chase"
const AI_RETURN_HOME := "return_home"


static func forward_vec(facing: int) -> Vector2:
	match facing:
		1:
			return Vector2(-1, 1)
		2:
			return Vector2(0, 1)
		3:
			return Vector2(1, 1)
		4:
			return Vector2(-1, 0)
		6:
			return Vector2(1, 0)
		7:
			return Vector2(-1, -1)
		8:
			return Vector2(0, -1)
		9:
			return Vector2(1, -1)
		_:
			return Vector2(0, 1)


## Euclidean cell distance ≤ 6 and angle(forward, to_player) ≤ 60°.
## Optional collision: if provided, also requires clear grid LoS (Bresenham / wall block).
static func player_in_vision(
	npc_cell: Vector2i, facing: int, player_cell: Vector2i, collision = null
) -> bool:
	var dx: float = float(player_cell.x - npc_cell.x)
	var dy: float = float(player_cell.y - npc_cell.y)
	var dist: float = sqrt(dx * dx + dy * dy)
	if dist > VISION_RANGE_CELLS + 0.0001:
		return false
	if dist < 0.0001:
		return true
	var to_player := Vector2(dx, dy).normalized()
	var fwd := forward_vec(facing)
	var cos_a: float = clampf(fwd.dot(to_player), -1.0, 1.0)
	if cos_a < cos(deg_to_rad(VISION_HALF_ANGLE_DEG)):
		return false
	if collision != null and not has_line_of_sight(collision, npc_cell, player_cell):
		return false
	return true


## Grid Bresenham cells from a to b (inclusive).
static func bresenham_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0: int = a.x
	var y0: int = a.y
	var x1: int = b.x
	var y1: int = b.y
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		out.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return out


## True when a cell blocks vision (void / fully impassable wall). Ignores actor occupancy.
static func cell_blocks_sight(collision, x: int, y: int) -> bool:
	if collision == null:
		return false
	if collision.has_method("is_valid") and not bool(collision.is_valid(x, y)):
		return true
	if collision.has_method("is_void_cell") and bool(collision.is_void_cell(x, y)):
		return true
	# Wall: no cardinal passage bit open on this tile (tile-only; ignore extra_blocked).
	if collision.has_method("is_passable"):
		var any_open := false
		for d in [2, 4, 6, 8]:
			if bool(collision.is_passable(x, y, d)):
				any_open = true
				break
		if not any_open:
			return true
	return false


## Clear LoS along Bresenham: intermediate cells must not block passage/walls.
## Also require can_pass_tiles (or can_pass) between consecutive cardinal steps when available.
static func has_line_of_sight(collision, from: Vector2i, to: Vector2i) -> bool:
	if collision == null:
		return true
	if from == to:
		return true
	var cells: Array[Vector2i] = bresenham_cells(from, to)
	# Intermediate cells (skip endpoints — standing on / targeting is fine).
	for i in range(1, cells.size() - 1):
		var c: Vector2i = cells[i]
		if cell_blocks_sight(collision, c.x, c.y):
			return false
	# Edge checks between consecutive cells (Bresenham may step diagonally).
	for i in range(cells.size() - 1):
		var a: Vector2i = cells[i]
		var b: Vector2i = cells[i + 1]
		var step := Vector2i(b.x - a.x, b.y - a.y)
		var cheb: int = maxi(absi(step.x), absi(step.y))
		if cheb != 1:
			continue
		var d: int = _dir_from_step(a, b)
		if d == 0:
			continue
		if TileId.is_cardinal(d):
			if collision.has_method("can_pass_tiles"):
				if not bool(collision.can_pass_tiles(a.x, a.y, d)):
					return false
			elif collision.has_method("can_pass"):
				# Fall back; occupancy on the far cell should not block vision.
				if not bool(collision.can_pass(a.x, a.y, d)):
					# Retry ignoring extra: if destination is only actor-blocked, allow.
					if collision.has_method("is_extra_blocked") and bool(collision.is_extra_blocked(b.x, b.y)):
						continue
					return false
		else:
			# Diagonal Bresenham step: both orthogonal corners must not fully block.
			var c1 := Vector2i(a.x + step.x, a.y)
			var c2 := Vector2i(a.x, a.y + step.y)
			if cell_blocks_sight(collision, c1.x, c1.y) and cell_blocks_sight(collision, c2.x, c2.y):
				return false
	return true


static func facing_toward(from: Vector2i, to: Vector2i) -> int:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	if dx == 0 and dy == 0:
		return 2
	if absi(dx) > absi(dy):
		return 6 if dx > 0 else 4
	if dy != 0:
		return 2 if dy > 0 else 8
	return 2


## True when this NPC should use chase AI (base aggressive OR temp enraged).
static func wants_chase(ai: Dictionary) -> bool:
	if bool(ai.get("aggressive", false)):
		return true
	return bool(ai.get("enraged", false))


static func get_home_cell(ai: Dictionary) -> Vector2i:
	var hv: Variant = ai.get("home_cell", Vector2i(-9999, -9999))
	if typeof(hv) == TYPE_VECTOR2I:
		return hv
	if typeof(hv) == TYPE_DICTIONARY:
		return Vector2i(int(hv.get("x", -9999)), int(hv.get("y", -9999)))
	return Vector2i(-9999, -9999)


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return GridUtil.chebyshev(a, b)


## Cell is within wander_radius of home (Chebyshev / king-move). radius 0 → only home.
static func within_wander_radius(cell: Vector2i, home: Vector2i, wander_radius: int) -> bool:
	var r: int = maxi(wander_radius, 0)
	return chebyshev(cell, home) <= r


## True when current cell is farther than leash_radius from home (Chebyshev).
## Invalid home → never beyond leash. leash_radius < 0 → disabled.
static func beyond_leash(cell: Vector2i, home: Vector2i, leash_radius: int) -> bool:
	if home.x <= -9990 or cell.x <= -9990:
		return false
	if leash_radius < 0:
		return false
	return chebyshev(cell, home) > maxi(leash_radius, 0)


## True when chase target cell is within engage range of NPC (Chebyshev).
## engage_range usually max(leash_radius, DEFAULT_ENGAGE_RANGE); <0 → DEFAULT_ENGAGE_RANGE.
static func target_in_engage_range(npc_cell: Vector2i, target_cell: Vector2i, engage_range: int) -> bool:
	if npc_cell.x <= -9990 or target_cell.x <= -9990:
		return false
	var r: int = engage_range if engage_range >= 0 else DEFAULT_ENGAGE_RANGE
	return chebyshev(npc_cell, target_cell) <= maxi(r, 0)


## True when AI is mid leash-reset (must not attack / re-aggro until home).
static func is_returning(ai: Dictionary) -> bool:
	return str(ai.get("ai_state", "")) == AI_RETURN_HOME


## One A* / greedy step toward goal. allow_onto_goal: true for return-home (step onto home).
## For chase, pass player cell with allow_onto_goal=false (does not step onto player).
static func next_step_dir(collision, from: Vector2i, goal: Vector2i, allow_onto_goal: bool = false) -> int:
	if collision == null:
		return 0
	if from == goal:
		return 0
	var man: int = maxi(absi(from.x - goal.x), absi(from.y - goal.y))
	if man <= 1 and not allow_onto_goal:
		return 0
	# Temporarily free goal occupancy so A* can aim at / past the goal cell when blocked.
	var had_block := false
	if collision.has_method("is_extra_blocked"):
		had_block = bool(collision.is_extra_blocked(goal.x, goal.y))
	if had_block and collision.has_method("set_extra_blocked"):
		collision.set_extra_blocked(goal.x, goal.y, false)
	var path: Array[Vector2i] = GridPath.find_path(collision, from, goal)
	if path.is_empty():
		path = GridPath.find_path_near(collision, from, goal, 2)
	if had_block and collision.has_method("set_extra_blocked"):
		collision.set_extra_blocked(goal.x, goal.y, true)
	if not path.is_empty():
		var next: Vector2i = path[0]
		if next == goal and not allow_onto_goal:
			return 0
		return _dir_from_step(from, next)
	# Greedy fallback: try 8-way that reduce Euclidean distance.
	var best_dir := 0
	var best_dist := INF
	var base := Vector2(float(from.x), float(from.y)).distance_to(Vector2(float(goal.x), float(goal.y)))
	for d in TileId.DIRS8:
		if not collision.can_pass(from.x, from.y, d):
			continue
		var delta: Vector2i = TileId.dir_delta(d)
		var nx: int = from.x + delta.x
		var ny: int = from.y + delta.y
		if not allow_onto_goal and nx == goal.x and ny == goal.y:
			continue
		var nd: float = Vector2(float(nx), float(ny)).distance_to(Vector2(float(goal.x), float(goal.y)))
		if nd < best_dist and nd < base - 0.01:
			best_dist = nd
			best_dir = d
	return best_dir


## One A* step toward player (does not step onto player cell). Returns RM dir or 0.
static func next_chase_dir(collision, from: Vector2i, player_cell: Vector2i) -> int:
	return next_step_dir(collision, from, player_cell, false)


## Step toward home_cell (may land on home).
static func next_home_dir(collision, from: Vector2i, home: Vector2i) -> int:
	return next_step_dir(collision, from, home, true)


## Idle: pick a random cardinal that stays within wander_radius of home (or 0 if none / radius 0).
static func next_idle_wander_dir(collision, from: Vector2i, home: Vector2i, wander_radius: int) -> int:
	if collision == null or wander_radius <= 0:
		return 0
	if home.x <= -9990:
		return 0
	var dirs: Array[int] = TileId.DIRS8.duplicate()
	dirs.shuffle()
	for d in dirs:
		if not collision.can_pass(from.x, from.y, d):
			continue
		var delta: Vector2i = TileId.dir_delta(d)
		var next := Vector2i(from.x + delta.x, from.y + delta.y)
		if not within_wander_radius(next, home, wander_radius):
			continue
		return d
	return 0


static func _dir_from_step(from: Vector2i, to: Vector2i) -> int:
	return TileId.dir_from_vec(Vector2(to - from))
