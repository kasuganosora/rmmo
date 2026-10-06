extends SceneTree
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const Doc = preload("res://scripts/world3d/world_document.gd")
var failed := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failed += 1
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 3 and args[0] == "--interrupted-writer":
		var document := Doc.new()
		document.add_box("block", Vector3.ZERO, Vector3.ONE)
		Io.save_fault = func(stage: String):
			if stage == args[2]:
				var marker := FileAccess.open(args[1] + ".paused", FileAccess.WRITE)
				marker.store_string("ready")
				marker.close()
				while true: OS.delay_msec(50)
			return false
		document.save(args[1])
		quit(2)
		return
	var dir := preload("res://scripts/world3d/map_paths.gd").cache_directory("save_%d" % Time.get_ticks_usec())
	var path := dir.path_join("whitebox map.gltf")
	var doc := Doc.new()
	doc.add_box("ground", Vector3.ZERO, Vector3(4, 0.2, 4))
	check(doc.save(path) == OK, "publish initial whitebox map with spaces in name")
	var original := FileAccess.get_file_as_bytes(path)
	var previous_uri := Io._buffer_uris(path)[0]
	var dependency := FileAccess.get_sha256(dir.path_join(previous_uri))
	doc.add_box("block", Vector3(2, 1, 0), Vector3.ONE)
	for stage in ["resources_ready", "before_publish"]:
		Io.save_fault = func(at: String): return at == stage
		check(doc.save(path) != OK, stage + " fault is reported")
		check(FileAccess.get_file_as_bytes(path) == original and FileAccess.get_sha256(dir.path_join(previous_uri)) == dependency, stage + " leaves previous document and geometry unchanged")
		check(Doc.open_file(path).records.size() == 1, stage + " previous map remains readable")
	Io.save_fault = Callable()
	check(doc.save(path) == OK and Doc.open_file(path).records.size() == 2, "successful save publishes new map")
	check(FileAccess.get_file_as_bytes(path + ".previous") == original, "replacement retains complete previous map entry")
	check(FileAccess.get_sha256(dir.path_join(previous_uri)) == dependency, "old resource version remains valid for backup")
	check(Io.restore_previous(path) == OK and Doc.open_file(path).records.size() == 1, "previous save can be restored through atomic entry replacement")
	check(Io.restore_previous(path) == OK and Doc.open_file(path).records.size() == 2, "recovery keeps the replaced map available for undo")
	doc = Doc.open_file(path)
	check(doc.save(path) == OK, "repeated replacement handles existing backup")
	var stale = Doc.open_file(path)
	doc.map_meta["revision_test"] = 2
	check(doc.save(path) == OK and stale.save(path) == ERR_BUSY, "stale editor document cannot overwrite a newer disk version")
	var lock := path + ".save-lock"
	DirAccess.make_dir_absolute(lock)
	var owner := FileAccess.open(lock.path_join("owner"), FileAccess.WRITE)
	owner.store_string(str(OS.get_process_id()))
	owner.close()
	check(doc.save(path) == ERR_BUSY, "concurrent owner cannot overwrite document")
	owner = FileAccess.open(lock.path_join("owner"), FileAccess.WRITE)
	owner.store_string("2147483647")
	owner.close()
	check(doc.save(path) == OK, "abandoned process lock recovers on next save")
	check(not DirAccess.dir_exists_absolute(lock), "save releases ownership lock")
	for stage in ["resources_ready", "before_publish"]:
		var baseline := FileAccess.get_file_as_bytes(path)
		var child := OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/test_world3d_save_reliability.gd", "--log-file", dir.path_join(stage + ".log"), "--", "--interrupted-writer", path, stage]))
		var deadline := Time.get_ticks_msec() + 10000
		while not FileAccess.file_exists(path + ".paused") and Time.get_ticks_msec() < deadline: await create_timer(0.05).timeout
		check(child > 0 and FileAccess.file_exists(path + ".paused"), stage + " child writer reaches interruption point")
		if child > 0: OS.kill(child)
		await create_timer(0.1).timeout
		check(FileAccess.get_file_as_bytes(path) == baseline and Doc.open_file(path).records.size() == 2, stage + " forcibly killed writer leaves a readable map")
		check(doc.save(path) == OK, stage + " killed writer lock is recovered")
		DirAccess.remove_absolute(path + ".paused")
	Io._remove_tree(dir)
	print("test_world3d_save_reliability: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
