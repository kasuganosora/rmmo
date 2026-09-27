extends SceneTree
## Subsystem check on the Axel whitebox. This file is not the shipped map.

const N := 256


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var failed := 0
	print("test_world3d_town: reading Axel256")
	var built: Dictionary = load("res://scripts/world3d/town_whitebox.gd").build()
	if not bool(built.get("ok", false)):
		print("test_world3d_town: FAIL %s" % str(built.get("error", "build")))
		quit(1)
		return
	var counts: Dictionary = built.get("counts", {})
	print("test_world3d_town: boxes %s" % str(counts))
	var paths = load("res://scripts/world3d/map_paths.gd")
	var town_dir: String = paths.cache_directory("axel_town")
	if town_dir == "":
		print("test_world3d_town: FAIL no external cache")
		quit(1)
		return
	var map := town_dir.path_join("map.gltf")
	var err: Error = built.doc.save(map)
	failed += _expect(err == OK, "save whitebox %s" % err)
	if err != OK:
		quit(1)
		return
	var land: PackedByteArray = built.land
	var goals: Dictionary = built.goals
	var spawn: Vector3 = built.spawn
	var session = root.get_node("GameSession")
	session.world3d_map_path = map
	session.world3d_spawn = spawn
	session.editor_return = false
	session.world3d_switches = {}
	change_scene_to_file("res://scenes/world_3d.tscn")
	var world: Node = null
	for _i in 600:
		await process_frame
		world = current_scene
		if world != null and world.get("_player") != null and not world._player.input_locked and str(world._map_path) != "":
			break
	if world == null or world.get("_player") == null:
		print("test_world3d_town: FAIL town scene did not boot")
		quit(1)
		return
	for _i in 8:
		await process_frame
	var feet: float = world._player.global_position.y
	failed += _expect(feet > 0.35 and feet < 1.3, "spawn stands on the street (y=%s)" % feet)
	failed += await _check_lights(world, land, int(counts.get("lamp", 0)))
	var start := Vector2i(int(floor(spawn.x)), int(floor(spawn.z)))
	failed += await _route(world, land, start, goals.get("gate", Vector2i(-1, -1)), "south gate")
	failed += await _route(world, land, start, goals.get("bridge", Vector2i(-1, -1)), "bridge")
	failed += await _route(world, land, start, goals.get("church", Vector2i(-1, -1)), "church")
	failed += await _blocked(world, land, start, goals.get("house", Vector2i(-1, -1)), "house")
	failed += await _blocked(world, land, _neighbor(land, goals.get("wall", Vector2i(-1, -1))), goals.get("wall", Vector2i(-1, -1)), "wall")
	failed += await _blocked(world, land, _neighbor(land, goals.get("water", Vector2i(-1, -1))), goals.get("water", Vector2i(-1, -1)), "water")
	Engine.time_scale = 1.0
	if current_scene != null:
		current_scene.free()
	print("test_world3d_town: %s" % ("FAIL %d" % failed if failed else "PASS"))
	quit(1 if failed else 0)


func _check_lights(world: Node, land: PackedByteArray, expected: int) -> int:
	var failed := 0
	var lamps: Array = []
	for child in world.get_children():
		if child is OmniLight3D:
			lamps.append(child)
	failed += _expect(lamps.size() == expected and expected > 100, "day scene has %d street lamps, expected %d" % [lamps.size(), expected])
	failed += _expect(world._sun != null and world._sun.light_energy > 0.5, "day sun is on")
	var lit := 0
	for lamp in lamps:
		if (lamp as OmniLight3D).light_energy > 0.01:
			lit += 1
	failed += _expect(lit == 0, "day turns street lamps off (%d still on)" % lit)
	world.set_night(true)
	failed += _expect(world._sun.light_energy < 0.1, "night sun dims")
	var weak := 0
	var uncovered := 0
	for lamp in lamps:
		var light := lamp as OmniLight3D
		if light.light_energy < 1.0 or light.omni_range < 8.0:
			weak += 1
		if not _lamp_covers_road(land, light):
			uncovered += 1
	failed += _expect(weak == 0, "night lamps stay bright (%d weak)" % weak)
	failed += _expect(uncovered == 0, "every lamp reaches a walkable cell (%d do not)" % uncovered)
	world.set_night(false)
	failed += _expect(world._sun.light_energy > 0.5, "day returns")
	return failed


func _lamp_covers_road(land: PackedByteArray, light: OmniLight3D) -> bool:
	var cx := int(floor(light.position.x))
	var cz := int(floor(light.position.z))
	for y in range(cz - 3, cz + 4):
		for x in range(cx - 3, cx + 4):
			if x < 0 or y < 0 or x >= N or y >= N or land[y * N + x] == 0:
				continue
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(light.position.x, light.position.z)) <= light.omni_range:
				return true
	return false


func _route(world: Node, land: PackedByteArray, start: Vector2i, goal: Vector2i, label: String) -> int:
	if goal.x < 0:
		return _expect(false, "%s goal missing" % label)
	var path := _bfs(land, start, goal)
	if path.is_empty():
		return _expect(false, "2D town has no walk from %s to %s (%s)" % [start, goal, label])
	print("test_world3d_town: walking %s (%d cells)" % [label, path.size()])
	world._player.global_position = Vector3(start.x + 0.5, 0.95, start.y + 0.5)
	world._player.velocity = Vector3.ZERO
	for _i in 15:
		await process_frame
	var err := await _follow(world, land, path)
	return _expect(err == "", "%s: %s" % [label, err if err != "" else "arrived"])


func _blocked(world: Node, land: PackedByteArray, start: Vector2i, into: Vector2i, label: String) -> int:
	if start.x < 0 or into.x < 0:
		return _expect(false, "%s sample missing" % label)
	var player = world._player
	player.input_locked = true
	player.global_position = Vector3(start.x + 0.5, 1.2, start.y + 0.5)
	world._apply_residency()
	await physics_frame
	player.move_and_collide(Vector3(0, -2.0, 0))
	var motion := Vector3(into.x - start.x, 0, into.y - start.y)
	if motion.length() > 1.2:
		motion = motion.normalized() * 1.2
	player.move_and_collide(motion)
	var cell := _cell(player.global_position)
	var entered: bool = land[cell.y * N + cell.x] == 0 or player.global_position.y < 0.15
	return _expect(not entered, "character stays out of the %s (at %s y=%.2f)" % [label, cell, player.global_position.y])


func _follow(world: Node, land: PackedByteArray, path: Array) -> String:
	var player = world._player
	player.input_locked = true
	var seen := Vector2i(-999, -999)
	for i in range(path.size() - 1):
		var a: Vector2i = path[i]
		var b: Vector2i = path[i + 1]
		player.global_position = Vector3(a.x + 0.5, 1.2, a.y + 0.5)
		player.velocity = Vector3.ZERO
		var chunk := Vector2i(int(a.x / 32), int(a.y / 32))
		if chunk != seen:
			world._apply_residency()
			await physics_frame
			seen = chunk
			player.global_position = Vector3(a.x + 0.5, 1.2, a.y + 0.5)
		player.move_and_collide(Vector3(0, -2.0, 0))
		if player.global_position.y < 0.2:
			return "no floor at %s (y=%.2f)" % [a, player.global_position.y]
		var before: Vector3 = player.global_position
		player.move_and_collide(Vector3(b.x - a.x, 0.0, b.y - a.y))
		var after: Vector3 = player.global_position
		var cell := _cell(after)
		if not _open_cell(land, cell):
			return "left the walkable town at %s between %s and %s" % [cell, a, b]
		if after.y < 0.2 or after.y > 1.6:
			return "height %.2f at %s" % [after.y, cell]
		var gained := Vector2(before.x, before.z).distance_to(Vector2(b.x + 0.5, b.y + 0.5)) - Vector2(after.x, after.z).distance_to(Vector2(b.x + 0.5, b.y + 0.5))
		if gained < 0.45:
			return "blocked at %s going to %s" % [a, b]
	return ""


func _bfs(land: PackedByteArray, start: Vector2i, goal: Vector2i) -> Array:
	if not _open_cell(land, start) or not _open_cell(land, goal):
		return []
	var prev := PackedInt32Array()
	prev.resize(N * N)
	prev.fill(-1)
	var queue: Array = [start]
	prev[start.y * N + start.x] = start.y * N + start.x
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		if at == goal:
			break
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = at + step
			if not _open_cell(land, nxt):
				continue
			var ni := nxt.y * N + nxt.x
			if prev[ni] != -1:
				continue
			prev[ni] = at.y * N + at.x
			queue.append(nxt)
	if prev[goal.y * N + goal.x] == -1:
		return []
	var path: Array = []
	var cur := goal
	while true:
		path.append(cur)
		if cur == start:
			break
		var parent: int = prev[cur.y * N + cur.x]
		cur = Vector2i(parent % N, int(parent / N))
	path.reverse()
	return path


func _neighbor(land: PackedByteArray, blocked: Vector2i) -> Vector2i:
	if blocked.x < 0:
		return Vector2i(-1, -1)
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nxt: Vector2i = blocked + step
		if _open_cell(land, nxt):
			return nxt
	return Vector2i(-1, -1)


func _open_cell(land: PackedByteArray, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < N and cell.y < N and land[cell.y * N + cell.x] != 0


func _cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.z)))


func _expect(ok: bool, label: String) -> int:
	if not ok:
		print("test_world3d_town: FAIL %s" % label)
		return 1
	return 0
