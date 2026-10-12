extends SceneTree
## CPU-only component timing; never changes the author map or builds caches.
const Index = preload("res://scripts/world3d/map_dependency_index.gd")
const ROOT := "D:/code/rmmo_runtime"
const MAP := ROOT + "/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var start := Time.get_ticks_usec()
	var index := Index.read(MAP, ROOT)
	var report := {"ok": index.get("ok", false), "index_read_us": Time.get_ticks_usec() - start, "ownership_us": [], "uuid_table_us": []}
	if not report.ok: print(index); quit(1); return
	for i in 7:
		start = Time.get_ticks_usec()
		report.ok = report.ok and Index._ownership_valid(index.extras, index.rows, index.groups)
		report.ownership_us.append(Time.get_ticks_usec() - start)
		start = Time.get_ticks_usec()
		var by_uuid := {}
		for row: Dictionary in index.rows: by_uuid[row.uuid] = row
		report.uuid_table_us.append(Time.get_ticks_usec() - start)
		report.ok = report.ok and by_uuid.size() == index.rows.size()
	if "--sealed" in OS.get_cmdline_user_args():
		start = Time.get_ticks_usec()
		var loading: Dictionary = Index.read_for_loading(MAP, ROOT)
		report.sealed_read_us = Time.get_ticks_usec() - start
		report.ok = report.ok and loading.ok
		if loading.ok:
			var timings: Array = []
			for i in 100:
				start = Time.get_ticks_usec()
				report.ok = report.ok and Index.validate_index_ownership(loading.index, ROOT, loading.proof, MAP)
				timings.append(Time.get_ticks_usec() - start)
			report.sealed_ownership_us = timings
	report.records = index.rows.size()
	report.source_unchanged = FileAccess.get_sha256(MAP) == index.source_sha256
	print(JSON.stringify(report))
	var output := ROOT + "/review_artifacts/dependency_validation_baseline_20261009.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	quit(0 if report.ok and report.source_unchanged else 1)
