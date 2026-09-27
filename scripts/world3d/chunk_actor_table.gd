extends RefCounted
## Every map actor lives in one chunk record. A tick only walks the player's chunk.

const Stream = preload("res://scripts/world3d/world_stream.gd")
const Motion = preload("res://scripts/world3d/world_motion.gd")
const N := 256
const VIEW_M := 12.0
## Below this, one core is cheaper than waking the pool.
const PARALLEL_MIN := 256

var _actors: Array = []
var _bins := {}
var _land := PackedByteArray()
var _lock := Mutex.new()
var _rng := RandomNumberGenerator.new()
var _slice_indexes: Array = []
var _slice_count := 1
var _slice_speed := 0.0
var _slice_chunk := Vector2i.ZERO
var _slice_focus := Vector3.ZERO
var _slice_limit := 0.0
var _slice_exits: Array = []
var _slice_views: Array = []
var _force_serial := false


func place_random(land: PackedByteArray, count: int, seed: int) -> void:
	_lock.lock()
	_land = land.duplicate()
	_rng.seed = seed
	var cells: Array = []
	for y in N:
		for x in N:
			if _land[y * N + x] != 0:
				cells.append(Vector2i(x, y))
	var n := mini(count, cells.size())
	for i in n:
		var j := i + _rng.randi_range(0, cells.size() - 1 - i)
		var swap: Vector2i = cells[i]
		cells[i] = cells[j]
		cells[j] = swap
	_actors.clear()
	_bins.clear()
	for i in n:
		var cell: Vector2i = cells[i]
		var x := float(cell.x) + 0.5
		var z := float(cell.y) + 0.5
		var chunk := Stream.chunk_key(Vector3(x, 0.0, z))
		_actors.append({
			"id": i,
			"x": x,
			"z": z,
			"dir": _rng.randi() % 4,
			"cool": _rng.randf_range(0.2, 2.0),
		})
		_add_bin(chunk, i)
	_lock.unlock()


func total() -> int:
	_lock.lock()
	var count := _actors.size()
	_lock.unlock()
	return count


func busiest() -> int:
	_lock.lock()
	var most := 0
	for key in _bins.keys():
		most = maxi(most, (_bins[key] as Array).size())
	_lock.unlock()
	return most


## Steps only the chunk under focus, then splits that chunk into a packet and a view list.
func simulate(focus: Vector3, view_m: float, dt: float) -> Dictionary:
	_lock.lock()
	var chunk := Stream.chunk_key(focus)
	var key := _binkey(chunk)
	var indexes: Array = []
	if _bins.has(key):
		indexes = (_bins[key] as Array).duplicate()
	var speed := Motion.WALK_MPS * dt
	var cores := _dispatch(indexes, speed, chunk, focus, view_m * view_m)
	for exits in _slice_exits:
		for raw in exits:
			var index := int(raw)
			var actor: Dictionary = _actors[index]
			var next_chunk := Stream.chunk_key(Vector3(float(actor["x"]), 0.0, float(actor["z"])))
			_remove_bin(key, index)
			_add_bin(next_chunk, index)
	var actors := _collect(key)
	var view: Array = []
	for part in _slice_views:
		view.append_array(part)
	var result := {
		"ok": true,
		"chunk": [chunk.x, chunk.y],
		"actors": actors,
		"view": view,
		"sent": actors.size(),
		"visible": view.size(),
		"simulated": indexes.size(),
		"total": _actors.size(),
		"cores": cores,
		"thread_id": OS.get_thread_caller_id(),
	}
	_lock.unlock()
	return result


func place_dense(land: PackedByteArray, chunk: Vector2i, count: int, seed: int) -> void:
	_lock.lock()
	_land = land.duplicate()
	var x0 := chunk.x * 32
	var z0 := chunk.y * 32
	for z in range(z0, mini(z0 + 32, N)):
		for x in range(x0, mini(x0 + 32, N)):
			_land[z * N + x] = 1
	_rng.seed = seed
	_actors.clear()
	_bins.clear()
	for i in count:
		var cell_x := x0 + (i % 32)
		var cell_z := z0 + ((i / 32) % 32)
		var x := float(cell_x) + 0.5
		var z := float(cell_z) + 0.5
		_actors.append({
			"id": i,
			"x": x,
			"z": z,
			"dir": i % 4,
			"cool": 0.2 + float(i % 7) * 0.15,
		})
		_add_bin(chunk, i)
	_lock.unlock()


func bench(focus: Vector3, repeats: int, parallel: bool) -> int:
	_force_serial = not parallel
	var started := Time.get_ticks_usec()
	for _i in repeats:
		simulate(focus, VIEW_M, 1.0 / 60.0)
	_force_serial = false
	return int((Time.get_ticks_usec() - started) / maxi(repeats, 1))


func _dispatch(indexes: Array, speed: float, chunk: Vector2i, focus: Vector3, limit: float) -> int:
	_slice_indexes = indexes
	_slice_speed = speed
	_slice_chunk = chunk
	_slice_focus = focus
	_slice_limit = limit
	var cores := 1
	if not _force_serial and indexes.size() >= PARALLEL_MIN:
		cores = maxi(2, mini(OS.get_processor_count() - 1, indexes.size() / 128))
	_slice_count = cores
	_slice_exits.clear()
	_slice_views.clear()
	_slice_exits.resize(cores)
	_slice_views.resize(cores)
	for slice in cores:
		_slice_exits[slice] = []
		_slice_views[slice] = []
	if cores == 1:
		_slice_task(0)
		return 1
	var group := WorkerThreadPool.add_group_task(Callable(self, "_slice_task"), cores, -1, true, "chunk actor coordinates")
	WorkerThreadPool.wait_for_group_task_completion(group)
	return cores


func _slice_task(slice: int) -> void:
	var count := _slice_indexes.size()
	var start := slice * count / _slice_count
	var end := (slice + 1) * count / _slice_count
	var exits: Array = _slice_exits[slice]
	var view: Array = _slice_views[slice]
	var chunk := _slice_chunk
	var speed := _slice_speed
	var focus := _slice_focus
	var limit := _slice_limit
	for n in range(start, end):
		var index := int(_slice_indexes[n])
		var actor: Dictionary = _actors[index]
		var dir := int(actor["dir"])
		var cool := float(actor["cool"]) - (speed / Motion.WALK_MPS)
		if cool <= 0.0:
			dir = (dir + 1 + int(actor["id"])) % 4
			cool = 0.8 + float(int(actor["id"]) % 5) * 0.25
		actor["dir"] = dir
		actor["cool"] = cool
		var heading := _heading(dir)
		var next_x := float(actor["x"]) + heading.x * speed
		var next_z := float(actor["z"]) + heading.y * speed
		if not _open(next_x, next_z):
			actor["dir"] = (dir + 1) % 4
			continue
		var next_chunk := Stream.chunk_key(Vector3(next_x, 0.0, next_z))
		actor["x"] = next_x
		actor["z"] = next_z
		if next_chunk != chunk:
			exits.append(index)
			continue
		var dx := next_x - focus.x
		var dz := next_z - focus.z
		if dx * dx + dz * dz <= limit:
			view.append({"id": int(actor["id"]), "x": next_x, "z": next_z})


func _collect(key: String) -> Array:
	var found: Array = []
	if not _bins.has(key):
		return found
	for raw in _bins[key]:
		var actor: Dictionary = _actors[int(raw)]
		found.append({"id": int(actor["id"]), "x": float(actor["x"]), "z": float(actor["z"])})
	return found


func _add_bin(chunk: Vector2i, index: int) -> void:
	var key := _binkey(chunk)
	if not _bins.has(key):
		_bins[key] = []
	(_bins[key] as Array).append(index)


func _remove_bin(key: String, index: int) -> void:
	if not _bins.has(key):
		return
	(_bins[key] as Array).erase(index)


func _binkey(chunk: Vector2i) -> String:
	return "%d,%d" % [chunk.x, chunk.y]


func _open(x: float, z: float) -> bool:
	var cx := int(floor(x))
	var cz := int(floor(z))
	if cx < 0 or cz < 0 or cx >= N or cz >= N:
		return false
	return _land[cz * N + cx] != 0


func _heading(dir: int) -> Vector2:
	if dir == 0:
		return Vector2(1, 0)
	if dir == 1:
		return Vector2(-1, 0)
	if dir == 2:
		return Vector2(0, 1)
	return Vector2(0, -1)
