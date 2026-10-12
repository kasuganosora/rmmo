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
	var unsafe_overlaps:=0
	var errors:Dictionary={}
	var cancellation_gate:Semaphore
	func parse(path: String) -> Dictionary:
		mutex.lock()
		active += 1
		peak = maxi(peak, active)
		calls.append(path)
		if path=="unsafe" and active>1:unsafe_overlaps+=1
		mutex.unlock()
		if cancellation_gate!=null:cancellation_gate.wait()
		else:OS.delay_msec(50 if path.begins_with("slow") else 3)
		mutex.lock()
		active -= 1
		finished.append(path)
		mutex.unlock()
		return {"error":errors.get(path,ERR_FILE_CORRUPT if path=="bad" else OK),"token":path}
	func cached(path:String)->Dictionary:
		mutex.lock();active+=1;peak=maxi(peak,active);mutex.unlock()
		OS.delay_msec(5)
		mutex.lock();active-=1;mutex.unlock()
		return {"hit":true,"packed":RefCounted.new()} if path.begins_with("cached") else {"hit":false,"reason":"test_miss"}
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
	var result: Dictionary = job.run(["slow", "fast", "slow", "last"], probe.parse)
	check(result.error == OK and result.entries.map(func(entry): return entry.path) == ["slow", "fast", "last"], "deduplicate and preserve first appearance order")
	check(probe.finished[0] == "fast" and probe.peak == 2 and probe.active == 0, "out of order completion bounded to two joined workers")
	check(probe.finished.find("last")<probe.finished.find("slow"),"finished worker immediately takes next model while first is still parsing")
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
	probe.cancellation_gate=Semaphore.new()
	var coordinator := Thread.new()
	check(coordinator.start(job.run.bind(["slow", "fast", "never"], probe.parse)) == OK, "background coordinator starts")
	var deadline := Time.get_ticks_msec() + 2000
	while probe.count() < 2 and Time.get_ticks_msec() < deadline: OS.delay_msec(1)
	check(job.run(["concurrent"], probe.parse).error == ERR_BUSY, "concurrent coordinator cannot mutate active preparation")
	job.cancel()
	probe.cancellation_gate.post();probe.cancellation_gate.post()
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
	probe=Probe.new();job=Preparation.new()
	result=job.run(["slow","fast","third","fourth","last"],probe.parse,99)
	check(result.error==OK and result.worker_limit==4 and probe.peak==4 and result.threads_joined==5,"explicit four-worker configuration is bounded and joins every model")
	probe=Probe.new();job=Preparation.new();job.inflight_byte_limit=8
	job.memory_estimator=func(_path:String):return {"estimated_bytes":6,"exclusive":false}
	result=job.run(["slow","fast","last"],probe.parse,4)
	check(result.error==OK and probe.peak==1 and result.peak_inflight_estimate_bytes==6,"memory admission reduces concurrency independently of thread limit")
	check(result.initial_required_resident_estimate_bytes==18 and result.result_resident_estimate_bytes==18 and result.peak_live_estimate_bytes==18 and result.inflight_reserved_at_return==0,"completed initial results stay charged as resident after in-flight ownership transfers")
	probe=Probe.new();job=Preparation.new();job.inflight_byte_limit=8
	job.memory_estimator=func(path:String):return {"estimated_bytes":100 if path=="unknown" else 3,"exclusive":path=="unknown"}
	result=job.run(["slow","unknown","fast"],probe.parse,4)
	check(result.error==OK and probe.peak==1 and result.peak_inflight_estimate_bytes==100,"oversized unknown task progresses exclusively without pretending its bytes fit the cap")
	probe=Probe.new();job=Preparation.new();job.cache_reader=probe.cached
	job.eligibility_checker=func(path:String):return path!="unsafe"
	job.memory_estimator=func(_path:String):return {"estimated_bytes":1,"exclusive":false}
	result=job.run(["slow","unsafe","cached_one","cached_two"],probe.parse,4)
	check(result.error==OK and result.native_cache_hits==2 and result.native_cache_misses==2 and not probe.calls.has("cached_one"),"native products use the independent read stage and misses explicitly return to fallback dispatch")
	check(result.serial_fallbacks==1 and probe.unsafe_overlaps==0 and result.entries.map(func(entry):return entry.path)==["slow","unsafe","cached_one","cached_two"],"unproven fallback waits for every active read or parser and preserves input order")
	check(result.result_resident_estimate_bytes==4 and result.initial_required_resident_estimate_bytes==4,"two-stage misses are charged once in final resident results")
	probe=Probe.new();probe.errors={"slow_error":ERR_FILE_CANT_READ,"bad":ERR_FILE_CORRUPT}
	result=Preparation.new().run(["slow_error","bad","never"],probe.parse)
	check(result.error==ERR_FILE_CANT_READ and probe.finished[0]=="bad" and result.threads_started==result.threads_joined,"out-of-order sibling errors retain deterministic input-order error and join all")
	probe=Probe.new();job=Preparation.new();job.cache_reader=probe.cached
	var checks:={}
	job.eligibility_checker=func(path:String):
		checks[path]=int(checks.get(path,0))+1
		return checks[path]==1
	job.memory_estimator=func(_path:String):return {"estimated_bytes":1,"exclusive":false}
	result=job.run(["slow","unsafe"],probe.parse)
	check(result.error==OK and result.serial_fallbacks==2 and probe.unsafe_overlaps==0,"eligibility lost during native read reroutes to exclusive fallback before any import")
	job=Preparation.new();job.cache_reader=func(_path:String):return {"hit":true,"packed":null}
	job.eligibility_checker=func(_path:String):return true
	job.memory_estimator=func(_path:String):return {"estimated_bytes":1,"exclusive":false}
	result=job.run(["broken"],func(_path:String):return {"error":OK})
	check(result.error==ERR_INVALID_DATA and result.inflight_reserved_at_return==0 and result.inflight_jobs_at_return==0,"malformed native handoff fails closed and releases in-flight reservations")
	print("MODEL_PARSE_PREPARATION passed=", passed, " failures=", failures)
	quit(0 if failures == 0 else 1)
