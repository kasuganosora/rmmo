extends SceneTree
## 500 wandering people on the Axel check whitebox. Far ones stay out of the scene.

const GUILD := Vector3(112.5, 0.95, 119.5)
const GATE := Vector3(103.5, 0.95, 245.5)
const DT := 1.0 / 60.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var paths = load("res://scripts/world3d/map_paths.gd")
	var town_dir: String = paths.cache_directory("axel_town")
	var map := town_dir.path_join("map.gltf") if town_dir != "" else ""
	if map == "" or not FileAccess.file_exists(map):
		print("test_world3d_npc_stress: FAIL whitebox glTF missing")
		quit(1)
		return
	var session = root.get_node("GameSession")
	session.world3d_map_path = map
	session.world3d_spawn = GUILD
	session.editor_return = false
	change_scene_to_file("res://scenes/world_3d.tscn")
	var world: Node = null
	for _i in 600:
		await process_frame
		world = current_scene
		if world != null and world.get("_player") != null and not world._player.input_locked:
			break
	if world == null or world.get("_player") == null:
		print("test_world3d_npc_stress: FAIL town did not boot")
		quit(1)
		return
	var land := _walkable()
	var crowd = load("res://scripts/world3d/npc_crowd.gd").new()
	crowd.setup(land, 500, 1000)
	var failed := 0
	var guild: Dictionary = _soak(world, crowd, GUILD, 360)
	failed += _expect(int(guild["outside_min"]) > 300, "guild keeps most of the thousand outside the loaded ring")
	failed += _expect(int(guild["active_min"]) > 80, "guild still simulates the people inside the ring")
	failed += _expect(int(guild["visible_max"]) > 0 and int(guild["visible_max"]) < int(guild["active_max"]), "some inside the ring are outside the view")
	failed += _expect(int(guild["body_leaks"]) == 0, "people outside the ring have no body")
	failed += _expect(int(guild["off_road"]) == 0, "nobody walks onto blocked ground")
	world._player.global_position = GATE
	world._apply_residency()
	var gate: Dictionary = _soak(world, crowd, GATE, 180)
	failed += _expect(int(gate["outside_min"]) > 300 and int(gate["active_min"]) > 40, "the gate ring is a different loaded set")
	failed += _expect(int(gate["body_leaks"]) == 0 and int(gate["off_road"]) == 0, "gate crowd stays on walkable ground and out of unloaded chunks")
	var guild_sum: int = crowd.checksum(GUILD)
	var gate_sum: int = crowd.checksum(GATE)
	failed += _expect(guild_sum > 0 and gate_sum > 0 and guild_sum != gate_sum, "the loaded people change when the view moves")
	_print_phase("guild", guild)
	_print_phase("gate", gate)
	print("npcs=1000 guild_checksum=%d gate_checksum=%d" % [guild_sum, gate_sum])
	print("test_world3d_npc_stress: %s" % ("FAIL %d" % failed if failed else "PASS"))
	crowd.release()
	world.free()
	quit(1 if failed else 0)


func _soak(world: Node, crowd, origin: Vector3, ticks: int) -> Dictionary:
	world._player.global_position = origin
	world._apply_residency()
	var samples: Array = []
	var active_min := 9999
	var active_max := 0
	var active_sum := 0
	var visible_max := 0
	var outside_min := 9999
	var spawned := 0
	var freed := 0
	var leaks := 0
	var off := 0
	for _i in ticks:
		var started := Time.get_ticks_usec()
		world._apply_residency()
		var row: Dictionary = crowd.tick(world, world._player.global_position, DT)
		samples.append(int(Time.get_ticks_usec() - started))
		var active := int(row["active"])
		var outside := int(row["outside"])
		active_min = mini(active_min, active)
		active_max = maxi(active_max, active)
		active_sum += active
		visible_max = maxi(visible_max, int(row["visible"]))
		outside_min = mini(outside_min, outside)
		spawned += int(row["spawned"])
		freed += int(row["freed"])
		if crowd.body_count() != active:
			leaks += 1
		off = maxi(off, crowd.off_road())
	samples.sort()
	return {
		"ticks": ticks,
		"active_min": active_min,
		"active_max": active_max,
		"active_mean": int(active_sum / ticks),
		"visible_max": visible_max,
		"outside_min": outside_min,
		"spawned": spawned,
		"freed": freed,
		"body_leaks": leaks,
		"off_road": off,
		"mean_us": _at(samples, 0.5, true),
		"p50_us": _at(samples, 0.50, false),
		"p95_us": _at(samples, 0.95, false),
		"max_us": samples[samples.size() - 1],
	}


func _walkable() -> PackedByteArray:
	var pack = load("res://scripts/map/tilemap_pack.gd").load_pack("user://content/packs/default", "Axel256")
	var col = pack.collision
	var land := PackedByteArray()
	land.resize(256 * 256)
	for y in 256:
		for x in 256:
			land[y * 256 + x] = 1 if col.is_landable(x, y) else 0
	return land


func _at(samples: Array, fraction: float, mean: bool) -> int:
	if mean:
		var total := 0
		for sample in samples:
			total += int(sample)
		return int(total / samples.size())
	var index := int(float(samples.size() - 1) * fraction)
	return int(samples[index])


func _print_phase(label: String, row: Dictionary) -> void:
	print("%s ticks=%d active=%d..%d mean=%d visible_max=%d outside_min=%d spawned=%d freed=%d mean_us=%d p50_us=%d p95_us=%d max_us=%d" % [label, int(row["ticks"]), int(row["active_min"]), int(row["active_max"]), int(row["active_mean"]), int(row["visible_max"]), int(row["outside_min"]), int(row["spawned"]), int(row["freed"]), int(row["mean_us"]), int(row["p50_us"]), int(row["p95_us"]), int(row["max_us"])])


func _expect(ok: bool, label: String) -> int:
	if not ok:
		print("test_world3d_npc_stress: FAIL %s" % label)
		return 1
	return 0
