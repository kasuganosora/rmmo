extends RefCounted
## Domain module: targeting geometry (range, AoE cells, facing, ground-cell resolve).

var ctrl
func _init(c):
	ctrl = c

func _in_range(npc_id: String, player_x: int, player_y: int, range_cells: int) -> bool:
	if range_cells <= 0:
		return true
	var cell: Vector2i = ctrl.stats.get_npc_cell(npc_id)
	if cell.x <= -9990:
		# Cell unknown: do not trust client — reject until register_npc / try_npc_move.
		return false
	var dist: int = maxi(absi(cell.x - player_x), absi(cell.y - player_y))
	return dist <= range_cells



func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))



func skill_target_mode(def: Dictionary) -> String:
	var m = str(def.get("target_mode", "")).strip_edges().to_lower()
	if m == "ground" or m == "unit" or m == "none" or m == "self":
		if m == "self":
			return "none"
		return m
	if bool(def.get("requires_target", false)):
		return "unit"
	return "none"



func _dir_delta(d: int) -> Vector2i:
	match d:
		1:
			return Vector2i(-1, 1)
		2:
			return Vector2i(0, 1)
		3:
			return Vector2i(1, 1)
		4:
			return Vector2i(-1, 0)
		6:
			return Vector2i(1, 0)
		7:
			return Vector2i(-1, -1)
		8:
			return Vector2i(0, -1)
		9:
			return Vector2i(1, -1)
		_:
			return Vector2i(0, 1)



func facing_toward(from: Vector2i, to: Vector2i) -> int:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	if dx == 0 and dy == 0:
		return 2
	var sx = 0
	if dx > 0:
		sx = 1
	elif dx < 0:
		sx = -1
	var sy = 0
	if dy > 0:
		sy = 1
	elif dy < 0:
		sy = -1
	if sx == -1 and sy == 1:
		return 1
	if sx == 0 and sy == 1:
		return 2
	if sx == 1 and sy == 1:
		return 3
	if sx == -1 and sy == 0:
		return 4
	if sx == 1 and sy == 0:
		return 6
	if sx == -1 and sy == -1:
		return 7
	if sx == 0 and sy == -1:
		return 8
	return 9



func cell_in_aoe(center: Vector2i, cell: Vector2i, radius: int, shape: String, facing: int = 2) -> bool:
	radius = maxi(radius, 0)
	var dx: int = cell.x - center.x
	var dy: int = cell.y - center.y
	var cheb: int = maxi(absi(dx), absi(dy))
	shape = shape.strip_edges().to_lower()
	match shape:
		"cross", "plus":
			return (dx == 0 or dy == 0) and cheb <= radius
		"line":
			var step: Vector2i = _dir_delta(facing)
			var p = center
			for i in range(radius + 1):
				if p == cell:
					return true
				p += step
			return false
		"cone":
			if cheb > radius:
				return false
			if cheb == 0:
				return true
			var fwd: Vector2i = _dir_delta(facing)
			var f = Vector2(float(fwd.x), float(fwd.y))
			if f.length_squared() < 0.0001:
				return true
			f = f.normalized()
			var to = Vector2(float(dx), float(dy)).normalized()
			return f.dot(to) >= cos(deg_to_rad(60.0))
		_:
			return cheb <= radius



func aoe_cells(center: Vector2i, radius: int, shape: String, facing: int = 2) -> Array:
	var out: Array = []
	radius = maxi(radius, 0)
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var c = Vector2i(x, y)
			if cell_in_aoe(center, c, radius, shape, facing):
				out.append(c)
	return out



func _cell_in_range(from: Vector2i, to: Vector2i, range_cells: int) -> bool:
	if range_cells <= 0:
		return true
	return _chebyshev(from, to) <= range_cells



func _resolve_ground_cell(
	def: Dictionary,
	target_npc_id: String,
	player_x: int,
	player_y: int,
	ground_x: int,
	ground_y: int
) -> Vector2i:
	var mode = skill_target_mode(def)
	if mode == "ground":
		if ground_x > -9990 and ground_y > -9990:
			return Vector2i(ground_x, ground_y)
		if not target_npc_id.is_empty():
			var tc: Vector2i = ctrl.stats.get_npc_cell(target_npc_id)
			if tc.x > -9990:
				return tc
		return Vector2i(-9999, -9999)
	if bool(def.get("requires_target", false)) and not target_npc_id.is_empty():
		var uc: Vector2i = ctrl.stats.get_npc_cell(target_npc_id)
		if uc.x > -9990:
			return uc
	return Vector2i(player_x, player_y)



func _collect_aoe_hostiles(
	center: Vector2i,
	radius: int,
	max_targets: int,
	shape: String = "circle",
	facing: int = 2
) -> Array:
	radius = maxi(radius, 0)
	max_targets = maxi(max_targets, 1)
	var scored: Array = []
	for npc_id_v in ctrl.stats.npcs.keys():
		var npc_id = str(npc_id_v)
		var st: Dictionary = ctrl.stats.npcs[npc_id]
		if int(st.get("hp", 0)) <= 0:
			continue
		if not bool(st.get("hostile", false)):
			continue
		var cell: Vector2i = ctrl.stats.get_npc_cell(npc_id)
		if cell.x <= -9990:
			continue
		if not cell_in_aoe(center, cell, radius, shape, facing):
			continue
		scored.append({"id": npc_id, "dist": _chebyshev(center, cell)})
	scored.sort_custom(func(a, b): return int(a.get("dist", 0)) < int(b.get("dist", 0)))
	var out: Array = []
	for i in range(mini(scored.size(), max_targets)):
		out.append(str(scored[i]["id"]))
	return out


