extends SceneTree
## Read-only CPU microprobe. No scene, texture, physics shape or cache writes.
const Cpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Terrain = preload("res://scripts/world3d/terrain_collision_preparer.gd")
const ROOT = "D:/code/rmmo_runtime/art_sources/stone_bridge_optimization_20261009/"
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func digest(bytes: PackedByteArray) -> String:
	var hash_ := HashingContext.new()
	hash_.start(HashingContext.HASH_SHA256)
	hash_.update(bytes)
	return hash_.finish().hex_encode()

func require(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
	return ok

func transformed_copy(faces: PackedVector3Array, basis: Basis) -> PackedVector3Array:
	var result := faces.duplicate()
	for i in result.size():
		result[i] = basis * result[i]
	return result

func run() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "original_record.json"))
	var raw := FileAccess.get_file_as_bytes(ROOT + "original_cooked.bin")
	if not require(digest(raw) == record.house_prefab.sha256, "Frozen raw identity mismatch"):
		return
	var data: Dictionary = bytes_to_var(raw)
	var report := {"kind": "isolated CPU microprobe, not game entry savings", "source_sha256": record.house_prefab.sha256, "identity_rounds": [], "face_rounds": []}
	var originals: Array = []
	for mesh: Dictionary in data.meshes:
		originals.append(digest(var_to_bytes(mesh.surfaces)))
	for repeat_ in 6:
		var rows: Array = []
		var all_started := Time.get_ticks_usec()
		for mesh_id in data.meshes.size():
			var started := Time.get_ticks_usec()
			var bytes := var_to_bytes(data.meshes[mesh_id].surfaces)
			var serialized := Time.get_ticks_usec()
			var key := digest(bytes)
			var finished := Time.get_ticks_usec()
			rows.append({"mesh": mesh_id, "bytes": bytes.size(), "serialize_ms": (serialized - started) / 1000.0, "sha_ms": (finished - serialized) / 1000.0})
			if not require(key == originals[mesh_id], "Geometry hash changed"):
				return
		report.identity_rounds.append({"total_ms": (Time.get_ticks_usec() - all_started) / 1000.0, "meshes": rows})
	var cpu := Cpu.new()
	cpu.surfaces = data.meshes[1].surfaces
	var local := cpu.collision_faces()
	var local_sha := digest(local.to_byte_array())
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(record.rotation[1])), 0.0))
	var expected := Terrain._extract(cpu.surfaces, basis)
	var expected_sha := digest(expected.to_byte_array())
	for mode in ["expand_transform", "reuse_transform", "reuse_transform", "expand_transform", "expand_transform", "reuse_transform", "reuse_transform", "expand_transform"]:
		var started := Time.get_ticks_usec()
		var result: PackedVector3Array = Terrain._extract(cpu.surfaces, basis) if mode == "expand_transform" else transformed_copy(local, basis)
		var elapsed := (Time.get_ticks_usec() - started) / 1000.0
		report.face_rounds.append({"mode": mode, "ms": elapsed, "vertices": result.size()})
		if not require(digest(result.to_byte_array()) == expected_sha, "Transformed face bytes changed"):
			return
		if not require(digest(local.to_byte_array()) == local_sha, "Shared local faces mutated"):
			return
	for mesh_id in data.meshes.size():
		if not require(digest(var_to_bytes(data.meshes[mesh_id].surfaces)) == originals[mesh_id], "Source arrays mutated"):
			return
	report.checks = checks
	var file := FileAccess.open("res://review_artifacts/bridge_geometry_cpu_micro_20261011.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("BRIDGE_CPU_PROBE checks=", checks, " source and transformed geometry verified")
	quit(0)
