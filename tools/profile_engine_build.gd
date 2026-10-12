extends SceneTree
## Opt-in, CPU-only build comparison. No map, image decode, renderer resource,
## shader warmup or cache mutation. Metadata-only unless --terrain is supplied.
const Terrain = preload("res://scripts/world3d/terrain_surface.gd")
var output := ""
var cells := 32
var jobs := 8
var workers := 1
var terrain_enabled := false

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg == "--terrain": terrain_enabled = true
		elif arg.begins_with("--cells="): cells = arg.trim_prefix("--cells=").to_int()
		elif arg.begins_with("--jobs="): jobs = arg.trim_prefix("--jobs=").to_int()
		elif arg.begins_with("--workers="): workers = arg.trim_prefix("--workers=").to_int()
	if cells < 2 or cells > 64 or jobs < 1 or jobs > 32 or workers < 1 or workers > 4:
		push_error("Expected cells 2..64, jobs 1..32 and workers 1..4")
		quit(1)
		return
	var features := {}
	for tag: String in ["editor", "editor_hint", "editor_runtime", "template", "debug", "release", "single", "double", "x86_64", "headless"]:
		features[tag] = OS.has_feature(tag)
	var report := {
		"version": Engine.get_version_info(), "executable": OS.get_executable_path(),
		"is_debug_build": OS.is_debug_build(), "editor_hint": Engine.is_editor_hint(),
		"debugger_active": EngineDebugger.is_active(), "features": features,
		"display_server": DisplayServer.get_name(), "processor_count": OS.get_processor_count(),
		"renderer": ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"),
		"probe_sha256": FileAccess.get_sha256("res://tools/profile_engine_build.gd"),
		"terrain_sha256": FileAccess.get_sha256("res://scripts/world3d/terrain_surface.gd"),
		"terrain_enabled": terrain_enabled,
		"scope": "synthetic Terrain.arrays CPU kernel; not an entry-loading benchmark",
		"failures": 0,
	}
	if terrain_enabled:
		var result := benchmark()
		report.terrain = result
		if not result.ok: report.failures += 1
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write diagnostic output: " + output)
			quit(1)
			return
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("ENGINE_BUILD_PROFILE ", JSON.stringify(report))
	quit(1 if report.failures else 0)

func fixture() -> Dictionary:
	var heights: Array = []
	var holes: Array = []
	for z in cells + 1:
		for x in cells + 1: heights.append(sin(x * 0.25) * cos(z * 0.23) * 2.0)
	for z in cells:
		for x in cells: holes.append(x > cells / 3 and x < cells / 2 and z > cells / 3 and z < cells / 2)
	return {"uuid": "engine_build_cpu_fixture", "kind": "box", "surface_id": "ground",
		"position": [0, 0, 0], "rotation": [0, 0, 0], "size": [24, 1, 24], "collision": "walk",
		"terrain_mesh": {"version": 1, "columns": cells, "rows": cells, "floor": -8.0, "heights": heights, "holes": holes}}

static func digest(value: Variant) -> String:
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(var_to_bytes(value))
	return hash_context.finish().hex_encode()

static func work(record: Dictionary, count: int) -> Dictionary:
	var samples: Array[float] = []
	var last: Array = []
	for i in count:
		var began := Time.get_ticks_usec()
		last = Terrain.arrays(record)
		samples.append((Time.get_ticks_usec() - began) / 1000.0)
	return {"samples_ms": samples, "arrays": last}

func benchmark() -> Dictionary:
	var record := fixture()
	# One untimed same-input warmup also provides the complete output identity.
	var baseline := Terrain.arrays(record)
	var expected := digest(baseline)
	baseline.clear()
	var batches: Array[Dictionary] = []
	var threads: Array[Thread] = []
	var failed := false
	var began := Time.get_ticks_usec()
	for worker in mini(workers, jobs):
		var count := int(jobs / workers) + (1 if worker < jobs % workers else 0)
		var thread := Thread.new()
		var error := thread.start(work.bind(record.duplicate(true), count))
		if error != OK:
			failed = true
			break
		threads.append(thread)
	for thread: Thread in threads: batches.append(thread.wait_to_finish())
	var wall_ms := (Time.get_ticks_usec() - began) / 1000.0
	var samples: Array[float] = []
	var signatures: Array[String] = []
	for batch: Dictionary in batches:
		samples.append_array(batch.samples_ms)
		var actual := digest(batch.arrays)
		signatures.append(actual)
		if actual != expected: failed = true
		batch.arrays.clear()
	samples.sort()
	if samples.size() != jobs: failed = true
	return {"ok": not failed, "cells": cells, "jobs": jobs, "requested_workers": workers,
		"started_workers": threads.size(), "wall_ms": wall_ms, "job_ms": samples,
		"median_job_ms": samples[samples.size() / 2] if not samples.is_empty() else 0.0,
		"output_sha256": expected, "worker_output_sha256": signatures,
		"wall_scope": "thread launch, isolated input copies, arrays, old-array release and join; output SHA occurs afterward",
		"memory_scope": "at most one final arrays result per worker; no ArrayMesh, image, texture or physics shape"}
