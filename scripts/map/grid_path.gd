extends RefCounted
## Grid pathfinding: 8-dir A* (octile costs, no corner-cut) over MapCollision.can_pass.

const TileId = preload("res://scripts/map/tile_id.gd")

const DIRS: Array[int] = [1, 2, 3, 4, 6, 7, 8, 9]
const COST_CARD: int = 10
const COST_DIAG: int = 14


## Returns waypoints from after start to goal (excluding start). Empty if none.
static func find_path(collision, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if collision == null:
		return empty
	if start == goal:
		return empty
	if collision.has_method("find_astar_path"):
		return collision.find_astar_path(start, goal)
	return _find_path_heap(collision, start, goal)


## Path to goal, or to nearest reachable landable cell within snap_radius of goal.
## Uses the same can_pass rules as MockServer.try_move. One A* for all snap cells.
static func find_path_near(
	collision,
	start: Vector2i,
	goal: Vector2i,
	snap_radius: int = 6
) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if collision == null:
		return empty
	if start == goal:
		return empty
	if not collision.is_valid(start.x, start.y):
		return empty

	# Prefer exact goal when it is standable / not occupied.
	if _is_standable_goal(collision, goal):
		var direct: Array[Vector2i] = find_path(collision, start, goal)
		if not direct.is_empty():
			return direct

	var candidates: Array[Vector2i] = _snap_candidates(collision, goal, snap_radius)
	if candidates.is_empty():
		return empty
	if collision.has_method("find_astar_path_any"):
		return collision.find_astar_path_any(start, candidates, goal)
	return _find_path_heap_any(collision, start, candidates, goal)


static func _is_standable_goal(collision, goal: Vector2i) -> bool:
	if collision.has_method("path_cell_flags"):
		var state: int=collision.path_cell_flags(goal.x,goal.y)
		return (state & (16|32|64))==0 and (state & 15)!=0
	if not collision.is_valid(goal.x, goal.y):
		return false
	if collision.has_method("is_extra_blocked") and collision.is_extra_blocked(goal.x, goal.y):
		return false
	if collision.has_method("is_landable"):
		return collision.is_landable(goal.x, goal.y)
	return true


static func _snap_candidates(collision, goal: Vector2i, snap_radius: int) -> Array[Vector2i]:
	var scored: Array = []
	for dy in range(-snap_radius, snap_radius + 1):
		for dx in range(-snap_radius, snap_radius + 1):
			var dist: int = maxi(absi(dx), absi(dy))
			if dist == 0 or dist > snap_radius:
				continue
			var c := Vector2i(goal.x + dx, goal.y + dy)
			if not _is_standable_goal(collision, c):
				continue
			scored.append({"c": c, "d": dist})
	scored.sort_custom(func(a, b): return int(a["d"]) < int(b["d"]))
	var out: Array[Vector2i] = []
	for item in scored:
		out.append(item["c"] as Vector2i)
	return out


## Octile distance in 10/14 units (admissible + consistent for 8-dir).
static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)
	if dx > dy:
		return COST_CARD * dx + (COST_DIAG - COST_CARD) * dy
	return COST_CARD * dy + (COST_DIAG - COST_CARD) * dx


static func _find_path_heap(collision, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var goals: Array[Vector2i] = [goal]
	return _find_path_heap_any(collision, start, goals, goal)


## Distance to the goal bounding rectangle is a consistent lower bound.
## Unlike anchor-minus-radius it does not collapse to zero far outside the goals.
static func _find_path_heap_any(
	collision,
	start: Vector2i,
	goals: Array[Vector2i],
	anchor: Vector2i
) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if goals.is_empty() or not collision.is_valid(start.x, start.y):
		return empty
	var w: int = int(collision.width) if "width" in collision else 0
	if w <= 0:
		return empty

	var goal_set: Dictionary = {}
	var bounds := Vector4i(2147483647,2147483647,-2147483647,-2147483647)
	for g in goals:
		if not collision.is_valid(g.x, g.y):
			continue
		if g == start:
			continue
		goal_set[_cid(g, w)] = true
		bounds.x=mini(bounds.x,g.x);bounds.y=mini(bounds.y,g.y)
		bounds.z=maxi(bounds.z,g.x);bounds.w=maxi(bounds.w,g.y)
	if goal_set.is_empty():
		return empty

	var start_cid: int = _cid(start, w)
	# Heap entries: Vector4i(x, y, g, f)
	var open_heap: Array[Vector4i] = []
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_cid: 0}
	var closed: Dictionary = {}
	var h0: int = _bounds_heuristic(start, bounds)
	_heap_push(open_heap, Vector4i(start.x, start.y, 0, h0))

	var max_iters: int = 80000
	if collision.has_method("path_search_budget"):
		max_iters = int(collision.path_search_budget())
	elif "height" in collision:
		max_iters = mini(w * int(collision.height) * 8, 200000)
	var iters: int = 0
	var pass_cache: Dictionary = {}

	while not open_heap.is_empty() and iters < max_iters:
		iters += 1
		var cur: Vector4i = _heap_pop(open_heap)
		var cx: int = cur.x
		var cy: int = cur.y
		var cid: int = cy * w + cx
		if closed.has(cid):
			continue
		var known_g: int = int(g_score.get(cid, -1))
		if cur.z != known_g:
			continue
		closed[cid] = true
		if goal_set.has(cid):
			return _reconstruct_cid(came_from, cid, w)

		var pass2: bool = _cached_pass(collision, pass_cache, w, cx, cy, 2)
		var pass4: bool = _cached_pass(collision, pass_cache, w, cx, cy, 4)
		var pass6: bool = _cached_pass(collision, pass_cache, w, cx, cy, 6)
		var pass8: bool = _cached_pass(collision, pass_cache, w, cx, cy, 8)
		if pass2:
			_relax(open_heap, came_from, g_score, closed, w, cid, cx, cy + 1, known_g + COST_CARD, anchor, bounds)
		if pass4:
			_relax(open_heap, came_from, g_score, closed, w, cid, cx - 1, cy, known_g + COST_CARD, anchor, bounds)
		if pass6:
			_relax(open_heap, came_from, g_score, closed, w, cid, cx + 1, cy, known_g + COST_CARD, anchor, bounds)
		if pass8:
			_relax(open_heap, came_from, g_score, closed, w, cid, cx, cy - 1, known_g + COST_CARD, anchor, bounds)
		# Diagonals: both origin cardinals + both side entries (same as MapCollision._can_pass_diagonal).
		if (
			pass2
			and pass6
			and _cached_pass(collision, pass_cache, w, cx + 1, cy, 2)
			and _cached_pass(collision, pass_cache, w, cx, cy + 1, 6)
		):
			_relax(open_heap, came_from, g_score, closed, w, cid, cx + 1, cy + 1, known_g + COST_DIAG, anchor, bounds)
		if (
			pass2
			and pass4
			and _cached_pass(collision, pass_cache, w, cx - 1, cy, 2)
			and _cached_pass(collision, pass_cache, w, cx, cy + 1, 4)
		):
			_relax(open_heap, came_from, g_score, closed, w, cid, cx - 1, cy + 1, known_g + COST_DIAG, anchor, bounds)
		if (
			pass8
			and pass6
			and _cached_pass(collision, pass_cache, w, cx + 1, cy, 8)
			and _cached_pass(collision, pass_cache, w, cx, cy - 1, 6)
		):
			_relax(open_heap, came_from, g_score, closed, w, cid, cx + 1, cy - 1, known_g + COST_DIAG, anchor, bounds)
		if (
			pass8
			and pass4
			and _cached_pass(collision, pass_cache, w, cx - 1, cy, 8)
			and _cached_pass(collision, pass_cache, w, cx, cy - 1, 4)
		):
			_relax(open_heap, came_from, g_score, closed, w, cid, cx - 1, cy - 1, known_g + COST_DIAG, anchor, bounds)
	return empty


static func _cached_pass(collision, cache: Dictionary, w: int, x: int, y: int, d: int) -> bool:
	if collision.has_method("path_cell_flags"):
		var delta: Vector2i=TileId.dir_delta(d)
		# Vector2i keys prevent out-of-bounds coordinates aliasing valid rows.
		var origin:=Vector2i(x,y)
		var target:=origin+delta
		if not cache.has(origin):cache[origin]=collision.path_cell_flags(x,y)
		if not cache.has(target):cache[target]=collision.path_cell_flags(target.x,target.y)
		var a: int=cache[origin];var b: int=cache[target]
		if (b & (16|32|64))!=0:return false
		var bit:=1 << (int(d/2)-1)
		var reverse_bit:=1 << (int(TileId.reverse_dir(d)/2)-1)
		return ((a & 16)!=0 or (a & bit)!=0) and (b & reverse_bit)!=0
	var k: int = (y * w + x) * 16 + d
	if cache.has(k):
		return bool(cache[k])
	var ok: bool = bool(collision.can_pass(x, y, d))
	cache[k] = ok
	return ok


static func _bounds_heuristic(cell: Vector2i, bounds: Vector4i) -> int:
	return _heuristic(cell,Vector2i(clampi(cell.x,bounds.x,bounds.z),clampi(cell.y,bounds.y,bounds.w)))


static func _cid(c: Vector2i, w: int) -> int:
	return c.y * w + c.x


static func _relax(
	heap: Array[Vector4i],
	came_from: Dictionary,
	g_score: Dictionary,
	closed: Dictionary,
	w: int,
	from_cid: int,
	nx: int,
	ny: int,
	tentative: int,
	anchor: Vector2i,
	bounds: Vector4i
) -> void:
	var nid: int = ny * w + nx
	if closed.has(nid):
		return
	if g_score.has(nid) and tentative >= int(g_score[nid]):
		return
	came_from[nid] = from_cid
	g_score[nid] = tentative
	var h: int = _bounds_heuristic(Vector2i(nx, ny), bounds)
	_heap_push(heap, Vector4i(nx, ny, tentative, tentative + h))


static func _heap_push(heap: Array[Vector4i], entry: Vector4i) -> void:
	heap.append(entry)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) >> 1
		if not _heap_worse(heap[parent], heap[i]):
			break
		var tmp: Vector4i = heap[i]
		heap[i] = heap[parent]
		heap[parent] = tmp
		i = parent


static func _heap_pop(heap: Array[Vector4i]) -> Vector4i:
	var result: Vector4i = heap[0]
	var last: Vector4i = heap[heap.size() - 1]
	heap.remove_at(heap.size() - 1)
	if heap.is_empty():
		return result
	heap[0] = last
	var i: int = 0
	var n: int = heap.size()
	while true:
		var left: int = (i << 1) + 1
		var right: int = left + 1
		var smallest: int = i
		if left < n and _heap_worse(heap[smallest], heap[left]):
			smallest = left
		if right < n and _heap_worse(heap[smallest], heap[right]):
			smallest = right
		if smallest == i:
			break
		var tmp: Vector4i = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest
	return result


## True when `a` should sink below `b` (higher f, or equal f with larger g).
static func _heap_worse(a: Vector4i, b: Vector4i) -> bool:
	if a.w != b.w:
		return a.w > b.w
	return a.z < b.z


static func _reconstruct_cid(came_from: Dictionary, current: int, w: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	while came_from.has(current):
		path.append(Vector2i(current % w, int(current / w)))
		current = int(came_from[current])
	path.reverse()
	return path
