extends SceneTree
## Full-town save benchmark. Writes only a unique temporary map.
const Doc = preload("res://scripts/world3d/world_document.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
func _init() -> void: call_deferred("run")
func run() -> void:
	var source := "D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var args := OS.get_cmdline_user_args()
	var label := args[0] if not args.is_empty() else "baseline"
	if label not in ["baseline", "streamed", "cached"]:
		push_error("Expected baseline, streamed or cached"); quit(2); return
	Io.engine_geometry_for_tests = label == "baseline"
	var source_hash := FileAccess.get_sha256(source)
	var output := Paths.cache_directory("save_benchmark_%s_%d" % [label, Time.get_ticks_usec()]).path_join("map.gltf")
	var started := Time.get_ticks_usec()
	var document = Doc.open_file(source)
	if document == null: quit(1); return
	var report := {"source_sha256": source_hash, "output": output, "open_ms": (Time.get_ticks_usec()-started)/1000.0}
	print("BENCH open ", report.open_ms)
	if label == "cached":
		var first: Error = document.save(output)
		report.first_save = document.last_save_metrics.duplicate(true)
		print("BENCH first ", report.first_save)
		# Real geometry edit on the temporary copy, including neighbor invalidation.
		document.checkpoint()
		document.records[0].terrain_mesh.heights[0] += 0.05
		var second: Error = document.save(output)
		report.edited_save = document.last_save_metrics.duplicate(true)
		print("BENCH edited ", report.edited_save)
		var reopened = Doc.open_file(output)
		report.ok = first == OK and second == OK and reopened != null and reopened.records == document.records and FileAccess.get_sha256(source) == source_hash
		report.repeat_output = output.get_base_dir().path_join("repeat.gltf")
		var repeated: Error = document.save(report.repeat_output)
		report.repeat_save = document.last_save_metrics.duplicate(true)
		report.ok = report.ok and repeated == OK and Doc.open_file(report.repeat_output).records == document.records
		var file := FileAccess.open(preload("res://scripts/asset/art_paths.gd").review_path("save_performance/"+label+".json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t")); file.close()
		print("BENCH complete ", report.ok)
		quit(0 if report.ok else 1); return
	started = Time.get_ticks_usec()
	var view: Node3D = document.build(false)
	report.build_ms = (Time.get_ticks_usec()-started)/1000.0
	print("BENCH build ", report.build_ms)
	started = Time.get_ticks_usec()
	var err := Io.save_scene_atomic(view, output)
	report.save_ms = (Time.get_ticks_usec()-started)/1000.0
	report.export = Io.last_export_metrics.duplicate(true)
	view.free()
	print("BENCH save ", report)
	var reopened = Doc.open_file(output)
	report.ok = err == OK and reopened != null and reopened.records == document.records and reopened.map_meta == document.map_meta and FileAccess.get_sha256(source) == source_hash
	var report_path := preload("res://scripts/asset/art_paths.gd").review_path("save_performance/"+label+".json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("BENCH complete ", report.ok)
	quit(0 if report.ok else 1)
