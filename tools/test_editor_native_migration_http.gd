extends "res://tools/test_world3d_mcp.gd"
## Real-editor integration for already published native products. Private desktop only.
## --verification=<publication_verification.json> --output=<fresh review_artifacts dir>
## --entry-plan=<editor_entry_plan.json> --offset=0 --limit=8 --engine-sha=<externally verified SHA>
## No authoring-source reads, import_file, source copies or formal catalog writes.
const NativeLibrary = preload("res://scripts/world_editor/asset_library.gd")

class ReviewEditor extends "res://scripts/world_editor/world_editor.gd":
	var review_entry_id := ""
	var review_thumbnail_path := ""
	# Limit the palette to the current real catalog entry so unrelated missing
	# thumbnails cannot create work or writes. Only the output filename changes;
	# discovery, placement, loading and editing still use production operations.
	func asset_items(query: String = "", category: String = "") -> Array:
		var selected: Array = []
		for entry: Dictionary in super.asset_items(query, category):
			if str(entry.get("prefab_path", entry.get("asset_path", ""))) != review_entry_id: continue
			var scoped := entry.duplicate(true)
			scoped.thumbnail_path = review_thumbnail_path
			selected.append(scoped)
		return selected

var output_dir := ""
var verification_path := ""
var checks: Array = []
var results: Array = []
var current: Dictionary = {}
var selected_models: Array = []
var selected_entries: Array = []
var source_identity: Dictionary = {}
var formal_catalog_path := ""
var formal_catalog_sha := ""
var blank_map := ""
var finalizing := false
var identity: Dictionary = {}
var started_ms := 0

func argument(name_: String, fallback: String = "") -> String:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with("--" + name_ + "="): return value.substr(name_.length() + 3)
	return fallback

func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write integration evidence: " + path)
		failed += 1
		return
	file.store_string(JSON.stringify(value, "\t")); file.close()

func check(ok: bool, label: String) -> void:
	var item := {"ok": ok, "check": label, "model_id": current.get("model_id", "batch"), "elapsed_ms": Time.get_ticks_msec() - started_ms}
	checks.append(item)
	if not current.is_empty(): current.checks.append(item)
	super.check(ok, str(item.model_id) + ": " + label)
	if not output_dir.is_empty():
		write_json(output_dir.path_join("progress.json"), {"current": current, "completed": results.size(), "failed": failed, "latest": item})

func idle() -> bool:
	var end := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < end:
		await process_frame
		if is_instance_valid(editor) and not editor.saving() and (editor._load_job == null or not editor._load_job.active):
			await settle()
			return not editor._load_failed
	return false

func native_identity(node: Node, model: Dictionary, label: String) -> void:
	var matches: Array = []
	var meshes := 0
	if is_instance_valid(node):
		var nodes: Array = [node]
		nodes.append_array(node.find_children("*", "", true, false))
		for child: Node in nodes:
			if child is MeshInstance3D and child.mesh != null: meshes += 1
			var owner_: Variant = child.get_meta("_compiled_resource_owner") if child.has_meta("_compiled_resource_owner") else null
			if not owner_ is PackedScene: continue
			var actual := {"node": str(child.name), "validated": owner_.get_meta("compiled_asset_validated", false), "source_sha": owner_.get_meta("_rmmo_source_digest", ""), "payload_sha": owner_.get_meta("_rmmo_native_payload_sha", "")}
			if actual.source_sha == source_identity.get(str(model.path), ""): matches.append(actual)
	var expected_source: String = str(source_identity.get(str(model.path), ""))
	var valid := not matches.is_empty() and meshes > 0
	for actual: Dictionary in matches:
		valid = valid and actual.validated and actual.source_sha == expected_source and actual.payload_sha == model.product_sha
	if is_instance_valid(node): valid = valid and not node.get_meta("missing_asset", false) and str(node.get_meta("paint_error", "")).is_empty()
	current.native_observations.append({"phase": label, "target_model": str(model.path), "mesh_instances_in_scope": meshes, "owners": matches})
	check(valid, label + " owns the SHA-bound native target " + str(model.path).get_file())

func picking_identity(id: String, label: String) -> void:
	var bodies: Array = editor._bodies_by_uuid.get(id, [])
	var valid := not bodies.is_empty()
	var picking := 0
	for value: Variant in bodies:
		var body := value as StaticBody3D
		if not is_instance_valid(body): valid = false; continue
		var visual: Variant = body.get_meta("visual") if body.has_meta("visual") else null
		if not is_instance_valid(visual) or not body.global_transform.is_equal_approx(visual.global_transform): valid = false
		if body.collision_layer & 1: picking += 1
	current.picking_observations.append({"phase": label, "bodies": bodies.size(), "picking_bodies": picking})
	check(valid and picking > 0, label + " keeps real picking bodies attached to moved visuals")

func metadata_unchanged(model: Dictionary, label: String) -> void:
	var mismatches: Array = []
	for path: String in model.metadata_sha:
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != model.metadata_sha[path]: mismatches.append(path)
	check(mismatches.is_empty(), label + " metadata matches publication verification (small JSON only)")
	if not mismatches.is_empty(): current.metadata_mismatches = mismatches

func drain_background(label: String) -> void:
	var deadline := Time.get_ticks_msec() + 120000
	var state: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var retirement := root.get_node_or_null("ResourceRetirement")
		var drainer := root.get_node_or_null("AssetWorkerDrainer")
		state = {"retirement_pending": retirement.pending.size() if retirement != null else 0, "drainer_jobs": drainer.jobs.size() if drainer != null else 0}
		if state.retirement_pending == 0 and state.drainer_jobs == 0: break
	if not current.is_empty(): current.background_after_unload = state
	check(state.get("retirement_pending", -1) == 0 and state.get("drainer_jobs", -1) == 0, label + " completes owned background retirement")

func review_thumbnail(entry: Dictionary) -> void:
	var key: String = str(entry.get("prefab_path", entry.get("asset_path", "")))
	var queued := await call_tool("repair_asset_thumbnails", {"asset_ids": [key]})
	check(queued.get("queued", 0) == 1, "HTTP thumbnail repair queues exactly the current model")
	var deadline := Time.get_ticks_msec() + 120000
	var state: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		await process_frame
		state = editor._thumbnails.state(entry)
		if state.get("status") in ["ready", "failed"]: break
	current.thumbnail = state
	var expected: String = editor.review_thumbnail_path
	var ready: bool = state.get("status") == "ready" and str(state.get("path", "")) == expected and FileAccess.file_exists(expected)
	check(ready, "actual thumbnail renderer writes only the temporary output")
	if ready:
		var image_ := Image.load_from_file(expected)
		check(image_ != null and not image_.is_empty() and image_.get_width() > 0 and image_.get_height() > 0, "thumbnail file decodes after real render")
		current.thumbnail.sha256 = FileAccess.get_sha256(expected)

func review_model(entry_plan: Dictionary) -> void:
	var mark := Time.get_ticks_msec()
	var failures_before := failed
	var entry_id: String = entry_plan.entry_id
	current = {"model_id": entry_id.get_file().get_basename(), "entry_id": entry_id, "entry_kind": entry_plan.kind, "targets": entry_plan.targets, "verification_sha256": identity.verification_sha256, "status": "running", "checks": [], "native_observations": [], "picking_observations": [], "pending": ["source/native visual comparison unless separately approved", "type-specific wind, transparency, LOD and moving-component review", "formal map deployment"]}
	persist_models(false)
	var candidates_valid := true
	for model: Dictionary in entry_plan.targets:
		metadata_unchanged(model, "before editor operations")
		var candidate: Dictionary = NativeLibrary.native_candidate(str(model.path))
		var valid: bool = not candidate.is_empty() and str(candidate.get("product", "")).replace("\\", "/") == str(model.product).replace("\\", "/") and candidate.get("payload_sha", "") == model.product_sha and candidate.get("source_sha", "") == source_identity.get(str(model.path), "")
		candidates_valid = candidates_valid and valid
		check(valid, "published target candidate binds actual product/source SHA: " + str(model.path).get_file())
	for input: String in entry_plan.inputs_sha256:
		check(FileAccess.get_sha256(input) == entry_plan.inputs_sha256[input], "actual prefab input matches entry plan")
	editor.review_entry_id = entry_id
	editor.review_thumbnail_path = output_dir.path_join("thumbnails").path_join(entry_id.sha256_text() + ".png")
	editor._query = ""; editor._asset_category = ""; editor._refresh_palette()
	var catalog := await call_tool("list_assets", {"limit": 100})
	var catalog_rows: Array = catalog.get("assets", [])
	check(catalog_rows.size() == 1 and catalog_rows[0].get("asset_id", "") == entry_id, "HTTP discovers the existing real asset/prefab library entry")
	var entries: Array = editor.asset_items()
	if not candidates_valid or entries.size() != 1:
		check(false, "cannot continue model without exact catalog/native candidate")
		await finish_model(entry_plan, mark, failures_before)
		return
	var entry: Dictionary = entries[0]
	var placed := await call_tool("place_asset", {"asset_id": entry_id, "position": [0, 0, 0]})
	var ids: Array = placed.get("ids", [])
	check(not ids.is_empty() and ids.size() == int(entry_plan.record_count) and editor._doc.records.size() == ids.size(), "HTTP places the actual entry with its original member count")
	if ids.is_empty():
		await finish_model(entry_plan, mark, failures_before)
		return
	current.object_ids = ids
	await settle()
	for model: Dictionary in entry_plan.targets: native_identity(editor._view, model, "placed")
	for id: String in ids:
		if editor._doc._find(id).get("kind") == "asset": picking_identity(id, "placed")
	var selected := await call_tool("select_objects", {"ids": ids})
	check(selected.get("selection", []) == ids, "HTTP selection targets the actual entry members")
	var initial_records: Array = editor._doc.records.duplicate(true)
	for id: String in ids: await call_tool("get_object", {"id": id})
	var history: int = editor._doc._undo.size()
	var delta := Vector3(1.25, 0.5, -1.75)
	await call_tool("transform_selection", {"translation": [delta.x, delta.y, delta.z]})
	var moved_records: Array = editor._doc.records.duplicate(true)
	var transform_valid := moved_records.size() == initial_records.size()
	for record: Dictionary in initial_records:
		var moved_record: Dictionary = editor._doc._find(str(record.uuid))
		var expected := Vector3(record.position[0], record.position[1], record.position[2]) + delta
		transform_valid = transform_valid and equivalent(moved_record.get("position", []), [expected.x, expected.y, expected.z]) and equivalent(moved_record.get("rotation", []), record.rotation) and equivalent(moved_record.get("size", []), record.size) and moved_record.get("asset_path", "") == record.get("asset_path", "")
	check(transform_valid, "real entry transform preserves every member's actual resource key and relative structure")
	check(editor._doc._undo.size() == history + 1, "transform creates one undo transaction")
	for id: String in ids:
		if editor._doc._find(id).get("kind") == "asset": picking_identity(id, "transformed")
	await call_tool("undo")
	check(equivalent(editor._doc.records, initial_records), "undo restores complete original entry records")
	await call_tool("redo")
	check(equivalent(editor._doc.records, moved_records), "redo restores complete edited entry records")
	var before_invalid: Array = editor._doc.records.duplicate(true)
	var invalid_history: int = editor._doc._undo.size()
	await call_tool("set_object_transform", {"id": ids[0], "size": [0, 1, 1]}, false)
	check(equivalent(before_invalid, editor._doc.records) and editor._doc._undo.size() == invalid_history, "invalid HTTP transform has no document/history side effects")
	var model_map := output_dir.path_join("maps").path_join(entry_id.sha256_text() + "/map.gltf")
	await call_tool("save_world", {"path": model_map})
	var saved: Array = editor._doc.records.duplicate(true)
	await call_tool("open_world", {"path": model_map})
	check(await idle(), "actual editor map load completes")
	check(equivalent(saved, editor._doc.records), "save/reopen preserves all records and instance identity")
	for model: Dictionary in entry_plan.targets: native_identity(editor._view, model, "reopened")
	for id: String in ids:
		if editor._doc._find(id).get("kind") == "asset": picking_identity(id, "reopened")
	current.load_state = editor._load_job.state()
	await call_tool("select_objects", {"ids": ids})
	await call_tool("focus_selection")
	# Execute the real palette handler; do not instantiate a separate static scene.
	editor._on_palette_selected(0)
	await settle()
	check(editor._preview.current_path == entry_id and is_instance_valid(editor._preview.scene), "real palette preview opens the actual asset/prefab entry")
	for model: Dictionary in entry_plan.targets: native_identity(editor._preview.scene, model, "palette preview")
	await RenderingServer.frame_post_draw
	var preview_image: Image = editor._preview.viewport_.get_texture().get_image()
	check(preview_image != null and not preview_image.is_empty(), "real preview viewport produces an image (not visual approval)")
	await review_thumbnail(entry)
	await finish_model(entry_plan, mark, failures_before)

func persist_models(complete: bool) -> void:
	for model: Dictionary in current.get("targets", []):
		var row := current.duplicate(true)
		row.erase("targets")
		row.model_id = str(model.path).get_file().get_basename()
		row.asset_path = model.path
		row.source_sha256_from_snapshot = source_identity.get(str(model.path), "")
		row.native_product = model.product
		row.actual_native_sha256_from_verification = model.product_sha
		row.shared_entry_evidence = true
		write_json(output_dir.path_join(str(row.model_id) + ".json"), row)
		if complete: results.append(row)

func finish_model(entry_plan: Dictionary, mark: int, failures_before: int) -> void:
	# Exercise production open/unload, then retire only the no-longer-displayed cache
	# ownership. Never substitute freeing a static test scene for editor lifecycle.
	editor._preview.show_asset("")
	editor.review_entry_id = ""; editor._refresh_palette()
	await call_tool("open_world", {"path": blank_map, "discard_changes": true})
	check(await idle(), "actual editor opens the empty map after review")
	var removed: bool = editor._doc.records.is_empty() and editor._bodies_by_uuid.is_empty()
	for old_id: String in current.get("object_ids", []): removed = removed and editor._view.get_node_or_null(NodePath(old_id)) == null
	check(removed, "editor unload removes previous document, instances and picking registration")
	current.cache_evicted_after_unload = {}
	for model: Dictionary in entry_plan.targets: current.cache_evicted_after_unload[model.path] = NativeLibrary.evict_cached_scene(str(model.path))
	await drain_background("editor unload")
	for model: Dictionary in entry_plan.targets: metadata_unchanged(model, "after editor operations")
	for input: String in entry_plan.inputs_sha256:
		check(FileAccess.get_sha256(input) == entry_plan.inputs_sha256[input], "actual prefab input bytes remain unchanged")
	check(FileAccess.get_sha256(formal_catalog_path) == formal_catalog_sha, "formal library bytes remain unchanged")
	current.elapsed_ms = Time.get_ticks_msec() - mark
	current.failed_checks = failed - failures_before
	current.status = "passed_editor_operations" if current.failed_checks == 0 else "failed_editor_operations"
	persist_models(true); current = {}

func finish(timed_out: bool = false) -> void:
	if finalizing: return
	finalizing = true
	if timed_out: check(false, "batch watchdog timeout; unfinished models remain pending")
	if not current.is_empty():
		current.status = "interrupted"
		persist_models(false)
	if is_instance_valid(editor):
		if editor._mcp != null: editor._mcp.stop()
		editor.queue_free()
		await settle()
	check(not is_instance_valid(editor), "real editor Node lifecycle exits")
	await drain_background("editor exit")
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc = null; session.world3d_editor_path = ""
	if not output_dir.is_empty():
		write_json(output_dir.path_join("report.json"), {"scope": "temporary-map actual editor integration only; no visual/type-specific/formal-map approval", "identity": identity, "fixture": {"catalog_filter": "one actual shared-library entry at a time", "thumbnail_output_redirected": true, "formal_catalog": formal_catalog_path, "formal_catalog_sha256": formal_catalog_sha, "content_root_override": false, "test_explicit_authoring_source_reads": false, "consumer_io_trace": "not measured; native owner identity checked"}, "expected": selected_models.size(), "completed": results.size(), "failed_checks": failed, "checks": checks, "models": results, "ok": not timed_out and failed == 0 and results.size() == selected_models.size()})
	print("EDITOR_NATIVE_MIGRATION_HTTP_FAILED=", failed)
	quit(1 if failed else 0)

func run() -> void:
	started_ms = Time.get_ticks_msec()
	Engine.max_fps = 60; root.size = Vector2i(1100, 800); rpc_timeout_ms = 240000
	verification_path = argument("verification")
	var requested_output := argument("output").replace("\\", "/").simplify_path()
	var review_root := Paths.external_root().replace("\\", "/").path_join("review_artifacts")
	if DisplayServer.get_name() == "headless" or verification_path.is_empty() or not Paths.allowed(verification_path) or not requested_output.to_lower().begins_with(review_root.to_lower() + "/") or not Paths.allowed(requested_output) or FileAccess.file_exists(requested_output.path_join("progress.json")) or FileAccess.file_exists(requested_output.path_join("report.json")):
		check(false, "graphical private desktop, existing verification and fresh external review output required"); quit(1); return
	output_dir = requested_output
	DirAccess.make_dir_recursive_absolute(output_dir.path_join("thumbnails"))
	var verification := read_json(verification_path)
	var snapshot_path := verification_path.get_base_dir().path_join("before/snapshot.json")
	var snapshot := read_json(snapshot_path)
	var entry_plan_path := argument("entry-plan", verification_path.get_base_dir().path_join("editor_entry_plan.json"))
	var entry_plan := read_json(entry_plan_path) if Paths.allowed(entry_plan_path) else {}
	var all_models: Array = verification.get("models", []).filter(func(row): return row.get("action") == "build")
	var all_entries: Array = entry_plan.get("entries", [])
	var offset := int(argument("offset", "0")); var limit := int(argument("limit", "8"))
	if not verification.get("ok", false) or not verification.get("source_unchanged", false) or not verification.get("inputs_unchanged", false) or all_models.is_empty() or offset < 0 or offset >= all_entries.size() or limit < 1 or limit > 8 or snapshot.is_empty() or entry_plan.get("publication_verification_sha256", "") != FileAccess.get_sha256(verification_path):
		check(false, "verified publication, source snapshot and nonempty batch of at most 8 required"); await finish(); return
	selected_entries = all_entries.slice(offset, mini(offset + limit, all_entries.size()))
	for item: Dictionary in selected_entries:
		for model: Dictionary in item.targets:
			var admitted: Array = all_models.filter(func(row): return row.path == model.path)
			if admitted.size() != 1 or not equivalent(admitted[0], model):
				check(false, "entry-plan target must exactly match actual publication verification"); await finish(); return
			selected_models.append(model)
	for row: Dictionary in snapshot.get("models", []): source_identity[str(row.path)] = str(row.get("source_sha", ""))
	identity = {"verification": verification_path, "verification_sha256": FileAccess.get_sha256(verification_path), "source_snapshot": snapshot_path, "source_snapshot_sha256": FileAccess.get_sha256(snapshot_path), "entry_plan": entry_plan_path, "entry_plan_sha256": FileAccess.get_sha256(entry_plan_path), "engine": OS.get_executable_path(), "engine_version": Engine.get_version_info(), "engine_sha256_supplied_by_runner": argument("engine-sha"), "engine_sha_requires_external_runner_verification": true, "test_sha256": FileAccess.get_sha256("res://tools/test_editor_native_migration_http.gd"), "base_http_test_sha256": FileAccess.get_sha256("res://tools/test_world3d_mcp.gd"), "offset": offset, "limit_entries": limit, "selected_entry_count": selected_entries.size(), "publication_build_count": all_models.size()}
	formal_catalog_path = Paths.external_root().path_join("packs/default/assets/library.json")
	formal_catalog_sha = FileAccess.get_sha256(formal_catalog_path)
	check(not formal_catalog_sha.is_empty() and formal_catalog_sha == entry_plan.get("library_sha256", "") and formal_catalog_path == entry_plan.get("library_path", ""), "read SHA-bound existing default catalog without changing content root")
	blank_map = output_dir.path_join("maps/empty/map.gltf")
	var doc := Doc.new()
	check(doc.save(blank_map) == OK, "create empty isolated temporary map")
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = blank_map; session.world3d_editor_doc = null
	editor = ReviewEditor.new(); editor._mcp_autostart = false; editor._draft_directory = output_dir.path_join("drafts")
	root.add_child(editor)
	check(await idle(), "production editor initializes the temporary map")
	var probe := TCPServer.new()
	while probe.listen(port, "127.0.0.1") != OK: port += 1
	probe.stop(); check(editor.start_mcp(port).get("ok", false), "start production loopback HTTP MCP")
	var initialized := await rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "native-migration-integration", "version": "1"}})
	check(initialized.has("result"), "real HTTP initialize")
	var discovered := await rpc("tools/list")
	var tool_names: Array = discovered.get("result", {}).get("tools", []).map(func(row): return row.name)
	for name_: String in ["list_assets", "place_asset", "select_objects", "get_object", "set_object_transform", "transform_selection", "undo", "redo", "save_world", "open_world", "repair_asset_thumbnails"]:
		check(tool_names.has(name_), "3D MCP discovers " + name_)
	await call_tool("configure_autosave", {"enabled": false})
	await call_tool("configure_transform", {"gravity_placement": false})
	create_timer(1800).timeout.connect(func(): finish(true))
	for item: Dictionary in selected_entries:
		if finalizing: return
		await review_model(item)
	await finish()
