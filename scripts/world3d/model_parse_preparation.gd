extends RefCounted
## Coordinator runs on the caller's loading worker, never the scene thread.
## cancel() is the only method intended for concurrent calls. run() always joins
## every started worker before returning, including failure and cancellation.
## Injected parsers must own their resources and must not touch nodes or caches.
## Cancellation is sticky: create a new preparation for a new load transaction.
## Default parsing only overlaps self-contained extension-free GLBs. The caller
## must keep the default GLTF extension registry unchanged during preparation.
var _mutex := Mutex.new()
var _cancelled := false
var _running := false

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func is_cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value

func run(paths: Array, parser: Callable = Callable(), worker_limit: int = 2, thread_starter: Callable = Callable()) -> Dictionary:
	_mutex.lock()
	if _running:
		_mutex.unlock()
		return {"error": ERR_BUSY, "cancelled": false, "entries": []}
	_running = true
	_mutex.unlock()
	var started := Time.get_ticks_usec()
	var unique: Array[String] = []
	var seen := {}
	for path in paths:
		if not path is String or path.is_empty():
			return _finish({"error": ERR_INVALID_PARAMETER, "cancelled": is_cancelled(), "entries": []}, started)
		if not seen.has(path):
			seen[path] = true
			unique.append(path)
	var parse := parser if parser.is_valid() else Callable(get_script(), "parse_gltf")
	var limit := clampi(worker_limit, 1, 2)
	var eligibility_started := Time.get_ticks_usec()
	var eligible := {}
	for path: String in unique:
		if is_cancelled(): break
		if parser.is_valid() or (limit > 1 and preload("res://scripts/world3d/embedded_glb.gd").can_copy(path)):
			eligible[path] = true
	var eligibility_us := Time.get_ticks_usec() - eligibility_started
	var entries: Array = []
	var error := OK
	var fallback_count := 0
	var parallel_batches := 0
	var next := 0
	while next < unique.size() and error == OK and not is_cancelled():
		var pending: Array = []
		var batch_size := 1
		if limit > 1 and next + 1 < unique.size() and eligible.has(unique[next]) and eligible.has(unique[next + 1]):
			batch_size = 2
			parallel_batches += 1
		# Batches deliberately bound both active parsers and unjoined results.
		# All siblings are joined even if an earlier sibling failed.
		for index in range(next, mini(next + batch_size, unique.size())):
			if is_cancelled(): break
			var path := unique[index]
			var worker := Thread.new()
			var task := _invoke.bind(parse, path)
			var launch: int = thread_starter.call(worker, task) if thread_starter.is_valid() else worker.start(task)
			if launch == OK:
				pending.append({"thread": worker})
			else:
				fallback_count += 1
				pending.append({"result": task.call()})
				next = index + 1
				# A failed synchronous sibling must not schedule more work.
				if int(pending.back().result.error) != OK: break
			next = index + 1
		for item: Dictionary in pending:
			var result: Dictionary = item.thread.wait_to_finish() if item.has("thread") else item.result
			entries.append(result)
			if error == OK and int(result.error) != OK: error = int(result.error)
	var cancelled := is_cancelled()
	return _finish({"error": ERR_SKIP if cancelled and error == OK else error, "cancelled": cancelled,
		"entries": entries, "unique_count": unique.size(), "worker_limit": limit,
		"fallback_count": fallback_count, "parallel_eligible_count": eligible.size(),
		"eligibility_us": eligibility_us, "parallel_batches": parallel_batches}, started)

func _finish(result: Dictionary, started: int) -> Dictionary:
	result.elapsed_us = Time.get_ticks_usec() - started
	_mutex.lock()
	_running = false
	_mutex.unlock()
	return result

static func _invoke(parser: Callable, path: String) -> Dictionary:
	var started := preload("res://scripts/world3d/load_trace.gd").begin("model.parse")
	var raw: Variant = parser.call(path)
	preload("res://scripts/world3d/load_trace.gd").elapsed("model.parse",started,{"path":path})
	var result: Dictionary = raw if raw is Dictionary else {"error": ERR_INVALID_DATA}
	if not result.get("error") is int: result.error = ERR_INVALID_DATA
	result.path = path
	result.elapsed_us = Time.get_ticks_usec() - started
	return result

static func parse_gltf(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"error": ERR_FILE_NOT_FOUND}
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state, 0, path.get_base_dir())
	return {"error": error, "document": document, "state": state}
