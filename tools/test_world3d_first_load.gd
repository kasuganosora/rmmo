extends SceneTree
const Doc = preload("res://scripts/world3d/world_document.gd")
const Loader = preload("res://scripts/world3d/map_loader.gd")
var failed := 0
var pulses := 0
var max_slice := 0
var last_time := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failed += 1
func run() -> void:
	var dir := preload("res://scripts/world3d/map_paths.gd").cache_directory("first_load_%d" % Time.get_ticks_usec())
	var doc := Doc.new()
	for z in 45:
		for x in 45: doc.add_box_silent("ground", Vector3(x * 4, -0.1, z * 4), Vector3(4, 0.2, 4))
	var path := dir.path_join("map.gltf")
	check(doc.save(path) == OK, "save 2025 object fixture")
	var started := Time.get_ticks_msec()
	var baseline := preload("res://scripts/world3d/gltf_map_io.gd").load_scene(path)
	var baseline_ms := Time.get_ticks_msec() - started
	baseline.free()
	var loader := Loader.new()
	root.add_child(loader)
	loader.progress.connect(func(_stage: String, done: int, total: int):
		pulses += 1
		check(done <= total, "bounded loading progress") if pulses == 1 else null
	)
	started = Time.get_ticks_msec()
	loader.start(path)
	var result: Array = await loader.finished
	var elapsed := Time.get_ticks_msec() - started
	var map: Node = result[0]
	check(map != null and map.get_meta("record_stream_load", false), "editor document takes direct-record streaming path")
	check(map.get_meta("stream_library", []).size() == 2025 and map.get_child_count() == 0, "full spatial library without whole-map scene nodes")
	check(pulses > 1, "index creation yields across frames with progress")
	print("LOAD_METRICS objects=2025 old_import_ms=%d direct_record_ms=%d slices=%d" % [baseline_ms, elapsed, pulses])
	var host := Node3D.new()
	root.add_child(host)
	host.add_child(map)
	while not map.has_meta("stream_chunk"):
		preload("res://scripts/world3d/world_stream.gd").sync(map, host, Vector3(2, 0.9, 2), 12)
		await process_frame
	check(map.get_child_count() < 2025 and map.get_meta("stream_bodies", {}).size() > 0, "spawn area loads with distant geometry absent")
	host.free()
	var cancelled := Loader.new()
	root.add_child(cancelled)
	cancelled.progress.connect(func(_stage: String, _done: int, _total: int): cancelled.cancel())
	cancelled.finished.connect(func(_scene: Node, _path: String, _error: String): check(false, "cancelled load must not publish"))
	cancelled.start(path)
	while is_instance_valid(cancelled): await process_frame
	check(true, "cancel during record construction cleans up without publishing")
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(dir)
	print("test_world3d_first_load: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
