extends SceneTree
const OUT = "D:/code/rmmo/review_artifacts/alarm_tower_game_20261011"
const ASSET = OUT + "/guild_alarm_tower_game.glb"
const Manifest = preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Memory = preload("res://scripts/world3d/asset_memory_estimate.gd")
const Builder = preload("res://scripts/world3d/collision_asset_builder.gd")
const Descriptor = preload("res://scripts/world3d/collision_asset_descriptor.gd")
const Drainer = preload("res://scripts/world3d/asset_worker_drainer.gd")
var worker := Thread.new()
var report: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manifest: Dictionary = Manifest.read(ASSET)
	var memory: Dictionary = Memory.estimate(ASSET)
	report = {"source_sha256": FileAccess.get_sha256(ASSET), "headless": DisplayServer.get_name(), "manifest": manifest, "memory_estimate": memory, "collision_cache_enabled": Descriptor.enabled}
	var file := FileAccess.open(ASSET, FileAccess.READ)
	file.seek(12)
	var json_size := file.get_32()
	file.get_32()
	var data: Dictionary = JSON.parse_string(file.get_buffer(json_size).get_string_from_utf8())
	var bin_size := file.get_32()
	file.close()
	report["source_scene_count"] = data.scenes.size()
	report["source_default_scene"] = data.get("scene", 0)
	var other: Dictionary = data.duplicate(true)
	other.scene = 1
	report["alternate_scene_manifest"] = Manifest.from_json(other, bin_size)
	var estimate: Dictionary = Builder.estimate(ASSET, OUT)
	report["collision_builder_estimate"] = estimate
	if estimate.is_empty():
		report["collision_build"] = {"skipped": true, "reason": "estimate unavailable"}
	else:
		var status := worker.start(build_collision.bind(int(estimate.estimated_bytes)))
		if status == OK:
			while worker.is_alive(): await process_frame
			var packet: Dictionary = worker.wait_to_finish()
			var summary: Dictionary = {}
			for key in ["ok", "reason", "cancelled", "admitted_bytes"]:
				if packet.has(key): summary[key] = packet[key]
			var prepared: Dictionary = packet.get("private_preparation", {})
			for key in ["error", "captured_meshes", "capture_bytes", "face_bytes", "capture_us", "face_us", "compiled"]:
				if prepared.has(key): summary["preparation_" + key] = prepared[key]
			report["collision_build"] = summary
			Drainer.dispose_result(packet)
		else:
			report["collision_build"] = {"skipped": true, "reason": "worker start failed", "error": status}
	var result := FileAccess.open(OUT + "/runtime_manifest_probe.json", FileAccess.WRITE)
	result.store_string(JSON.stringify(report, "\t"))
	result.close()
	print("RUNTIME_MANIFEST_PROBE ", JSON.stringify(report))
	quit()

func build_collision(admitted_bytes: int) -> Dictionary:
	return Builder.build(ASSET, OUT, admitted_bytes)
