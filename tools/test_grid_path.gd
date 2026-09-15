extends SceneTree

const TilemapPack = preload("res://scripts/map/tilemap_pack.gd")
const GridPath = preload("res://scripts/map/grid_path.gd")
const TileId = preload("res://scripts/map/tile_id.gd")
const MapCollision = preload("res://scripts/map/map_collision.gd")

func _init() -> void:
	_test_dirs()
	_test_synthetic_8dir()
	_test_demo_map()
	print("ALL PATH TESTS OK")
	quit(0)


func _test_dirs() -> void:
	assert(TileId.dir_delta(1) == Vector2i(-1, 1))
	assert(TileId.dir_delta(3) == Vector2i(1, 1))
	assert(TileId.dir_delta(7) == Vector2i(-1, -1))
	assert(TileId.dir_delta(9) == Vector2i(1, -1))
	assert(TileId.dir_from_vec(Vector2(1, 1)) == 3)
	assert(TileId.dir_from_vec(Vector2(-1, 1)) == 1)
	assert(TileId.dir_from_vec(Vector2(1, -1)) == 9)
	assert(TileId.dir_from_vec(Vector2(-1, -1)) == 7)
	assert(TileId.dir_from_vec(Vector2(1, 0)) == 6)
	assert(TileId.reverse_dir(1) == 9)
	assert(TileId.reverse_dir(3) == 7)
	assert(TileId.cardinal_facing(3) == 2)
	assert(TileId.cardinal_facing(9) == 8)
	assert(TileId.is_dir(3) and not TileId.is_dir(5) and not TileId.is_dir(0))


func _open_grid(w: int, h: int) -> RefCounted:
	var data := PackedInt32Array()
	data.resize(4 * w * h)
	for y in range(h):
		for x in range(w):
			data[y * w + x] = 1
	var flags := PackedInt32Array()
	flags.resize(16)
	var col = MapCollision.new()
	col.setup(w, h, data, flags)
	return col


func _set_z0(col, x: int, y: int, tid: int) -> void:
	_set_tile(col, x, y, 0, tid)


func _set_tile(col, x: int, y: int, z: int, tid: int) -> void:
	var w: int = int(col.width)
	var h: int = int(col.height)
	var data: PackedInt32Array = col.data
	data[(z * h + y) * w + x] = tid
	col.data = data


func _block_cell(col, x: int, y: int) -> void:
	# Top layer decides passage first; empty z3 with flag 0 would ignore a z0 wall.
	_set_tile(col, x, y, 3, 2)
	_set_flag(col, 2, TileId.FLAG_DIRS)


func _set_flag(col, tid: int, flag: int) -> void:
	var flags: PackedInt32Array = col.flags
	if tid >= flags.size():
		flags.resize(tid + 1)
	flags[tid] = flag
	col.flags = flags


func _test_synthetic_8dir() -> void:
	var col = _open_grid(12, 12)
	assert(col.can_pass(2, 2, 3))
	assert(col.can_pass(2, 2, 9))
	var p: Array[Vector2i] = GridPath.find_path(col, Vector2i(1, 1), Vector2i(6, 6))
	print("diag path len=", p.size(), " -> ", p)
	assert(p.size() == 5)
	assert(p[p.size() - 1] == Vector2i(6, 6))
	var prev := Vector2i(1, 1)
	for step in p:
		var delta: Vector2i = step - prev
		assert(maxi(absi(delta.x), absi(delta.y)) == 1)
		var d: int = TileId.dir_from_vec(Vector2(delta))
		assert(col.can_pass(prev.x, prev.y, d))
		prev = step

	# Corner-cut: walls on both adjacent cells block the diagonal.
	_block_cell(col, 2, 1)
	_block_cell(col, 1, 2)
	col._astar = null
	assert(not col.can_pass(1, 1, 3))
	var cut: Array[Vector2i] = GridPath.find_path(col, Vector2i(1, 1), Vector2i(2, 2))
	assert(cut.is_empty() or cut.size() > 1 or cut[0] != Vector2i(2, 2))

	# One-sided wall still blocks (no squeeze through a corner).
	var col2 = _open_grid(8, 8)
	_block_cell(col2, 2, 1)
	assert(not col2.can_pass(1, 1, 3))

	# Occupancy on a corner cell blocks diagonal (matches try_move).
	var col3 = _open_grid(8, 8)
	col3.set_extra_blocked(2, 1, true)
	assert(not col3.can_pass(1, 1, 3))
	assert(col3.can_pass(1, 1, 2))

	# Snap uses Chebyshev; blocked goal still finds a neighbor.
	var blocked := Vector2i(4, 4)
	col3.set_extra_blocked(blocked.x, blocked.y, true)
	var near: Array[Vector2i] = GridPath.find_path_near(col3, Vector2i(1, 1), blocked, 6)
	assert(not near.is_empty())
	var last: Vector2i = near[near.size() - 1]
	assert(maxi(absi(last.x - blocked.x), absi(last.y - blocked.y)) <= 6)
	assert(last != blocked)

	var t0 := Time.get_ticks_usec()
	var big = _open_grid(64, 64)
	var longp: Array[Vector2i] = GridPath.find_path(big, Vector2i(1, 1), Vector2i(62, 62))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH 64 open 8-dir %.2f ms len=%d" % [ms, longp.size()])
	assert(longp.size() == 61)
	assert(ms < 80.0)


func _test_demo_map() -> void:
	var pack = TilemapPack.load_pack("res://demo_map")
	if pack == null or pack.collision == null:
		push_error("TEST FAIL: no collision")
		quit(1)
		return
	var col = pack.collision
	var spawn: Vector2i = col.find_spawn_near()
	print("spawn=", spawn, " size=", col.width, "x", col.height)

	var p0 = GridPath.find_path(col, spawn, spawn)
	assert(p0.is_empty())

	var found_goal: Vector2i = spawn
	for d in TileId.DIRS8:
		if col.can_pass(spawn.x, spawn.y, d):
			found_goal = spawn + TileId.dir_delta(d)
			break
	var p1 = GridPath.find_path(col, spawn, found_goal)
	print("neighbor path len=", p1.size(), " -> ", p1)
	assert(p1.size() == 1)
	assert(p1[0] == found_goal)

	# BFS farthest reachable (8-dir)
	var queue: Array[Vector2i] = [spawn]
	var visited: Dictionary = {spawn: true}
	var qi := 0
	var farthest: Vector2i = spawn
	var far_dist := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		var dist := maxi(absi(cur.x - spawn.x), absi(cur.y - spawn.y))
		if dist > far_dist:
			far_dist = dist
			farthest = cur
		for d2 in TileId.DIRS8:
			if not col.can_pass(cur.x, cur.y, d2):
				continue
			var n: Vector2i = cur + TileId.dir_delta(d2)
			if visited.has(n):
				continue
			visited[n] = true
			queue.append(n)
	var p2 = GridPath.find_path(col, spawn, farthest)
	print("farthest reachable=", farthest, " dist=", far_dist, " path len=", p2.size())
	assert(not p2.is_empty())
	assert(p2[p2.size() - 1] == farthest)

	# Path must respect can_pass at each 8-dir step
	var prev := spawn
	for step in p2:
		var delta: Vector2i = step - prev
		assert(maxi(absi(delta.x), absi(delta.y)) == 1)
		var d3: int = TileId.dir_from_vec(Vector2(delta))
		assert(col.can_pass(prev.x, prev.y, d3))
		prev = step

	# Unreachable void far away -> empty within snap
	var void_cell := Vector2i(0, 0)
	var p3 = GridPath.find_path_near(col, spawn, void_cell, 6)
	print("void path_near len=", p3.size())
	assert(p3.is_empty())

	# Blocked furniture near spawn -> snap to nearby walkable
	var blocked: Vector2i = spawn
	var got := false
	for r in range(1, 10):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2i(spawn.x + dx, spawn.y + dy)
				if col.is_valid(c.x, c.y) and not col.is_landable(c.x, c.y):
					blocked = c
					got = true
					break
			if got:
				break
		if got:
			break
	if got:
		var p4 = GridPath.find_path_near(col, spawn, blocked, 6)
		print("blocked=", blocked, " snapped len=", p4.size())
		assert(not p4.is_empty())
		var last: Vector2i = p4[p4.size() - 1]
		assert(col.is_landable(last.x, last.y))
		assert(maxi(absi(last.x - blocked.x), absi(last.y - blocked.y)) <= 6)
