extends SceneTree
## Relink only the reviewed pennant source. No model import/export or directory copy.
## Default writes a fresh temporary map. Production requires explicit --publish,
## rereads the latest document and uses the ordinary atomic/conflict-aware save.
const Doc = preload("res://scripts/world3d/world_document.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Manifest = preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Pose = preload("res://scripts/world3d/pose_save.gd")
const FORMAL = "D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const SOURCE = "D:/code/rmmo_runtime/cache/world3d/reference_load_checkpoint_26004507/map.gltf"
const ORIGINAL = "D:/code/rmmo_runtime/cache/world3d/bridge_street_finish_20261006/assets/ca443721d86d712acc2627f25fd4cdc1755584d7057ae008b770627d4db969e1.glb"
const ART = "D:/code/rmmo_runtime/art_sources/bridge_long_pennant_optimization_20261009"
const CANDIDATE = ART + "/bridge_long_pennants_lossless.glb"
const CANDIDATE_SHA = "c88390233a731974ef2d020be023d47365c46104a4dc9a22d85d2f2fc4e5a64d"
const CANDIDATE_BYTES = 75581472
const EXPECTED_INSTANCES = 2
var failures := 0
var report := {"checks": [], "changed": [], "candidate": CANDIDATE,
	"accepted_candidate_sha256": CANDIDATE_SHA,
	"source_integrity_scope": "Map and rmres closure and the accepted candidate full GLB SHA are freshly verified. Original GLB inspection reads JSON/accessor bounds only. Imported semantics are checked by the production loader/GPU run and the independent 27-check art comparison."}

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> bool:
	report.checks.append({"ok": ok, "label": label})
	print("PENNANT_REFERENCE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
	return ok

func json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func finish(path: String) -> void:
	report.failures = failures
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: push_error("Cannot write pennant reference report"); quit(1); return
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("PENNANT_REFERENCE_REPORT ", path)
	quit(0 if failures == 0 else 1)

func run() -> void:
	var publish := false
	var output := ""
	var report_path := "D:/code/rmmo_runtime/review_artifacts/bridge_pennant_reference_20261009.json"
	var review_path := report_path
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--publish": publish = true
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		elif arg.begins_with("--review="): review_path = arg.trim_prefix("--review=")
		else: push_error("Unsupported argument: " + arg); quit(1); return
	if not Paths.allowed(report_path, Paths.external_root().path_join("review_artifacts")):
		push_error("Report must stay in review_artifacts"); quit(1); return
	if publish:
		if not output.is_empty(): push_error("--publish does not accept --output"); quit(1); return
		if report_path == review_path:
			push_error("--publish requires a separate --report to preserve temporary review evidence"); quit(1); return
		if not Paths.allowed(review_path, Paths.external_root().path_join("review_artifacts")):
			push_error("--review must stay in review_artifacts"); quit(1); return
		var reviewed := json(review_path)
		if not check(reviewed.get("failures", -1) == 0 and reviewed.get("mode") == "temporary" and reviewed.get("accepted_candidate_sha256") == CANDIDATE_SHA and reviewed.get("changed", []).size() == EXPECTED_INSTANCES, "explicit publish has a passing temporary relink report"):
			finish(report_path); return
		output = FORMAL
	elif output.is_empty():
		output = Paths.external_root().path_join("cache/world3d/reference_pennant_checkpoint_%d/map.gltf" % Time.get_ticks_usec())
	if not publish and (not Paths.allowed(output, Paths.external_root().path_join("cache/world3d")) or output.get_extension().to_lower() != "gltf" or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_base_dir())):
		push_error("Temporary output requires a new directory under cache/world3d"); quit(1); return
	var source := FORMAL if publish else SOURCE
	report.mode = "publish" if publish else "temporary"
	report.source = source; report.output = output
	var accepted := json(ART + "/lossless_audit.json")
	var comparison := json(ART + "/comparison.json")
	if not check(accepted.get("output_sha256") == CANDIDATE_SHA and accepted.get("output_bytes") == CANDIDATE_BYTES and accepted.get("exact_resolved_render_graph_equal", false) and accepted.get("nodes_transforms_wind_and_collision_extras_equal", false), "independent art audit identifies the accepted lossless candidate"):
		finish(report_path); return
	var art_checks: Variant = comparison.get("checks", [])
	if not check(art_checks is Array and art_checks.size() == 27 and art_checks.all(func(row): return row.get("ok", false)), "independent 27-check art comparison passed"):
		finish(report_path); return
	if not check(Paths.allowed(ORIGINAL) and Paths.allowed(CANDIDATE), "model paths remain inside authorized content root"):
		finish(report_path); return
	if not check(FileAccess.get_sha256(CANDIDATE) == CANDIDATE_SHA, "complete candidate source SHA matches the visually accepted artifact"):
		finish(report_path); return
	var old_bounds := Manifest.read(ORIGINAL)
	var new_bounds := Manifest.read(CANDIDATE)
	if not check(old_bounds.get("known", false) and new_bounds.get("known", false) and new_bounds.get("file_length") == CANDIDATE_BYTES and old_bounds.get("local_bounds") == new_bounds.get("local_bounds"), "original and candidate GLB headers prove identical local accessor bounds"):
		finish(report_path); return
	report.bounds = str(new_bounds.local_bounds)
	report.original_bytes = old_bounds.file_length
	report.candidate_bytes = new_bounds.file_length
	report.original_json_sha256 = old_bounds.json_sha256
	report.candidate_json_sha256 = new_bounds.json_sha256
	report.original_source_map_sha256 = FileAccess.get_sha256(source)
	var formal_before := FileAccess.get_sha256(FORMAL)
	var benchmark_before := FileAccess.get_sha256(SOURCE)
	var started := Time.get_ticks_usec()
	var doc = Doc.open_file(source)
	if not check(doc != null, "open complete source author document with normal closure validation"):
		finish(report_path); return
	report.open_ms = (Time.get_ticks_usec() - started) / 1000.0
	var before: Array = doc.records.duplicate(true)
	var before_meta: Dictionary = doc.map_meta.duplicate(true)
	var matches: Array = doc.records.filter(func(record): return record.get("asset_path", "") == ORIGINAL)
	if not check(matches.size() == EXPECTED_INSTANCES, "exactly two source pennant instances are eligible"):
		finish(report_path); return
	if not check(matches.all(func(record): return record.get("kind") == "asset" and not record.get("editor_locked", false)), "relinked instances are ordinary unlocked assets"):
		finish(report_path); return
	doc.checkpoint()
	for record: Dictionary in matches:
		var original: Dictionary = record.duplicate(true)
		record.asset_path = CANDIDATE
		var compared: Dictionary = record.duplicate(true); compared.asset_path = ORIGINAL
		check(Pose.same(original, compared), "preserve every author field for " + record.uuid)
		report.changed.append({"uuid": record.uuid, "position": record.position, "rotation": record.rotation, "size": record.size, "old_asset_path": ORIGINAL, "new_asset_path": CANDIDATE})
	var after: Array = doc.records.duplicate(true)
	check(doc.undo() and Pose.same(doc.records, before), "undo restores exact complete source author records")
	check(doc.redo() and Pose.same(doc.records, after), "redo restores exact candidate author records")
	check(Pose.same(doc.map_meta, before_meta), "metadata and spawn remain unchanged")
	for i in before.size():
		var expected: Dictionary = before[i].duplicate(true)
		if expected.get("asset_path", "") == ORIGINAL: expected.asset_path = CANDIDATE
		if not Pose.same(expected, doc.records[i]): check(false, "unrelated author record changed: " + str(expected.get("uuid")))
	if failures: finish(report_path); return
	check(FileAccess.get_sha256(source) == report.original_source_map_sha256, "source map did not change while relink was prepared")
	if failures: finish(report_path); return
	started = Time.get_ticks_usec()
	if not check(doc.save(output) == OK, "native atomic reference-map save succeeds with conflict protection"):
		finish(report_path); return
	report.save_ms = (Time.get_ticks_usec() - started) / 1000.0
	report.save_metrics = doc.last_save_metrics.duplicate(true)
	check(report.save_metrics.export.images_written == 0 and report.save_metrics.export.texture_export_passes == 0, "relink exports no models or textures")
	var reopened = Doc.open_file(output)
	check(reopened != null and Pose.same(reopened.records, after) and Pose.same(reopened.map_meta, before_meta), "saved map reopens with exact author records and metadata")
	if reopened != null: check(reopened.missing_assets().is_empty(), "reopened map has no missing asset references")
	var original_compact: Dictionary = json(source).nodes[0].extras
	var saved_compact: Dictionary = json(output).nodes[0].extras
	if not publish:
		var changed_compact: Array = []
		for i in original_compact.rmmo_records.size():
			if not Pose.same(original_compact.rmmo_records[i], saved_compact.rmmo_records[i]): changed_compact.append(original_compact.rmmo_records[i].uuid)
		check(changed_compact.size() == EXPECTED_INSTANCES and changed_compact.all(func(id): return report.changed.any(func(row): return row.uuid == id)), "only the two pennant compact references changed")
		report.changed_compact_ids = changed_compact
		check(FileAccess.get_sha256(FORMAL) == formal_before, "formal map remains unchanged")
	check(FileAccess.get_sha256(SOURCE) == benchmark_before, "original benchmark map remains unchanged")
	var after_bounds := Manifest.read(CANDIDATE)
	check(after_bounds.get("known", false) and after_bounds.get("json_sha256") == new_bounds.json_sha256 and after_bounds.get("file_length") == CANDIDATE_BYTES, "candidate header remains unchanged across map publication")
	report.output_sha256 = FileAccess.get_sha256(output)
	report.records = doc.records.size()
	finish(report_path)
