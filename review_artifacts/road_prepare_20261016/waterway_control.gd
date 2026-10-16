extends "res://tools/benchmark_road_prepare.gd"
## Narrow paired CPU control. Existing A/B/C measurements remain untouched.
## --report=res://review_artifacts/road_prepare_20261016/waterway_control/result.json
const Legacy = preload("res://review_artifacts/road_prepare_20261016/road_tools_full_chain_ref.gd")
const PAIRS := 10
var control_context: Node3D
var control_args: Dictionary
var prepared_bytes: Dictionary = {}
var warmups: Array = []
var paired_samples: Array = []

func sample(tool: RefCounted, version: String, phase: String, pair: int, slot: int) -> Dictionary:
	var before := var_to_bytes([Fixture.state(control_context), control_args])
	var started := Time.get_ticks_usec()
	var result: Dictionary = tool.prepare(control_args)
	var wall_ms := (Time.get_ticks_usec() - started) / 1000.
	# Everything below, including hashes and state copying, is outside timing.
	var after := var_to_bytes([Fixture.state(control_context), control_args])
	var encoded := var_to_bytes(result)
	check(result.get("ok", false), "%s %s/%d/%d succeeds" % [version, phase, pair, slot])
	check(before == after, "%s %s/%d/%d input bytes unchanged" % [version, phase, pair, slot])
	if version == "current": check(tool.last_profile.is_empty(), "current control probe remains OFF")
	if not prepared_bytes.has(version): prepared_bytes[version] = encoded
	check(encoded == prepared_bytes[version], "%s %s/%d/%d deterministic complete return" % [version, phase, pair, slot])
	return {"version": version, "phase": phase, "pair": pair, "slot": slot, "wall_ms": wall_ms,
		"input_sha256": bytes_sha(before), "full_result_sha256": bytes_sha(encoded), "ok": result.get("ok", false)}

func median(values: Array) -> float:
	var ordered := values.duplicate(); ordered.sort()
	return ordered[ordered.size() / 2] if ordered.size() % 2 else (ordered[ordered.size() / 2 - 1] + ordered[ordered.size() / 2]) * .5

func run() -> void:
	report_path = "res://review_artifacts/road_prepare_20261016/waterway_control/result.json"
	if not initialize(): finish(); return
	check(not quick and (selected.is_empty() or selected == "waterway_bound_bridge"), "control is exactly ten full pairs of the waterway fixture")
	if failures: finish(); return
	var evidence_root := "res://review_artifacts/road_prepare_20261016/"
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(evidence_root + "full_chain_metadata.json"))
	for filename: String in frozen.files:
		check(FileAccess.get_sha256(evidence_root + filename) == frozen.files[filename], "independent original chain SHA " + filename)
	if failures: finish(); return
	var fixture := Fixture.build("waterway_bound_bridge")
	check(fixture.construction_error.is_empty(), "native WaterwayPlan fixture built", fixture.construction_error)
	if failures: finish(); return
	control_context = Fixture.context(fixture); control_args = fixture.args.duplicate(true)
	var original_state := var_to_bytes([Fixture.state(control_context), control_args])
	var current := Roads.new(); current.editor = control_context; current.profile_enabled = false
	var old := Legacy.new(); old.editor = control_context
	var fixture_bytes := var_to_bytes(fixture)
	write_bytes(report_path.get_base_dir().path_join("input_fixture.bin"), fixture_bytes)
	write_bytes(report_path.get_base_dir().path_join("input_state.bin"), original_state)
	# Exactly one warmup per version. These values are retained, but are not
	# included in any measured-pair statistic.
	warmups.append(sample(current, "current", "warmup", -1, 0))
	warmups.append(sample(old, "legacy", "warmup", -1, 1))
	var pairs: Array = []; var current_times: Array = []; var legacy_times: Array = []
	var differences: Array = []; var ratios: Array = []
	for index in PAIRS:
		var order := ["current", "legacy"] if index % 2 == 0 else ["legacy", "current"]
		var row := {"pair": index, "order": order}
		for slot in 2:
			var version: String = order[slot]
			var observed := sample(current if version == "current" else old, version, "measured", index, slot)
			paired_samples.append(observed); row[version + "_ms"] = observed.wall_ms
		row.current_minus_legacy_ms = row.current_ms - row.legacy_ms
		row.current_over_legacy = row.current_ms / row.legacy_ms
		current_times.append(row.current_ms); legacy_times.append(row.legacy_ms)
		differences.append(row.current_minus_legacy_ms); ratios.append(row.current_over_legacy)
		pairs.append(row)
	check(prepared_bytes.current == prepared_bytes.legacy, "all current and legacy complete result bytes match")
	var reference_sha := bytes_sha(prepared_bytes.legacy)
	check((warmups + paired_samples).all(func(value): return value.full_result_sha256 == reference_sha and value.input_sha256 == bytes_sha(original_state)), "all 22 samples share identical full result and input SHA")
	check(original_state == var_to_bytes([Fixture.state(control_context), control_args]), "entire control leaves document, history and arguments untouched")
	write_bytes(report_path.get_base_dir().path_join("current_result.bin"), prepared_bytes.current)
	write_bytes(report_path.get_base_dir().path_join("legacy_result.bin"), prepared_bytes.legacy)
	report.samples = paired_samples; report.warmups = warmups; report.pairs = pairs
	report.fixture = {"name": fixture.name, "records": fixture.records.size(), "fixture_sha256": bytes_sha(fixture_bytes), "input_sha256": bytes_sha(original_state), "full_result_sha256": reference_sha}
	report.control_script_sha256 = FileAccess.get_sha256("res://review_artifacts/road_prepare_20261016/waterway_control.gd")
	report.reference_manifest = frozen
	report.statistics = {"n_pairs": PAIRS, "n_per_version": PAIRS, "current_raw_wall_ms": current_times,
		"legacy_raw_wall_ms": legacy_times, "current_median_ms": median(current_times), "legacy_median_ms": median(legacy_times),
		"paired_current_minus_legacy_raw_ms": differences, "paired_current_minus_legacy_median_ms": median(differences),
		"paired_current_over_legacy_raw": ratios, "paired_current_over_legacy_median": median(ratios),
		"current_slower_pairs": differences.filter(func(value): return value > 0.).size(),
		"current_faster_pairs": differences.filter(func(value): return value < 0.).size()}
	report.method = {"scope": "One process, real current prepare and independently frozen original road_tools/fit/projection chain; only waterway_bound_bridge; no editor publication, GPU, HTTP or user map.",
		"order": "Exactly one warmup per version (current then legacy), then ten pairs with alternating current/legacy and legacy/current order; every observation retained.",
		"timing": "External wall around prepare only. Setup, state copies, byte serialization, hashes, report I/O and checks excluded. Both versions use the same immutable input context.",
		"probes": "Current profile_enabled=false throughout; legacy has no probe. Exact empty current last_profile checked after every call.",
		"statistics": "Separate warmup values, raw measured pairs, unpaired version medians and paired differences/ratios. No percentile, significance or stable system-noise claim.",
		"interpretation": "Diagnostic follow-up for the original A/C OFF increase. It does not replace or delete A/B/C; this fixture does not run terrain fitting or existing-pavement preservation.",
		"identity": "Every full return and every input state must have identical bytes across versions and repetitions, retaining IDs, tokens, errors and numeric types."}
	print("WATERWAY_PAIRED_CONTROL ", JSON.stringify(report.statistics))
	current.editor = null; old.editor = null; control_context._waterways.editor = null; control_context.free()
	finish()
