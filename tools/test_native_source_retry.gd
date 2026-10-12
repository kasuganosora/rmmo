extends SceneTree
## CPU-only resource ownership/scheduling regression; no mesh, texture or GPU.
const Preparation = preload("res://scripts/world3d/model_parse_preparation.gd")
const OLD_SHA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const NEW_SHA = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const REASON = "candidate_source_changed_after_read"
var failures: int = 0
var passed: int = 0

class Lifetime extends RefCounted:
	var probe: RefCounted
	var kind: String = ""
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and probe != null:
			probe.record_release(kind, OS.get_thread_caller_id())

class Probe extends RefCounted:
	var mode: String = "success"
	var controller: WeakRef
	var mutex: Mutex = Mutex.new()
	var estimates: Dictionary = {}
	var eligibility: Dictionary = {}
	var native_calls: Array[String] = []
	var raw_calls: Array[String] = []
	var resources: Array[Dictionary] = []
	var releases: Array[Dictionary] = []
	func record_release(kind: String, thread_id: int) -> void:
		mutex.lock(); releases.append({"kind":kind, "thread":thread_id}); mutex.unlock()
	func observe(resource: RefCounted, kind: String) -> void:
		var marker: Lifetime = Lifetime.new(); marker.probe = self; marker.kind = kind
		resource.set_meta("native_retry_test_lifetime", marker)
		mutex.lock(); resources.append({"kind":kind, "ref":weakref(resource)}); mutex.unlock()
	func estimate(path: String) -> Dictionary:
		mutex.lock()
		estimates[path] = int(estimates.get(path, 0)) + 1
		var count: int = estimates[path]
		mutex.unlock()
		return {"estimated_bytes":40 if count == 1 else 60, "exclusive":false}
	func eligible(path: String) -> bool:
		mutex.lock()
		eligibility[path] = int(eligibility.get(path, 0)) + 1
		var count: int = eligibility[path]
		mutex.unlock()
		return not (mode == "serial" and count > 1)
	func candidate(_path: String) -> Dictionary:
		return {"estimated_bytes":20, "exclusive":false, "source_sha":OLD_SHA, "payload_sha":NEW_SHA}
	func legacy_cache(_path: String) -> Dictionary:
		return {"hit":false, "reason":"unexpected_legacy_reader"}
	func native(path: String, _candidate: Dictionary) -> Dictionary:
		mutex.lock(); native_calls.append(path); mutex.unlock()
		if path == "sibling_bad": return {"error":ERR_FILE_CORRUPT}
		# The sibling fails while this result is still running, so the retry
		# cannot accidentally start raw before the scheduler notices failure.
		if mode == "sibling": OS.delay_msec(25)
		var packed: PackedScene = PackedScene.new()
		var empty: Node3D = Node3D.new()
		var pack_error: Error = packed.pack(empty)
		empty.free()
		if pack_error != OK: return {"error":pack_error, "packed":packed}
		observe(packed, "native")
		var reply: Dictionary = {"error":ERR_BUSY, "packed":packed, "compiled":true, "source_digest":OLD_SHA, "native_source_retry":true, "cache_reason":REASON}
		match mode:
			"cancel": controller.get_ref().cancel()
			"wrong_digest": reply.source_digest = NEW_SHA
			"wrong_digest_type": reply.source_digest = 123
			"wrong_error": reply.error = ERR_INVALID_DATA
			"wrong_error_type": reply.error = "busy"
			"wrong_compiled": reply.compiled = false
			"wrong_compiled_type": reply.compiled = "true"
			"wrong_reason": reply.cache_reason = "other_failure"
			"wrong_reason_type": reply.cache_reason = 123
			"wrong_marker_type": reply.native_source_retry = "true"
			"empty_marker": reply.native_source_retry = ""
			"false_marker": reply.native_source_retry = false
			"missing_marker": reply.erase("native_source_retry")
			"ordinary_fallback":
				reply.erase("native_source_retry"); reply.error = OK; reply.fallback_required = true
			"marker_and_fallback": reply.fallback_required = true
			"marker_and_false_fallback": reply.fallback_required = false
			"wrong_packed_type":
				# Retain the real PackedScene too, so a malformed injected result
				# cannot move its last owner onto this worker during the test.
				reply.retained_resources = [packed]
				var other: RefCounted = RefCounted.new(); observe(other, "wrong_type")
				reply.packed = other
		return reply
	func raw(path: String) -> Dictionary:
		mutex.lock(); raw_calls.append(path); mutex.unlock()
		var resource: RefCounted = RefCounted.new(); observe(resource, "raw")
		return {"error":ERR_FILE_CORRUPT if mode == "raw_failure" else OK, "compiled":false, "source_digest":NEW_SHA, "raw_resource":resource}
	func all_alive() -> bool:
		return not resources.is_empty() and resources.all(func(item: Dictionary): return item.ref.get_ref() != null)
	func all_released_on_main() -> bool:
		return resources.all(func(item: Dictionary): return item.ref.get_ref() == null) and releases.size() == resources.size() and releases.all(func(item: Dictionary): return item.thread == OS.get_main_thread_id())

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label_: String) -> void:
	print("PASS " if ok else "FAIL ", label_)
	if ok: passed += 1
	else: failures += 1

func job(probe: Probe) -> RefCounted:
	var controller: RefCounted = Preparation.new()
	controller.inflight_byte_limit = 100
	controller.memory_estimator = probe.estimate
	controller.eligibility_checker = probe.eligible
	controller.cache_reader = probe.legacy_cache
	controller.candidate_provider = probe.candidate
	controller.candidate_reader = probe.native
	probe.controller = weakref(controller)
	return controller

static func start_failure(_thread: Thread, _task: Callable) -> Error:
	return ERR_CANT_CREATE

static func entry_for(result: Dictionary, path: String) -> Dictionary:
	for entry: Dictionary in result.get("entries", []):
		if entry.get("path") == path: return entry
	return {}

static func contains_old_native(result: Dictionary, path: String) -> bool:
	# Keep these strong aliases local to this helper; the release assertion
	# must not accidentally pin a packet through a test-local entry variable.
	var entry: Dictionary = entry_for(result, path)
	for packet: Variant in entry.get("retained_resources", []):
		if packet is Dictionary and packet.get("packed") is PackedScene and packet.get("native_source_retry") == true and packet.get("source_digest") == OLD_SHA and packet.get("cache_reason") == REASON: return true
	return false

static func stages_for(result: Dictionary, path: String) -> Array:
	return result.get("admission_profile", {}).get("tasks", {}).get(path, {}).get("stages", [])

func settled(result: Dictionary, label_: String) -> void:
	check(result.get("inflight_jobs_at_return", -1) == 0 and result.get("inflight_reserved_at_return", -1) == 0, label_ + ": all inflight admissions released")
	check(result.get("threads_started", -1) == result.get("threads_joined", -2), label_ + ": every started worker joined")

func dispose(result: Dictionary, probe: Probe, label_: String) -> void:
	check(probe.all_alive() and probe.releases.is_empty(), label_ + ": every resource remains owned after worker return")
	result.clear()
	check(probe.all_released_on_main(), label_ + ": clearing the main-owned result releases native/raw resources only on main")

func test_retry(mode: String, synchronous: bool = false) -> void:
	var probe: Probe = Probe.new(); probe.mode = mode
	var controller: RefCounted = job(probe)
	var result: Dictionary = controller.run(["retry"], probe.raw, 2, start_failure if synchronous else Callable())
	var label_: String = mode + (" synchronous-start-failure" if synchronous else "")
	var wanted: Error = ERR_FILE_CORRUPT if mode == "raw_failure" else OK
	check(result.error == wanted and probe.native_calls == ["retry"] and probe.raw_calls == ["retry"], label_ + ": exact source retry runs raw once")
	check(result.entries.size() == 1 and entry_for(result, "retry").get("source_digest") == NEW_SHA and entry_for(result, "retry").get("compiled") == false, label_ + ": final entry carries new raw identity")
	check(contains_old_native(result, "retry"), label_ + ": old native packet remains quarantined in final entry")
	check(result.get("result_resident_estimate_bytes", -1) == 80 and result.get("peak_live_estimate_bytes", 0) >= 80, label_ + ": native 20 and refreshed raw 60 stay charged together")
	check(int(probe.estimates.get("retry", 0)) >= 2, label_ + ": raw envelope is refreshed after source change")
	var stages: Array = stages_for(result, "retry")
	var expected_stages: int = 3 if mode == "serial" else 2
	check(stages.size() == expected_stages and stages[0].reserved_bytes == 20 and stages.back().stage == "raw_import" and stages.back().reserved_bytes == 60, label_ + ": independent native/raw reservations")
	if mode == "serial":
		check(result.get("serial_fallbacks", 0) == 1 and stages[1].reserved_bytes == 60, "serial eligibility requeue preserves quarantine without duplicating its charge")
	if synchronous:
		check(result.get("fallback_count", 0) == 2 and result.threads_started == 0, "failed thread starts execute both stages synchronously without losing ownership")
	settled(result, label_); dispose(result, probe, label_)

func test_cancel() -> void:
	var probe: Probe = Probe.new(); probe.mode = "cancel"
	var controller: RefCounted = job(probe)
	var result: Dictionary = controller.run(["retry", "never"], probe.raw, 1)
	check(result.cancelled and result.error == ERR_SKIP and probe.raw_calls.is_empty() and probe.native_calls == ["retry"], "cancel during native result prevents raw and unscheduled siblings")
	check(result.entries.size() == 1 and entry_for(result, "retry").get("error") == ERR_SKIP and entry_for(result, "retry").get("elapsed_us") is int, "cancel returns timed error entry for the quarantined native packet")
	check(contains_old_native(result, "retry") and result.result_resident_estimate_bytes == 20, "cancel keeps only native quarantine ownership and its charge")
	settled(result, "cancel"); dispose(result, probe, "cancel")

func test_sibling_failure() -> void:
	var probe: Probe = Probe.new(); probe.mode = "sibling"
	var controller: RefCounted = job(probe)
	var result: Dictionary = controller.run(["retry", "sibling_bad", "never"], probe.raw, 2)
	check(result.error == ERR_FILE_CORRUPT and probe.raw_calls.is_empty() and probe.native_calls.size() == 2 and not probe.native_calls.has("never"), "real sibling failure takes priority over the synthetic skipped retry")
	check(result.entries.map(func(entry: Dictionary): return entry.path) == ["retry", "sibling_bad"], "failure entries preserve original input order")
	check(entry_for(result, "retry").get("error") == ERR_SKIP and entry_for(result, "sibling_bad").get("error") == ERR_FILE_CORRUPT and contains_old_native(result, "retry"), "sibling error and skipped quarantined retry both remain observable")
	settled(result, "sibling"); dispose(result, probe, "sibling")

func test_invalid(mode: String) -> void:
	var probe: Probe = Probe.new(); probe.mode = mode
	var controller: RefCounted = job(probe)
	var result: Dictionary = controller.run(["retry"], probe.raw, 1)
	check(result.error != OK and probe.raw_calls.is_empty() and result.entries.size() == 1, mode + ": malformed marker never authorizes raw retry")
	check(stages_for(result, "retry").size() == 1 and not result.admission_profile.stages.has("raw_import"), mode + ": no raw-stage admission occurred")
	settled(result, mode); dispose(result, probe, mode)

func run() -> void:
	check(DisplayServer.get_name() == "headless", "CPU test runs headless")
	test_retry("success")
	test_retry("raw_failure")
	test_retry("success", true)
	test_retry("serial")
	test_cancel()
	test_sibling_failure()
	for mode: String in ["wrong_digest", "wrong_digest_type", "wrong_error", "wrong_error_type", "wrong_compiled", "wrong_compiled_type", "wrong_reason", "wrong_reason_type", "wrong_marker_type", "empty_marker", "false_marker", "missing_marker", "wrong_packed_type", "ordinary_fallback", "marker_and_fallback", "marker_and_false_fallback"]:
		test_invalid(mode)
	print("NATIVE_SOURCE_RETRY passes=", passed, " failures=", failures)
	quit(0 if failures == 0 else 1)
