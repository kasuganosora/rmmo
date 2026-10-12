extends SceneTree
## Run on the private graphics desktop; never rebuilds native products or GLBs.
## --asset=absolute.glb (repeatable), or --paths-json=absolute.json (string list)
## --output=report.json; optional --content-root=absolute external content root.
const Footprint = preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Drainer = preload("res://scripts/world3d/asset_worker_drainer.gd")
const Atomic = preload("res://scripts/world3d/atomic_file.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var paths: Array[String] = []
	var root_path := Paths.external_root()
	var output := ""
	var list_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--asset="): paths.append(argument.trim_prefix("--asset="))
		elif argument.begins_with("--paths-json="): list_path = argument.trim_prefix("--paths-json=")
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--content-root="): root_path = argument.trim_prefix("--content-root=")
		else: fail("unknown argument: " + argument); return
	if not list_path.is_empty():
		var file := FileAccess.open(list_path, FileAccess.READ)
		if file == null or file.get_length() > 1048576: fail("unreadable or oversized paths list"); return
		var values: Variant = JSON.parse_string(file.get_as_text()); file.close()
		if not values is Array or values.size() > 4096: fail("paths JSON must be a bounded string list"); return
		for value in values:
			if not value is String: fail("paths JSON contains a non-string"); return
			if value not in paths: paths.append(value)
	if paths.is_empty() or root_path.is_empty(): fail("at least one asset and an external content root are required"); return
	if DisplayServer.get_name() == "headless": fail("resource readback requires the private graphics runner"); return
	if output.is_empty(): output = Footprint.directory(root_path).path_join("build_report.json")
	# Only this diagnostic report may live under review_artifacts. Resource
	# descriptors are always written by Footprint.build inside derived cache.
	var reviews := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("rmmo_runtime/review_artifacts")
	if output.get_extension().to_lower() != "json" or (not Paths.allowed(output, Footprint.directory(root_path)) and not Paths.allowed(output, reviews)):
		fail("report must be JSON under derived footprints or sibling runtime/review_artifacts"); return
	var results: Array = []
	var failures := 0
	var started := Time.get_ticks_usec()
	for path in paths:
		var asset_started := Time.get_ticks_usec()
		var result := Footprint.build(path, root_path)
		result.elapsed_us = Time.get_ticks_usec() - asset_started
		results.append(result)
		if not result.get("ok", false): failures += 1
		print("COMPILED_FOOTPRINT ", JSON.stringify(result))
		Drainer.synchronize_transfer()
		await process_frame
	var report := {"version":1, "engine":Engine.get_version_info(), "content_root":root_path, "assets":results, "failures":failures, "elapsed_us":Time.get_ticks_usec()-started, "native_products_modified":false, "source_assets_modified":false}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var temporary := output + ".%d.tmp" % OS.get_process_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: fail("report open failed"); return
	file.store_string(JSON.stringify(report, "\t")); file.flush(); var error := file.get_error(); file.close()
	if error == OK: error = Atomic.publish(temporary, output)
	if error != OK: fail("report atomic publish failed"); return
	print("COMPILED_FOOTPRINT_COMPLETE failures=", failures, " report=", output)
	quit(0 if failures == 0 else 1)

func fail(message: String) -> void:
	push_error("COMPILED_FOOTPRINT: " + message)
	quit(1)
