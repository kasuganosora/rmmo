extends SceneTree
## CPU-only ownership/gate tests. No source models, renderer assets or disk caches.
const Prefetch = preload("res://scripts/world3d/initial_model_prefetch.gd")
var passed := 0
var failures := 0

class Tracked extends RefCounted:
	var probe: RefCounted
	var label := ""
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and probe != null:
			probe.destroyed(label, OS.get_thread_caller_id())

class Probe extends RefCounted:
	var mutex := Mutex.new()
	var cached_paths: Array = []
	var raw_paths: Array = []
	var weak_resources: Array = []
	var destruction_threads: Array = []
	func payload(path: String) -> RefCounted:
		var value := Tracked.new()
		value.probe = self; value.label = path
		mutex.lock(); weak_resources.append(weakref(value)); mutex.unlock()
		return value
	func cached(path: String) -> Dictionary:
		mutex.lock(); cached_paths.append(path); mutex.unlock()
		if path.begins_with("compiled"):
			return {"hit": true, "packed": payload(path), "source_digest": "a".repeat(64)}
		return {"hit": false, "reason": "intentional_cpu_miss"}
	func parse(path: String) -> Dictionary:
		mutex.lock(); raw_paths.append(path); mutex.unlock()
		return {"error": OK, "payload": payload(path), "source_digest": "b".repeat(64)}
	func destroyed(_path: String, thread: int) -> void:
		mutex.lock(); destruction_threads.append(thread); mutex.unlock()
	func counts() -> Dictionary:
		mutex.lock()
		var result := {"cached": cached_paths.size(), "raw": raw_paths.size(), "destroyed": destruction_threads.size()}
		mutex.unlock()
		return result
	func all_released_on_main() -> bool:
		mutex.lock()
		var okay := destruction_threads.all(func(id): return id == OS.get_main_thread_id())
		for value: WeakRef in weak_resources: okay = okay and value.get_ref() == null
		mutex.unlock()
		return okay

class InjectedPreparation extends "res://scripts/world3d/model_parse_preparation.gd":
	var probe: RefCounted
	func run(paths: Array, _parser: Callable = Callable(), worker_limit: int = 2, thread_starter: Callable = Callable(), content_root: String = "", verified_sources: Dictionary = {}) -> Dictionary:
		return super.run(paths, probe.parse, worker_limit, thread_starter, content_root, verified_sources)

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS: " if value else "FAIL: ", label)
	if value: passed += 1
	else: failures += 1

func preparation(probe: Probe) -> RefCounted:
	var result := InjectedPreparation.new()
	result.probe = probe
	result.cache_reader = probe.cached
	result.memory_estimator = func(_path: String): return {"estimated_bytes": 4, "exclusive": false, "known": true}
	result.eligibility_checker = func(_path: String): return true
	result.inflight_byte_limit = 8
	return result

func wait_cached(probe: Probe, count: int) -> bool:
	var deadline := Time.get_ticks_msec() + 2000
	while probe.counts().cached < count and Time.get_ticks_msec() < deadline: OS.delay_msec(1)
	return probe.counts().cached >= count

func wait_packet(helper: RefCounted) -> bool:
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		helper._mutex.lock(); var ready: bool = not helper._discarded.is_empty(); helper._mutex.unlock()
		if ready: return true
		OS.delay_msec(1)
	return false

func wait_done(worker: Thread) -> bool:
	var deadline := Time.get_ticks_msec() + 2000
	while worker.is_alive() and Time.get_ticks_msec() < deadline: OS.delay_msec(1)
	return not worker.is_alive()

func assert_no_cycle(helper: RefCounted, controller: RefCounted) -> Array:
	return [weakref(helper), weakref(controller)]

func run() -> void:
	var probe := Probe.new()
	var controller: RefCounted = preparation(probe)
	var helper: RefCounted = Prefetch.new()
	check(not helper.start(["raw_failure"], controller, 2, "", func(_worker: Thread, _task: Callable): return ERR_CANT_CREATE), "coordinator start failure skips speculation without synchronous gate wait")
	check(probe.counts().cached == 0 and probe.counts().raw == 0 and not controller.fallback_gate.is_valid(), "failed start performs no parse and removes the gate")
	check(not helper.take(["raw_failure"]).accepted, "failed-start take requests normal authoritative fallback")
	var weak := assert_no_cycle(helper, controller)
	helper = null; controller = null
	check(weak[0].get_ref() == null and weak[1].get_ref() == null, "failed start leaves no helper/controller ownership cycle")

	probe = Probe.new(); controller = preparation(probe); helper = Prefetch.new()
	check(helper.start(["compiled_a", "raw_b", "compiled_a"], controller, 2, ""), "mixed private preparation starts")
	check(wait_cached(probe, 2), "compiled reads execute before take and duplicate hints are deduplicated")
	OS.delay_msec(10)
	check(probe.counts().raw == 0 and helper._worker.is_alive(), "raw miss waits at validation gate while parser remains independent")
	var taken: Dictionary = helper.take(["raw_b", "compiled_a"])
	check(taken.accepted and taken.result.error == OK and probe.counts().raw == 1, "matching unordered actual path set opens raw gate and accepts the batch")
	check(taken.result.entries.size() == 2 and taken.result.threads_started == taken.result.threads_joined, "matching take joins every native and fallback worker")
	check(taken.result.peak_inflight_estimate_bytes <= 8 and taken.result.inflight_reserved_at_return == 0, "speculation preserves the single bounded admission ledger")
	check(probe.counts().destroyed == 0, "accepted result keeps resources alive until main consumes them")
	taken.clear()
	check(probe.counts().destroyed == 2 and probe.all_released_on_main(), "accepted resources release on consuming main thread")
	weak = assert_no_cycle(helper, controller)
	helper = null; controller = null
	check(weak[0].get_ref() == null and weak[1].get_ref() == null, "matching take leaves no helper/controller ownership cycle")
	# Avoid a deliberately detected leak persisting into unrelated assertions.
	if weak[1].get_ref() != null: weak[1].get_ref().fallback_gate = Callable()

	probe = Probe.new(); controller = preparation(probe); helper = Prefetch.new()
	check(helper.start(["compiled_extra", "raw_extra"], controller, 2, "") and wait_cached(probe, 2), "mismatch fixture prepares private native result")
	var taker := Thread.new()
	check(taker.start(helper.take.bind(["compiled_actual"])) == OK and wait_packet(helper), "mismatch joins cancelled batch and queues disposal packet")
	check(taker.is_alive() and probe.counts().raw == 0 and probe.counts().destroyed == 0, "mismatch waits for main ack and never opens extra raw path")
	helper.drain_discarded()
	check(wait_done(taker), "main disposal acknowledgement unblocks mismatch fallback")
	taken = taker.wait_to_finish()
	check(not taken.accepted and probe.counts().destroyed == 1 and probe.all_released_on_main(), "mismatch releases rejected resources on main before replacement is admitted")
	var released: int = helper._released
	helper.drain_discarded()
	check(helper._released == released, "duplicate drain neither double releases nor acknowledges twice")
	weak = assert_no_cycle(helper, controller)
	helper = null; controller = null
	check(weak[0].get_ref() == null and weak[1].get_ref() == null, "mismatch take leaves no helper/controller ownership cycle")
	if weak[1].get_ref() != null: weak[1].get_ref().fallback_gate = Callable()

	probe = Probe.new(); controller = preparation(probe); helper = Prefetch.new()
	check(helper.start(["compiled_abandon", "raw_abandon"], controller, 2, "") and wait_cached(probe, 2), "early-abandon fixture starts")
	var abandoner := Thread.new()
	check(abandoner.start(helper.abandon) == OK and wait_done(abandoner), "abandon cancels blocked gate and joins without waiting for main disposal")
	abandoner.wait_to_finish()
	check(probe.counts().raw == 0 and probe.counts().destroyed == 0 and wait_packet(helper), "abandon retains successful sibling in quarantine")
	helper.drain_discarded()
	check(probe.counts().destroyed == 1 and probe.all_released_on_main(), "abandoned sibling is finally released by main")
	weak = assert_no_cycle(helper, controller)
	helper = null; controller = null
	check(weak[0].get_ref() == null and weak[1].get_ref() == null, "abandon leaves no helper/controller ownership cycle")
	if weak[1].get_ref() != null: weak[1].get_ref().fallback_gate = Callable()

	probe = Probe.new(); controller = preparation(probe); helper = Prefetch.new()
	check(helper.start(["compiled_exit", "raw_exit"], controller, 2, "") and wait_cached(probe, 2), "shutdown-ack fixture starts")
	taker = Thread.new()
	check(taker.start(helper.take.bind(["different"])) == OK and wait_packet(helper), "shutdown fixture is blocked waiting for main acknowledgement")
	helper.cancel()
	check(wait_done(taker), "cancel escapes ack wait without process frames or an early resource drop")
	taken = taker.wait_to_finish()
	check(not taken.accepted and probe.counts().destroyed == 0, "shutdown escape keeps packet resources available for final main drain")
	helper.drain_discarded()
	check(probe.counts().destroyed == 1 and probe.all_released_on_main(), "exit-tree style final drain releases retained packet on main")
	weak = assert_no_cycle(helper, controller)
	helper = null; controller = null
	check(weak[0].get_ref() == null and weak[1].get_ref() == null, "cancelled ack leaves no ownership cycle")
	if weak[1].get_ref() != null: weak[1].get_ref().fallback_gate = Callable()

	probe = Probe.new(); controller = preparation(probe); helper = Prefetch.new()
	check(helper.start(["raw_cancel"], controller, 1, "") and wait_cached(probe, 1), "blocked raw cancellation fixture starts")
	helper.cancel()
	taken = helper.take(["raw_cancel"])
	check(taken.accepted and taken.result.cancelled and taken.result.error == ERR_SKIP and probe.counts().raw == 0, "cancel before matching take cannot reopen a cancelled raw gate")
	taken.clear(); controller.fallback_gate = Callable(); helper = null; controller = null

	probe = Probe.new(); controller = preparation(probe); helper = Prefetch.new()
	helper.cancel()
	check(helper.start(["raw_never"], controller, 1, ""), "pre-cancelled helper may start only a cancelled coordinator")
	taken = helper.take(["raw_never"])
	check(taken.result.cancelled and taken.result.entries.is_empty() and probe.counts().cached == 0, "sticky cancellation prevents all source preparation")
	taken.clear(); controller.fallback_gate = Callable(); helper = null; controller = null
	print("INITIAL_MODEL_PREFETCH passed=", passed, " failures=", failures)
	probe=Probe.new();controller=preparation(probe);helper=Prefetch.new()
	check(not helper.allow_validated_raw(),"cold overlap cannot open a missing controller")
	check(helper.start(["raw_cold"],controller,1,"") and wait_cached(probe,1),"cold overlap starts with ordinary validation gate closed")
	check(helper.allow_validated_raw(),"validated full closure explicitly opens cold private preparation")
	var deadline:=Time.get_ticks_msec()+3000
	while probe.counts().raw==0 and Time.get_ticks_msec()<deadline:OS.delay_msec(1)
	check(probe.counts().raw==1,"cold raw work runs before selected take while CPU directory may build")
	taken=helper.take(["raw_cold"])
	check(taken.accepted and taken.result.error==OK,"matching selected sources consume the overlapped result")
	taken.clear();controller.fallback_gate=Callable();helper=null;controller=null
	probe=Probe.new();controller=preparation(probe);helper=Prefetch.new();helper.cancel()
	check(not helper.allow_validated_raw(),"cancelled cold gate cannot reopen")
	print("INITIAL_MODEL_PREFETCH_COLD passed=",passed," failures=",failures)
	quit(0 if failures == 0 else 1)
