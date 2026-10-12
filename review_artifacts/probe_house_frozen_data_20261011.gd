extends SceneTree
## Read-only authored definition/CPU audit. No scenes, materials or cache writes.
const SELECTION = "res://review_artifacts/house_audit_selection_20261011.json"
const Cook = preload("res://scripts/world3d/runtime_mesh_cache.gd")
var checks := 0
var failed := false

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
		failed = true
		push_error(message)
	return ok

func read_definition(path: String, reference: Dictionary) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if not require(bytes.size() == int(reference.length) and digest(bytes) == reference.sha256, "rmres identity: " + path):
		return {}
	if not require(bytes.slice(0, 8).get_string_from_ascii() == "RMMORES1", "rmres header"):
		return {}
	var count := bytes.decode_u64(8)
	if not require(count > 0 and count <= 67108864, "rmres size bound"):
		return {}
	var raw := bytes.slice(16).decompress(count, FileAccess.COMPRESSION_ZSTD)
	if not require(raw.size() == count, "rmres decompressed length"):
		return {}
	var value: Variant = bytes_to_var(raw)
	if not require(value is Dictionary, "rmres dictionary"):
		return {}
	return value

func frozen_data(definition: Dictionary) -> Dictionary:
	var prefab: Dictionary = definition.house_prefab
	var raw := Marshalls.base64_to_raw(prefab.data).decompress(int(prefab.length), FileAccess.COMPRESSION_ZSTD)
	if not require(raw.size() == int(prefab.length) and digest(raw) == prefab.sha256, "Frozen payload identity"):
		return {}
	var data: Variant = bytes_to_var(raw)
	if not require(data is Dictionary and Cook.valid_data(data), "Frozen schema"):
		return {}
	return data

func mesh_info(mesh: Dictionary, materials: Array) -> Dictionary:
	var summary := {"vertices": 0, "triangles": 0, "surfaces": mesh.surfaces.size(), "nonwhite_colors": 0, "nonwhite_colors_disabled": 0, "color_vertices": 0, "collision_visual_attribute_bytes": 0}
	var raw := var_to_bytes(mesh.surfaces)
	summary.geometry_sha = digest(raw)
	summary.geometry_bytes = raw.size()
	for slot in mesh.surfaces.size():
		var arrays: Array = mesh.surfaces[slot]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		summary.vertices += vertices.size()
		summary.triangles += indices.size() / 3 if indices != null and not indices.is_empty() else vertices.size() / 3
		var material: Dictionary = materials[mesh.materials[slot]]
		var enabled: bool = material.get("vertex_color", false) or material.get("values", {}).get("vertex_color_use_as_albedo", false)
		var colors: Variant = arrays[Mesh.ARRAY_COLOR]
		if colors is PackedColorArray:
			summary.color_vertices += colors.size()
			for color: Color in colors:
				if color != Color.WHITE:
					summary.nonwhite_colors += 1
					if not enabled: summary.nonwhite_colors_disabled += 1
		for index in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			if arrays[index] != null: summary.collision_visual_attribute_bytes += arrays[index].to_byte_array().size()
	return summary

func run() -> void:
	var selection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SELECTION))
	var map_path: String = selection.map
	if not require(FileAccess.get_sha256(map_path) == selection.map_sha, "Map changed before audit"):
		quit(1); return
	var map_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var compacts: Dictionary = {}
	for node: Dictionary in map_data.nodes:
		for record: Dictionary in node.get("extras", {}).get("rmmo_records", []): compacts[record.uuid] = record
	if not require(not compacts.is_empty(), "Authored node metadata missing"):
		quit(1); return
	var refs: Dictionary = {}
	var instances: Array = []
	for row: Dictionary in selection.house_rows:
		var key: String = row.reference.sha256
		if not refs.has(key): refs[key] = {"reference": row.reference, "users": 0, "example_uuid": row.uuid}
		refs[key].users += 1
		var record: Dictionary = compacts[row.uuid]
		instances.append({"uuid": row.uuid, "reference_sha": key, "group": row.group_id, "rotation": record.rotation, "state": record.rmmo_state})
	var definitions: Array = []
	for key: String in refs:
		var entry: Dictionary = refs[key]
		var definition := read_definition(map_path.get_base_dir().path_join(entry.reference.uri), entry.reference)
		if failed: quit(1); return
		var result := {"reference_sha": key, "reference": entry.reference, "users": entry.users, "example_uuid": entry.example_uuid, "kind": definition.get("kind", ""), "asset_path": definition.get("asset_path", ""), "frozen": definition.has("house_prefab")}
		if definition.has("house_prefab"):
			var data := frozen_data(definition)
			if failed: quit(1); return
			result.prefab_sha = definition.house_prefab.sha256
			result.prefab_raw_bytes = definition.house_prefab.length
			result.meshes = []
			result.entry = data.entries[0]
			result.material_count = data.materials.size()
			result.geometry_bytes = 0
			for mesh: Dictionary in data.meshes:
				var info := mesh_info(mesh, data.materials)
				result.geometry_bytes += info.geometry_bytes
				result.meshes.append(info)
		definitions.append(result)
		if definitions.size() % 100 == 0: print("HOUSE_AUDIT definitions=", definitions.size())
	var candidates: Array = definitions.filter(func(row: Dictionary) -> bool: return row.frozen)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.geometry_bytes > b.geometry_bytes)
	var samples: Array = []
	var sampled: Dictionary = {}
	for at in [0, candidates.size() / 2, candidates.size() - 1]:
		var row: Dictionary = candidates[int(at)]
		if sampled.has(row.prefab_sha): continue
		sampled[row.prefab_sha] = true
		var definition := read_definition(map_path.get_base_dir().path_join(row.reference.uri), row.reference)
		var data := frozen_data(definition)
		var rounds: Array = []
		for repeat_ in 6:
			var started := Time.get_ticks_usec()
			var keys: Array = []
			for mesh: Dictionary in data.meshes: keys.append(digest(var_to_bytes(mesh.surfaces)))
			rounds.append((Time.get_ticks_usec() - started) / 1000.0)
			for mesh_id in data.meshes.size(): require(keys[mesh_id] == row.meshes[mesh_id].geometry_sha, "Geometry identity mismatch")
		samples.append({"reference_sha": row.reference_sha, "example_uuid": row.example_uuid, "geometry_bytes": row.geometry_bytes, "identity_rounds_ms": rounds})
	for entry: Dictionary in refs.values():
		require(FileAccess.get_sha256(map_path.get_base_dir().path_join(entry.reference.uri)) == entry.reference.sha256, "rmres changed during audit")
	require(FileAccess.get_sha256(map_path) == selection.map_sha, "Map changed during audit")
	var output := {"map": map_path, "map_sha": selection.map_sha, "note": "Read-only CPU/source audit, identity timings are per resource operation, not whole-game savings", "definitions": definitions, "instances": instances, "samples": samples, "checks": checks, "failed": failed}
	var file := FileAccess.open("res://review_artifacts/house_frozen_data_audit_20261011.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ")); file.close()
	print("HOUSE_FROZEN_AUDIT_FINISHED definitions=", definitions.size(), " checks=", checks, " failed=", failed)
	quit(1 if failed else 0)
