extends "res://tools/test_deferred_asset_scene.gd"
## Private-desktop GPU only. Tiny fixture raw estimates are padded UP to cover
## native admission despite its 64 MiB floor; this is not a performance sample.
const Compiled = preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint = preload("res://scripts/world3d/compiled_asset_footprint.gd")
const NativeReader = preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Estimate = preload("res://scripts/world3d/asset_memory_estimate.gd")
var raw_floor := 0
var content_root := ""
var temporary_files: Array[String] = []

class Lifetime extends RefCounted:
	var observer: RefCounted
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and observer != null:
			observer.releases.append(OS.get_thread_caller_id())

class Observe extends RefCounted:
	var content_root := ""
	var mode := ""
	var resources: Array[WeakRef] = []
	var releases: Array[int] = []
	var controller: WeakRef
	func read(path: String, candidate: Dictionary) -> Dictionary:
		var result: Dictionary = NativeReader.read(path, candidate, content_root)
		if result.get("packed") != null:
			var packed: PackedScene = result.packed
			var marker := Lifetime.new(); marker.observer = self
			packed.set_meta("native_budget_test_lifetime", marker)
			resources.append(weakref(packed))
			var state := packed.get_state(); var seen := {}
			for node in state.get_node_count():
				for property in state.get_node_property_count(node):
					watch_value(state.get_node_property_value(node, property), seen)
			if mode == "fatal": result.error = ERR_BUSY
			if mode == "forbidden_fallback": result.error = OK; result.fallback_required = true
			if mode == "cancel" and controller != null: controller.get_ref().cancel()
		return result
	func watch_value(value: Variant, seen: Dictionary) -> void:
		if value is Resource:
			var id: int = value.get_instance_id()
			if seen.has(id): return
			seen[id] = true; resources.append(weakref(value))
			# Watch the real texture, not a new Image returned by GPU readback.
			if value is ImageTexture or value is Image: return
			for property in value.get_property_list():
				if int(property.usage) & PROPERTY_USAGE_STORAGE:
					watch_value(value.get(property.name), seen)
		elif value is Array:
			for item in value: watch_value(item, seen)
		elif value is Dictionary:
			for key in value:
				watch_value(key, seen); watch_value(value[key], seen)
	func alive() -> bool:
		return not resources.is_empty() and resources.all(func(value: WeakRef): return value.get_ref() != null)
	func released() -> bool:
		return not resources.is_empty() and resources.all(func(value: WeakRef): return value.get_ref() == null) and releases.size() == 1 and releases[0] == OS.get_main_thread_id()

class ObservedPreparation extends "res://scripts/world3d/model_parse_preparation.gd":
	var raw_calls := 0
	func _guarded_fallback(path: String, parse: Callable, require_eligible: bool) -> Dictionary:
		raw_calls += 1
		return super._guarded_fallback(path, parse, require_eligible)

static func padded_raw(path: String, minimum: int) -> Dictionary:
	var estimate: Dictionary = Estimate.estimate(path)
	estimate.estimated_bytes = maxi(int(estimate.estimated_bytes), minimum)
	return estimate

func make_job(observer: Observe, snapshot: Dictionary = {}) -> RefCounted:
	var job := ObservedPreparation.new()
	job.memory_estimator = padded_raw.bind(raw_floor)
	job.candidate_reader = observer.read
	observer.content_root = content_root; observer.controller = weakref(job)
	if not snapshot.is_empty():
		var fixed := snapshot.duplicate(true)
		job.candidate_provider = func(_path: String): return fixed.duplicate(true)
	return job

func prepare(job: RefCounted, path: String, verified_sources: Dictionary = {}) -> Dictionary:
	var worker := Thread.new()
	var error := worker.start(job.run.bind([path], Callable(), 2, Callable(), content_root, verified_sources))
	check(error == OK, "background coordinator starts")
	if error != OK: return {"error":error, "entries":[]}
	while worker.is_alive(): await process_frame
	var result: Dictionary = worker.wait_to_finish()
	Drainer.synchronize_transfer()
	check(result.get("inflight_jobs_at_return", -1) == 0 and result.get("inflight_reserved_at_return", -1) == 0 and result.get("threads_joined", -1) == result.get("threads_started", -2), "workers and reservations settle before main takes ownership")
	return result

func release_packet(packet: Dictionary, observer: Observe, expect_resources: bool) -> void:
	Drainer.synchronize_transfer(); packet.clear(); Drainer.synchronize_transfer()
	await process_frame
	if expect_resources: check(observer.released(), "PackedScene, mesh, material and texture release on main after renderer synchronization")

func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "temporary file can be written")
	if file != null: file.store_buffer(bytes); file.close()

func scene_from(packet: Dictionary) -> Node:
	if packet.get("error", FAILED) != OK or packet.get("entries", []).size() != 1: return null
	var entry: Dictionary = packet.entries[0]
	return entry.packed.instantiate() if entry.get("packed") != null else Io.generate_scene(entry.document, entry.state)

func compare_scene(packet: Dictionary, expected: Dictionary, label_: String) -> void:
	var scene: Node = scene_from(packet)
	check(scene != null, label_ + ": scene instantiates")
	if scene == null: return
	check(var_to_bytes(capture(scene)) == var_to_bytes(expected), label_ + ": geometry, pixels, materials and visibility equal raw source")
	Drainer.dispose_scene(scene)

func test_miss(path: String, candidate: Dictionary, expected: Dictionary, kind: String) -> void:
	var product: String = candidate.product
	var bytes := FileAccess.get_file_as_bytes(product)
	if kind == "missing":
		check(DirAccess.rename_absolute(product, product + ".test-held") == OK, "temporarily hide this test's private product")
	else:
		var corrupt := bytes.duplicate(); corrupt[corrupt.size() / 2] ^= 1
		write_bytes(product, corrupt)
	var observer := Observe.new(); var job := make_job(observer, candidate)
	var packet: Dictionary = await prepare(job, path)
	if kind == "missing": check(DirAccess.rename_absolute(product + ".test-held", product) == OK, "restore this test's hidden product")
	else: write_bytes(product, bytes)
	check(packet.error == OK and job.raw_calls == 1 and observer.resources.is_empty(), kind + ": preallocation miss imports raw without creating a native resource")
	var tasks: Dictionary = packet.get("admission_profile", {}).get("tasks", {})
	var stages: Array = tasks.get(path, {}).get("stages", [])
	check(stages.size() == 2 and stages[0].stage == "compiled_read" and stages[0].reserved_bytes == candidate.estimated_bytes and stages[1].stage == "raw_import" and stages[1].reserved_bytes >= raw_floor, kind + ": raw re-enters its full separate reservation")
	check(packet.get("result_resident_estimate_bytes", 0) >= raw_floor, kind + ": raw result keeps its full retained charge")
	compare_scene(packet, expected, kind + " fallback")
	await release_packet(packet, observer, false)

func cleanup() -> void:
	Drainer.synchronize_transfer()
	for path in temporary_files:
		if path.get_extension() == "glb": Library._compiled_imports.erase(path)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func test_import_integration(path: String, candidate: Dictionary) -> void:
	var descriptor := Footprint.descriptor_path(path, content_root)
	var existing: Dictionary = Library._compile_footprint(path)
	check(existing.get("ok", false) and existing.get("reused", false), "AssetLibrary reuses an existing verified native footprint")
	check(existing.get("estimated_bytes", 0) == candidate.estimated_bytes and existing.get("resident_bytes", 0) == candidate.resident_bytes, "AssetLibrary footprint reuse preserves the candidate's budget")
	# The descriptor belongs to this uniquely named test source. Do not remove
	# another source's descriptor or invalidate any shared compiled product.
	check(temporary_files.has(descriptor) and Paths.allowed(descriptor, Footprint.directory(content_root)), "automatic rebuild fixture owns the descriptor being removed")
	if not temporary_files.has(descriptor) or not Paths.allowed(descriptor, Footprint.directory(content_root)): return
	check(DirAccess.remove_absolute(descriptor) == OK and not FileAccess.file_exists(descriptor), "remove only this test's descriptor to exercise automatic import repair")
	var repaired: Dictionary = Library._compile_import(path)
	var repaired_footprint: Dictionary = repaired.get("footprint", {})
	check(repaired.get("ok", false) and repaired.get("reused", false), "AssetLibrary import retains the successful existing native compilation")
	check(repaired_footprint.get("ok", false) and not repaired_footprint.get("reused", true) and FileAccess.file_exists(descriptor), "AssetLibrary import automatically rebuilds a missing footprint")
	var rebuilt := Footprint.candidate(path, content_root, candidate.source_sha)
	check(not rebuilt.is_empty() and rebuilt.get("payload_sha") == candidate.payload_sha and rebuilt.get("estimated_bytes") == candidate.estimated_bytes and rebuilt.get("resident_bytes") == candidate.resident_bytes, "automatic footprint repair binds the same source/product and budget")
	var descriptor_bytes := FileAccess.get_file_as_bytes(descriptor)
	var repeated: Dictionary = Library._compile_import(path)
	check(repeated.get("ok", false) and repeated.get("reused", false) and repeated.get("footprint", {}).get("ok", false) and repeated.get("footprint", {}).get("reused", false), "repeated AssetLibrary import reuses both native compilation and footprint")
	check(FileAccess.get_file_as_bytes(descriptor) == descriptor_bytes and FileAccess.get_sha256(str(candidate.product)) == candidate.payload_sha, "repeated import preserves descriptor bytes and the immutable native payload")

func test_same_length_change(path: String, candidate: Dictionary, source_bytes: PackedByteArray) -> void:
	# Change one vertex to another finite float, preserving GLB and PNG lengths.
	var changed := source_bytes.duplicate()
	var bin_start: int = 28 + int(changed.decode_u32(12))
	var vertex := PackedFloat32Array([.125]).to_byte_array()
	for index in 4: changed[bin_start + index] = vertex[index]
	write_bytes(path, changed)
	var changed_sha := FileAccess.get_sha256(path)
	check(changed.size() == source_bytes.size() and changed_sha != candidate.source_sha, "source replacement preserves length but changes full identity")
	var raw_scene: Node = Io.load_scene(path)
	check(raw_scene != null, "same-length replacement is still a valid static GLB")
	var changed_capture: Dictionary = capture(raw_scene) if raw_scene != null else {}
	if raw_scene != null: Drainer.dispose_scene(raw_scene); raw_scene = null
	var observer := Observe.new(); var job := make_job(observer, candidate)
	var packet: Dictionary = await prepare(job, path)
	check(packet.error == OK and job.raw_calls == 1 and observer.alive(), "same-length stale source retires native resources and follows raw fallback")
	check(packet.get("retired_native_estimate_bytes", 0) == candidate.estimated_bytes and packet.get("result_resident_estimate_bytes", 0) >= raw_floor + candidate.estimated_bytes, "retired native and fresh raw reservations are both charged")
	var stages: Array = packet.get("admission_profile", {}).get("tasks", {}).get(path, {}).get("stages", [])
	check(stages.size() == 2 and stages[1].stage == "raw_import" and stages[1].reserved_bytes >= raw_floor, "same-length replacement reserves full refreshed raw envelope")
	check(packet.entries.size() == 1 and packet.entries[0].get("source_digest") == changed_sha, "raw result identifies the actual same-length replacement")
	# GLTFState scene generation is a consuming operation. Hold one actual raw
	# instance across the retirement fence instead of generating it twice.
	var fallback_scene:Node=scene_from(packet)
	check(fallback_scene!=null,"same-length raw fallback instantiates")
	if fallback_scene!=null and not changed_capture.is_empty():check(var_to_bytes(capture(fallback_scene))==var_to_bytes(changed_capture),"same-length raw fallback preserves current source")
	var loader:=preload("res://scripts/world3d/map_loader.gd").new()
	loader._asset_states[path]=packet.entries[0]
	loader._release_retired_models()
	check(observer.released() and not packet.entries[0].has("retained_resources"), "MapLoader main handoff releases retired native resources immediately after join")
	if fallback_scene!=null:
		if not changed_capture.is_empty():check(var_to_bytes(capture(fallback_scene))==var_to_bytes(changed_capture),"raw geometry, pixels and materials survive retired native cleanup")
		Drainer.dispose_scene(fallback_scene);fallback_scene=null
	loader._asset_states.clear();loader.free()
	await release_packet(packet, observer, true)
	observer = Observe.new(); job = make_job(observer, candidate)
	packet = await prepare(job, path, {path:candidate.source_sha})
	check(packet.error == ERR_BUSY and job.raw_calls == 1 and observer.alive(), "known expected source SHA rejects changed source and retains retired native resources")
	stages = packet.get("admission_profile", {}).get("tasks", {}).get(path, {}).get("stages", [])
	check(stages.size() == 2 and stages[1].reserved_bytes >= raw_floor, "identity rejection never bypasses raw-stage re-admission")
	await release_packet(packet, observer, true)
	write_bytes(path, source_bytes)
	check(FileAccess.get_sha256(path) == candidate.source_sha, "restore original source identity after same-length replacement tests")

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("NATIVE_MODEL_BUDGET_GPU timeout"); quit(2))
	if DisplayServer.get_name() == "headless": push_error("Private-desktop GPU required"); quit(2); return
	Engine.max_fps = 60
	content_root = Paths.external_root()
	var folder := Paths.cache_directory("native_model_budget_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("source.glb")
	static_fixture(path, Color(.17, .43, .79, 1), false, float(Time.get_ticks_usec() % 10000000))
	temporary_files.append(path)
	var source_bytes := FileAccess.get_file_as_bytes(path)
	var original: Node = Io.load_scene(path)
	check(original != null, "temporary static source imports raw")
	if original == null: cleanup(); quit(1); return
	var expected := capture(original); Drainer.dispose_scene(original); original = null
	var existing := DirAccess.get_files_at(Compiled.directory(content_root))
	var built: Dictionary = Compiled.build(path)
	check(built.get("ok", false), "real static fixture builds a native product")
	if not built.get("ok", false): cleanup(); quit(1); return
	var index := Compiled.index_path(path, content_root)
	temporary_files.append(index)
	var manifest_bytes := FileAccess.get_file_as_bytes(index)
	var manifest: Dictionary = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	var product := Compiled.directory(content_root).path_join(str(manifest.payload_sha) + ".scn")
	check(not existing.has(product.get_file()), "mutation fixture owns a new payload, never a preexisting shared cache entry")
	if existing.has(product.get_file()): cleanup(); quit(1); return
	temporary_files.append(product)
	var footprint: Dictionary = Footprint.build(path, content_root)
	check(footprint.get("ok", false), "offline footprint measures the verified native resource graph")
	if not footprint.get("ok", false): print(footprint); cleanup(); quit(1); return
	temporary_files.append(Footprint.descriptor_path(path, content_root))
	var candidate: Dictionary = Footprint.candidate(path, content_root, FileAccess.get_sha256(path))
	check(not candidate.is_empty(), "source/payload-bound descriptor produces a fixed candidate")
	if candidate.is_empty(): cleanup(); quit(1); return
	test_import_integration(path, candidate)
	raw_floor = int(candidate.estimated_bytes) + 128 * 1024 * 1024
	print("TEST_ONLY conservative raw padding=", raw_floor, " native=", candidate.estimated_bytes)
	var observer := Observe.new(); var job := make_job(observer)
	var packet: Dictionary = await prepare(job, path)
	check(packet.error == OK and packet.get("native_cache_hits", 0) == 1 and job.raw_calls == 0 and observer.alive(), "real candidate read retains a native hit without raw import")
	check(packet.get("result_resident_estimate_bytes", 0) == candidate.estimated_bytes, "completed native result retains its admitted estimate")
	compare_scene(packet, expected, "native")
	await release_packet(packet, observer, true)
	# Changing the manifest cannot replace the product already reserved.
	var changed := manifest.duplicate(true); changed.payload_sha = "0".repeat(64); changed.bytes = 1
	write_bytes(index, JSON.stringify(changed).to_utf8_buffer())
	observer = Observe.new(); job = make_job(observer, candidate)
	packet = await prepare(job, path)
	write_bytes(index, manifest_bytes)
	check(packet.error == OK and packet.get("native_cache_hits", 0) == 1 and job.raw_calls == 0, "fixed candidate survives manifest generation replacement")
	compare_scene(packet, expected, "fixed candidate")
	await release_packet(packet, observer, true)
	await test_miss(path, candidate, expected, "missing")
	await test_miss(path, candidate, expected, "corrupt")
	await test_same_length_change(path, candidate, source_bytes)
	for mode in ["fatal", "forbidden_fallback", "cancel"]:
		observer = Observe.new(); observer.mode = mode; job = make_job(observer)
		packet = await prepare(job, path)
		var wanted: int = ERR_BUSY if mode == "fatal" else (ERR_INVALID_DATA if mode == "forbidden_fallback" else ERR_SKIP)
		check(packet.error == wanted and packet.entries.size() == 1 and job.raw_calls == 0, mode + ": resource-created failure/cancel retains result without raw fallback")
		check(observer.alive() and observer.releases.is_empty(), mode + ": GPU resource ownership survives every worker exit")
		await release_packet(packet, observer, true)
	check(FileAccess.get_file_as_bytes(path) == source_bytes, "source GLB is unchanged through every preparation/failure case")
	cleanup(); DirAccess.remove_absolute(folder)
	print("NATIVE_MODEL_BUDGET_GPU failures=", failures)
	quit(0 if failures == 0 else 1)
