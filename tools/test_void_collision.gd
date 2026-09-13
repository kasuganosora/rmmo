extends SceneTree
## Headless checks: void edge collision + indoor floors stay walkable.

const TilemapPack = preload("res://scripts/map/tilemap_pack.gd")
const GridPath = preload("res://scripts/map/grid_path.gd")
const TileId = preload("res://scripts/map/tile_id.gd")


func _fail(msg: String) -> void:
	push_error("TEST FAIL: " + msg)
	quit(1)


func _init() -> void:
	_check_street()
	_check_indoor("res://demo_map", 7472)
	_check_indoor("res://bath_map", 5888)
	print("ALL VOID COLLISION TESTS OK")
	quit(0)


func _check_street() -> void:
	var pack = TilemapPack.load_pack("res://street_map")
	if pack == null or pack.collision == null:
		_fail("street_map pack")
		return
	var col = pack.collision
	if int(col.void_tile_id) != 3296:
		_fail("street void_tile_id=%s want 3296" % str(col.void_tile_id))
		return
	if col.is_landable(68, 23):
		_fail("street (68,23) must not be landable")
		return
	if col.is_landable(70, 23):
		_fail("street (70,23) empty must not be landable")
		return
	if not col.is_landable(67, 23):
		_fail("street (67,23) road must stay landable")
		return
	# Cannot walk east into void strip.
	if col.can_pass(67, 23, 6):
		_fail("street can_pass into (68,23)")
		return
	# Out of bounds blocked.
	if col.can_pass(74, 23, 6):
		_fail("street OOB east must block")
		return
	# Escape if already in void.
	if not col.can_pass(68, 23, 4):
		_fail("street escape from void west")
		return
	# Pathfinding must not route into void.
	var path: Array[Vector2i] = GridPath.find_path(col, Vector2i(67, 23), Vector2i(68, 23))
	if not path.is_empty():
		_fail("street AStar path into void")
		return
	var near: Array[Vector2i] = GridPath.find_path_near(col, Vector2i(67, 23), Vector2i(70, 23), 6)
	for step in near:
		if col.is_void_cell(step.x, step.y):
			_fail("street path_near entered void %s" % str(step))
			return
	print("street_map void OK void_tile_id=", col.void_tile_id)


func _check_indoor(pack_path: String, expect_void: int) -> void:
	var pack = TilemapPack.load_pack(pack_path)
	if pack == null or pack.collision == null:
		_fail(pack_path + " pack")
		return
	var col = pack.collision
	if int(col.void_tile_id) != expect_void:
		_fail("%s void_tile_id=%s want %d" % [pack_path, str(col.void_tile_id), expect_void])
		return
	var spawn: Vector2i = col.find_spawn_near()
	if not col.is_landable(spawn.x, spawn.y):
		_fail("%s spawn not landable %s" % [pack_path, str(spawn)])
		return
	if col.is_void_cell(spawn.x, spawn.y):
		_fail("%s spawn in void" % pack_path)
		return
	# At least one neighbor passable on floors.
	var any_move := false
	for d in [2, 4, 6, 8]:
		if col.can_pass(spawn.x, spawn.y, d):
			any_move = true
			break
	if not any_move:
		_fail("%s trapped at spawn %s" % [pack_path, str(spawn)])
		return
	# Void filler not landable.
	var void_checked := false
	for y in range(col.height):
		for x in range(col.width):
			if col.is_void_cell(x, y) and col.tile_id(x, y, 0) == expect_void:
				if col.is_landable(x, y):
					_fail("%s void filler landable at %d,%d" % [pack_path, x, y])
					return
				void_checked = true
				break
		if void_checked:
			break
	print(pack_path, " indoor OK spawn=", spawn, " void_tile_id=", col.void_tile_id)

