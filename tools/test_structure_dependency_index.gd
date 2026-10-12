extends SceneTree
## CPU-only frozen structures; temporary maps only, no production index rebuild.
const Index = preload("res://scripts/world3d/map_dependency_index.gd")
const Prepare = preload("res://scripts/world3d/chunk_reference_preparation.gd")
const Fixture = preload("res://tools/structure_dependency_fixture.gd")
const Files = preload("res://tools/test_map_dependency_index.gd")
const Cursor = preload("res://scripts/world3d/document_open_cursor.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")

class WorkerErrors extends Logger:
	var errors: Array[String] = []
	var guard := Mutex.new()
	func _log_error(function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _backtraces: Array) -> void:
		guard.lock(); errors.append(function + ": " + code + " " + rationale); guard.unlock()

var files: SceneTree
var names: Array[String] = []
var passed := 0
var failed := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS: " if value else "FAIL: ", label)
	if value: passed += 1
	else: failed += 1
func write_map(name_: String, records: Array, meta: Dictionary = {}) -> Dictionary:
	names.append(name_)
	return files.fixture(name_, records, Fixture.metadata(records) if meta.is_empty() else meta)
func clip(x: float, width: float = .1) -> AABB:
	return AABB(Vector3(x, -10, -.1), Vector3(width, 20, .2))
func entries(index: Dictionary, wanted: Array) -> Array:
	var result: Array = []
	for entry: Dictionary in Index.select(index, []).deferred_entries:
		if entry.record_index in wanted: result.append(entry)
	return result

func textured_worker() -> void:
	var texture_path: String = files.folder.path_join("frozen_structure_material.png")
	files.created.append(texture_path)
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8); image.fill(Color(.4, .5, .6, 1))
	check(image.save_png(texture_path) == OK, "textured worker fixture writes a real temporary PNG")
	var material := {"name": "worker texture", "color": [1, 1, 1, 1], "roughness": .9, "tile_size": [1, 1], "texture_path": texture_path}
	var records: Array = [Fixture.wall("textured_wall", 0), Fixture.bridge("textured_bridge", 100, files.content_root)]
	for record: Dictionary in records:
		var data := Index.Prefab.decode(record.house_prefab).duplicate(true)
		data.materials = [{"paint": material.duplicate(true), "cull": 0}]
		var encoded := var_to_bytes(data)
		record.house_prefab = {"version": 1, "sha256": Index.Store._sha(encoded), "length": encoded.size(), "data": Marshalls.raw_to_base64(encoded.compress(FileAccess.COMPRESSION_ZSTD))}
		record.prefab_materials = [material.duplicate(true)]
		if record.has("bridge_mesh"):
			record.bridge_materials = {"deck": material.duplicate(true), "masonry": material.duplicate(true), "trim": material.duplicate(true)}
	var source := write_map("textured_worker", records)
	var source_sha := FileAccess.get_sha256(source.path)
	var built := Index.build(source.path, files.content_root, records)
	var index := Index.read(source.path, files.content_root)
	check(built.ok and index.ok and index.rows[0].reason == "native_fortification" and index.rows[1].reason == "native_bridge", "textured fortification and bridge enter source-bound native directory")
	if not built.ok or not index.ok: return
	# Engine errors can be printed while GDScript returns a successful Dictionary.
	# Count the logger callback as a failure as well as checking result.error.
	var logger := WorkerErrors.new(); OS.add_logger(logger)
	var worker := Thread.new()
	var started := worker.start(Prepare.prepare.bind(index, entries(index, [0, 1]), source.path, files.content_root))
	check(started == OK, "textured native reference preparation starts on an actual worker thread")
	var result: Dictionary = worker.wait_to_finish() if started == OK else {"error": "thread_start_failed", "records": []}
	OS.remove_logger(logger)
	check(result.error.is_empty() and result.records.size() == 2 and result.get("selected_closure_verified", false), "worker passes explicit snapshot content root through selected structure validation")
	var held: Dictionary = result.get("prefab_cpu", {})
	var complete := held.size() == 2
	for record: Dictionary in records:
		var packet: Dictionary = held.get(record.house_prefab.sha256, {})
		if packet.is_empty() or packet.get("data", {}).get("materials", []) != [{"paint": material, "cull": 0}]: complete = false
	check(complete, "worker-owned fortification and bridge packets preserve their real texture definitions")
	check(logger.errors.is_empty(), "textured worker emits zero engine or script errors, independently of assertion counts")
	for error in logger.errors: print("TEXTURED_WORKER_ENGINE_ERROR ", error)
	check(FileAccess.get_sha256(source.path) == source_sha, "threaded textured preparation preserves the exact source snapshot")

func run() -> void:
	files = Files.new(); files.content_root = Paths.external_root()
	files.folder = Paths.cache_directory("structure_directory_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	textured_worker()
	if "--worker-only" in OS.get_cmdline_user_args(): finish(); return
	var records := Fixture.records(files.content_root)
	var source := write_map("structures", records)
	var sha := FileAccess.get_sha256(source.path)
	var built := Index.build(source.path, files.content_root, records)
	check(built.ok, "complete frozen fortification and bridge snapshot indexes")
	if not built.ok: print(built); finish(); return
	var index := Index.read(source.path, files.content_root)
	check(index.ok, "source-bound directory roundtrips")
	if not index.ok: print(index); finish(); return
	check(index.groups.size() == 5 and index.rows[0].group_id != index.rows[1].group_id, "two distant wall modules never form a whole-ring loading group")
	check(index.rows[2].group_id == index.rows[3].group_id and index.groups[index.rows[2].group_id].members == [2, 3], "complete double gate has one atomic group")
	check(index.rows[4].group_id != index.rows[2].group_id, "equal fixture names on different fortification owners remain separate")
	check(index.rows[5].reason == "native_bridge" and index.groups[index.rows[5].group_id].members == [5], "whole frozen bridge is one self-contained group")
	check(Index.select(index, []).record_indices.is_empty(), "validated frozen structures do not become global by default")
	check(Index.select(index, [clip(0)]).record_indices == [0], "near wall requires no far ring modules or gates")
	check(Index.select(index, [clip(522)]).record_indices == [2, 3], "touching one gate loads both leaves without adjacent wall or other owner")
	check(Index.select(index, [clip(890)]).record_indices == [5], "bridge actual footprint crosses proxy bounds and includes boundary")
	check(index.rows[5].asset_path.is_empty() and index.models.is_empty(), "frozen bridge recipe model path is provenance, not a model import")
	var selected := Index.select(index, [clip(520)])
	var hydrated := Cursor.hydrate_references(selected.extras, source.path, files.content_root)
	check(hydrated.ok and Index.validate_selected(index, hydrated.extras.rmmo_records).ok, "selected non-building group preserves registry validation")
	check(selected.extras.editor_layout == source.extras.editor_layout and index.extras.rmmo_records.size() == 6, "complete author metadata remains separate from selected records")
	check(not Index.validate_selected(index, [hydrated.extras.rmmo_records[0]]).ok, "missing gate leaf cannot pass selected ownership")
	var requested := entries(index, [2, 3])
	check(not Prepare.prepare(index, [requested[0]], source.path, files.content_root).error.is_empty(), "worker rejects split gate before resource preparation")
	var prepared := Prepare.prepare(index, requested, source.path, files.content_root)
	check(prepared.error.is_empty() and prepared.records.size() == 2 and prepared.record_indices == [2, 3], "worker hydrates exactly complete requested gate in source order")
	check(prepared.get("prefab_cpu", {}).size() == 1 and prepared.get("read_profile", {}).get("prefab_instances", 0) == 2, "gate CPU geometry is prepared and held by one admitted job")
	var bridge_prepared := Prepare.prepare(index, entries(index, [5]), source.path, files.content_root)
	if not bridge_prepared.error.is_empty(): print("BRIDGE_PREPARE_ERROR ", bridge_prepared.error)
	check(bridge_prepared.error.is_empty() and bridge_prepared.records.size() == 1, "whole bridge has a working demanded native CPU path")
	# Full hinge sweep conservatively covers any supported runtime open state.
	var row: Dictionary = index.rows[2]; var record: Dictionary = records[2]
	var bounds: AABB = Index.Prefab.decode(record.house_prefab).meshes[0].bounds
	var sweep_ok := true
	for step in 11:
		var pose := Index.Fixtures.pose(Transform3D(Basis.IDENTITY, Vector3(520, 2, 0)), record.fixture, step / 10.0)
		for corner in 8:
			var point := pose * bounds.get_endpoint(corner)
			if not row.bounds.grow(.001).has_point(point): sweep_ok = false
	check(sweep_ok, "gate directory contains every hinge angle including collision vertices")
	var detailed: Dictionary = records[5].duplicate(true)
	var data := Index.Prefab.decode(detailed.house_prefab).duplicate(true)
	# A collision-only mesh extends beyond the visible deck and stored proxy.
	data.meshes.append({"bounds": AABB(Vector3.ZERO, Vector3.ONE), "box_size": Vector3(30, 3, 8), "surfaces": [], "materials": []})
	data.entries[0][1][1] = 1
	var bytes := var_to_bytes(data)
	detailed.house_prefab = {"version": 1, "sha256": Index.Store._sha(bytes), "length": bytes.size(), "data": Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	var transformed_ok := true
	for angle in [0, 15, 45, 89, 135, 270]:
		detailed.rotation = [11, angle, -7]; detailed.size = [1.5, .8, .75]
		var actual := Index._classify(detailed, files.content_root, {})
		var pose := Transform3D(Basis.from_euler(Vector3(11, angle, -7) * PI / 180).scaled_local(Vector3(1.5, .8, .75)), Vector3(900, -.4, 0))
		var solid := AABB(Vector3(-15, -1.5, -4), Vector3(30, 3, 8))
		if not actual.bounds_known or actual.reason != "native_bridge": transformed_ok = false
		for corner in 8:
			if not actual.bounds.has_point(pose * solid.get_endpoint(corner)): transformed_ok = false
	check(transformed_ok, "full Euler and nonuniform scale include collision-only geometry beyond visual/proxy bounds")
	# Recomputed definition-derived bounds and prefab semantics reject forged hints.
	var forged := index.duplicate(true)
	forged.rows[2].bounds = AABB(Vector3(520, 2, 0), Vector3(.1, .1, .1)); forged.rows[2].chunk_min = Vector2i(16, 0); forged.rows[2].chunk_max = Vector2i(16, 0)
	forged.groups = Index._groups(forged.rows)
	check(not Prepare.prepare(forged, entries(forged, [2, 3]), source.path, files.content_root).error.is_empty(), "worker rejects an undersized forged gate footprint")
	var changed: Array = records.duplicate(true); changed[2].fortification.id = "other_ring"
	check(not Index.build(source.path, files.content_root, changed).ok, "unsaved owner changes cannot borrow authored rmres/source identity")
	changed = records.duplicate(true); changed[1].prefab_locked = false
	var unlocked := write_map("unlocked", changed)
	check(not Index.build(unlocked.path, files.content_root, changed).ok, "unlocked frozen records cannot produce trusted directory proofs")
	# Unknown behavior only falls back; known members sharing a fixture also stay eager.
	changed = records.duplicate(true); changed[3].future_geometry = {"effect": true}
	var unknown := write_map("unknown_leaf", changed)
	var unknown_index := Index.build(unknown.path, files.content_root, changed)
	check(unknown_index.ok and Index.select(unknown_index, []).record_indices == [2, 3], "unknown gate behavior forces its entire namespace global")
	changed = records.duplicate(true); changed[1].future_geometry = true
	unknown = write_map("unknown_wall", changed); unknown_index = Index.build(unknown.path, files.content_root, changed)
	check(unknown_index.ok and Index.select(unknown_index, []).record_indices == [1], "unknown nonactive module stays global without collecting the whole ring")
	changed = records.duplicate(true); changed[5].future_geometry = true
	unknown = write_map("unknown_bridge", changed); unknown_index = Index.build(unknown.path, files.content_root, changed)
	check(unknown_index.ok and Index.select(unknown_index, []).record_indices == [5], "unknown bridge behavior remains global")
	changed = records.duplicate(true); changed[1].prefab_tower_center = [512, 0]
	var tower := write_map("tower_center", changed); var tower_index := Index.build(tower.path, files.content_root, changed)
	check(tower_index.ok and tower_index.rows[1].reason == "native_fortification" and Index.select(tower_index, []).record_indices.is_empty(), "valid frozen tower authoring center adds no runtime geometry dependency")
	changed[1].prefab_tower_center = [512]
	var malformed := write_map("bad_tower_center", changed); var malformed_index := Index.build(malformed.path, files.content_root, changed)
	check(malformed_index.ok and Index.select(malformed_index, []).record_indices == [1], "unknown tower metadata shape stays global")
	var metadata := Fixture.metadata(records); metadata.editor_layout.fortifications[0].parts.pop_back()
	var bad_manifest := write_map("missing_manifest_leaf", records, metadata)
	var bad_index := Index.build(bad_manifest.path, files.content_root, records)
	check(bad_index.ok and Index.select(bad_index, []).record_indices == [0, 1, 2, 3], "incomplete owner manifest conservatively keeps that owner global")
	metadata = Fixture.metadata(records); metadata.editor_layout.fortifications[0].parts.append({"id": "missing_record", "signature": "0".repeat(64)})
	bad_manifest = write_map("missing_record", records, metadata); bad_index = Index.build(bad_manifest.path, files.content_root, records)
	check(bad_index.ok and Index.select(bad_index, []).record_indices == [0, 1, 2, 3], "manifest with an absent compact member cannot create partial closure")
	metadata = Fixture.metadata(records); metadata.editor_layout.fortifications = {"broken": true}
	bad_manifest = write_map("invalid_manifest", records, metadata); bad_index = Index.build(bad_manifest.path, files.content_root, records)
	check(bad_index.ok and Index.select(bad_index, []).record_indices == [0, 1, 2, 3, 4], "invalid manifest type keeps all fortification records global")
	# Envelope rehashing cannot bypass group/member/locked compact proofs.
	var cache: String = Index.cache_path(source.path, files.content_root)
	var original := FileAccess.get_file_as_bytes(cache)
	var payload: Dictionary = bytes_to_var(original.slice(49)); payload.groups[index.rows[2].group_id].members = [2]
	files.replace_payload(cache, payload)
	check(not Index.read(source.path, files.content_root).ok, "tampered group cannot drop a compact gate leaf")
	payload = bytes_to_var(original.slice(49)); payload.rows[2].group_id = index.rows[4].group_id; payload.groups = Index._groups(payload.rows)
	files.replace_payload(cache, payload)
	check(not Index.read(source.path, files.content_root).ok, "forged cross-owner namespace rejected even when groups recomputed")
	payload = bytes_to_var(original.slice(49)); payload.rows[2].prefab_locked = false
	files.replace_payload(cache, payload)
	check(not Index.read(source.path, files.content_root).ok, "forged unlock proof cannot keep owner spatial")
	files.write_bytes(cache, original)
	var source_bytes := FileAccess.get_file_as_bytes(source.path)
	files.write_bytes(source.path, source_bytes + " ".to_utf8_buffer())
	check(not Index.read(source.path, files.content_root).ok and not Prepare.prepare(index, requested, source.path, files.content_root).error.is_empty(), "full source SHA invalidates directory and worker even for whitespace changes")
	files.write_bytes(source.path, source_bytes)
	var reference: Dictionary = source.extras.rmmo_records[5].rmmo_ref
	var resource_path: String = files.folder.path_join(reference.uri)
	var resource_bytes := FileAccess.get_file_as_bytes(resource_path)
	files.write_bytes(resource_path, "broken resource".to_utf8_buffer())
	check(Index.read(source.path, files.content_root).ok and Prepare.prepare(index, entries(index, [0]), source.path, files.content_root).error.is_empty(), "bad undemanded bridge payload does not poison independent nearby wall")
	check(not Prepare.prepare(index, entries(index, [5]), source.path, files.content_root).error.is_empty(), "bad bridge payload fails when that closure is demanded")
	files.write_bytes(resource_path, resource_bytes)
	check(FileAccess.get_sha256(source.path) == sha, "tests leave authored source bytes unchanged")
	finish()

func finish() -> void:
	for path in files.created:
		if Paths.allowed(path, files.content_root) and FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for name_ in names: DirAccess.remove_absolute(files.folder.path_join(name_ + ".gltf.resources"))
	DirAccess.remove_absolute(files.folder); files.free()
	print("STRUCTURE_DEPENDENCY_INDEX passed=", passed, " failures=", failed)
	quit(0 if failed == 0 else 1)
