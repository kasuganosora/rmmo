extends SceneTree
## Small CPU-only proof fixtures. Never builds a real map directory or uses GPU.
const Index = preload("res://scripts/world3d/map_dependency_index.gd")
const Proof = preload("res://scripts/world3d/dependency_index_proof.gd")
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

class ReplaceBeforeFinal extends RefCounted:
	var path := ""
	var bytes := PackedByteArray()
	var calls := 0
	func is_cancelled() -> bool:
		calls += 1
		if calls == 5: FileAccess.open(path, FileAccess.WRITE).store_buffer(bytes)
		return false

var files: SceneTree
var passed := 0
var failed := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS: " if value else "FAIL: ", label)
	if value: passed += 1
	else: failed += 1
func entries(index: Dictionary, wanted: Array) -> Array:
	var result: Array = []
	for entry: Dictionary in Index.select(index, []).deferred_entries:
		if entry.record_index in wanted: result.append(entry)
	return result
func sealed(value: Variant) -> bool:
	if value is Dictionary:
		if not value.is_read_only(): return false
		for child in value.values():
			if not sealed(child): return false
	elif value is Array:
		if not value.is_read_only(): return false
		for child in value:
			if not sealed(child): return false
	return true

func run() -> void:
	files = Files.new(); files.content_root = Paths.external_root()
	files.folder = Paths.cache_directory("dependency_proof_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var records := Fixture.records(files.content_root)
	var source: Dictionary = files.fixture("proof", records, Fixture.metadata(records))
	var built := Index.build(source.path, files.content_root, records)
	var ordinary := Index.read(source.path, files.content_root)
	var loading := Index.read_for_loading(source.path, files.content_root)
	check(built.ok and ordinary.ok and loading.ok and loading.proof is Proof, "only verified disk load issues typed ownership proof")
	if not loading.ok: print(loading); finish(); return
	var index: Dictionary = loading.index; var proof: Proof = loading.proof
	check(not ordinary.is_read_only() and not ordinary.rows.is_read_only(), "ordinary read keeps its original mutable API")
	check(sealed(index) and sealed(proof.rows_by_uuid()), "complete directory and cached UUID lookup are recursively readonly")
	check(is_same(proof.rows_by_uuid()[records[2].uuid], index.rows[2]), "cached UUID lookup points at exact sealed rows")
	check(Index.validate_index_ownership(index, files.content_root, proof, source.path), "issued proof accepts only its exact complete directory")
	check(not Index.validate_index_ownership(index.duplicate(), files.content_root, proof, source.path), "shallow dictionary copy cannot borrow proof")
	check(not Index.validate_index_ownership(index.duplicate(true), files.content_root, proof, source.path), "deep dictionary copy cannot borrow proof")
	check(not Index.validate_index_ownership(index, files.folder, proof, source.path), "proof rejects a different content root")
	check(not Index.validate_index_ownership(index, files.content_root, proof, source.path + ".other"), "proof rejects a different map path")
	check(not Index.validate_index_ownership(index, files.content_root, Proof.new(), source.path), "default constructed proof is invalid")
	var fake: Proof = Proof.issue(ordinary.duplicate(true), source.path, files.content_root, RefCounted.new())
	check(fake != null and not Index.validate_index_ownership(index, files.content_root, fake, source.path), "caller-created issuer cannot certify an otherwise valid dictionary")
	var changed := ordinary.duplicate(true)
	changed.groups[changed.rows[2].group_id].members = [2]
	changed.closure_complete = true; changed.selected_closure_verified = true; changed.validated = true
	check(not Index.validate_index_ownership(changed, files.content_root), "mutable input still revalidates full ownership regardless of forged boolean flags")
	changed = index.duplicate(true); changed.source_sha256 = "0".repeat(64)
	check(not Index.validate_index_ownership(changed, files.content_root, proof, source.path), "outer source SHA replacement cannot borrow an old proof")
	var deserialized: Dictionary = bytes_to_var(var_to_bytes(index))
	check(not Index.validate_index_ownership(deserialized, files.content_root, proof, source.path), "serialized directory never carries process-local proof identity")
	var selected := Index.select(index, [AABB(Vector3(519, -10, -1), Vector3(4, 20, 2))])
	check(is_same(selected.compact_records[0], index.extras.rmmo_records[2]) and selected.compact_records[0].is_read_only(), "selected header shares readonly compact descriptors")
	check(not is_same(selected.extras.editor_layout, index.extras.editor_layout) and not selected.extras.editor_layout.is_read_only(), "runtime author metadata is a separate deeply mutable copy")
	selected.extras.editor_layout.fortifications[0].parts[0].id = "runtime_only"
	selected.extras.spawn[0] = -100
	check(index.extras.editor_layout.fortifications[0].parts[0].id == "near_wall" and index.extras.spawn[0] == 0, "nested runtime metadata mutation cannot alter sealed author state")
	selected = Index.select(index, [AABB(Vector3(519, -10, -1), Vector3(4, 20, 2))])
	var hydrated := Cursor.hydrate_references(selected.extras, source.path, files.content_root)
	var validated := Index.validate_selected(index, hydrated.extras.rmmo_records, files.content_root, proof)
	check(hydrated.ok and validated.ok and validated.ownership_proof_used, "selected validation uses cached proof while preserving local business checks")
	check(not Index.validate_selected(index, [hydrated.extras.rmmo_records[0]], files.content_root, proof).ok, "sealed proof never permits incomplete gate namespace")
	hydrated.extras.rmmo_records[0].fixture.open = .5
	hydrated.extras.rmmo_records[0].position[0] = -100
	check(index.extras.rmmo_records[2].rmmo_state.fixture.open == 0 and index.extras.rmmo_records[2].position[0] == 520, "hydration creates independent mutable pose and fixture state")
	check(not Index.validate_selected(index, hydrated.extras.rmmo_records, files.content_root, proof).ok, "sealed proof still rejects changed selected pose or state")
	var normal_result := Prepare.prepare(ordinary, entries(ordinary, [5]), source.path, files.content_root)
	check(normal_result.error.is_empty() and not normal_result.read_profile.ownership_proof_used, "mutable preparation keeps complete validation fallback")
	var logger := WorkerErrors.new(); OS.add_logger(logger)
	var gate_worker := Thread.new(); var bridge_worker := Thread.new()
	var gate_started := gate_worker.start(Prepare.prepare.bind(index, entries(index, [2, 3]), source.path, files.content_root, null, proof))
	var bridge_started := bridge_worker.start(Prepare.prepare.bind(index, entries(index, [5]), source.path, files.content_root, null, proof))
	var gate: Dictionary = gate_worker.wait_to_finish() if gate_started == OK else {"error": "thread failed"}
	var bridge: Dictionary = bridge_worker.wait_to_finish() if bridge_started == OK else {"error": "thread failed"}
	OS.remove_logger(logger)
	check(gate.error.is_empty() and bridge.error.is_empty() and gate.records.size() == 2 and bridge.records.size() == 1, "parallel workers share one immutable proof and prepare complete independent groups")
	check(logger.errors.is_empty(), "parallel proof preparations emit zero engine or script errors")
	for error in logger.errors: print("PROOF_WORKER_ENGINE_ERROR ", error)
	check(gate.read_profile.ownership_proof_used and bridge.read_profile.ownership_proof_used, "both worker jobs report actual typed proof use")
	check(bridge.read_profile.has("preflight_ownership_us") and bridge.read_profile.has("selected_ownership_us") and bridge.read_profile.has("selected_uuid_lookup_us") and bridge.read_profile.elapsed_us >= bridge.read_profile.preflight_us, "profile now includes previously omitted source/ownership preflight")
	check(not Prepare.prepare(index, entries(index, [2]), source.path, files.content_root, null, proof).error.is_empty(), "proof path still rejects a missing fixture leaf before resource IO")
	check(not Prepare.prepare(index.duplicate(), entries(index, [5]), source.path, files.content_root, null, proof).error.is_empty(), "worker refuses mismatched proof rather than silently trusting a copied dictionary")
	# Snapshot proof does not certify bytes still on disk: both final checks stay.
	var source_bytes := FileAccess.get_file_as_bytes(source.path)
	files.write_bytes(source.path, source_bytes + " ".to_utf8_buffer())
	check(not Prepare.prepare(index, entries(index, [5]), source.path, files.content_root, null, proof).error.is_empty(), "sealed proof does not bypass initial full source SHA")
	files.write_bytes(source.path, source_bytes)
	var replace := ReplaceBeforeFinal.new(); replace.path = source.path; replace.bytes = source_bytes + " ".to_utf8_buffer()
	check(not Prepare.prepare(index, entries(index, [5]), source.path, files.content_root, replace, proof).error.is_empty() and replace.calls >= 5, "sealed proof does not bypass final source SHA after mid-job replacement")
	files.write_bytes(source.path, source_bytes)
	var reference: Dictionary = index.extras.rmmo_records[5].rmmo_ref
	var resource_path: String = files.folder.path_join(reference.uri)
	var resource_bytes := FileAccess.get_file_as_bytes(resource_path)
	replace = ReplaceBeforeFinal.new(); replace.path = resource_path; replace.bytes = "broken rmres".to_utf8_buffer()
	check(not Prepare.prepare(index, entries(index, [5]), source.path, files.content_root, replace, proof).error.is_empty() and replace.calls >= 5, "sealed proof retains final demanded rmres SHA verification")
	files.write_bytes(resource_path, resource_bytes)
	var forged := ordinary.duplicate(true)
	forged.rows[5].bounds = AABB(Vector3(900, 0, 0), Vector3(.1, .1, .1)); forged.groups = Index._groups(forged.rows)
	check(not Prepare.prepare(forged, entries(forged, [5]), source.path, files.content_root).error.is_empty(), "mutable fallback still recomputes true structure bounds")
	var alias: Array = [{"value": 1}]; var aliases := {"a": alias, "b": alias}
	check(Proof._seal(aliases, 0, [], [100]) and is_same(aliases.a, aliases.b) and sealed(aliases), "recursive seal covers aliases and every nested dictionary")
	var cycle: Array = []; cycle.append(cycle)
	check(not Proof._seal(cycle, 0, [], [100]), "cycle is rejected before publication")
	cycle.clear()
	check(not Proof._seal({"object": RefCounted.new()}, 0, [], [100]) and not Proof._seal(PackedByteArray([1]), 0, [], [100]), "mutable or executable Variant types outside directory contract are rejected")
	check(not Proof._seal([1, 2, 3], 0, [], [2]), "freeze has a bounded traversal budget")
	check(FileAccess.get_sha256(source.path) == index.source_sha256 and Index.validate_index_ownership(index, files.content_root, proof, source.path), "parallel jobs and mutation probes leave original proof and author snapshot intact")
	finish()

func finish() -> void:
	for path in files.created:
		if Paths.allowed(path, files.content_root) and FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(files.folder.path_join("proof.gltf.resources"))
	DirAccess.remove_absolute(files.folder); files.free()
	print("DEPENDENCY_INDEX_PROOF passed=", passed, " failures=", failed)
	quit(0 if failed == 0 else 1)
