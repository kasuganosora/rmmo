extends SceneTree
## Read-only source benchmark. Only small, disposable race fixtures are changed.
## Each final check and simulated publication is synchronous: no await/callback.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const SOURCE = "D:/code/rmmo_runtime/cache/world3d/bridge_perf_20261006/map.gltf"
const EXPECTED_SHA = "95999c6c22d14a14d3187ea0df865db5fb3dcb52276b6c6ec3426559c74bc62d"
const CHUNK = 4 * 1024 * 1024
var failures := 0
var report := {"samples": [], "checks": [], "chunk_bytes": CHUNK}
var output := "D:/code/rmmo_runtime/review_artifacts/document_final_check_20261007.json"

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS: " if value else "FAIL: ", label)
	report.checks.append({"ok": value, "label": label})
	if not value: failures += 1

static func snapshot(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var size := file.get_length()
	var bytes := file.get_buffer(size)
	if bytes.size() != size or file.get_error() != OK: return {}
	file.close()
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK: return {}
	return {"bytes": bytes, "signature": context.finish().hex_encode()}

static func verify(path: String, original: Dictionary, method: String) -> Dictionary:
	var start := Time.get_ticks_usec()
	var before := OS.get_static_memory_usage()
	var peak := before
	var accepted := false
	var bytes: PackedByteArray = original.get("bytes", PackedByteArray())
	var signature: String = original.get("signature", "")
	# No prepared Boolean is used as proof, including for missing/empty files.
	if not original.has("bytes") or signature.length() != 64:
		return {"ok": false, "ms": (Time.get_ticks_usec()-start)/1000.0}
	if method == "sha":
		var current := FileAccess.get_sha256(path)
		accepted = current.length() == 64 and current == signature
	else:
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null and file.get_length() == bytes.size():
			if method == "whole":
				var current := file.get_buffer(bytes.size())
				peak = maxi(peak, OS.get_static_memory_usage())
				accepted = current.size() == bytes.size() and file.get_error() == OK and current == bytes
			else:
				accepted = true
				var offset := 0
				while offset < bytes.size():
					var count := mini(CHUNK, bytes.size()-offset)
					var current := file.get_buffer(count)
					var expected := bytes.slice(offset, offset+count)
					peak = maxi(peak, OS.get_static_memory_usage())
					if current.size() != count or file.get_error() != OK or current != expected:
						accepted = false
						break
					offset += count
			accepted = accepted and file.get_length() == bytes.size()
			file.close()
	# A publication marker is deliberately in the same call, not a deferred task.
	var published := accepted
	return {"ok": published, "method": method, "ms": (Time.get_ticks_usec()-start)/1000.0,
		"static_before_bytes": before, "static_sampled_peak_bytes": peak,
		"static_sampled_delta_bytes": peak-before, "process_static_lifetime_peak_bytes": OS.get_static_memory_peak_usage()}

func write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes)
	var ok := file.get_error() == OK
	file.close()
	return ok

func race_tests() -> void:
	var directory := Paths.cache_directory("final_bytes_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("race.gltf")
	check(write_bytes(path, "{\"same_size\":\"A\"}".to_utf8_buffer()), "create private race fixture")
	var original := snapshot(path)
	var before_time := FileAccess.get_modified_time(path)
	# Preserve exact Windows UTC timestamp, not just Godot's seconds resolution.
	var command := "$p='%s'; $t=[IO.File]::GetLastWriteTimeUtc($p); $b=[IO.File]::ReadAllBytes($p); $b[$b.Length-3]=66; [IO.File]::WriteAllBytes($p,$b); [IO.File]::SetLastWriteTimeUtc($p,$t); if ([IO.File]::GetLastWriteTimeUtc($p).Ticks -ne $t.Ticks) {exit 2}" % path.replace("'", "''")
	var process_output: Array = []
	var exit_code := OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", command]), process_output, true, false)
	check(exit_code == 0 and FileAccess.get_modified_time(path) == before_time and FileAccess.get_file_as_bytes(path).size() == original.bytes.size(), "race changes bytes but retains exact UTC mtime and length")
	for method in ["sha", "whole", "chunk"]:
		check(not verify(path, original, method).ok, method+": reject same-length same-mtime change after initial snapshot/hash")
		check(not verify(directory.path_join("missing.gltf"), original, method).ok, method+": reject read/open failure")
		check(not verify(path, {"prepared": true}, method).ok, method+": untrusted prepared Boolean cannot accept")
	check(write_bytes(path, original.bytes), "restore exact original bytes")
	for method in ["sha", "whole", "chunk"]:
		check(verify(path, original, method).ok, method+": identical bytes accepted")
	check(write_bytes(path, original.bytes.slice(0, 4)), "truncate private fixture")
	for method in ["sha", "whole", "chunk"]:
		check(not verify(path, original, method).ok, method+": truncated file rejected")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)

func run() -> void:
	var source := SOURCE
	var repeats := 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="): source = arg.trim_prefix("--source=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--repeats="): repeats = maxi(1, int(arg.trim_prefix("--repeats=")))
	var thread := Thread.new()
	var preparation_start := Time.get_ticks_usec()
	var error := thread.start(snapshot.bind(source), Thread.PRIORITY_LOW)
	check(error == OK, "start independent snapshot/hash worker")
	if error != OK: quit(1); return
	while thread.is_alive(): await process_frame
	var original: Dictionary = thread.wait_to_finish()
	report.preparation_ms = (Time.get_ticks_usec()-preparation_start)/1000.0
	check(not original.is_empty(), "worker produced complete byte snapshot and matching digest")
	if original.is_empty(): quit(1); return
	report.source = source; report.source_bytes = original.bytes.size(); report.source_sha = original.signature
	if source == SOURCE: check(original.signature == EXPECTED_SHA, "frozen benchmark fixture matches expected SHA")
	for iteration in repeats:
		for method in ["sha", "whole", "chunk", "chunk", "whole", "sha"]:
			await process_frame
			var frame_before := Engine.get_process_frames()
			var result := verify(source, original, method)
			result.iteration = iteration
			result.process_frame_delta = Engine.get_process_frames()-frame_before
			report.samples.append(result)
			check(result.ok and result.process_frame_delta == 0, method+": full verification/publication in one main-thread unit")
			print("FINAL_CHECK_SAMPLE ", JSON.stringify(result))
	race_tests()
	report.failures = failures
	report.note = "Engine static allocation metrics, not OS RSS. Main-thread maximum unit is the maximum synchronous sample ms. Per-method peak is sampled while byte buffers coexist; lifetime peak is cumulative. Source bytes stay resident for all methods. No disk source changes are made."
	var destination := FileAccess.open(output, FileAccess.WRITE)
	if destination == null: push_error("Cannot write report: "+output); quit(1); return
	destination.store_string(JSON.stringify(report, "\t")); destination.close()
	print("DOCUMENT_FINAL_CHECK_FINISHED failures=", failures, " report=", output)
	quit(0 if failures == 0 else 1)
