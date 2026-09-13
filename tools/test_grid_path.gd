extends SceneTree

const TilemapPack = preload("res://scripts/map/tilemap_pack.gd")
const GridPath = preload("res://scripts/map/grid_path.gd")
const TileId = preload("res://scripts/map/tile_id.gd")

func _init() -> void:
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
	for d in [2, 4, 6, 8]:
		if col.can_pass(spawn.x, spawn.y, d):
			found_goal = spawn + TileId.dir_delta(d)
			break
	var p1 = GridPath.find_path(col, spawn, found_goal)
	print("neighbor path len=", p1.size(), " -> ", p1)
	assert(p1.size() == 1)
	assert(p1[0] == found_goal)

	# BFS farthest reachable
	var queue: Array[Vector2i] = [spawn]
	var visited: Dictionary = {spawn: true}
	var qi := 0
	var farthest: Vector2i = spawn
	var far_dist := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		var dist := absi(cur.x - spawn.x) + absi(cur.y - spawn.y)
		if dist > far_dist:
			far_dist = dist
			farthest = cur
		for d2 in [2, 4, 6, 8]:
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

	# Path must respect can_pass at each step
	var prev := spawn
	for step in p2:
		var delta: Vector2i = step - prev
		assert(absi(delta.x) + absi(delta.y) == 1)
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
		assert(absi(last.x - blocked.x) + absi(last.y - blocked.y) <= 6)

	print("ALL PATH TESTS OK")
	quit(0)