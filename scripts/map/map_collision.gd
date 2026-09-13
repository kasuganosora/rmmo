extends RefCounted
## Passage checks for tilemap packs (no events).
## Maintains an AStar2D graph (tile edges) with extra_blocked as disabled points.

const TileId = preload("res://scripts/map/tile_id.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")

var width: int = 0
var height: int = 0
var data: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
## Extra occupancy from NPCs etc. Key "x,y" -> true when blocked.
var extra_blocked: Dictionary = {}
## Outdoor / padding void filler tile (z0-only), e.g. demo 7472 / street 3296.
## Detected at setup; cells with only this tile (or fully empty) are impassable.
var void_tile_id: int = 0
## Optional MapExt (null/empty = MV-only).
var ext: RefCounted = null

## Native path graph: directed edges from tile passage; occupancy = disabled points.
var _astar: AStar2D = null


func setup(p_width: int, p_height: int, p_data: PackedInt32Array, p_flags: PackedInt32Array) -> void:
	width = p_width
	height = p_height
	data = p_data
	flags = p_flags
	extra_blocked.clear()
	_astar = null
	void_tile_id = _detect_void_tile_id()
	ext = null


func set_ext(p_ext: RefCounted) -> void:
	ext = p_ext


func clear_extra_blocked() -> void:
	if _astar != null:
		for key in extra_blocked.keys():
			var cell := _parse_extra_key(key)
			if cell.x >= 0:
				_astar.set_point_disabled(_cell_id(cell.x, cell.y), false)
	extra_blocked.clear()


func set_extra_blocked(x: int, y: int, blocked: bool = true) -> void:
	var key := "%d,%d" % [x, y]
	if blocked:
		extra_blocked[key] = true
	elif extra_blocked.has(key):
		extra_blocked.erase(key)
	if _astar != null and is_valid(x, y):
		_astar.set_point_disabled(_cell_id(x, y), blocked)


func is_extra_blocked(x: int, y: int) -> bool:
	return extra_blocked.has("%d,%d" % [x, y])


func apply_npc_blocks(npcs: Array) -> void:
	## Block cells for NPCs that are not through.
	for item in npcs:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = item
		if bool(n.get("through", false)):
			continue
		var cell_v: Variant = n.get("cell", {})
		if typeof(cell_v) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = cell_v
		set_extra_blocked(int(c.get("x", 0)), int(c.get("y", 0)), true)


func is_valid(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func tile_id(x: int, y: int, z: int) -> int:
	if not is_valid(x, y):
		return 0
	if z >= MapExt.EXT_Z_BASE:
		if ext != null and ext.has_method("tile_z"):
			return int(ext.tile_z(z, x, y))
		return 0
	var idx: int = (z * height + y) * width + x
	if idx < 0 or idx >= data.size():
		return 0
	return int(data[idx])


func ext_tile(id: String, x: int, y: int) -> int:
	if ext == null or not ext.has_method("tile"):
		return 0
	return int(ext.tile(id, x, y))


func meta_at(x: int, y: int) -> int:
	return ext_tile("meta", x, y)


func settings_at(x: int, y: int) -> int:
	return ext_tile("settings", x, y)


func layered_tiles(x: int, y: int) -> Array[int]:
	var tiles: Array[int] = []
	# Order z=3,2,1,0 (shadow bits still indexed into flags)
	for i in range(4):
		tiles.append(tile_id(x, y, 3 - i))
	return tiles


func flag_of(tile: int) -> int:
	if tile < 0 or tile >= flags.size():
		return 0
	return int(flags[tile])


## True for out-of-content void: fully empty layers, or z0-only detected filler tile.
## Matches MapField paint skip (black Void / clear color).
func is_void_cell(x: int, y: int) -> bool:
	if not is_valid(x, y):
		return true
	var t0: int = tile_id(x, y, 0)
	var t1: int = tile_id(x, y, 1)
	var t2: int = tile_id(x, y, 2)
	var t3: int = tile_id(x, y, 3)
	if t0 == 0 and t1 == 0 and t2 == 0 and t3 == 0:
		return true
	if void_tile_id > 0 and t0 == void_tile_id and t1 == 0 and t2 == 0 and t3 == 0:
		return true
	return false


func _is_empty_cell(x: int, y: int) -> bool:
	if not is_valid(x, y):
		return false
	return (
		tile_id(x, y, 0) == 0
		and tile_id(x, y, 1) == 0
		and tile_id(x, y, 2) == 0
		and tile_id(x, y, 3) == 0
	)


func _detect_void_tile_id() -> int:
	## Prefer MV-style outdoor padding tile used as black void filler.
	## 1) Most common z0-only tile on the map border (demo/bath).
	## 2) Else most common z0-only tile adjacent to fully-empty cells (street strip).
	if width <= 0 or height <= 0:
		return 0
	var border_counts: Dictionary = {}
	for y in range(height):
		for x in range(width):
			if x != 0 and y != 0 and x != width - 1 and y != height - 1:
				continue
			var t0: int = tile_id(x, y, 0)
			var t1: int = tile_id(x, y, 1)
			var t2: int = tile_id(x, y, 2)
			var t3: int = tile_id(x, y, 3)
			if t0 <= 0:
				continue
			if t1 != 0 or t2 != 0 or t3 != 0:
				continue
			border_counts[t0] = int(border_counts.get(t0, 0)) + 1
	var best_id: int = 0
	var best_n: int = 0
	for k in border_counts.keys():
		var n: int = int(border_counts[k])
		if n > best_n:
			best_n = n
			best_id = int(k)
	var border_thresh: int = maxi(4, (width + height) / 2)
	if best_n >= border_thresh and not _tile_is_common_ground(best_id):
		return best_id

	# Street-like maps: empty columns at the edge, void filler strip just inside.
	var adj_counts: Dictionary = {}
	for y in range(height):
		for x in range(width):
			var t0b: int = tile_id(x, y, 0)
			var t1b: int = tile_id(x, y, 1)
			var t2b: int = tile_id(x, y, 2)
			var t3b: int = tile_id(x, y, 3)
			if t0b <= 0:
				continue
			if t1b != 0 or t2b != 0 or t3b != 0:
				continue
			var touches_empty: bool = false
			for d in [2, 4, 6, 8]:
				var delta: Vector2i = TileId.dir_delta(d)
				var nx: int = x + delta.x
				var ny: int = y + delta.y
				if _is_empty_cell(nx, ny):
					touches_empty = true
					break
			if not touches_empty:
				continue
			adj_counts[t0b] = int(adj_counts.get(t0b, 0)) + 1
	best_id = 0
	best_n = 0
	var second_n: int = 0
	for k2 in adj_counts.keys():
		var n2: int = int(adj_counts[k2])
		if n2 > best_n:
			second_n = best_n
			best_n = n2
			best_id = int(k2)
		elif n2 > second_n:
			second_n = n2
	var adj_thresh: int = maxi(4, (width + height) / 4)
	# Require a clear winner so road tiles that merely touch empty are not picked.
	if best_n >= adj_thresh and best_n >= second_n * 2 and not _tile_is_common_ground(best_id):
		return best_id
	return 0


func _tile_is_common_ground(tid: int) -> bool:
	## Don't treat the map's actual floor as outdoor void padding.
	if tid <= 0 or width <= 0 or height <= 0:
		return false
	var n := 0
	var total: int = width * height
	for y in range(height):
		for x in range(width):
			if tile_id(x, y, 0) == tid:
				n += 1
	return n * 5 >= total


func check_passage(x: int, y: int, bit: int) -> bool:
	if not is_valid(x, y):
		return false
	# Void filler / empty ground: never landable (MV empty returns false; filler matches paint).
	if is_void_cell(x, y):
		return false
	var meta: int = meta_at(x, y)
	if (meta & MapExt.META_FORCE_BLOCK) != 0:
		return false
	if (meta & MapExt.META_FORCE_PASS) != 0:
		return true
	if _ext_water_blocks(x, y, meta):
		return false
	for tile in layered_tiles(x, y):
		var flag: int = flag_of(tile)
		if (flag & 0x10) != 0:
			continue
		if (flag & bit) == 0:
			return true
		if (flag & bit) == bit:
			return false
	return false


func _ext_water_blocks(x: int, y: int, meta: int) -> bool:
	if (meta & MapExt.META_WATER) != 0:
		return true
	if ext != null and bool(ext.get("water_through")):
		return false
	if ext != null and ext.has_method("has_tiles") and ext.has_tiles("water"):
		return ext_tile("water", x, y) > 0
	return false


func is_passable(x: int, y: int, d: int) -> bool:
	var bit: int = (1 << (int(d / 2) - 1)) & 0x0f
	return check_passage(x, y, bit)


func can_pass(x: int, y: int, d: int) -> bool:
	var delta: Vector2i = TileId.dir_delta(d)
	var x2: int = x + delta.x
	var y2: int = y + delta.y
	if not is_valid(x2, y2):
		return false
	if is_extra_blocked(x2, y2):
		return false
	# Never enter void (empty or filler). Allow escaping an already-void cell onto ground.
	if is_void_cell(x2, y2):
		return false
	var rev: int = TileId.reverse_dir(d)
	if is_void_cell(x, y):
		return is_passable(x2, y2, rev)
	return is_passable(x, y, d) and is_passable(x2, y2, rev)


## Tile-only passage (ignores extra_blocked). Used to build the static edge graph.
func can_pass_tiles(x: int, y: int, d: int) -> bool:
	var delta: Vector2i = TileId.dir_delta(d)
	var x2: int = x + delta.x
	var y2: int = y + delta.y
	if not is_valid(x2, y2):
		return false
	if is_void_cell(x2, y2):
		return false
	var rev: int = TileId.reverse_dir(d)
	if is_void_cell(x, y):
		return is_passable(x2, y2, rev)
	return is_passable(x, y, d) and is_passable(x2, y2, rev)


func is_landable(x: int, y: int) -> bool:
	if not is_valid(x, y):
		return false
	if is_void_cell(x, y):
		return false
	if is_extra_blocked(x, y):
		return false
	for d in [2, 4, 6, 8]:
		if is_passable(x, y, d):
			return true
	return false


func find_spawn_near(cx: int = -1, cy: int = -1) -> Vector2i:
	if width <= 0 or height <= 0:
		return Vector2i.ZERO
	if cx < 0:
		cx = width / 2
	if cy < 0:
		cy = height / 2
	var max_r: int = maxi(width, height)
	for radius in range(0, max_r):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if radius > 0 and absi(dx) != radius and absi(dy) != radius:
					continue
				var x: int = cx + dx
				var y: int = cy + dy
				if is_landable(x, y):
					return Vector2i(x, y)
	return Vector2i(clampi(cx, 0, width - 1), clampi(cy, 0, height - 1))


func _cell_id(x: int, y: int) -> int:
	return y * width + x


func _parse_extra_key(key: Variant) -> Vector2i:
	var s := str(key)
	var parts: PackedStringArray = s.split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


func ensure_path_graph() -> AStar2D:
	if _astar != null:
		return _astar
	_rebuild_path_graph()
	return _astar


func _rebuild_path_graph() -> void:
	_astar = AStar2D.new()
	if width <= 0 or height <= 0:
		return
	for y in range(height):
		for x in range(width):
			_astar.add_point(_cell_id(x, y), Vector2(x, y))
	for y in range(height):
		for x in range(width):
			var from_id: int = _cell_id(x, y)
			for d in [2, 4, 6, 8]:
				if not can_pass_tiles(x, y, d):
					continue
				var delta: Vector2i = TileId.dir_delta(d)
				var to_id: int = _cell_id(x + delta.x, y + delta.y)
				# Directed edge (RPG Maker one-way walls).
				if not _astar.are_points_connected(from_id, to_id, false):
					_astar.connect_points(from_id, to_id, false)
	for key in extra_blocked.keys():
		var cell := _parse_extra_key(key)
		if is_valid(cell.x, cell.y):
			_astar.set_point_disabled(_cell_id(cell.x, cell.y), true)


## Waypoints after start to goal (excludes start). Empty if none.
## Temporarily allows pathing from an occupied start cell (player standing there).
func find_astar_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not is_valid(start.x, start.y) or not is_valid(goal.x, goal.y):
		return empty
	if start == goal:
		return empty
	# Goals in void / empty padding are never standable.
	if is_void_cell(goal.x, goal.y):
		return empty
	var astar: AStar2D = ensure_path_graph()
	if astar == null:
		return empty
	var sid: int = _cell_id(start.x, start.y)
	var gid: int = _cell_id(goal.x, goal.y)
	if not astar.has_point(sid) or not astar.has_point(gid):
		return empty
	if astar.is_point_disabled(gid):
		return empty
	var start_was_disabled: bool = astar.is_point_disabled(sid)
	if start_was_disabled:
		astar.set_point_disabled(sid, false)
	var ids: PackedInt64Array = astar.get_id_path(sid, gid)
	if start_was_disabled:
		astar.set_point_disabled(sid, true)
	if ids.is_empty():
		return empty
	var path: Array[Vector2i] = []
	# Skip start (index 0); convert point ids back to cells.
	for i in range(1, ids.size()):
		var id: int = int(ids[i])
		var x: int = id % width
		var y: int = int(id / width)
		path.append(Vector2i(x, y))
	return path
