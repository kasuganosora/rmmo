extends "res://tools/test_deferred_asset_scene.gd"
## Root runs this via run_godot_background.py. All sources/products are tiny,
## uniquely named fixtures; no formal map or shared AssetLibrary publication.
const Compiled = preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint = preload("res://scripts/world3d/compiled_asset_footprint.gd")
const NativeReader = preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Trace = preload("res://scripts/world3d/load_trace.gd")
var temporary_files: Array[String] = []
var content_root := ""

class Lifetime extends RefCounted:
	var observer: RefCounted
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and observer != null:
			observer.releases.append(OS.get_thread_caller_id())

class PrivatePreparation extends RefCounted:
	var mode := "stable"
	var path := ""
	var changed_bytes := PackedByteArray()
	var calls := 0
	var caller_id := 0
	var schema_validated := false
	var write_error := OK
	var capture_complete := false
	var resources: Array[WeakRef] = []
	var nodes: Array[WeakRef] = []
	var releases: Array[int] = []
	var marker_count := 0
	var seen := {}
	func mark(resource: Object) -> void:
		var marker := Lifetime.new(); marker.observer = self
		resource.set_meta("test_private_preparation_lifetime", marker)
		marker_count += 1
	func watch(value: Variant) -> void:
		if value is Resource:
			var id: int = value.get_instance_id()
			if seen.has(id): return
			seen[id] = true; resources.append(weakref(value))
			# ImageTexture.get_image() makes a new readback Image, not an owned one.
			if value is ImageTexture or value is Image or value is Script: return
			for info in value.get_property_list():
				if int(info.usage) & PROPERTY_USAGE_STORAGE and str(info.name) != "script":
					watch(value.get(info.name))
			if value is Mesh and value.has_meta("ground_cpu_cache"):
				watch(value.get_meta("ground_cpu_cache"))
		elif value is Array:
			for item in value: watch(item)
		elif value is Dictionary:
			for key in value: watch(key); watch(value[key])
	func watch_scene(scene: Node) -> void:
		nodes.append(weakref(scene))
		if scene is MeshInstance3D:
			watch(scene.mesh); watch(scene.material_override)
			if scene.mesh.has_meta("ground_cpu_cache"): watch(scene.mesh.get_meta("ground_cpu_cache"))
			for slot in scene.get_surface_override_material_count():
				watch(scene.get_surface_override_material(slot))
		for child in scene.get_children(): watch_scene(child)
	func prepare(packed: PackedScene) -> Variant:
		calls += 1; caller_id = OS.get_thread_caller_id()
		schema_validated = packed.get_meta("compiled_asset_validated", false)
		watch(packed)
		var packed_state := packed.get_state()
		for node in packed_state.get_node_count():
			for property in packed_state.get_node_property_count(node):
				watch(packed_state.get_node_property_value(node, property))
		mark(packed)
		var scene: Node = Compiled.instantiate(packed)
		if scene == null: return {"error":ERR_CANT_CREATE, "scene":scene}
		var cpu: Dictionary = Deferred._capture_static_meshes(scene, true)
		capture_complete = cpu.error.is_empty() and cpu.captured_meshes > 0 and cpu.face_bytes > 0
		watch_scene(scene); mark(scene)
		# Explicit parser resources exercise the packet's complete ownership on
		# error paths too; this callback does not perform an additional raw parse.
		var document := GLTFDocument.new(); var state := GLTFState.new()
		watch(document); watch(state); mark(document); mark(state)
		var packet := {"error":OK, "scene":scene, "capture":cpu,
			"document":document, "state":state,
			"source_digest":"callback_must_not_replace_identity", "packed":"callback_value",
			"native_source_retry":true, "fallback_required":true}
		if not capture_complete: packet.error = ERR_INVALID_DATA; return packet
		if mode == "replace" or mode == "fail_replace":
			# The mutation occurs only AFTER native instantiate and CPU capture.
			var file := FileAccess.open(path, FileAccess.WRITE)
			write_error = FileAccess.get_open_error()
			if file != null: file.store_buffer(changed_bytes); file.close()
		if mode == "cancel":
			var token := Drainer.CancelToken.new(); token.cancel()
			packet.capture = Deferred._capture_static_meshes(scene, true, token)
			packet.error = ERR_SKIP; packet.cancelled = true
		elif mode == "fail" or mode == "fail_replace": packet.error = ERR_CANT_CREATE
		elif mode == "malformed_error": packet.error = "not an integer"
		elif mode == "missing_error": packet.erase("error")
		elif mode == "missing_scene": packet.retained_resources = [scene]; packet.erase("scene")
		elif mode == "malformed_return": return [packet, scene, document, state]
		return packet
	func alive() -> bool:
		return not resources.is_empty() and resources.all(func(ref: WeakRef): return ref.get_ref() != null) and nodes.all(func(ref: WeakRef): return ref.get_ref() != null) and releases.is_empty()
	func released() -> bool:
		return not resources.is_empty() and resources.all(func(ref: WeakRef): return ref.get_ref() == null) and nodes.all(func(ref: WeakRef): return ref.get_ref() == null) and releases.size() == marker_count and releases.all(func(id: int): return id == OS.get_main_thread_id())

func native_read(path: String, candidate: Dictionary, observer: PrivatePreparation = null) -> Dictionary:
	var worker := Thread.new()
	var callback := Callable() if observer == null else observer.prepare
	var error := worker.start(NativeReader.read.bind(path, candidate, content_root, callback))
	check(error == OK, "native private reader starts on a worker")
	if error != OK: return {"error":error}
	while worker.is_alive(): await process_frame
	var packet: Dictionary = worker.wait_to_finish()
	Drainer.synchronize_transfer()
	return packet

func release_packet(packet: Dictionary, observer: PrivatePreparation = null) -> void:
	# Exercise the production main-thread ownership transfer, including nested
	# malformed return containers and alias references to the same owned Node.
	var alias := packet
	Drainer.dispose_result(packet)
	check(packet.is_empty() and alias.is_empty(), "main disposal clears the original packet even through aliases")
	await process_frame
	if observer != null: check(observer.released(), "all callback Nodes, meshes, materials, textures, CPU caches and parser resources release on main")

func compare_scene(packet: Dictionary, expected: Dictionary) -> void:
	var prepared: Variant = packet.get("private_preparation")
	check(prepared is Dictionary and prepared.get("scene") is Node, "private callback scene is returned without publishing")
	if not prepared is Dictionary or not prepared.get("scene") is Node: return
	var scene: Node = prepared.scene
	check(not scene.is_inside_tree() and scene.get_parent() == null, "prepared scene stays private and off-tree")
	check(var_to_bytes(capture(scene)) == var_to_bytes(expected), "prepared native geometry, material pixels, visibility and collision metadata match raw source")
	var plain: MeshInstance3D = scene.find_child("Plain", true, false)
	var grass: MeshInstance3D = scene.find_child("Grass", true, false)
	check(plain != null and grass != null, "fixture contains both collision and noncollision nodes")
	if plain == null or grass == null: return
	var cpu: Mesh = plain.mesh.get_meta("ground_cpu_cache")
	check(cpu != null and plain.mesh == grass.mesh and prepared.capture.captured_meshes == 1, "shared mesh CPU capture is performed exactly once")
	if cpu != null:
		check(cpu._collision_faces == plain.mesh.get_faces(), "captured collision triangle soup exactly matches original GPU mesh")
		check(Deferred.Stream._spec(plain).collision_mesh == cpu, "main streaming collection consumes the callback's existing CPU geometry")
	check(plain.get_meta("extras").get("rmmo_collision") == "block" and grass.get_meta("extras").get("rmmo_collision") == "none", "blocking and nonblocking collision roles remain distinct")

func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "temporary source can be restored")
	if file != null: file.store_buffer(bytes); file.close()

func test_raw_root_rejection(path: String, digest: String) -> void:
	# The valid fixture remains inside the real content root, but outside this
	# deliberately narrower caller root. No symlink or invalid GLB is involved.
	var wrong_root := path.get_base_dir().path_join("narrow_root")
	check(Paths.allowed(path, content_root) and not Paths.allowed(path, wrong_root), "root rejection fixture is valid but outside the explicitly supplied root")
	var calls: Array[Callable] = [
		Deferred.prepare_scene.bind(path, digest, null, {}, false, wrong_root, true),
		Deferred._fallback_scene.bind(path, null, wrong_root)]
	var labels := ["raw_only prepare_scene", "serialized raw fallback"]
	for index in calls.size():
		Trace.start()
		var worker := Thread.new()
		var code := worker.start(calls[index])
		check(code == OK, labels[index] + ": rejection worker starts")
		if code != OK: Trace.stop(); continue
		while worker.is_alive(): await process_frame
		var packet: Dictionary = worker.wait_to_finish()
		var trace := Trace.stop()
		check(packet.get("error", "") == "素材路径无效：" + path and packet.size() == 1 and not packet.has("retained_resources"), labels[index] + ": outside root fails without parser, scene or retained resources")
		var work_started := false
		for stat: Dictionary in trace.stats:
			if stat.label != "deferred.raw_import_wait": work_started = true
		check(not work_started, labels[index] + ": no SHA, native read, parse, generate or CPU capture stage runs")
		await release_packet(packet)

func cleanup() -> void:
	Drainer.synchronize_transfer()
	for path in temporary_files:
		if path.get_extension() == "glb": Library._compiled_imports.erase(path)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("DEFERRED_NATIVE_PREPARATION_GPU timeout"); quit(2))
	if DisplayServer.get_name() == "headless": push_error("Private-desktop GPU required"); quit(2); return
	Engine.max_fps = 60; content_root = Paths.external_root()
	NativeReader.source_precheck_enabled = false
	var folder := Paths.cache_directory("deferred_native_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("source.glb"); temporary_files.append(path)
	static_fixture(path, Color(.23, .51, .71, 1), false, float(Time.get_ticks_usec() % 10000000))
	var original: Node = Io.load_scene(path)
	check(original != null, "temporary fixture imports raw")
	if original == null: cleanup(); quit(1); return
	var expected := capture(original); Drainer.dispose_scene(original); original = null
	var source_bytes := FileAccess.get_file_as_bytes(path)
	var changed := source_bytes.duplicate()
	var bin_start: int = 28 + int(changed.decode_u32(12))
	var vertex := PackedFloat32Array([.125]).to_byte_array()
	for index in 4: changed[bin_start + index] = vertex[index]
	check(changed.size() == source_bytes.size() and changed != source_bytes, "source mutation changes a finite vertex without changing GLB length")
	var existing := DirAccess.get_files_at(Compiled.directory(content_root))
	var built := Compiled.build(path)
	check(built.get("ok", false), "fixture builds an actual native PackedScene")
	if not built.get("ok", false): cleanup(); quit(1); return
	var index_path := Compiled.index_path(path, content_root); temporary_files.append(index_path)
	var candidate := Footprint._identity(path, content_root)
	check(not candidate.is_empty(), "fixed candidate has source and payload identity")
	if candidate.is_empty(): cleanup(); quit(1); return
	await test_raw_root_rejection(path, candidate.source_sha)
	var product: String = candidate.product
	if not existing.has(product.get_file()): temporary_files.append(product)
	var index_bytes := FileAccess.get_file_as_bytes(index_path)
	# A newer index must not make the admitted immutable candidate switch product.
	write_bytes(index_path, "{}".to_utf8_buffer())
	var observer := PrivatePreparation.new()
	var packet := await native_read(path, candidate, observer)
	write_bytes(index_path, index_bytes)
	check(packet.get("error", FAILED) == OK and observer.calls == 1 and observer.schema_validated and observer.caller_id != OS.get_main_thread_id(), "fixed native candidate performs one validated private preparation on worker")
	check(packet.get("source_digest") == candidate.source_sha and packet.get("compiled_payload_bytes") == candidate.bytes and packet.get("packed") is PackedScene and not packet.has("native_source_retry") and not packet.has("fallback_required"), "callback cannot overwrite any accepted identity, ownership or retry flags")
	check(observer.capture_complete and observer.alive(), "complete native capture remains strongly owned through worker exit")
	compare_scene(packet, expected)
	check(not Library._scenes.has(path), "private preparation never publishes a global AssetLibrary template")
	await release_packet(packet, observer)
	# Existing callers keep the old packet shape and successful native behavior.
	packet = await native_read(path, candidate)
	check(packet.get("error", FAILED) == OK and not packet.has("private_preparation"), "omitting callback preserves native reader behavior and result shape")
	await release_packet(packet)
	for mode in ["replace", "fail_replace", "cancel", "fail", "malformed_error", "missing_error", "missing_scene", "malformed_return"]:
		observer = PrivatePreparation.new(); observer.mode = mode; observer.path = path; observer.changed_bytes = changed
		packet = await native_read(path, candidate, observer)
		var wanted := ERR_INVALID_DATA
		if mode == "replace": wanted = ERR_BUSY
		elif mode == "cancel": wanted = ERR_SKIP
		elif mode == "fail" or mode == "fail_replace": wanted = ERR_CANT_CREATE
		check(packet.get("error", OK) == wanted and observer.calls == 1 and observer.capture_complete and observer.alive(), mode + ": callback failure or source rejection retains all prepared resources")
		check(packet.has("private_preparation") and packet.get("native_source_retry", false) == (mode == "replace") and not packet.get("fallback_required", false), mode + ": only a successful callback followed by source mismatch can request native retry")
		if mode == "replace" or mode == "fail_replace":
			check(observer.write_error == OK and FileAccess.get_file_as_bytes(path) == changed and FileAccess.get_sha256(path) != candidate.source_sha, mode + ": final gate detects same-length replacement after capture")
			write_bytes(path, source_bytes)
		if mode == "cancel": check(packet.private_preparation.capture.get("cancelled", false), "callback cancellation comes from the actual CPU capture cancellation gate")
		check(not Library._scenes.has(path), mode + ": failure cannot publish a global template")
		await release_packet(packet, observer)
	check(FileAccess.get_file_as_bytes(path) == source_bytes, "all cases leave the original source bytes intact")
	cleanup(); DirAccess.remove_absolute(folder)
	print("DEFERRED_NATIVE_PREPARATION_GPU failures=", failures)
	quit(0 if failures == 0 else 1)
