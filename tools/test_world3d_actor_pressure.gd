extends SceneTree
## Tens of thousands of map actors. The server packet and the scene stay on one chunk's view.

const GUILD := Vector3(112.5, 0.0, 119.5)
const GATE := Vector3(103.5, 0.0, 245.5)
const COUNT := 10000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var server = root.get_node("MockServer")
	var table = load("res://scripts/world3d/chunk_actor_table.gd").new()
	table.place_random(_walkable(), COUNT, 10000)
	var total: int = table.total()
	var busiest: int = table.busiest()
	server.world3d_mount_actors(table)
	var main_thread := OS.get_thread_caller_id()
	var host := Node3D.new()
	host.name = "ActorView"
	root.add_child(host)
	var guild: Dictionary = _frame(server, GUILD)
	failed += _expect(int(guild.get("total", 0)) == total and total >= COUNT, "the map still holds every actor")
	failed += _expect(int(guild.get("sent", 0)) > 0 and int(guild.get("sent", 0)) * 5 < total, "the packet is only the player's chunk")
	failed += _expect(int(guild.get("visible", 0)) < int(guild.get("sent", 0)), "the chunk is larger than the view")
	failed += _expect(_same_chunk(guild), "every sent actor is inside that chunk")
	failed += _expect(int(guild.get("thread_id", main_thread)) != main_thread, "coordinates are stepped off the render thread")
	var apply_us := _apply(host, guild.get("view", []))
	failed += _expect(host.get_child_count() == int(guild.get("visible", 0)), "scene nodes match the view list")
	var moved := _wait_move(server, GUILD, guild)
	failed += _expect(moved, "people in the chunk actually walk")
	var gate: Dictionary = _frame(server, GATE)
	failed += _expect(int(gate.get("chunk", [0, 0])[1]) != int(guild.get("chunk", [0, 0])[1]), "changing chunks changes the packet")
	failed += _expect(_same_chunk(gate) and int(gate.get("sent", 0)) * 5 < total, "the new packet is still one chunk")
	_apply(host, gate.get("view", []))
	failed += _expect(host.get_child_count() == int(gate.get("visible", 0)), "leaving the chunk drops the previous view")
	server.world3d_release_actors()
	var dense = load("res://scripts/world3d/chunk_actor_table.gd").new()
	var Stream = load("res://scripts/world3d/world_stream.gd")
	dense.place_dense(_walkable(), Stream.chunk_key(GUILD), 4096, 7)
	dense.bench(GUILD, 2, false)
	dense.bench(GUILD, 2, true)
	var serial_us: int = dense.bench(GUILD, 24, false)
	var parallel_us: int = dense.bench(GUILD, 24, true)
	# Speed depends on hardware and scheduling. Compare completed results,
	# never treat queued work as a successful or faster simulation.
	var serial = load("res://scripts/world3d/chunk_actor_table.gd").new()
	var parallel = load("res://scripts/world3d/chunk_actor_table.gd").new()
	serial.place_dense(_walkable(), Stream.chunk_key(GUILD), 4096, 7)
	parallel.place_dense(_walkable(), Stream.chunk_key(GUILD), 4096, 7)
	serial._force_serial = true
	for step in 10:
		var expected: Dictionary = serial.simulate(GUILD, 12.0, 1.0 / 60.0)
		var actual: Dictionary = parallel.simulate(GUILD, 12.0, 1.0 / 60.0)
		failed += _expect(expected["actors"] == actual["actors"] and expected["view"] == actual["view"], "parallel tick %d matches completed serial tick" % step)
	print("dense=4096 serial_us=%d parallel_us=%d cores=%d" % [serial_us, parallel_us, OS.get_processor_count()])
	print("total=%d busiest_chunk=%d" % [total, busiest])
	print("guild sent=%d visible=%d step_us=%d apply_us=%d thread=%d" % [int(guild.get("sent", 0)), int(guild.get("visible", 0)), int(guild.get("step_us", 0)), apply_us, int(guild.get("thread_id", 0))])
	print("gate sent=%d visible=%d step_us=%d" % [int(gate.get("sent", 0)), int(gate.get("visible", 0)), int(gate.get("step_us", 0))])
	print("main_thread=%d" % main_thread)
	print("test_world3d_actor_pressure: %s" % ("FAIL %d" % failed if failed else "PASS"))
	host.free()
	quit(1 if failed else 0)


func _frame(server, focus: Vector3) -> Dictionary:
	var generation: int = server.world3d_actor_generation()
	server.try_world3d_chunk(focus.x, focus.z)
	for _i in 200:
		var packet: Dictionary = server.try_world3d_chunk(focus.x, focus.z)
		if int(packet.get("generation", 0)) > generation and bool(packet.get("ok", false)):
			return packet
		OS.delay_msec(2)
	return server.try_world3d_chunk(focus.x, focus.z)


func _wait_move(server, focus: Vector3, before: Dictionary) -> bool:
	var start := {}
	for actor in before.get("actors", []):
		start[int(actor.get("id", -1))] = float(actor.get("x", 0.0))
	for _i in 40:
		var packet: Dictionary = _frame(server, focus)
		for actor in packet.get("actors", []):
			var id := int(actor.get("id", -1))
			if start.has(id) and absf(float(actor.get("x", 0.0)) - float(start[id])) > 0.05:
				return true
	return false


func _apply(host: Node, view: Array) -> int:
	var started := Time.get_ticks_usec()
	load("res://scripts/world3d/view_actors.gd").apply(host, view)
	return int(Time.get_ticks_usec() - started)


func _same_chunk(packet: Dictionary) -> bool:
	var chunk: Array = packet.get("chunk", [])
	if chunk.size() < 2:
		return false
	var Stream = load("res://scripts/world3d/world_stream.gd")
	for actor in packet.get("actors", []):
		var key: Vector2i = Stream.chunk_key(Vector3(float(actor.get("x", 0.0)), 0.0, float(actor.get("z", 0.0))))
		if key.x != int(chunk[0]) or key.y != int(chunk[1]):
			return false
	return true


func _walkable() -> PackedByteArray:
	var pack = load("res://scripts/map/tilemap_pack.gd").load_pack("user://content/packs/default", "Axel256")
	var col = pack.collision
	var land := PackedByteArray()
	land.resize(256 * 256)
	for y in 256:
		for x in 256:
			land[y * 256 + x] = 1 if col.is_landable(x, y) else 0
	return land


func _expect(ok: bool, label: String) -> int:
	if not ok:
		print("test_world3d_actor_pressure: FAIL %s" % label)
		return 1
	return 0
