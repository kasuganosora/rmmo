extends RefCounted
## Check-only crowd. Far people stay as coordinates; only the loaded ring gets a body.

const Stream = preload("res://scripts/world3d/world_stream.gd")
const Motion = preload("res://scripts/world3d/world_motion.gd")
const N := 256
const COUNT := 500

var land := PackedByteArray()
var agents: Array = []
var _rng := RandomNumberGenerator.new()
var _shape: CapsuleShape3D
var _mesh: CapsuleMesh


func setup(walkable: PackedByteArray, seed: int, count: int = COUNT) -> void:
	land = walkable
	_rng.seed = seed
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.28
	_shape.height = 1.2
	_mesh = CapsuleMesh.new()
	_mesh.radius = 0.28
	_mesh.height = 1.2
	var cells: Array = []
	for y in N:
		for x in N:
			if land[y * N + x] != 0:
				cells.append(Vector2i(x, y))
	for i in count:
		var j := i + _rng.randi_range(0, cells.size() - 1 - i)
		var swap: Vector2i = cells[i]
		cells[i] = cells[j]
		cells[j] = swap
		var cell: Vector2i = cells[i]
		agents.append({
			"x": float(cell.x) + 0.5,
			"z": float(cell.y) + 0.5,
			"dir": _rng.randi() % 4,
			"cool": _rng.randf_range(0.2, 2.0),
			"body": null,
		})


func tick(host: Node, origin: Vector3, dt: float) -> Dictionary:
	var solid := Stream.ring(origin, Stream.COLLISION_RADIUS)
	var draw := Stream.ring(origin, Stream.RENDER_RADIUS)
	var active := 0
	var visible := 0
	var outside := 0
	var spawned := 0
	var freed := 0
	var speed := Motion.WALK_MPS * dt
	for index in agents.size():
		var agent: Dictionary = agents[index]
		agent["cool"] = float(agent["cool"]) - dt
		if float(agent["cool"]) <= 0.0:
			agent["dir"] = _rng.randi() % 4
			agent["cool"] = _rng.randf_range(0.6, 2.4)
		var step := _heading(int(agent["dir"])) * speed
		var next_x := float(agent["x"]) + step.x
		var next_z := float(agent["z"]) + step.y
		var key := Stream.chunk_key(Vector3(float(agent["x"]), 0.0, float(agent["z"])))
		var body: CharacterBody3D = agent["body"] as CharacterBody3D
		if body != null and not is_instance_valid(body):
			body = null
			agent["body"] = null
		if not solid.has(key):
			outside += 1
			if _open(next_x, next_z):
				agent["x"] = next_x
				agent["z"] = next_z
			else:
				agent["dir"] = _rng.randi() % 4
			if body != null:
				body.free()
				agent["body"] = null
				freed += 1
			continue
		if body == null:
			body = _spawn(host, index, float(agent["x"]), float(agent["z"]))
			agent["body"] = body
			spawned += 1
		active += 1
		var shown: bool = draw.has(key)
		var view := body.get_node_or_null("View") as MeshInstance3D
		if view != null:
			view.visible = shown
		if shown:
			visible += 1
		var before := body.global_position
		var hit := body.move_and_collide(Vector3(step.x, 0.0, step.y))
		var after := body.global_position
		if not _open(after.x, after.z):
			body.global_position = before
			agent["dir"] = _rng.randi() % 4
			after = before
		elif hit != null and after.distance_squared_to(before) < 0.0004:
			agent["dir"] = _rng.randi() % 4
		agent["x"] = after.x
		agent["z"] = after.z
	return {
		"active": active,
		"visible": visible,
		"outside": outside,
		"spawned": spawned,
		"freed": freed,
	}


func body_count() -> int:
	var count := 0
	for agent in agents:
		var body: CharacterBody3D = agent["body"] as CharacterBody3D
		if body != null and is_instance_valid(body):
			count += 1
	return count


func checksum(origin: Vector3) -> int:
	var solid := Stream.ring(origin, Stream.COLLISION_RADIUS)
	var total := 0
	for index in agents.size():
		var agent: Dictionary = agents[index]
		var key := Stream.chunk_key(Vector3(float(agent["x"]), 0.0, float(agent["z"])))
		if solid.has(key):
			total += index + 1
	return total


func off_road() -> int:
	var bad := 0
	for agent in agents:
		if not _open(float(agent["x"]), float(agent["z"])):
			bad += 1
	return bad


func release() -> void:
	for agent in agents:
		var body: CharacterBody3D = agent["body"] as CharacterBody3D
		if body != null and is_instance_valid(body):
			body.free()
		agent["body"] = null


func _spawn(host: Node, index: int, x: float, z: float) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "CrowdNpc%d" % index
	body.position = Vector3(x, 0.95, z)
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	shape.shape = _shape
	body.add_child(shape)
	var view := MeshInstance3D.new()
	view.name = "View"
	view.mesh = _mesh
	body.add_child(view)
	host.add_child(body)
	return body


func _open(x: float, z: float) -> bool:
	var cx := int(floor(x))
	var cz := int(floor(z))
	if cx < 0 or cz < 0 or cx >= N or cz >= N:
		return false
	return land[cz * N + cx] != 0


func _heading(dir: int) -> Vector2:
	if dir == 0:
		return Vector2(1, 0)
	if dir == 1:
		return Vector2(-1, 0)
	if dir == 2:
		return Vector2(0, 1)
	return Vector2(0, -1)
