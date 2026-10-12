extends SceneTree
## Pure CPU/headless benchmark. No ResourceLoader, GPU, native extension or
## source writes. Sequential whole-file SHA-256, bounded streaming buffers.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const METHODS = ["builtin", "256k", "1m", "4m"]
const BUFFERS = {"256k":256 * 1024, "1m":1024 * 1024, "4m":4 * 1024 * 1024}
const ORDERS = [["builtin", "256k", "1m", "4m"], ["4m", "1m", "256k", "builtin"], ["1m", "builtin", "4m", "256k"]]
var report: Dictionary = {"version":1, "failures":0, "checks":[], "samples":[], "rounds":3}
var output: String = ""
var input: String = ""

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label_: String) -> bool:
	report.checks.append({"ok":ok, "label":label_})
	print("PASS " if ok else "FAIL ", label_)
	if not ok: report.failures += 1
	return ok

static func size_of(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return -1
	var size: int = file.get_length()
	file.close()
	return size

static func valid_sha(value: String) -> bool:
	if value.length() != 64: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true

static func builtin(path: String, expected_bytes: int) -> Dictionary:
	var before: int = size_of(path)
	var started: int = Time.get_ticks_usec()
	var sha: String = FileAccess.get_sha256(path)
	var elapsed: int = Time.get_ticks_usec() - started
	var after: int = size_of(path)
	# The public convenience API exposes neither read/update times nor its
	# internal error status/byte count. Do not invent those measurements.
	return {"method":"builtin", "error":OK if valid_sha(sha) and before == expected_bytes and after == expected_bytes else ERR_FILE_CANT_READ,
		"sha256":sha, "wall_us":elapsed, "read_us":null, "update_us":null, "finish_us":null, "open_close_us":null,
		"bytes":expected_bytes, "byte_count_kind":"expected_file_size_not_observed_by_builtin_api",
		"chunk_bytes":32768, "chunk_bytes_evidence":"local Godot core/io/file_access.cpp get_sha256",
		"read_calls":null, "read_errors_observable":false, "size_before":before, "size_after":after}

static func stream_hash(path: String, method: String, chunk_bytes: int, expected_bytes: int) -> Dictionary:
	var row: Dictionary = {"method":method, "error":OK, "sha256":"", "wall_us":0, "read_us":0, "update_us":0, "finish_us":0,
		"open_close_us":0, "bytes":0, "byte_count_kind":"observed_bytes_read_and_hashed", "chunk_bytes":chunk_bytes,
		"max_chunk_bytes":0, "read_calls":0, "read_errors_observable":true, "last_file_error":OK, "reason":""}
	var started: int = Time.get_ticks_usec()
	var phase: int = Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	row.open_close_us += Time.get_ticks_usec() - phase
	if file == null:
		row.error = FileAccess.get_open_error(); row.reason = "open"; row.wall_us = Time.get_ticks_usec() - started
		return row
	row.size_before = file.get_length()
	var hash_: HashingContext = HashingContext.new()
	if row.size_before != expected_bytes:
		row.error = ERR_BUSY; row.reason = "size_changed_before_read"
	else:
		row.error = hash_.start(HashingContext.HASH_SHA256)
		if row.error != OK: row.reason = "hash_start"
	while row.error == OK and int(row.bytes) < expected_bytes:
		var requested: int = mini(chunk_bytes, expected_bytes - int(row.bytes))
		phase = Time.get_ticks_usec()
		var bytes: PackedByteArray = file.get_buffer(requested)
		row.read_us += Time.get_ticks_usec() - phase
		row.read_calls += 1; row.max_chunk_bytes = maxi(int(row.max_chunk_bytes), bytes.size())
		row.last_file_error = file.get_error()
		if bytes.size() != requested or row.last_file_error != OK:
			row.error = ERR_FILE_CANT_READ; row.reason = "short_read_or_file_error"
			bytes = PackedByteArray()
			break
		phase = Time.get_ticks_usec()
		var updated: Error = hash_.update(bytes)
		row.update_us += Time.get_ticks_usec() - phase
		if updated != OK:
			row.error = updated; row.reason = "hash_update"
			bytes = PackedByteArray()
			break
		row.bytes += bytes.size()
		# Release the previous chunk before allocating the next. No whole-file
		# PackedByteArray or retained list of chunks is ever constructed.
		bytes = PackedByteArray()
	if row.error == OK:
		row.size_after = file.get_length()
		if int(row.bytes) != expected_bytes or file.get_position() != expected_bytes or row.size_after != expected_bytes or file.get_error() != OK:
			row.error = ERR_BUSY; row.reason = "length_position_or_error_after_read"
		else:
			phase = Time.get_ticks_usec()
			var sum: PackedByteArray = hash_.finish()
			row.sha256 = sum.hex_encode()
			row.finish_us = Time.get_ticks_usec() - phase
			if sum.size() != 32: row.error = ERR_INVALID_DATA; row.reason = "hash_finish"
	phase = Time.get_ticks_usec()
	file.close()
	row.open_close_us += Time.get_ticks_usec() - phase
	row.wall_us = Time.get_ticks_usec() - started
	row.path_size_after_close = size_of(path)
	if row.error == OK and row.path_size_after_close != expected_bytes:
		row.error = ERR_BUSY; row.reason = "path_size_changed_after_close"
	return row

static func median(values: Array) -> float:
	if values.is_empty(): return 0.0
	var ordered: Array = values.duplicate(); ordered.sort()
	var middle: int = ordered.size() / 2
	return float(ordered[middle]) if ordered.size() % 2 else (float(ordered[middle - 1]) + float(ordered[middle])) * .5

func summarize() -> void:
	var summary: Dictionary = {}
	for method: String in METHODS:
		var walls: Array = []; var reads: Array = []; var updates: Array = []
		for sample: Dictionary in report.samples:
			if sample.method != method or sample.error != OK: continue
			walls.append(sample.wall_us)
			if sample.read_us != null: reads.append(sample.read_us)
			if sample.update_us != null: updates.append(sample.update_us)
		var wall: float = median(walls)
		summary[method] = {"valid_samples":walls.size(), "median_wall_us":wall, "median_read_us":null if reads.is_empty() else median(reads),
			"median_update_us":null if updates.is_empty() else median(updates), "median_mib_per_second":float(report.selected_bytes) * 1000000.0 / 1048576.0 / wall if wall > 0 else 0}
	var baseline: float = float(summary.builtin.median_wall_us)
	for method: String in METHODS:
		summary[method].wall_ratio_to_builtin = float(summary[method].median_wall_us) / baseline if baseline > 0 else 0
	report.summary = summary

func run() -> void:
	var root_path: String = Paths.external_root()
	var reviews: String = root_path.path_join("review_artifacts")
	input = reviews.path_join("native_budget_20261010/initial_paths.json")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input = argument.trim_prefix("--input=").replace("\\", "/").simplify_path()
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=").replace("\\", "/").simplify_path()
	if not check(DisplayServer.get_name() == "headless", "pure CPU benchmark requires headless execution"): quit(1); return
	if not check(Paths.allowed(input, reviews) and Paths.allowed(output, reviews) and output.get_extension() == "json" and output != input, "input/output stay in external review artifacts"): quit(1); return
	var file: FileAccess = FileAccess.open(input, FileAccess.READ)
	if not check(file != null and file.get_length() <= 65536, "bounded initial-path input"): quit(1); return
	var raw: Variant = JSON.parse_string(file.get_as_text()); file.close()
	if not check(raw is Array and raw.size() == 9, "input contains the nine initial model paths"): quit(1); return
	var seen: Dictionary = {}; var sizes: Array = []
	var selected: String = ""; var selected_size: int = -1
	for value: Variant in raw:
		if not check(value is String and Paths.allowed(value, root_path) and value.get_extension().to_lower() == "glb" and not seen.has(value), "unique allowed source path"): quit(1); return
		var path: String = value; var size: int = size_of(path)
		if not check(size > 0, "source exists and has readable length"): quit(1); return
		seen[path] = true; sizes.append({"path":path, "bytes":size})
		if size > selected_size: selected = path; selected_size = size
	report.input = input; report.input_sha = FileAccess.get_sha256(input)
	report.selection = sizes; report.selected_path = selected; report.selected_bytes = selected_size
	report.engine = Engine.get_version_info(); report.executable = OS.get_executable_path()
	report.features = {"editor":OS.has_feature("editor"), "debug":OS.has_feature("debug"), "release":OS.has_feature("release")}
	report.order = ORDERS; report.os = OS.get_name(); report.processor_name = OS.get_processor_name()
	report.scope = "Three sequential rounds per method on the same largest initial GLB; no cache eviction, GPU, concurrent hashing or source writes. Builtin read/update timings are unavailable. Streaming read_us includes PackedByteArray allocation/copy; update_us uses the same CryptoCore SHA-256 backend. Warm file-cache effects and order remain visible in raw samples."
	print("HASH_BUFFER_SELECTED ", selected, " bytes=", selected_size)
	var reference: String = ""
	for round_index in ORDERS.size():
		for method: String in ORDERS[round_index]:
			var sample: Dictionary = builtin(selected, selected_size) if method == "builtin" else stream_hash(selected, method, int(BUFFERS[method]), selected_size)
			sample.round = round_index + 1; sample.order_in_round = ORDERS[round_index].find(method)
			if reference.is_empty() and sample.error == OK: reference = str(sample.sha256)
			sample.matches_reference = sample.error == OK and valid_sha(str(sample.sha256)) and sample.sha256 == reference
			report.samples.append(sample)
			check(sample.matches_reference, "round %d %s full SHA equals the reference" % [round_index + 1, method])
			if method != "builtin":
				check(sample.bytes == selected_size and int(sample.max_chunk_bytes) <= int(BUFFERS[method]), "stream reads every byte using bounded chunks")
			print("HASH_BUFFER_SAMPLE ", JSON.stringify(sample))
			await process_frame
	report.reference_sha256 = reference
	check(report.samples.size() == 12 and not reference.is_empty(), "all four methods complete three rounds")
	check(FileAccess.get_sha256(input) == report.input_sha and size_of(selected) == selected_size, "selection report and source length remain unchanged")
	summarize()
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	file = FileAccess.open(output, FileAccess.WRITE)
	if file == null: push_error("Cannot write hash benchmark report"); quit(1); return
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("SOURCE_HASH_BUFFERS_FINISHED failures=", report.failures, " output=", output)
	quit(0 if report.failures == 0 else 1)
