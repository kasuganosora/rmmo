extends SceneTree
## Chunk residency on the Axel check whitebox. Not a shipped-map test.

const Stream = preload("res://scripts/world3d/world_stream.gd")
const GUILD := Vector3(112.5, 0.95, 119.5)
const GATE := Vector3(103.5, 0.95, 245.5)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var paths = load("res://scripts/world3d/map_paths.gd")
	var town_dir: String = paths.cache_directory("axel_town")
	var map := town_dir.path_join("map.gltf") if town_dir != "" else ""
	if map == "" or not FileAccess.file_exists(map):
		print("test_world3d_stream: FAIL whitebox glTF missing")
		quit(1)
		return
	var session = root.get_node("GameSession")
	session.world3d_map_path = map
	session.world3d_spawn = GUILD
	session.editor_return = false
	var started := Time.get_ticks_msec()
	change_scene_to_file("res://scenes/world_3d.tscn")
	var world: Node = null
	for _i in 600:
		await process_frame
		world = current_scene
		if world != null and world.get("_player") != null and not world._player.input_locked:
			break
	var enter_ms := Time.get_ticks_msec() - started
	if world == null or world.get("_map_root") == null or world.get("_player") == null:
		print("test_world3d_stream: FAIL town did not boot")
		quit(1)
		return
	var failed := 0
	var guild := _measure(world, "guild")
	failed += _expect(int(guild["library"]) > 1000, "library keeps the whole check map")
	failed += _expect(int(guild["meshes"]) < int(guild["library"]) / 2, "spawn keeps under half the meshes")
	failed += _expect(int(guild["bodies"]) < int(guild["library"]) / 2, "spawn keeps under half the bodies")
	failed += _expect(int(guild["visible"]) > 0 and int(guild["hidden"]) == 0, "visuals stay inside the draw ring")
	failed += _expect(int(guild["bodies"]) > int(guild["visible"]), "the collision ring keeps bodies without visuals")
	failed += _expect(_resident_bounds(world), "each loaded object overlaps its draw or collision ring")
	var library: Array = world._map_root.get_meta(&"stream_library", [])
	var near_id := _uuid_in_chunk(library, Stream.chunk_key(GUILD))
	var far_id := _uuid_in_chunk(library, Stream.chunk_key(GATE))
	failed += _expect(near_id != "" and far_id != "", "guild and south-gate chunks both exist in the library")
	failed += _expect(world._map_root.get_node_or_null(near_id) != null, "guild chunk is instantiated")
	failed += _expect(world._map_root.get_node_or_null(far_id) == null and world.get_node_or_null(far_id + "_body") == null, "south gate stays out of the guild ring")
	var steady := _time_syncs(world, 20)
	world._player.global_position = GATE
	var move_us := _time_syncs(world, 1)
	var gate := _measure(world, "gate")
	failed += _expect(world._map_root.get_node_or_null(far_id) != null, "walking to the gate instantiates that chunk")
	failed += _expect(world._map_root.get_node_or_null(near_id) == null and world.get_node_or_null(near_id + "_body") == null, "leaving the guild drops that chunk")
	failed += _expect(int(gate["meshes"]) < int(gate["library"]) / 2, "gate residency stays under half the meshes")
	_print_row("enter_ms", enter_ms)
	_print_row("guild", guild)
	_print_row("gate", gate)
	var paced := _paced_step(world)
	failed += _expect(int(paced["steps"]) < 160, "one chunk of preloading finishes within a short walk")
	failed += _expect(int(paced["max_us"]) < 16000, "a gameplay frame no longer rebuilds the whole ring")
	print("steady_sync_us=%d" % steady)
	print("move_sync_us=%d" % move_us)
	print("paced_steps=%d paced_max_us=%d" % [int(paced["steps"]), int(paced["max_us"])])
	print("lamps=%d lamps_are_not_chunked=%s" % [int(guild["lamps"]), str(int(guild["lamps"]) == int(gate["lamps"]) and int(guild["lamps"]) > 100)])
	print("test_world3d_stream: %s" % ("FAIL %d" % failed if failed else "PASS"))
	world.free()
	quit(1 if failed else 0)


func _measure(world: Node, _label: String) -> Dictionary:
	var map_root: Node = world._map_root
	var library: Array = map_root.get_meta(&"stream_library", [])
	var meshes := 0
	var visible := 0
	var live := {}
	var drawn := {}
	for child in map_root.get_children():
		if not (child is MeshInstance3D):
			continue
		meshes += 1
		var mesh := child as MeshInstance3D
		var key := Stream.chunk_key(mesh.global_position)
		live[key] = true
		if mesh.visible:
			visible += 1
			drawn[key] = true
	var bodies := 0
	var lamps := 0
	for child in world.get_children():
		if child is StaticBody3D:
			bodies += 1
		elif child is OmniLight3D:
			lamps += 1
	return {
		"library": library.size(),
		"meshes": meshes,
		"visible": visible,
		"hidden": meshes - visible,
		"bodies": bodies,
		"lamps": lamps,
		"chunks_live": live.size(),
		"chunks_drawn": drawn.size(),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"physics_bodies": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
	}


func _resident_bounds(world: Node) -> bool:
	var focus := Stream.chunk_key(world._player.global_position)
	var draw := Stream._ring_at(focus, Stream.RENDER_RADIUS)
	var solid := Stream._ring_at(focus, Stream.COLLISION_RADIUS)
	var map_root: Node = world._map_root
	var meshes: Dictionary = map_root.get_meta("stream_meshes", {})
	var bodies: Dictionary = map_root.get_meta("stream_bodies", {})
	for spec in map_root.get_meta("stream_library", []):
		if meshes.has(spec["uuid"]) and not Stream._overlaps(spec, draw):
			return false
		if bodies.has(spec["uuid"]) and not Stream._overlaps(spec, solid):
			return false
	return true


func _uuid_in_chunk(library: Array, wanted: Vector2i) -> String:
	for spec in library:
		var key: Variant = spec.get("chunk", null)
		if key is Vector2i and (key as Vector2i) == wanted:
			return str(spec.get("uuid", ""))
	return ""


func _paced_step(world: Node) -> Dictionary:
	world._player.global_position = GUILD
	world._apply_residency()
	world._player.global_position = Vector3(112.5, 0.95, 151.5)
	var max_us := 0
	var steps := 0
	var map_root: Node = world._map_root
	while steps < 160:
		var started := Time.get_ticks_usec()
		Stream.sync(map_root, world, world._player.global_position, Stream.FRAME_BUDGET)
		max_us = maxi(max_us, int(Time.get_ticks_usec() - started))
		steps += 1
		if _settled(map_root, world._player.global_position):
			break
	return {"steps": steps, "max_us": max_us}


func _settled(map_root: Node, origin: Vector3) -> bool:
	if not map_root.has_meta(&"stream_chunk"):
		return false
	var chunk: Variant = map_root.get_meta(&"stream_chunk")
	var jobs: Variant = map_root.get_meta(&"stream_jobs", [])
	return chunk is Vector2i and (chunk as Vector2i) == Stream.chunk_key(origin) and jobs is Array and (jobs as Array).is_empty()


func _time_syncs(world: Node, times: int) -> int:
	var started := Time.get_ticks_usec()
	for _i in times:
		world._apply_residency()
	return int((Time.get_ticks_usec() - started) / times)


func _print_row(label: String, row) -> void:
	if row is Dictionary:
		var item: Dictionary = row
		print("%s library=%d meshes=%d visible=%d hidden=%d bodies=%d chunks_live=%d chunks_drawn=%d nodes=%d physics=%d" % [label, int(item["library"]), int(item["meshes"]), int(item["visible"]), int(item["hidden"]), int(item["bodies"]), int(item["chunks_live"]), int(item["chunks_drawn"]), int(item["nodes"]), int(item["physics_bodies"])])
	else:
		print("%s=%s" % [label, str(row)])


func _expect(ok: bool, label: String) -> int:
	if not ok:
		print("test_world3d_stream: FAIL %s" % label)
		return 1
	return 0
