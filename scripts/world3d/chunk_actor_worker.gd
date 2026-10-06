extends RefCounted
## One worker owns chunk coordinates. The render thread only reads the view list.

const Table = preload("res://scripts/world3d/chunk_actor_table.gd")
const DT := 1.0 / 60.0

var _table = null
var _thread: Thread
var _wake := Semaphore.new()
var _mutex := Mutex.new()
var _running := false
var _focus := Vector3.ZERO
var _view_m := Table.VIEW_M
var _published := {"ok": false}
var _generation := 0
var _pending := false


func start(table) -> void:
	_table = table
	_running = true
	_thread = Thread.new()
	_thread.start(Callable(self, "_loop"))


func kick(focus: Vector3, view_m: float) -> void:
	_mutex.lock()
	_focus = focus
	_view_m = view_m
	var wake := not _pending
	_pending = true
	_mutex.unlock()
	if wake:
		_wake.post()


func latest() -> Dictionary:
	_mutex.lock()
	var copy: Dictionary = _published.duplicate(true)
	copy["generation"] = _generation
	_mutex.unlock()
	return copy


func stop() -> void:
	if _thread == null:
		return
	_mutex.lock()
	_running = false
	_mutex.unlock()
	_wake.post()
	_thread.wait_to_finish()
	_thread = null


func _loop() -> void:
	var last_step := Time.get_ticks_usec()
	while true:
		_wake.wait()
		_mutex.lock()
		var running := _running
		var focus := _focus
		var view_m := _view_m
		_pending = false
		_mutex.unlock()
		if not running:
			return
		var started := Time.get_ticks_usec()
		var elapsed := clampf(float(started - last_step) / 1000000.0, 0.0, 0.25)
		last_step = started
		var result: Dictionary = _table.simulate(focus, view_m, elapsed)
		result["step_us"] = int(Time.get_ticks_usec() - started)
		_mutex.lock()
		_published = result
		_generation += 1
		_mutex.unlock()
