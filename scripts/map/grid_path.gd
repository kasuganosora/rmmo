extends RefCounted
## Grid pathfinding via MapCollision AStar2D (4-dir tile edges + occupancy).
## Falls back to a heap A* if the collision object has no native graph.

const TileId = preload("res://scripts/map/tile_id.gd")

const DIRS: Array[int] = [2, 4, 6, 8]


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
## Uses the same can_pass rules as MockServer.try_move.
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

	# Snap: try landable cells near goal (closest first), one A* each — no full-map BFS.
	var candidates: Array[Vector2i] = _snap_candidates(collision, goal, snap_radius)
	for c in candidates:
		if c == start:
			continue
		var path: Array[Vector2i] = find_path(collision, start, c)
		if not path.is_empty():
			return path
	return empty


static func _is_standable_goal(collision, goal: Vector2i) -> bool:
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
			var dist: int = absi(dx) + absi(dy)
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


static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Binary-heap A* fallback (Dictionary closed/open). Kept for non-MapCollision callers.
static func _find_path_heap(collision, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not collision.is_valid(start.x, start.y) or not collision.is_valid(goal.x, goal.y):
		return empty

	# open_heap: Array of Vector2i; f_score / g_score Dictionaries; heap keyed by f.
	var open_heap: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}
	var f_score: Dictionary = {start: _heuristic(start, goal)}
	var in_open: Dictionary = {start: true}
	var closed: Dictionary = {}
	var max_iters: int = collision.width * collision.height * 4 if ("width" in collision) else 20000
	var iters: int = 0

	while not open_heap.is_empty() and iters < max_iters:
		iters += 1
		var current: Vector2i = _heap_pop(open_heap, f_score)
		in_open.erase(current)
		if current == goal:
			return _reconstruct(came_from, current)
		closed[current] = true
		for d in DIRS:
			if not collision.can_pass(current.x, current.y, d):
				continue
			var neighbor: Vector2i = current + TileId.dir_delta(d)
			if closed.has(neighbor):
				continue
			var tentative: int = int(g_score[current]) + 1
			if g_score.has(neighbor) and tentative >= int(g_score[neighbor]):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			f_score[neighbor] = tentative + _heuristic(neighbor, goal)
			if not in_open.has(neighbor):
				_heap_push(open_heap, f_score, neighbor)
				in_open[neighbor] = true
	return empty


static func _heap_push(heap: Array[Vector2i], f_score: Dictionary, cell: Vector2i) -> void:
	heap.append(cell)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) >> 1
		if int(f_score.get(heap[i], 0x7fffffff)) >= int(f_score.get(heap[parent], 0x7fffffff)):
			break
		var tmp: Vector2i = heap[i]
		heap[i] = heap[parent]
		heap[parent] = tmp
		i = parent


static func _heap_pop(heap: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var result: Vector2i = heap[0]
	var last: Vector2i = heap[heap.size() - 1]
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
		if left < n and int(f_score.get(heap[left], 0x7fffffff)) < int(f_score.get(heap[smallest], 0x7fffffff)):
			smallest = left
		if right < n and int(f_score.get(heap[right], 0x7fffffff)) < int(f_score.get(heap[smallest], 0x7fffffff)):
			smallest = right
		if smallest == i:
			break
		var tmp: Vector2i = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest
	return result


static func _reconstruct(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	while came_from.has(current):
		path.append(current)
		current = came_from[current] as Vector2i
	path.reverse()
	return path
