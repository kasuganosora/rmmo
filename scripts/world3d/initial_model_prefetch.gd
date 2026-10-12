extends RefCounted
## Parser-owned speculative batch, with main-thread disposal on rejection.
## Only cancel() and drain_discarded() may run concurrently with the parser.
const Drainer = preload("res://scripts/world3d/asset_worker_drainer.gd")
var _mutex := Mutex.new()
var _cancelled := false
var _raw_allowed := false
var _controller: RefCounted
var _worker: Thread
var _paths: Dictionary = {}
var _discarded: Array = []
var _released := 0
var started_us := 0

func start(paths: Array, controller: RefCounted, workers: int, content_root: String, starter: Callable = Callable()) -> bool:
	if paths.is_empty(): return false
	for path: String in paths: _paths[path] = true
	_mutex.lock()
	_controller = controller
	if _cancelled: _controller.cancel()
	_mutex.unlock()
	controller.fallback_gate = _wait_for_validation
	_worker = Thread.new()
	started_us = Time.get_ticks_usec()
	var task: Callable = controller.run.bind(paths.duplicate(), Callable(), workers, Callable(), content_root)
	var error: int = starter.call(_worker, task) if starter.is_valid() else _worker.start(task)
	if error == OK: return true
	# Never run synchronously here: this parser must first open the raw gate.
	_worker = null; controller.fallback_gate = Callable(); _paths.clear()
	return false

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	if _controller != null: _controller.cancel()
	_mutex.unlock()

func _wait_for_validation() -> bool:
	while true:
		_mutex.lock()
		var cancelled := _cancelled
		var allowed := _raw_allowed
		_mutex.unlock()
		if cancelled or _controller.is_cancelled(): return false
		if allowed: return true
		OS.delay_usec(500)
	return false

func take(actual_paths: Array) -> Dictionary:
	if _worker == null: return {"accepted": false}
	var actual: Dictionary = {}
	for path: String in actual_paths: actual[path] = true
	if actual == _paths:
		_mutex.lock(); _raw_allowed = true; _mutex.unlock()
		var result: Dictionary = _worker.wait_to_finish(); _worker = null
		return {"accepted": true, "result": result}
	# Hints never override hydrated records. Drain the rejected batch before a
	# replacement budget starts; main clears the shared packet's resource refs.
	_controller.cancel()
	var packet: Dictionary = _worker.wait_to_finish(); _worker = null
	_mutex.lock()
	var target := _released + 1
	_discarded.append(packet)
	_mutex.unlock()
	while true:
		_mutex.lock()
		var ready := _released >= target
		var cancelled := _cancelled
		_mutex.unlock()
		# Exit-tree cannot pump _process. Keep the packet for its final main drain.
		if ready or cancelled: break
		OS.delay_usec(500)
	return {"accepted": false}

func abandon() -> void:
	if _worker == null: return
	_controller.cancel()
	var packet: Dictionary = _worker.wait_to_finish(); _worker = null
	_mutex.lock(); _discarded.append(packet); _mutex.unlock()

func drain_discarded() -> void:
	_mutex.lock()
	var packets := _discarded.duplicate()
	_discarded.clear()
	_mutex.unlock()
	if packets.is_empty(): return
	Drainer.synchronize_transfer()
	for packet: Dictionary in packets: packet.clear()
	Drainer.synchronize_transfer()
	_mutex.lock(); _released += packets.size(); _mutex.unlock()
