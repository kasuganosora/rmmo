extends SceneTree
## Pure CPU real road_tools.prepare benchmark. Never opens or saves a map.
## --report=res://review_artifacts/road_prepare_20261016/before/result.json
## --case=<one name from road_prepare_fixture.names()> --quick (one preparation per case)
const Fixture = preload("res://tools/road_prepare_fixture.gd")
const Roads = preload("res://scripts/world_editor/road_tools.gd")
const REFERENCE := "res://review_artifacts/road_prepare_20261016/reference.gd.txt"
const REFERENCE_SHA := "061c4df3a456ff9ae0d0a950d18d8380dee438f725559af5ec27d9a69caa41eb"
var failures := 0
var checks: Array = []
var report: Dictionary = {"version": 1, "fixtures": [], "samples": []}
var report_path := "res://review_artifacts/road_prepare_20261016/quick/result.json"
var selected := ""
var quick := false
var reference: GDScript

func _init() -> void:
	run.call_deferred()

func check(condition: bool, label_: String, details: Variant = {}) -> void:
	checks.append({"ok": condition, "label": label_, "details": details})
	print(("PASS " if condition else "FAIL ") + label_)
	if not condition: failures += 1

func bytes_sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()

func value_sha(value: Variant) -> String:
	return bytes_sha(var_to_bytes(value))

func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "open evidence " + path.get_file())
	if file != null: file.store_buffer(bytes); file.close()

func source_hashes(directory: String, result: Dictionary) -> void:
	var listing := DirAccess.open(directory)
	if listing == null: return
	for file: String in listing.get_files():
		if file.ends_with(".gd"): result[directory.path_join(file)] = FileAccess.get_sha256(directory.path_join(file))
	for child: String in listing.get_directories(): source_hashes(directory.path_join(child), result)

func initialize() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--case="): selected = argument.trim_prefix("--case=")
		elif argument == "--quick": quick = true
		else: check(false, "unknown argument", argument)
	var absolute := ProjectSettings.globalize_path(report_path).replace("\\", "/").simplify_path()
	var allowed := ProjectSettings.globalize_path("res://review_artifacts/road_prepare_20261016/").replace("\\", "/").simplify_path().trim_suffix("/") + "/"
	if not absolute.begins_with(allowed):
		push_error("Report must be under this worktree's review_artifacts/road_prepare_20261016"); quit(2); return false
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	check(selected.is_empty() or selected in Fixture.names(), "selected fixture exists")
	check(FileAccess.get_sha256(REFERENCE) == REFERENCE_SHA, "frozen pre-profile source SHA is exact")
	reference = GDScript.new(); reference.source_code = FileAccess.get_file_as_string(REFERENCE)
	check(reference.reload() == OK, "frozen original source compiles")
	var scripts := {}
	source_hashes("res://scripts/world_editor", scripts); source_hashes("res://scripts/world3d", scripts)
	for path: String in ["res://tools/benchmark_road_prepare.gd", "res://tools/road_prepare_fixture.gd", "res://tools/test_road_prepare_differential.gd", "res://project.godot", REFERENCE]:
		if FileAccess.file_exists(path): scripts[path] = FileAccess.get_sha256(path)
	var commit: Array = []; OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "HEAD"], commit)
	report.merge({"engine": Engine.get_version_info(), "engine_executable": OS.get_executable_path(),
		"engine_executable_sha256": FileAccess.get_sha256(OS.get_executable_path()), "head_commit": "".join(commit).strip_edges(),
		"script_sha256": scripts, "reference_sha256": REFERENCE_SHA, "quick": quick,
		"display": DisplayServer.get_name(), "method": {
			"service": "Unmodified real road_tools.prepare; minimal Node3D context with real WorldDocument, AuthoringView, material library and WaterwayTools. No scene publication, HTTP, save or gameplay.",
			"first": "First prepare of this fixture in this process; setup and earlier fixtures can warm engine/OS caches. Not a cold-OS measurement.",
			"order": "first ON, warm ON twice, warm OFF three times; quick only first ON. Reference runs after measured calls.",
			"timing": "External wall around prepare only; profiles copied afterwards. Input serialization, hashing, setup, evidence writes and reference excluded.",
			"identity": "Exact var_to_bytes SHA256 of entire return, with IDs, tokens, manifest, errors and types retained. No fields removed or normalized.",
			"statistics": "Raw observations and median only; fixed run order cannot isolate probe cost from cache/order variation.",
			"scope": "CPU candidate preparation, no GPU/frame time, town latency, RSS/VRAM, editor publication or traversal claim."}}, true)
	return failures == 0

func measure_case(fixture: Dictionary) -> void:
	var name_: String = fixture.name
	check(fixture.construction_error.is_empty(), name_ + " native fixture constructed", fixture.construction_error)
	if not fixture.construction_error.is_empty(): return
	var context := Fixture.context(fixture)
	var input_bytes := var_to_bytes(Fixture.state(context)); var args_bytes := var_to_bytes(fixture.args)
	var input_hash := bytes_sha(input_bytes)
	write_bytes(report_path.get_base_dir().path_join(name_ + "_input.bin"), var_to_bytes(fixture))
	var tool := Roads.new(); tool.editor = context
	var hashes: Array = []; var first_result: Dictionary = {}; var samples: Array = []
	for index in (1 if quick else 6):
		var enabled := index < 3; tool.profile_enabled = enabled
		var label_ := "first_prepare" if index == 0 else ("warm_on_%d" % index if enabled else "warm_off_%d" % (index - 2))
		var started := Time.get_ticks_usec()
		var result: Dictionary = tool.prepare(fixture.args)
		var wall_ms := (Time.get_ticks_usec() - started) / 1000.
		var profile: Dictionary = tool.last_profile.duplicate(true)
		var total := 0.
		for duration in profile.get("stages_ms", {}).values(): total += float(duration)
		var result_hash := value_sha(result); hashes.append(result_hash)
		var sample := {"fixture": name_, "label": label_, "profiling_on": enabled, "wall_ms": wall_ms,
			"profile": profile, "stage_sum_ms": total, "unattributed_ms": wall_ms - total,
			"full_result_sha256": result_hash, "input_sha256": input_hash, "ok": result.get("ok", false)}
		samples.append(sample); report.samples.append(sample)
		print("ROAD_PREPARE_SAMPLE ", JSON.stringify(sample))
		check(result.get("ok", false) == fixture.expected_ok, name_ + "/" + label_ + " expected result", {} if result.get("ok", false) else result)
		check(input_bytes == var_to_bytes(Fixture.state(context)) and args_bytes == var_to_bytes(fixture.args), name_ + "/" + label_ + " input bytes unchanged")
		check(enabled or profile.is_empty(), name_ + "/" + label_ + " disabled probes empty")
		if index == 0: first_result = result.duplicate(true)
		else: check(result_hash == hashes[0], name_ + "/" + label_ + " full result identical")
	var original = reference.new(); original.editor = context
	var expected: Dictionary = original.prepare(fixture.args)
	var expected_hash := value_sha(expected)
	check(hashes.all(func(value): return value == expected_hash), name_ + " complete result matches frozen original", {"current": hashes[0], "reference": expected_hash})
	check(input_bytes == var_to_bytes(Fixture.state(context)), name_ + " original also leaves bytes unchanged")
	write_bytes(report_path.get_base_dir().path_join(name_ + "_result.bin"), var_to_bytes(first_result))
	write_bytes(report_path.get_base_dir().path_join(name_ + "_reference_result.bin"), var_to_bytes(expected))
	for path: String in fixture.dependencies:
		check(FileAccess.get_sha256(path) == fixture.dependencies[path], name_ + " external source unchanged: " + path.get_file())
	report.fixtures.append({"name": name_, "records": fixture.records.size(), "road_nodes": fixture.layout.roads.nodes.size(),
		"road_edges": fixture.layout.roads.edges.size(), "terrain_cells": terrain_cells(fixture.records), "input_bytes": input_bytes.size(),
		"input_sha256": input_hash, "fixture_sha256": value_sha(fixture), "args": fixture.args, "dependencies": fixture.dependencies,
		"full_result_sha256": hashes[0], "reference_result_sha256": expected_hash, "statistics": statistics(samples)})
	original.editor = null; tool.editor = null; context._waterways.editor = null; context.free()

func terrain_cells(records: Array) -> int:
	var total := 0
	for record: Dictionary in records:
		if record.has("terrain_mesh"): total += int(record.terrain_mesh.rows) * int(record.terrain_mesh.columns)
	return total

func statistics(samples: Array) -> Dictionary:
	var grouped := {"first": [], "warm_on": [], "warm_off": []}; var out := {}
	for sample: Dictionary in samples:
		grouped["first" if sample.label == "first_prepare" else ("warm_on" if sample.profiling_on else "warm_off")].append(sample.wall_ms)
	for key: String in grouped:
		var ordered: Array = grouped[key].duplicate(); ordered.sort(); var median: Variant = null
		if not ordered.is_empty(): median = ordered[ordered.size() / 2] if ordered.size() % 2 else (ordered[ordered.size() / 2 - 1] + ordered[ordered.size() / 2]) * .5
		out[key] = {"n": ordered.size(), "raw_wall_ms": grouped[key], "median_wall_ms": median}
	return out

func finish() -> void:
	report.failures = failures; report.checks = checks
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null: push_error("Cannot write road benchmark report"); quit(2); return
	file.store_string(JSON.stringify(report, "  ")); file.close()
	print("ROAD_PREPARE_BENCHMARK ", report_path, " checks=", checks.size(), " failures=", failures)
	quit(1 if failures else 0)

func run() -> void:
	if not initialize(): finish(); return
	for name_: String in Fixture.names():
		if selected.is_empty() or selected == name_: measure_case(Fixture.build(name_))
	finish()
