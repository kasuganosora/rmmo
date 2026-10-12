extends SceneTree
## Read-only CPU microprobe; never loads images/models or mutates resources.
const Store = preload("res://scripts/world3d/map_resource_store.gd")
const Trace = preload("res://scripts/world3d/load_trace.gd")
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const SELECT = "res://review_artifacts/house_audit_selection_20261011.json"
var checks := 0
var failed := false

func _initialize() -> void:
	call_deferred("run")

func require(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failed = true
		push_error(message)
	return value

func run() -> void:
	var selection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SELECT))
	if not require(FileAccess.get_sha256(selection.map) == selection.map_sha, "Map identity before probe"):
		quit(1); return
	var unique: Dictionary = {}; var groups: Dictionary = {}
	for row: Dictionary in selection.house_rows:
		var ref: Dictionary = row.reference
		unique[ref.sha256] = ref
		if not groups.has(row.group_id): groups[row.group_id] = {}
		groups[row.group_id][ref.sha256] = ref
	var repeated: Array = []
	for group: Dictionary in groups.values(): repeated.append_array(group.values())
	var result: Dictionary = {"scope": "Serial warm-filesystem CPU microprobe of production Store._read only. Unique versus all group-definition pairs; NOT an entry A/B or actual scheduled group count. Retains every per-call file SHA/safety/raw identity check; no proposed cache implemented.", "map_sha": selection.map_sha, "unique": unique.size(), "groups": groups.size(), "group_definition_pairs": repeated.size(), "rounds": []}
	var definitions: Dictionary = {}
	for mode: String in ["unique", "group_pairs", "group_pairs", "unique"]:
		var refs: Array = unique.values() if mode == "unique" else repeated
		var total_bytes := 0
		Trace.start()
		var started := Time.get_ticks_usec()
		for ref: Dictionary in refs:
			var path: String = selection.map.get_base_dir().path_join(ref.uri)
			var item: Dictionary = Store._read(path, ref.sha256, int(ref.length), true)
			if not require(item.ok, "Read " + ref.sha256):
				Trace.stop(); quit(1); return
			total_bytes += int(ref.length)
			if not definitions.has(ref.sha256): definitions[ref.sha256] = item.definition
		var elapsed_us := Time.get_ticks_usec() - started
		var trace: Dictionary = Trace.stop()
		result.rounds.append({"mode": mode, "calls": refs.size(), "file_bytes_read": total_bytes, "elapsed_ms": elapsed_us / 1000.0, "stats": trace.stats, "events_dropped": trace.dropped})
		print("HOUSE_OUTER ", mode, " calls=", refs.size(), " ms=", elapsed_us / 1000.0)
	# Measure only the already-verified texture-check fast path. All keys are
	# explicit successful test inputs; this does not validate any image decode.
	var texture_checks: Dictionary = {}; var cached_keys := 0; var paint_entries := 0
	for definition: Dictionary in definitions.values():
		for material: Dictionary in Paint.definitions(definition):
			for field: String in Paint.MAP_FIELDS:
				var path: String = material.get(field, "")
				if path.is_empty(): continue
				texture_checks[["decoded_texture", path, field == "normal_path" and material.get("normal_format", "opengl") == "directx"]] = true
	cached_keys = texture_checks.size()
	var check_rounds: Array = []
	for round_: int in range(4):
		var started := Time.get_ticks_usec()
		for row: Dictionary in selection.house_rows:
			var definition: Dictionary = definitions[row.reference.sha256]
			if not Paint.texture_error(definition, texture_checks).is_empty():
				require(false, "Preseeded texture check failed"); quit(1); return
		check_rounds.append((Time.get_ticks_usec() - started) / 1000.0)
	for row: Dictionary in selection.house_rows:
		paint_entries += Paint.definitions(definitions[row.reference.sha256]).size()
	result.texture_fast_path = {"records": selection.house_rows.size(), "material_visits": paint_entries, "preseeded_successful_keys": cached_keys, "round_ms": check_rounds, "note": "All checks preseeded true. CPU dictionary/list validation only; no texture I/O, decode, upload or publication reproduction."}
	for ref: Dictionary in unique.values():
		require(FileAccess.get_sha256(selection.map.get_base_dir().path_join(ref.uri)) == ref.sha256, "Reference unchanged after probe")
	require(FileAccess.get_sha256(selection.map) == selection.map_sha, "Map unchanged after probe")
	result.checks = checks; result.failed = failed
	var file := FileAccess.open("res://review_artifacts/house_outer_reads_cpu_20261011.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  ")); file.close()
	print("HOUSE_OUTER checks=", checks, " failed=", failed)
	quit(1 if failed else 0)
