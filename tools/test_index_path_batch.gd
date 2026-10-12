extends SceneTree
## CPU-only path-authority parity. Uses tiny generated models and native maps.
## No real map, model, permission setting, or production cache is modified.
const Index = preload("res://scripts/world3d/map_dependency_index.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Cursor = preload("res://scripts/world3d/document_open_cursor.gd")
const Files = preload("res://tools/test_map_dependency_index.gd")
const ModelFixture = preload("res://tools/test_asset_bounds_manifest.gd")
const REPEATED = 48
var passed := 0
var failures := 0
var skipped := 0
var files: SceneTree
var model_fixture: SceneTree
var original_mode := true
var source: Dictionary = {}
var cache := ""
var cache_bytes := PackedByteArray()
var author_bytes := PackedByteArray()
var model_path := ""
var unknown_path := ""
var unknown_bytes := "unsupported model fixture".to_utf8_buffer()

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS: " if value else "FAIL: ", label)
	if value: passed += 1
	else: failures += 1

func read_mode(enabled: bool) -> Dictionary:
	Index.batch_path_validation = enabled
	return Index.read(source.path, files.content_root)

func source_asset(id: String, x: float, path: String) -> Dictionary:
	var record: Dictionary = files.box(id, x)
	record.kind = "asset"; record.asset_path = path; record.size = [1, 1, 1]
	return record

func assert_rejected(payload: Dictionary, label: String) -> void:
	files.replace_payload(cache, payload)
	for enabled: bool in [false, true]:
		var result := read_mode(enabled)
		check(not result.ok and result.get("reason") == "invalid_index_schema", "%s rejects with batch=%s" % [label, enabled])
	files.write_bytes(cache, cache_bytes)

func test_modes(records: Array) -> void:
	var ordinary := read_mode(false)
	var batched := read_mode(true)
	check(ordinary.ok and batched.ok, "both path modes read the same valid repeated-model directory")
	if not ordinary.ok or not batched.ok: return
	check(ordinary == batched, "complete directory contents and author metadata match between modes")
	check(batched.models.size() == 1 and batched.rows.size() == REPEATED + 1, "many records share one model identity; final global path is absent from models")
	var repeats := 0
	for row: Dictionary in batched.rows:
		if row.asset_path == model_path and row.classification == "spatial": repeats += 1
	check(repeats == REPEATED and batched.rows[-1].asset_path == unknown_path and batched.rows[-1].classification == "global" and not batched.models.has(unknown_path), "fixture exercises both seeded and first-seen global paths")
	var demands: Array = [[], [AABB(Vector3(0, -10, -8), Vector3(34, 30, 16))], [AABB(Vector3(0, -10, -8), Vector3(34, 30, 16)), AABB(Vector3(630, -10, -8), Vector3(50, 30, 16))]]
	for clips: Array in demands:
		var old_selection := Index.select(ordinary, clips)
		var new_selection := Index.select(batched, clips)
		check(old_selection == new_selection, "selected/deferred order, globals, bounds and closure match for %d demand regions" % clips.size())
		var old_records := Cursor.hydrate_references(old_selection.extras, source.path, files.content_root)
		var new_records := Cursor.hydrate_references(new_selection.extras, source.path, files.content_root)
		check(old_records.ok and new_records.ok and old_records.extras == new_records.extras and old_records.dependencies == new_records.dependencies, "both modes hydrate identical records with real resource checks for %d regions" % clips.size())
	for enabled: bool in [false, true]:
		Index.batch_path_validation = enabled
		var loading := Index.read_for_loading(source.path, files.content_root)
		check(loading.ok and loading.index.rows == ordinary.rows and Index.validate_index_ownership(loading.index, files.content_root, loading.proof, source.path), "batch=%s retains genuine sealed loading proof" % enabled)
	check(records.size() == REPEATED + 1 and FileAccess.get_file_as_bytes(source.path) == author_bytes, "reading and sealing leave authored records and map bytes intact")

func test_invalid_paths() -> void:
	var original: Dictionary = bytes_to_var(cache_bytes.slice(49))
	# String.chr(0) is normalized to U+FFFD by this engine before it can reach
	# the validator. Do not substitute another character and call it a NUL test.
	skipped += 1
	print("SKIP: embedded NUL is not representable by this Godot String fixture; production NUL defense remains unchanged")
	var invalids: Array = [
		{"label": "external sibling", "path": files.content_root.get_base_dir().path_join("outside_index_batch/model.glb")},
		{"label": "adjacent root prefix", "path": files.content_root.trim_suffix("/") + "_adjacent/model.glb"},
		{"label": "relative path", "path": "model.glb"}
	]
	for item: Dictionary in invalids:
		var payload := original.duplicate(true)
		payload.rows[-1].asset_path = item.path
		assert_rejected(payload, "late global non-model " + item.label)
		payload = original.duplicate(true)
		var model: Dictionary = payload.models[model_path]
		payload.models.erase(model_path); payload.models[item.path] = model
		assert_rejected(payload, "model dictionary " + item.label)
	var malformed := original.duplicate(true)
	malformed.rows[-1].asset_path = 7
	assert_rejected(malformed, "late global non-string path")
	malformed = original.duplicate(true)
	malformed.rows[REPEATED - 1].asset_path = invalids[0].path
	malformed.rows[REPEATED - 1].classification = "global"
	assert_rejected(malformed, "late previously repeated row changes to a new external path")
	for enabled: bool in [false, true]:
		check(read_mode(enabled).ok, "valid restored directory reads again after tamper probes with batch=%s" % enabled)

func test_model_replacement() -> void:
	var original_bytes := FileAccess.get_file_as_bytes(model_path)
	var changed: Dictionary = model_fixture.data()
	changed.nodes[0].translation[0] = -400
	model_fixture.write(model_path, changed)
	var old_result := read_mode(false)
	var new_result := read_mode(true)
	check(old_result.ok and new_result.ok and old_result == new_result, "same-path model replacement remains observable on the next read in both modes")
	if old_result.ok and new_result.ok:
		var conservative := 0
		for row: Dictionary in new_result.rows:
			if row.asset_path == model_path and row.classification == "global" and row.reason == "model_bounds_changed" and not row.bounds_known: conservative += 1
		check(conservative == REPEATED, "every repeated source instance is downgraded when actual GLB bounds change")
		check(Index.select(old_result, []).record_indices == Index.select(new_result, []).record_indices and Index.select(new_result, []).record_indices.size() == REPEATED + 1, "changed model cannot remain hidden in an undemanded chunk")
	files.write_bytes(model_path, original_bytes)
	for enabled: bool in [false, true]:
		var restored := read_mode(enabled)
		check(restored.ok and restored.rows[0].classification == "spatial", "restored source is reconsidered independently with batch=%s" % enabled)

func test_optional_link() -> void:
	# The path was accepted as an ordinary global asset above. Replace only this
	# exact test-owned file with a symlink; do not enable privileges/developer mode.
	check(Paths.allowed(unknown_path, files.content_root) and FileAccess.get_file_as_bytes(unknown_path) == unknown_bytes, "optional link fixture starts from the owned ordinary file")
	DirAccess.remove_absolute(unknown_path)
	var directory := DirAccess.open(files.folder)
	var error: int = directory.create_link(model_path, unknown_path)
	if error != OK:
		skipped += 1
		print("SKIP: DirAccess.create_link unavailable under current account/platform: ", error_string(error))
		files.write_bytes(unknown_path, unknown_bytes)
		check(read_mode(true).ok, "unsupported link attempt restores the valid ordinary fixture")
		return
	check(directory.is_link(unknown_path.get_file()), "DirAccess created only the requested test-owned file link")
	for enabled: bool in [false, true]:
		var result := read_mode(enabled)
		check(not result.ok and result.get("reason") == "invalid_index_schema", "subsequent read rejects a former valid path now replaced by a link with batch=%s" % enabled)
	# Unlink the exact leaf, never recurse or follow it when cleaning up.
	var removed := DirAccess.remove_absolute(unknown_path)
	check(removed == OK and FileAccess.file_exists(model_path), "unlink removes the test link and preserves its target")
	if removed == OK: files.write_bytes(unknown_path, unknown_bytes)
	check(read_mode(true).ok, "restored ordinary leaf is validated afresh after the link probe")

func finish() -> void:
	Index.batch_path_validation = original_mode
	if not source.is_empty():
		check(FileAccess.get_file_as_bytes(source.path) == author_bytes and FileAccess.get_file_as_bytes(cache) == cache_bytes, "all probes preserve the original test map and restore its index exactly")
	if files != null and not files.folder.is_empty():
		for path: String in files.created:
			if Paths.allowed(path, files.content_root) and FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(files.folder.path_join("batch.gltf.resources"))
		DirAccess.remove_absolute(files.folder)
	if files != null: files.free()
	if model_fixture != null: model_fixture.free()
	print("INDEX_PATH_BATCH passed=", passed, " failures=", failures, " skipped=", skipped)
	quit(0 if failures == 0 else 1)

func run() -> void:
	if DisplayServer.get_name() != "headless": quit(2); return
	original_mode = Index.batch_path_validation
	files = Files.new(); model_fixture = ModelFixture.new()
	files.content_root = Paths.external_root()
	files.folder = Paths.cache_directory("index_path_batch_test_%d" % Time.get_ticks_usec())
	if files.folder.is_empty() or DirAccess.make_dir_recursive_absolute(files.folder) != OK:
		check(false, "create owned temporary fixture directory"); finish(); return
	model_path = files.folder.path_join("model.glb")
	unknown_path = files.folder.path_join("global_unknown.glb")
	files.created.append(model_path); files.created.append(unknown_path)
	model_fixture.write(model_path, model_fixture.data())
	files.write_bytes(unknown_path, unknown_bytes)
	var records: Array = []
	for i in REPEATED: records.append(source_asset("repeat_%d" % i, i * 40.0, model_path))
	records.append(source_asset("last_global", 2000, unknown_path))
	source = files.fixture("batch", records)
	if source.is_empty(): check(false, "create native reference fixture"); finish(); return
	var built := Index.build(source.path, files.content_root, records)
	check(built.ok, "build small real dependency index from authored reference records")
	if not built.ok: print(built); source.clear(); finish(); return
	cache = Index.cache_path(source.path, files.content_root)
	cache_bytes = FileAccess.get_file_as_bytes(cache)
	author_bytes = FileAccess.get_file_as_bytes(source.path)
	test_modes(records)
	test_invalid_paths()
	test_model_replacement()
	test_optional_link()
	finish()
