extends "res://tools/test_deferred_asset_scene.gd"
## Private-desktop GPU runner only. All sources below are small disposable GLBs.
const Prefetch = preload("res://scripts/world3d/initial_model_prefetch.gd")
const Compiled = preload("res://scripts/world3d/compiled_asset_cache.gd")

class Lifetime extends RefCounted:
	var observer: RefCounted
	var kind := ""
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and observer != null:
			observer.record_destruction(kind, OS.get_thread_caller_id())

class Observer extends RefCounted:
	var mutex := Mutex.new()
	var content_root := ""
	var cache_calls := 0
	var gates := 0
	var raw_returns := 0
	var packed_refs: Array = []
	var state_refs: Array = []
	var releases: Array = []
	func read(path: String) -> Dictionary:
		var result: Dictionary = Compiled.read(path, "", content_root)
		if result.get("hit", false):
			var marker := Lifetime.new(); marker.observer = self; marker.kind = "packed"
			# Test-only metadata tracks the actual private PackedScene's last owner.
			# It is added after cache validation and never saved or globally cached.
			result.packed.set_meta("prefetch_test_lifetime", marker)
			mutex.lock(); packed_refs.append(weakref(result.packed)); mutex.unlock()
		mutex.lock(); cache_calls += 1; mutex.unlock()
		return result
	func at_gate() -> void:
		mutex.lock(); gates += 1; mutex.unlock()
	func raw_result(result: Dictionary) -> void:
		if result.get("error") != OK or not result.get("state") is GLTFState: return
		var marker := Lifetime.new(); marker.observer = self; marker.kind = "state"
		result.state.set_meta("prefetch_test_lifetime", marker)
		mutex.lock(); raw_returns += 1; state_refs.append(weakref(result.state)); mutex.unlock()
	func record_destruction(kind: String, thread: int) -> void:
		mutex.lock(); releases.append({"kind": kind, "thread": thread}); mutex.unlock()
	func snapshot() -> Dictionary:
		mutex.lock()
		var value := {"cache_calls": cache_calls, "gates": gates, "raw_returns": raw_returns, "packed_count": packed_refs.size(), "release_count": releases.size()}
		mutex.unlock()
		return value
	func packed_alive() -> bool:
		mutex.lock()
		var okay := not packed_refs.is_empty() and packed_refs.all(func(value: WeakRef): return value.get_ref() != null)
		mutex.unlock()
		return okay
	func all_released_on_main() -> bool:
		mutex.lock()
		var okay := releases.size() == packed_refs.size() + state_refs.size()
		okay = okay and releases.all(func(value: Dictionary): return value.thread == OS.get_main_thread_id())
		okay = okay and packed_refs.all(func(value: WeakRef): return value.get_ref() == null)
		okay = okay and state_refs.all(func(value: WeakRef): return value.get_ref() == null)
		mutex.unlock()
		return okay

class ObservedPreparation extends "res://scripts/world3d/model_parse_preparation.gd":
	var observer: RefCounted
	func _guarded_fallback(path: String, parse: Callable, require_eligible: bool) -> Dictionary:
		observer.at_gate()
		# Keep the real raw importer, full source SHA transaction and admission.
		var result := super._guarded_fallback(path, parse, require_eligible)
		observer.raw_result(result)
		return result

func make_controller(observer: Observer) -> RefCounted:
	var controller := ObservedPreparation.new()
	controller.observer = observer; controller.cache_reader = observer.read
	return controller

func await_gate(observer: Observer, expected_hits: int) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var status := observer.snapshot()
		if status.gates > 0 and status.packed_count == expected_hits: return true
		await process_frame
	return false

func await_packet(helper: RefCounted) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		helper._mutex.lock(); var ready: bool = not helper._discarded.is_empty(); helper._mutex.unlock()
		if ready: return true
		await process_frame
	return false

func join_with_frames(worker: Thread, helper: RefCounted, drain: bool = true) -> Variant:
	var deadline := Time.get_ticks_msec() + 10000
	while worker.is_alive() and Time.get_ticks_msec() < deadline:
		if drain: helper.drain_discarded()
		await process_frame
	if worker.is_alive():
		check(false, "worker finishes while main pumps renderer and quarantine")
		helper.cancel()
		Drainer.drain_shutdown(worker)
		helper.drain_discarded()
		return null
	var value: Variant = worker.wait_to_finish()
	Drainer.synchronize_transfer()
	if drain: helper.drain_discarded()
	return value

func cancel_cleanup(helper: RefCounted) -> void:
	helper.cancel()
	var worker := Thread.new()
	if worker.start(helper.abandon) == OK: await join_with_frames(worker, helper)
	else:
		# The private desktop keeps the renderer pumping even on startup failure.
		if helper._worker != null:
			while helper._worker.is_alive(): await process_frame
		helper.abandon(); helper.drain_discarded()

func test_discard(compiled_path: String, raw_path: String, mode: String) -> void:
	print("PREFETCH_GPU_", mode.to_upper(), "_BEGIN")
	var observer := Observer.new(); observer.content_root = Paths.external_root()
	var controller := make_controller(observer)
	var helper := Prefetch.new()
	check(helper.start([compiled_path, raw_path], controller, 2, observer.content_root), mode + ": real private model coordinator starts")
	var ready := await await_gate(observer, 1)
	check(ready and observer.packed_alive() and observer.snapshot().raw_returns == 0, mode + ": real native product is retained while raw import is gated")
	if not ready:
		await cancel_cleanup(helper); return
	check(not Library._scenes.has(compiled_path) and not Library._scenes.has(raw_path), mode + ": speculative preparation has not polluted AssetLibrary")
	var caller := Thread.new()
	if mode == "mismatch":
		check(caller.start(helper.take.bind([raw_path])) == OK, "mismatch: parser-side take starts")
		var quarantined := await await_packet(helper)
		check(quarantined and caller.is_alive() and observer.packed_alive(), "mismatch: private PackedScene survives until main disposal acknowledgement")
		if not quarantined: helper.cancel()
		var rejected: Variant = await join_with_frames(caller, helper)
		check(rejected is Dictionary and not rejected.get("accepted", true) and not rejected.has("result"), "mismatch: parser receives no rejected GPU resource packet")
	else:
		if mode == "cancel": helper.cancel()
		check(caller.start(helper.abandon) == OK, mode + ": early parser return joins through abandon")
		await join_with_frames(caller, helper, false)
		check(observer.packed_alive() and observer.snapshot().release_count == 0, mode + ": successful sibling remains quarantined after worker join")
		helper.drain_discarded()
	check(observer.snapshot().raw_returns == 0, mode + ": cancellation never opens the unvalidated raw path")
	check(observer.snapshot().release_count == 1 and observer.all_released_on_main(), mode + ": real PackedScene weak reference expires only through main drain")
	helper.drain_discarded()
	check(observer.snapshot().release_count == 1, mode + ": repeated drain does not destroy resources twice")
	print("PREFETCH_GPU_", mode.to_upper(), "_END")

func test_raw_success(raw_path: String, expected: Dictionary) -> void:
	print("PREFETCH_GPU_RAW_SUCCESS_BEGIN")
	var observer := Observer.new(); observer.content_root = Paths.external_root()
	var controller := make_controller(observer)
	var helper := Prefetch.new()
	check(helper.start([raw_path], controller, 2, observer.content_root), "raw: real cache-miss coordinator starts")
	var ready := await await_gate(observer, 0)
	check(ready and observer.snapshot().raw_returns == 0, "raw: no GLTFDocument/GLTFState is returned before validation opens")
	if not ready:
		await cancel_cleanup(helper); return
	var caller := Thread.new()
	check(caller.start(helper.take.bind([raw_path])) == OK, "raw: parser-side matching take opens gate")
	var taken: Variant = await join_with_frames(caller, helper)
	check(taken is Dictionary and taken.get("accepted", false) and taken.result.error == OK, "raw: real append and complete source transaction succeed")
	if not taken is Dictionary or not taken.get("accepted", false) or taken.result.error != OK:
		if taken is Dictionary: taken.clear()
		return
	var entry: Dictionary = taken.result.entries[0]
	check(not entry.get("compiled", false) and entry.get("document") is GLTFDocument and entry.get("state") is GLTFState and not entry.has("scene"), "raw: handoff contains private parser state, never an unowned worker Node")
	check(entry.source_digest == FileAccess.get_sha256(raw_path), "raw: returned geometry identity matches complete current source SHA")
	check(taken.result.threads_started == taken.result.threads_joined and taken.result.inflight_reserved_at_return == 0, "raw: all preparation workers and admission reservations are settled")
	var scene: Node = Io.generate_scene(entry.document, entry.state)
	check(scene != null, "raw: verified parser state generates a scene on main")
	if scene != null:
		check(var_to_bytes(capture(scene)) == var_to_bytes(expected), "raw: generated geometry, pixels, material and metadata exactly match the serial fixture")
		Drainer.dispose_scene(scene)
	entry.clear(); taken.clear()
	Drainer.synchronize_transfer()
	check(observer.snapshot().raw_returns == 1 and observer.all_released_on_main(), "raw: GLTFState ownership ends on main after its scene is safely destroyed")
	check(not Library._scenes.has(raw_path), "raw: successful private handoff does not publish a global scene template")
	print("PREFETCH_GPU_RAW_SUCCESS_END")

func run() -> void:
	Engine.max_fps = 60
	create_timer(90).timeout.connect(func(): quit(2))
	if DisplayServer.get_name() == "headless":
		check(false, "real GPU lifecycle test requires the private-desktop runner"); quit(1); return
	var folder := Paths.cache_directory("initial_model_prefetch_gpu_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var compiled_path := folder.path_join("compiled.glb")
	var raw_path := folder.path_join("raw.glb")
	static_fixture(compiled_path, Color(.2, .6, .3, 1))
	static_fixture(raw_path, Color(.8, .3, .2, 1))
	var original: Node = Io.load_scene(raw_path)
	check(original != null, "temporary serial reference fixture loads")
	if original == null: quit(1); return
	var expected := capture(original)
	Drainer.dispose_scene(original)
	print("PREFETCH_GPU_BUILD_BEGIN")
	check(Compiled.build(compiled_path).ok, "temporary static source compiles for a genuine native hit")
	Drainer.synchronize_transfer()
	print("PREFETCH_GPU_BUILD_END")
	check(not FileAccess.file_exists(Compiled.index_path(raw_path)), "raw fixture has no compiled product to hide its real import")
	var library_before: Dictionary = Library._scenes.duplicate()
	await test_discard(compiled_path, raw_path, "mismatch")
	await test_discard(compiled_path, raw_path, "abandon")
	await test_discard(compiled_path, raw_path, "cancel")
	await test_raw_success(raw_path, expected)
	Drainer.synchronize_transfer()
	check(Library._scenes == library_before and not Library._scenes.has(compiled_path) and not Library._scenes.has(raw_path), "all prefetch outcomes preserve global AssetLibrary contents")
	print("INITIAL_MODEL_PREFETCH_GPU failures=", failures)
	quit(0 if failures == 0 else 1)
