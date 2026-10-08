extends SceneTree
const Preparation = preload("res://scripts/world3d/model_parse_preparation.gd")
var failures := 0
var passed := 0
class Probe extends RefCounted:
	var mutex := Mutex.new()
	var calls := []
	var finished := []
	var active := 0
	var peak := 0
	func parse(path: String) -> Dictionary:
		mutex.lock()
		active += 1
		peak = maxi(peak, active)
		calls.append(path)
		mutex.unlock()
		OS.delay_msec(50 if path == "slow" else 3)
		mutex.lock()
		active -= 1
		finished.append(path)
		mutex.unlock()
		return {"error": ERR_FILE_CORRUPT if path == "bad" else OK, "token": path}
	func count() -> int:
		mutex.lock()
		var value := calls.size()
		mutex.unlock()
		return value

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if ok: passed += 1
	else: failures += 1
func run() -> void:
	create_timer(15).timeout.connect(func(): quit(2))
	var probe := Probe.new()
	var job := Preparation.new()
	var result: Dictionary = job.run(["slow", "fast", "slow", "last"], probe.parse, 99)
	check(result.error == OK and result.entries.map(func(entry): return entry.path) == ["slow", "fast", "last"], "deduplicate and preserve first appearance order")
	check(probe.finished[0] == "fast" and probe.peak == 2 and probe.active == 0, "out of order completion bounded to two joined workers")
	check(result.entries.all(func(entry): return entry.token == entry.path and entry.elapsed_us > 0), "retain parser payload and independent timing")
	probe = Probe.new()
	result = Preparation.new().run(["slow", "bad", "never"], probe.parse)
	check(result.error == ERR_FILE_CORRUPT and result.entries.size() == 2 and probe.active == 0 and probe.count() == 2, "failure joins sibling and does not launch next batch")
	probe = Probe.new()
	result = Preparation.new().run(["slow", "fast"], probe.parse, 2, func(_thread: Thread, _task: Callable): return ERR_CANT_CREATE)
	check(result.error == OK and result.fallback_count == 2 and probe.peak == 1 and probe.active == 0, "thread launch failure uses same synchronous parser")
	probe = Probe.new()
	result = Preparation.new().run(["bad", "never"], probe.parse, 2, func(_thread: Thread, _task: Callable): return ERR_CANT_CREATE)
	check(result.error == ERR_FILE_CORRUPT and probe.count() == 1, "synchronous failure does not start later sibling")
	probe = Probe.new()
	job = Preparation.new()
	var coordinator := Thread.new()
	check(coordinator.start(job.run.bind(["slow", "fast", "never"], probe.parse)) == OK, "background coordinator starts")
	var deadline := Time.get_ticks_msec() + 2000
	while probe.count() < 2 and Time.get_ticks_msec() < deadline: OS.delay_msec(1)
	check(job.run(["concurrent"], probe.parse).error == ERR_BUSY, "concurrent coordinator cannot mutate active preparation")
	job.cancel()
	result = coordinator.wait_to_finish()
	check(result.cancelled and result.error == ERR_SKIP and probe.active == 0 and probe.count() == 2, "cancel joins all started workers and blocks unscheduled work")
	job = Preparation.new(); job.cancel(); probe = Probe.new()
	result = job.run(["never"], probe.parse)
	check(result.cancelled and result.entries.is_empty() and probe.count() == 0, "cancel before start never launches parser")
	probe = Probe.new()
	var launches := [0]
	result = Preparation.new().run(["slow", "fast"], probe.parse, 2, func(worker: Thread, task: Callable):
		launches[0] += 1
		return worker.start(task) if launches[0] == 1 else ERR_CANT_CREATE)
	check(result.error == OK and result.fallback_count == 1 and probe.peak == 2 and probe.active == 0, "mixed worker and synchronous fallback preserve concurrency bound and join")
	probe = Probe.new()
	result = Preparation.new().run(["ok", 3], probe.parse)
	check(result.error == ERR_INVALID_PARAMETER and probe.count() == 0, "invalid input fails before parser side effects")
	result = Preparation.new().run(["malformed"], func(_path): return {})
	check(result.error == ERR_INVALID_DATA, "malformed injected result fails closed")
	result = Preparation.new().run([])
	check(result.error == OK and result.entries.is_empty(), "empty input completes without model resources")
	print("MODEL_PARSE_PREPARATION passed=", passed, " failures=", failures)
	quit(0 if failures == 0 else 1)
