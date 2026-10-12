extends SceneTree
const Manifest = preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Memory = preload("res://scripts/world3d/asset_memory_estimate.gd")
const INPUT = "D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/foliage/foliage_2k_manifest.json"
const OUT = "D:/code/rmmo/review_artifacts/town_asset_size_audit_20261011/foliage_2k_runtime_manifest_probe.json"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INPUT))
	var result: Dictionary = {"headless": DisplayServer.get_name(), "assets": [], "passed": true}
	for row: Dictionary in data.assets:
		var source: Dictionary = Manifest.read(row.source_lossless)
		var candidate: Dictionary = Manifest.read(row.output)
		var equal: bool = source.get("known", false) and candidate.get("known", false) and source.local_bounds == candidate.local_bounds and source.mesh_nodes == candidate.mesh_nodes
		result.passed = result.passed and equal
		result.assets.append({"asset": row.asset, "profile": row.profile, "candidate": row.output, "candidate_sha256": FileAccess.get_sha256(row.output), "source_known": source.known, "candidate_known": candidate.known, "candidate_reason": candidate.reason, "exact_default_bounds_and_mesh_nodes": equal, "candidate_memory": Memory.estimate(row.output)})
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t")); file.close()
	print("FOLIAGE_2K_MANIFEST_PROBE passed=", result.passed)
	quit(0 if result.passed else 1)
