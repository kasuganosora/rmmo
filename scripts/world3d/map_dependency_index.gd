extends RefCounted
## Disposable CPU dependency directory. It proves a map snapshot and spatial
## hints, not that deferred rmres/model bytes have been read or validated.
## Author v2 metadata stays complete; selected definitions still go through the
## ordinary resource reader and business validation before publication.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Store = preload("res://scripts/world3d/map_resource_store.gd")
const Cursor = preload("res://scripts/world3d/document_open_cursor.gd")
const Snapshot = preload("res://scripts/world3d/document_source_snapshot.gd")
const Manifest = preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const Imported = preload("res://scripts/world3d/imported_building.gd")
const Road = preload("res://scripts/world3d/road_surface.gd")
const RoadPreparation = preload("res://scripts/world3d/native_road_preparation.gd")
const Fort = preload("res://scripts/world3d/fortification_data.gd")
const Fixtures = preload("res://scripts/world3d/building_fixtures.gd")
const Prefab = preload("res://scripts/world3d/house_prefab.gd")
const PrefabTextures = preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Bridge = preload("res://scripts/world3d/bridge_data.gd")
const OwnershipProof = preload("res://scripts/world3d/dependency_index_proof.gd")
static var _loading_proof_issuer := RefCounted.new()
static var batch_path_validation:=true # Probe-only old-loop comparison switch.
const VERSION := 4
const MAGIC := "RMMODEPS1"
const MAX_BYTES := 64 * 1024 * 1024
const CHUNK_M := 32.0
const MAX_CHUNK_SPAN := 256
const COMMON_FIELDS := ["uuid", "position", "rotation", "size", "kind", "surface_id", "collision", "color", "invisible", "surface_paint", "editor_group", "editor_group_name", "editor_name", "editor_hidden", "editor_locked"]
const ASSET_FIELDS := ["asset_path", "asset_id", "asset_name", "name", "label", "thumbnail_path", "bounds_position", "bounds_size", "category", "tags", "model_building", "model_building_states"]
const FROZEN_FIELDS := ["house_prefab", "prefab_locked", "prefab_materials"]
const FORT_FIELDS := ["fortification", "fixture", "prefab_tower_center"]
const BRIDGE_FIELDS := ["bridge_mesh", "bridge_materials", "asset_path", "bounds_position", "bounds_size"]
const ROAD_FIELDS := ["road_mesh", "road_clearance", "road_source", "road_kerb_material"]

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "closure_complete": false}

static func generator_key() -> String:
	var hashes: Array = [VERSION, Engine.get_version_info().hash]
	hashes.append(FileAccess.get_sha256("res://scripts/world3d/imported_building.gd"))
	for name in ["map_dependency_index", "dependency_index_proof", "asset_bounds_manifest", "world_document", "building_blueprint", "building_fixtures", "house_prefab", "prefab_texture_preparation", "fortification_data", "bridge_data", "structure_prefab", "river_material_data", "candle_sconce_mesh", "candle_sconce_data", "terrain_surface", "terrain_furrows", "road_surface", "road_kerb", "native_road_preparation", "surface_materials", "document_schema"]:
		hashes.append(FileAccess.get_sha256("res://scripts/world3d/" + name + ".gd"))
	return str(hashes).sha256_text()

static func cache_path(path: String, content_root: String) -> String:
	if not Paths.allowed(path, content_root) or path.get_extension().to_lower() != "gltf": return ""
	var target := content_root.path_join("cache/world3d/dependency_indexes").path_join(path.replace("\\", "/").simplify_path().sha256_text() + ".bin")
	return target if Paths.allowed(target, content_root) else ""

static func _source(path: String, content_root: String, expected_sha: String) -> Dictionary:
	if cache_path(path, content_root).is_empty(): return _fail("invalid_map_path")
	var source_file := FileAccess.open(path, FileAccess.READ)
	if source_file == null or source_file.get_length() > Snapshot.RETAIN_LIMIT: return _fail("source_missing_or_too_large")
	source_file.close()
	var source = Snapshot.read_file(path)
	if not source.error.is_empty() or (not expected_sha.is_empty() and source._signature != expected_sha): return _fail("source_sha_mismatch")
	var native: int = Cursor.native_root(source._data)
	if native < 0: return _fail("not_native_v2")
	var extra: Dictionary = source._data.nodes[native].extras
	var closure := _compact_closure(extra, path, content_root)
	if not closure.ok: return closure
	return {"ok": true, "source": source, "extras": extra, "dependencies": closure.dependencies}

## This checks only the complete authored reference header, without reading any
## rmres payload. It must never seed the resource identity/decoded caches.
static func _compact_closure(extra: Dictionary, path: String, content_root: String) -> Dictionary:
	var compact: Variant = extra.get("rmmo_records")
	var declared: Variant = extra.get("rmmo_resource_dependencies")
	if not compact is Array or compact.size() > Store.MAX_RECORDS or not declared is Dictionary: return _fail("invalid_reference_header")
	var paths: Dictionary = Store._path_batch(path, content_root)
	if paths.is_empty(): return _fail("invalid_resource_root")
	var ids := {}; var actual := {}; var lengths := {}
	for record in compact:
		if not Store._shape(record, true) or ids.has(record.uuid): return _fail("invalid_compact_record")
		ids[record.uuid] = true
		var reference: Dictionary = record.rmmo_ref
		if reference.size() != 4 or reference.get("version") != 1 or not Store._integer(reference.get("length")): return _fail("invalid_reference")
		if reference.length <= 16 or reference.length > Store.MAX_FILE_BYTES: return _fail("invalid_reference_length")
		if Store._batch_location(paths, reference.get("uri"), reference.get("sha256")).is_empty(): return _fail("invalid_reference_path")
		if lengths.has(reference.uri) and lengths[reference.uri] != reference.length: return _fail("conflicting_reference_length")
		actual[reference.uri] = reference.sha256; lengths[reference.uri] = reference.length
	if declared != actual or not Store._finish_paths(paths): return _fail("reference_header_closure_mismatch")
	return {"ok": true, "dependencies": actual}

## The caller supplies its fully hydrated, semantically validated snapshot.
## Re-encoding unique definitions proves it is the exact compact source snapshot;
## a caller cannot accidentally publish bounds from a different edited document.
static func build(path: String, content_root: String, hydrated_records: Array, source_sha: String = "") -> Dictionary:
	var opened := _source(path, content_root, source_sha)
	if not opened.ok: return opened
	var compact: Array = opened.extras.rmmo_records
	if compact.size() != hydrated_records.size(): return _fail("hydrated_count_mismatch")
	if not Blueprint.valid_meta(opened.extras) or not Blueprint.valid_ownership(opened.extras, hydrated_records): return _fail("invalid_full_building_ownership")
	var rows: Array = []; var models := {}; var definitions := {}; var definition_bytes := {}
	for i in compact.size():
		var record: Variant = hydrated_records[i]
		if not Store._shape(record) or record.uuid != compact[i].uuid: return _fail("hydrated_identity_mismatch")
		for field in Store.FIELDS:
			if field == "uuid": continue
			for axis in 3:
				if float(record[field][axis]) != float(compact[i][field][axis]): return _fail("hydrated_pose_mismatch")
		for field in Store.STATE_FIELDS:
			if record.has(field) != compact[i].rmmo_state.has(field) or not _json_equal(record.get(field), compact[i].rmmo_state.get(field), 0, [2000000]): return _fail("hydrated_state_mismatch")
		var definition: Dictionary = Store._definition(record)
		var sha: String = compact[i].rmmo_ref.sha256
		if definitions.has(sha):
			if definitions[sha] != definition: return _fail("hydrated_definition_mismatch")
		else:
			var encoded: Dictionary = Store._encode(definition)
			if not encoded.ok or encoded.sha256 != sha or encoded.length != compact[i].rmmo_ref.length: return _fail("hydrated_definition_mismatch")
			definitions[sha] = definition
			definition_bytes[sha] = int(encoded.get("serialized_raw_bytes", 0))
			if definition_bytes[sha] <= 0: definition_bytes[sha] = var_to_bytes(definition).size()
		var row := _classify(record, content_root, models)
		row.uuid = record.uuid; row.order = i; row.reference = compact[i].rmmo_ref.duplicate(true)
		row.prefab_locked = record.get("prefab_locked", false) == true
		row.group_id = "building:" + str(record.building.id) if record.has("building") else ""
		# Variant/string/container overhead and both immutable geometry handoffs.
		# This is deliberately conservative; compressed rmres bytes are not RAM.
		row.memory_bytes = mini(64 * 1024 * 1024 * 1024, definition_bytes[sha] * 8 + int(record.get("house_prefab", {}).get("length", 0)) * 4 + 65536)
		# Paths only: current bounded image headers are read at job admission, so
		# changing image dimensions does not leave a stale persisted byte estimate.
		row.prefab_textures = PrefabTextures.sources(record)
		if row.reason == "native_road":
			var preparation := RoadPreparation.estimate(record)
			if preparation.ok:
				row.memory_bytes = mini(64 * 1024 * 1024 * 1024, row.memory_bytes + int(preparation.estimated_bytes))
			else:
				row.classification = "global"; row.reason = "road_preparation_unknown"
		rows.append(row)
	var fort_owners := _fortification_owners(opened.extras, rows)
	for row: Dictionary in rows:
		row.group_id = _expected_group(compact[row.order], row, fort_owners)
		if row.reason == "native_fortification" and row.group_id.is_empty(): row.reason = "fortification_manifest_global"
	var groups := _groups(rows)
	for row: Dictionary in rows:
		if not row.group_id.is_empty() and groups[row.group_id].bounds_known:
			row.classification = "group"
			if row.group_id.begins_with("building:"): row.reason = "building_group"
	var payload := {"version": VERSION, "source_sha256": opened.source._signature, "generator": generator_key(), "rows": rows, "models": models, "groups": groups}
	if not _ownership_valid(opened.extras, rows, groups): return _fail("invalid_ownership_directory")
	if not _imported_sources_valid(opened.extras, rows): return _fail("imported_building_source_mismatch")
	if not Store.verify_dependencies(opened.dependencies, path, content_root) or not opened.source.matches_disk(): return _fail("source_changed_during_build")
	for model_path: String in models:
		var current: Dictionary = Manifest.read(model_path)
		if not current.get("known",false) or current.get("json_sha256") != models[model_path].json_sha256 or current.get("file_length") != models[model_path].file_length: return _fail("model_changed_during_build")
	var target := cache_path(path, content_root)
	var bytes := var_to_bytes(payload)
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return _fail("index_too_large")
	if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK or not Paths.allowed(target, content_root): return _fail("index_directory_unavailable")
	var temporary := target + ".%d.%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not Paths.allowed(temporary, content_root): return _fail("invalid_temporary_path")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _fail("index_write_failed")
	file.store_buffer(MAGIC.to_ascii_buffer()); file.store_64(bytes.size()); file.store_buffer(Store._sha(bytes).hex_decode()); file.store_buffer(bytes)
	file.flush(); var error := file.get_error(); file.close()
	if error != OK or not Paths.allowed(temporary, content_root) or not Paths.allowed(target, content_root): return _fail("index_write_failed")
	if not opened.source.matches_disk():
		DirAccess.remove_absolute(temporary); return _fail("source_changed_before_index_publish")
	if DirAccess.rename_absolute(temporary, target) != OK:
		DirAccess.remove_absolute(temporary); return _fail("index_publish_failed")
	return _result(payload, opened.extras, target)

static func read(path: String, content_root: String, expected_source_sha: String = "") -> Dictionary:
	var opened := _source(path, content_root, expected_source_sha)
	if not opened.ok: return opened
	var target := cache_path(path, content_root)
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null or file.get_length() < 49 or file.get_buffer(9).get_string_from_ascii() != MAGIC: return _fail("index_missing_or_header")
	var length := file.get_64()
	if length <= 0 or length > MAX_BYTES or file.get_length() != length + 49: return _fail("invalid_index_length")
	var checksum := file.get_buffer(32); var bytes := file.get_buffer(length); file.close()
	if bytes.size() != length or Store._sha(bytes).hex_decode() != checksum: return _fail("index_payload_sha_mismatch")
	var data: Variant = bytes_to_var(bytes) # Never allow Objects or scripts.
	if not data is Dictionary or not _valid_payload(data, opened.extras.rmmo_records, content_root) or not _ownership_valid(opened.extras, data.rows, data.groups): return _fail("invalid_index_schema")
	if data.source_sha256 != opened.source._signature or data.generator != generator_key(): return _fail("stale_index")
	if not _imported_sources_valid(opened.extras, data.rows): return _fail("imported_building_source_mismatch")
	# Bounds refer to the source accessor JSON. A changed or missing model cannot
	# silently retain an old far-away footprint. Keep it eager until rebuilt.
	var changed_models := {}
	for model_path: String in data.models:
		var current: Dictionary = Manifest.read(model_path) if Paths.allowed(model_path, content_root) else {}
		var expected: Dictionary = data.models[model_path]
		if not current.get("known", false) or current.get("json_sha256") != expected.json_sha256 or current.get("file_length") != expected.file_length or current.get("local_bounds") != expected.local_bounds:
			changed_models[model_path] = true
	for row: Dictionary in data.rows:
		if changed_models.has(row.asset_path):
			row.classification = "global"; row.reason = "model_bounds_changed"; row.bounds_known = false
	if not Paths.allowed(target, content_root) or not opened.source.matches_disk(): return _fail("source_changed_during_index_read")
	return _result(data, opened.extras, target)

static func _result(data: Dictionary, extras: Dictionary, path: String) -> Dictionary:
	return {"ok": true, "reason": "", "source_sha256": data.source_sha256, "generator": data.generator, "rows": data.rows, "models": data.models, "groups": data.groups, "extras": extras, "index_path": path, "closure_complete": false}

## Only this disk-reading factory issues a process-local proof. Ordinary read()
## stays mutable and retains its complete validation path for callers/tests.
static func read_for_loading(path: String, content_root: String, expected_source_sha: String = "") -> Dictionary:
	var index := read(path, content_root, expected_source_sha)
	if not index.ok: return {"ok": false, "reason": index.reason, "index": {}, "proof": null}
	# read() has already downgraded changed model footprints and made its final
	# source observation. No reference to this fresh result has escaped yet.
	var proof: OwnershipProof = OwnershipProof.issue(index, path, content_root, _loading_proof_issuer)
	if proof == null: return {"ok": false, "reason": "unsealable_dependency_directory", "index": {}, "proof": null}
	return {"ok": true, "reason": "", "index": index, "proof": proof}

static func validate_index_ownership(index: Dictionary, content_root: String = "", ownership_proof: OwnershipProof = null, source_path: String = "") -> bool:
	if ownership_proof != null: return ownership_proof.matches(index, content_root, _loading_proof_issuer, source_path)
	return index.get("ok", false) and _ownership_valid(index.extras, index.rows, index.groups)

static func _vec(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

static func _json_equal(a: Variant, b: Variant, depth: int, budget: Array) -> bool:
	budget[0] -= 1
	if depth > 64 or budget[0] < 0: return false
	if (a is int or a is float) and (b is int or b is float): return is_finite(float(a)) and float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not (key is String or key is StringName) or not b.has(str(key)) or not _json_equal(a[key], b[str(key)], depth + 1, budget): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _json_equal(a[i], b[i], depth + 1, budget): return false
		return true
	return typeof(a) in [TYPE_NIL, TYPE_BOOL, TYPE_STRING] and typeof(a) == typeof(b) and a == b

static func _finite_bounds(bounds: AABB) -> bool:
	return Manifest._finite_box(bounds)

static func _classify(record: Dictionary, root: String, models: Dictionary) -> Dictionary:
	var result := {"classification": "global", "reason": "unknown_geometry", "bounds_known": false, "bounds": AABB(), "chunk_min": Vector2i.ZERO, "chunk_max": Vector2i.ZERO, "terrain_halo": 0.0, "asset_path": "", "owner_keys": []}
	for owner in ["building", "fortification"]:
		if record.get(owner) is Dictionary: result.owner_keys.append(owner + ":" + str(record[owner].get("id", "")))
	if record.has("model_building"):result.owner_keys.append("building:"+str(record.uuid))
	if record.has("terrain_mesh"):
		var terrain = preload("res://scripts/world3d/terrain_surface.gd")
		if terrain.valid(record):
			result.bounds = terrain.transform(record) * terrain.bounds(record); result.bounds_known = _finite_bounds(result.bounds)
			# The normal/height context also needs one interpolation sample.
			result.terrain_halo = 8.0 + maxf(float(record.size[0]) / record.terrain_mesh.columns, float(record.size[2]) / record.terrain_mesh.rows)
		result.reason = "terrain_context_global"
	elif record.has("house_prefab"):
		var prefab := _prefab_bounds(record)
		if prefab.known: result.bounds = prefab.bounds; result.bounds_known = true
		result.reason = "prefab_ownership_global"
		if record.has("fortification"):
			if _frozen_structure(record, "fortification", root):
				result.reason = "native_fortification"
			else:
				result.bounds_known = false; result.reason = "unsupported_fortification_behavior"
		elif record.has("bridge_mesh"):
			if _frozen_structure(record, "bridge", root):
				result.reason = "native_bridge"
			else:
				result.bounds_known = false; result.reason = "unsupported_bridge_behavior"
	elif record.get("building_shape") == "candle_sconce" and preload("res://scripts/world3d/candle_sconce_mesh.gd").valid(record):
		var candle := _candle_bounds(record)
		if candle.known: result.bounds = candle.bounds; result.bounds_known = true
		result.reason = "candle_ownership_global"
	elif record.has("model_building"):
		result.asset_path=str(record.get("asset_path",""))
		if Imported.valid_record(record) and _fields_allowed(record,COMMON_FIELDS+ASSET_FIELDS):
			_classify_model(record,root,models,result)
	elif not result.owner_keys.is_empty() or record.has("fixture"):
		result.reason = "ownership_global"
	elif record.has("road_mesh") and _fields_allowed(record, COMMON_FIELDS + ROAD_FIELDS) and Road.valid(record):
		var road := _road_bounds(record)
		if road.known:
			result.bounds = road.bounds; result.bounds_known = true
			result.classification = "spatial"; result.reason = "native_road"
	elif record.get("kind") == "box" and _fields_allowed(record, COMMON_FIELDS):
		var size := _vec(record.size)
		result.bounds = Transform3D(Basis.from_euler(_vec(record.rotation) * PI / 180.0), _vec(record.position)) * AABB(-size / 2.0, size)
		result.bounds_known = _finite_bounds(result.bounds); result.reason = "native_box"
		if result.bounds_known: result.classification = "spatial"
	elif record.get("kind") == "asset" and _fields_allowed(record, COMMON_FIELDS + ASSET_FIELDS):
		_classify_model(record,root,models,result)
	if record.has("building") and not _fields_allowed(record, COMMON_FIELDS + ["building", "fixture", "house_prefab", "prefab_locked", "prefab_materials", "window_design", "building_shape"]):
		result.bounds_known = false; result.reason = "unsupported_building_behavior"
	if result.bounds_known:
		result.chunk_min = Vector2i(floori(result.bounds.position.x / CHUNK_M), floori(result.bounds.position.z / CHUNK_M))
		result.chunk_max = Vector2i(floori(result.bounds.end.x / CHUNK_M), floori(result.bounds.end.z / CHUNK_M))
		if (result.chunk_max - result.chunk_min).length() > MAX_CHUNK_SPAN:
			result.classification = "global"; result.reason = "large_spanning_record"
			if record.has("fortification") or record.has("bridge_mesh"): result.bounds_known = false
	return result

static func _classify_model(record:Dictionary,root:String,models:Dictionary,result:Dictionary)->void:
	var path:=str(record.get("asset_path",""));result.asset_path=path
	if not Paths.allowed(path,root):result.reason="invalid_model_path";return
	var source:Dictionary=models[path].merged({"known":true}) if models.has(path) else Manifest.read(path)
	var placed:Dictionary=Manifest.apply_record(source,record)
	if placed.get("known",false):
		models[path]={"json_sha256":source.json_sha256,"file_length":source.file_length,"local_bounds":source.local_bounds}
		result.bounds=placed.world_bounds;result.bounds_known=true;result.classification="spatial";result.reason="model_accessor_bounds"

# Bind exact source annotations and complete bytes, not a claimed record volume
# or an unchanged accessor header hiding replaced mesh/material binary data.
static func _imported_sources_valid(extras:Dictionary,rows:Array)->bool:
	var hashes:Dictionary={};var descriptors:Dictionary={}
	for row:Dictionary in rows:
		var state:Dictionary=extras.rmmo_records[row.order].rmmo_state
		if not state.has("model_building"):continue
		var path:String=row.asset_path
		if path.is_empty() or not FileAccess.file_exists(path):return false
		if not hashes.has(path):
			hashes[path]=FileAccess.get_sha256(path)
			descriptors[path]=Imported.source_descriptor(path,hashes[path])
		if hashes[path]!=state.model_building.source_sha:return false
		if descriptors[path].is_empty() or not Imported.same(descriptors[path],state.model_building):return false
	return true

## Road.vertices includes both slab faces, the grade, and every persisted kerb
## section point. Kerb adjacency is resolved when authoring; runtime arrays only
## connect those stored points. Paint changes UVs/materials, not positions.
## Never regenerate kerbs from this selected subset or substitute record.size.
static func _road_bounds(record: Dictionary) -> Dictionary:
	var pose := Transform3D(Basis.from_euler(_vec(record.rotation) * PI / 180.0), _vec(record.position))
	var bounds := AABB(); var first := true; var magnitude := 1.0
	for local: Vector3 in Road.vertices(record):
		var point := pose * local
		if not point.is_finite(): return {"known": false}
		bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point); first = false
		magnitude = maxf(magnitude, maxf(absf(point.x), maxf(absf(point.y), absf(point.z))))
	# Keep inclusive chunk boundaries conservative across float32 mesh/AABB math.
	# This is numerical padding, not a neighbour dependency or terrain halo.
	bounds = bounds.grow(maxf(.001, magnitude * .000001))
	return {"known": not first and _finite_bounds(bounds), "bounds": bounds}

static func _candle_bounds(record: Dictionary) -> Dictionary:
	var source = preload("res://scripts/world3d/candle_sconce_mesh.gd")
	var scale_: Vector3 = _vec(record.size) / source.SIZE
	var box := AABB(); var first := true
	for surface: Dictionary in source.DATA.surfaces:
		for raw: Array in surface.vertices:
			var point := _vec(raw) * scale_
			if not point.is_finite(): return {"known": false}
			box = AABB(point, Vector3.ZERO) if first else box.expand(point); first = false
	var result: AABB = Transform3D(Basis.from_euler(_vec(record.rotation) * PI / 180.0), _vec(record.position)) * box
	return {"known": not first and _finite_bounds(result), "bounds": result}

## Frozen geometry is authoritative: no recipe regeneration, terrain sampling,
## neighbour adjacency, or external model import is needed. Unknown behavior is
## never granted this proof even if its old prefab happens to have valid bounds.
static func _frozen_structure(record: Dictionary, kind: String, root: String) -> bool:
	if not Prefab.valid(record) or record.has("surface_paint") or not preload("res://scripts/world3d/surface_materials.gd").valid(record, false, root): return false
	if kind == "fortification":
		if not _fields_allowed(record, COMMON_FIELDS + FROZEN_FIELDS + FORT_FIELDS) or not Fort.valid_record(record) or not Fixtures.valid(record): return false
		if record.fortification.get("role") != "prefab" or str(record.fortification.get("id", "")).is_empty(): return false
		if record.has("prefab_tower_center"):
			var center: Variant = record.prefab_tower_center
			if not center is Array or center.size() != 2: return false
			for coordinate in center:
				if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)): return false
		return true
	return _fields_allowed(record, COMMON_FIELDS + FROZEN_FIELDS + BRIDGE_FIELDS) and Bridge.valid(record) and preload("res://scripts/world3d/river_material_data.gd").valid(record)

## Only complete baked manifests prove a fortification's compact membership.
## Signatures are editor regeneration provenance, not runtime identities: an
## authorized moved module may have an old signature. The map SHA and rmres SHA
## bind its current pose and geometry instead. Invalid/legacy manifests stay global.
static func _fortification_owners(extras: Dictionary, rows: Array) -> Dictionary:
	var layout: Variant = extras.get("editor_layout", {})
	if not layout is Dictionary: return {}
	var regions: Variant = layout.get("fortifications", [])
	if not regions is Array or not Fort.valid(regions): return {}
	var members := {}; var invalid := {}; var parts := {}
	for i in rows.size():
		var state: Dictionary = extras.rmmo_records[i].rmmo_state
		if not state.has("fortification"): continue
		var owner: Variant = state.fortification
		if not owner is Dictionary: return {}
		var id := str(owner.get("id", ""))
		if not members.has(id): members[id] = {}; parts[id] = {}
		members[id][str(extras.rmmo_records[i].uuid)] = true
		var proof := {"kind": "box", "fortification": owner}
		if state.has("fixture"): proof.fixture = state.fixture
		if not rows[i].prefab_locked or owner.get("role") != "prefab" or str(owner.get("part", "")).is_empty() or not Fort.valid_record(proof) or not Fixtures.valid(proof) or state.has("building") or parts[id].has(str(owner.get("part", ""))): invalid[id] = true
		parts[id][str(owner.get("part", ""))] = true
	var result := {}
	for region: Dictionary in regions:
		var id: String = region.settings.id
		if not region.get("baked", false) or not members.has(id) or invalid.has(id): continue
		var declared := {}
		for part: Dictionary in region.parts: declared[str(part.id)] = true
		if declared == members[id]: result[id] = true
	return result

static func _expected_group(compact: Dictionary, row: Dictionary, fort_owners: Dictionary) -> String:
	var state: Dictionary = compact.rmmo_state
	if state.has("building"): return "building:" + str(state.building.get("id", ""))
	if state.has("model_building"):return "building:"+str(compact.uuid)
	if state.has("fortification"):
		var owner := str(state.fortification.get("id", ""))
		if not fort_owners.has(owner): return ""
		if state.has("fixture"): return "fortification_fixture:" + JSON.stringify([owner, str(state.fixture.id)])
		return "fortification_module:" + JSON.stringify([owner, str(compact.uuid)])
	if row.reason == "native_bridge" and row.prefab_locked and not state.has("fixture"): return "bridge:" + str(compact.uuid)
	return ""

static func _groups(rows: Array) -> Dictionary:
	var groups := {}
	for row: Dictionary in rows:
		if row.group_id.is_empty(): continue
		if not groups.has(row.group_id): groups[row.group_id] = {"members": [], "bounds": AABB(), "bounds_known": true, "owner_id": row.group_id.trim_prefix("building:") if row.group_id.begins_with("building:") else ""}
		var group: Dictionary = groups[row.group_id]
		if row.bounds_known:
			group.bounds = row.bounds if group.members.is_empty() else group.bounds.merge(row.bounds)
		else: group.bounds_known = false
		group.members.append(row.order)
	return groups

## Full compact state plus the source-bound derived locked proof is enough to
## check registry closure without decoding every frozen component. This is not
## model/texture/definition integrity: only demanded members receive that check.
static func _ownership_valid(extras: Dictionary, rows: Array, groups: Dictionary) -> bool:
	if not Blueprint.valid_meta(extras) or not extras.get("rmmo_records") is Array or rows.size() != extras.rmmo_records.size(): return false
	var fort_owners := _fortification_owners(extras, rows)
	var proofs: Array = []
	for i in rows.size():
		var row: Dictionary = rows[i]; var compact: Dictionary = extras.rmmo_records[i]
		var state: Dictionary = compact.rmmo_state; var expected_owners: Array = []
		for owner in ["building", "fortification"]:
			if state.has(owner):
				if not state[owner] is Dictionary: return false
				expected_owners.append(owner + ":" + str(state[owner].get("id", "")))
		if state.has("model_building"):
			var authored:Dictionary=compact.merged(state,true)
			if not Imported.valid_record(authored) or not expected_owners.is_empty() or extras.get("building_instances",{}).has(compact.uuid):return false
			expected_owners.append("building:"+str(compact.uuid))
		if row.owner_keys != expected_owners: return false
		var expected_group := _expected_group(compact, row, fort_owners)
		if row.group_id != expected_group: return false
		if not expected_group.is_empty() and (not groups.has(expected_group) or not groups[expected_group] is Dictionary or (groups[expected_group].get("bounds_known", false) == true) != (row.classification == "group")): return false
		if row.reason == "native_fortification" and (not state.has("fortification") or expected_group.is_empty() or not row.prefab_locked): return false
		if row.reason == "native_bridge" and (not expected_owners.is_empty() or state.has("fixture") or not row.prefab_locked or expected_group.is_empty()): return false
		if row.classification == "group":
			var reason: String = "building_group" if expected_group.begins_with("building:") else ("native_bridge" if expected_group.begins_with("bridge:") else "native_fortification")
			if row.reason != reason: return false
		var proof := {"uuid": compact.uuid, "prefab_locked": row.prefab_locked}
		if state.has("building"):
			var b: Dictionary = state.building
			if not b.get("id") is String or not b.get("part") is String: return false
			proof.building = b
		proofs.append(proof)
	# Original ownership logic, with only the already-proven expensive per-record
	# geometry validation skipped. All registry/part/locked constraints remain.
	if not Blueprint.valid_ownership(extras, proofs, true): return false
	return _json_equal_groups(groups, _groups(rows))

static func _json_equal_groups(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size(): return false
	for key in expected:
		if not actual.has(key) or not actual[key] is Dictionary or actual[key] != expected[key]: return false
	return true

static func _fields_allowed(record: Dictionary, allowed: Array) -> bool:
	for field in record:
		if field not in allowed: return false
	return true

## Inspect actual immutable vertices, not the authored size proxy or stored AABB.
## Both visible and solid groups contribute. Fixtures cover every hinge angle.
static func _prefab_bounds(record: Dictionary) -> Dictionary:
	var local:Dictionary=preload("res://scripts/world3d/house_prefab.gd").local_bounds(record.house_prefab)
	if not local.known:return {"known":false}
	var bounds:AABB=local.bounds
	var pose := Transform3D(Basis.from_euler(_vec(record.rotation) * PI / 180.0), _vec(record.position))
	if record.get("kind") == "asset": pose.basis = pose.basis.scaled_local(_vec(record.size))
	if record.has("fixture"):
		if not preload("res://scripts/world3d/building_fixtures.gd").valid(record): return {"known": false}
		var pivot: Vector3 = pose * _vec(record.fixture.pivot); var radius := 0.0
		for i in 8: radius = maxf(radius, (pose * bounds.get_endpoint(i)).distance_to(pivot))
		bounds = AABB(pivot - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	else: bounds = pose * bounds
	if record.has("fortification") or record.has("bridge_mesh"):
		# Frozen float32 vertices and transformed AABBs may round on opposite
		# sides of a chunk boundary. Keep structure selection conservative.
		var magnitude := 1.0
		for value in [bounds.position.x, bounds.position.y, bounds.position.z, bounds.end.x, bounds.end.y, bounds.end.z]: magnitude = maxf(magnitude, absf(value))
		bounds = bounds.grow(maxf(.001, magnitude * .000001))
	return {"known": _finite_bounds(bounds), "bounds": bounds}

static func _valid_payload(data: Dictionary, compact: Array, root: String) -> bool:
	if data.size() != 6 or data.get("version") != VERSION or not Store._digest(data.get("source_sha256")) or not Store._digest(data.get("generator")): return false
	if not data.get("rows") is Array or data.rows.size() != compact.size() or not data.get("models") is Dictionary or data.models.size() > Store.MAX_RECORDS or not data.get("groups") is Dictionary or data.groups.size() > 4096: return false
	# A directory contains many instances of a small set of models. Resolve
	# each exact path once in this validation call, then recheck the whole set
	# before returning. Never persist this filesystem observation across loads.
	var checked_paths:Dictionary={}
	for path in data.models:
		var model: Variant = data.models[path]
		if not path is String or not Paths.allowed(path, root) or not model is Dictionary or model.size() != 3: return false
		checked_paths[path]=true
		if not Store._digest(model.get("json_sha256")) or not model.get("file_length") is int or model.file_length < 28 or not model.get("local_bounds") is AABB or not _finite_bounds(model.local_bounds): return false
	for i in data.rows.size():
		var row: Variant = data.rows[i]
		if not row is Dictionary or row.size() != 16 or row.get("uuid") != compact[i].uuid or row.get("order") != i or row.get("reference") != compact[i].rmmo_ref: return false
		if not row.get("prefab_locked") is bool or not row.get("group_id") is String or row.group_id.length() > 2048: return false
		if not row.get("memory_bytes") is int or row.memory_bytes < 65536 or row.memory_bytes > 64 * 1024 * 1024 * 1024: return false
		if not PrefabTextures.valid_sources(row.get("prefab_textures")):return false
		for source:Array in row.prefab_textures.values():
			if not checked_paths.has(source[0]):
				if not Paths.allowed(source[0],root):return false
				checked_paths[source[0]]=true
		if row.get("classification") not in ["spatial", "global", "group"] or not row.get("reason") is String or row.reason.length() > 100: return false
		if not row.get("bounds_known") is bool or not row.get("bounds") is AABB or not _finite_bounds(row.bounds): return false
		if not row.get("chunk_min") is Vector2i or not row.get("chunk_max") is Vector2i: return false
		if not row.get("terrain_halo") is float or not is_finite(row.terrain_halo) or row.terrain_halo < 0 or row.terrain_halo > 100000: return false
		if not row.get("asset_path") is String:return false
		if not row.asset_path.is_empty() and (not batch_path_validation or not checked_paths.has(row.asset_path)):
			if not Paths.allowed(row.asset_path,root):return false
			checked_paths[row.asset_path]=true
		if not row.get("owner_keys") is Array or row.owner_keys.size() > 2: return false
		for owner in row.owner_keys:
			if not owner is String or owner.length() > 2048: return false
		if row.classification == "spatial":
			if not row.bounds_known or not row.owner_keys.is_empty() or row.terrain_halo != 0.0 or row.reason not in ["native_box", "native_road", "model_accessor_bounds"]: return false
			if row.reason == "model_accessor_bounds" and not data.models.has(row.asset_path): return false
		if row.classification == "group" and (row.group_id.is_empty() or not row.bounds_known): return false
		if row.bounds_known:
			if row.chunk_min != Vector2i(floori(row.bounds.position.x / CHUNK_M), floori(row.bounds.position.z / CHUNK_M)) or row.chunk_max != Vector2i(floori(row.bounds.end.x / CHUNK_M), floori(row.bounds.end.z / CHUNK_M)): return false
	if batch_path_validation:
		for path:String in checked_paths:
			if not Paths.allowed(path,root):return false
	return true

static func _overlaps_xz(a: AABB, b: AABB) -> bool:
	return a.position.x <= b.end.x and a.end.x >= b.position.x and a.position.z <= b.end.z and a.end.z >= b.position.z

## Multiple simultaneous demand clips support origin/teleport pins. Empty clips
## select globals only. Original indices make render order/UUID identity stable.
static func select(index: Dictionary, clips: Array, terrain_halo: float = 8.0) -> Dictionary:
	if not index.get("ok", false) or not index.get("extras") is Dictionary or not index.extras.get("rmmo_records") is Array or not index.get("groups") is Dictionary or not index.get("rows") is Array: return _fail("invalid_index")
	if clips.size() > 64 or not is_finite(terrain_halo) or terrain_halo < 0 or terrain_halo > 100000: return _fail("invalid_demand")
	for clip in clips:
		if not clip is AABB or not _finite_bounds(clip): return _fail("invalid_demand")
	var selected_groups := {}
	for key: String in index.groups:
		var group: Dictionary = index.groups[key]
		var needed: bool = not group.bounds_known
		if not needed:
			for clip: AABB in clips:
				if _overlaps_xz(group.bounds, clip): needed = true; break
		if needed: selected_groups[key] = true
	var selected: Array = []; var deferred: Array = []; var records: Array = []; var dependencies := {}; var deferred_records: Array = []; var deferred_entries: Array = []
	for row: Dictionary in index.rows:
		var grouped: bool = not row.group_id.is_empty()
		var needed: bool = selected_groups.has(row.group_id) if grouped else row.classification == "global"
		if not needed and not grouped:
			for clip: AABB in clips:
				var halo: float = maxf(terrain_halo, row.terrain_halo) if row.terrain_halo > 0 else 0.0
				if _overlaps_xz(row.bounds, clip.grow(halo)): needed = true; break
		var record: Dictionary = index.extras.rmmo_records[row.order]
		if needed:
			selected.append(row.order); records.append(record); dependencies[record.rmmo_ref.uri] = record.rmmo_ref.sha256
		else:
			deferred.append(row.order); deferred_records.append(record); deferred_entries.append({"record_index": row.order, "compact_record": record, "bounds": index.groups[row.group_id].bounds if grouped else row.bounds, "classification": "group" if grouped else row.classification, "reason": row.reason, "asset_path": row.asset_path, "group_id": row.group_id, "memory_bytes": row.memory_bytes})
	# Runtime metadata is mutable; the directory and compact descriptors are not.
	# Exclude the full compact record array before deep-copying metadata so local
	# selection does not duplicate every authored record. Store.read_records later
	# creates independently mutable hydrated poses/states for the selected records.
	var extra: Dictionary = {}
	for key in index.extras:
		if key in ["rmmo_records", "rmmo_resource_dependencies"]: continue
		var value: Variant = index.extras[key]
		extra[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	extra.rmmo_records = records; extra.rmmo_resource_dependencies = dependencies
	return {"ok": true, "record_indices": selected, "compact_records": records, "dependencies": dependencies, "extras": extra, "deferred_indices": deferred, "deferred_compact_records": deferred_records, "deferred_entries": deferred_entries, "selected_groups": selected_groups.keys(), "selected_count": selected.size(), "deferred_count": deferred.size(), "closure_complete": false, "selected_closure_verified": false}

## Call only after selected rmres bytes were hydrated/verified by Store. Returns
## a validation-only registry view; complete author metadata remains in index.
## Selected building and fortification fixture groups are atomic; standalone frozen
## fortification modules and bridges are individual groups, never an entire ring.
static func validate_selected(index: Dictionary, hydrated_records: Array, content_root: String = "", ownership_proof: OwnershipProof = null) -> Dictionary:
	var ownership_started := Time.get_ticks_usec()
	if not validate_index_ownership(index, content_root, ownership_proof): return _fail("invalid_full_ownership_directory")
	var ownership_us := Time.get_ticks_usec() - ownership_started
	var lookup_started := Time.get_ticks_usec()
	var by_uuid: Dictionary = ownership_proof.rows_by_uuid() if ownership_proof != null else {}
	var groups := {}; var by_index := {}; var positions := {}
	if ownership_proof == null:
		for row: Dictionary in index.rows: by_uuid[row.uuid] = row
	var uuid_lookup_us := Time.get_ticks_usec() - lookup_started
	for record in hydrated_records:
		if not Store._shape(record) or not by_uuid.has(record.uuid) or positions.has(record.uuid): return _fail("invalid_selected_identity")
		var row: Dictionary = by_uuid[record.uuid]; var compact: Dictionary = index.extras.rmmo_records[row.order]
		for field in Store.FIELDS:
			if not _json_equal(record[field], compact[field], 0, [2000000]): return _fail("selected_pose_mismatch")
		for field in Store.STATE_FIELDS:
			if record.has(field) != compact.rmmo_state.has(field) or not _json_equal(record.get(field),compact.rmmo_state.get(field),0,[2000000]): return _fail("selected_state_mismatch")
		if (record.get("prefab_locked",false)==true) != row.prefab_locked: return _fail("selected_locked_proof_mismatch")
		if row.reason in ["native_fortification", "native_bridge"] and row.classification == "group":
			var actual := _classify(record, content_root, {})
			if actual.reason != row.reason or not actual.bounds_known or not actual.bounds.is_equal_approx(row.bounds): return _fail("selected_structure_geometry_mismatch")
		positions[record.uuid] = true; by_index[row.order] = true
		if not row.group_id.is_empty(): groups[row.group_id] = true
	for group: String in groups:
		for member in index.groups[group].members:
			if not by_index.has(member): return _fail("incomplete_selected_building")
	var meta: Dictionary = index.extras.duplicate(); var registry := {}
	for group: String in groups:
		if not group.begins_with("building:"): continue
		var id: String = index.groups[group].owner_id
		if index.extras.get("building_instances",{}).has(id):registry[id]=index.extras.building_instances[id]
		elif not positions.has(id):return _fail("missing_imported_building_owner")
	meta.building_instances = registry
	if not Blueprint.valid_ownership(meta, hydrated_records): return _fail("invalid_selected_building_ownership")
	return {"ok": true, "validation_extras": meta, "selected_groups": groups.keys(), "closure_complete": false, "ownership_validation_us": ownership_us, "uuid_lookup_us": uuid_lookup_us, "ownership_proof_used": ownership_proof != null}
