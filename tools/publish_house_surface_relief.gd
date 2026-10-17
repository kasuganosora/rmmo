extends SceneTree
## Explicit, review-bound publication of technical house material channels.
## Default/preflight and --check-baseline perform no filesystem writes.
## Usage and the selection/visual-decision schemas are printed by --help.

const Library = preload("res://scripts/world_editor/surface_material_library.gd")
const Surfaces = preload("res://scripts/world3d/surface_materials.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const REVIEW := "D:/code/rmmo_runtime/review_artifacts/house_surface_relief_20261014"
const CANDIDATES := "D:/code/rmmo_runtime/art_sources/house_surface_relief_20261014"
const MATERIALS := "D:/code/rmmo_runtime/packs/default/assets/materials"
const BASELINE := REVIEW + "/baseline_inventory.json"
const IDS := ["roofs/terracotta_plain", "roofs/terracotta_warm", "walls/earthen_plaster", "walls/troweled_plaster", "walls/exterior_limewash", "walls/lime_plaster", "walls/stone_tiles_facade", "walls/castle_rubble", "walls/natural_red_brick", "walls/outdoor_rough_stone"]
const CHANNELS := ["texture_path", "normal_path", "roughness_path", "metallic_path", "ao_path", "height_path"]
const WALL_CHANGES := ["normal_path", "roughness_path", "normal_format", "normal_strength", "roughness"]
const ROOF_CHANGES := ["normal_path", "normal_strength"]

var errors: Array[String] = []
var baseline: Dictionary = {}
var selection: Dictionary = {}
var visual: Dictionary = {}
var plans: Array[Dictionary] = []
var files: Dictionary = {}
var writes: Dictionary = {}
var options: Dictionary = {}
var receipt: Dictionary = {}
var self_test_root: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_parse_args()
	if options.has("help") and errors.is_empty():
		_help()
		quit(0)
		return
	if not errors.is_empty():
		_finish(2)
		return
	if options.has("self-test"):
		_self_test()
		return
	baseline = _json(BASELINE, "baseline inventory")
	_check_baseline()
	if options.has("check-baseline"):
		receipt = {"mode": "baseline_check", "formal_writes": false, "baseline_path": BASELINE, "baseline_sha256": _sha(BASELINE), "families_checked": baseline.get("items", []).size(), "scope": "Ten material definitions, original channels, rollback definitions and explicitly listed protected files; no whole-model or historical-map scan."}
		_finish(0 if errors.is_empty() else 2)
		return
	if errors.is_empty():
		_prepare_selection()
	if errors.is_empty():
		for item in selection.get("items", []):
			_prepare_item(item)
	if errors.is_empty():
		# A final whole preflight catches edits made while evidence was being read.
		_check_baseline()
		_require_sha(BASELINE, str(selection.baseline_inventory_sha256), "baseline at preflight completion")
	receipt = {"schema_version": 1, "date": "2026-10-14", "mode": "publish" if options.has("publish") else "preflight", "formal_writes": false, "selection_path": options.get("selection", ""), "selection_sha256": options.get("selection-sha256", ""), "baseline_path": BASELINE, "baseline_sha256": _sha(BASELINE), "visual_decision_path": selection.get("visual_decision_path", ""), "visual_decision_sha256": selection.get("visual_decision_sha256", ""), "items": [], "new_channel_files": [], "conservation_scope": "All 10 baseline definitions/original channel files and baseline protected_files. Other model/map files are excluded by the publication write whitelist; their contents were not traversed.", "protected_files_before": baseline.get("protected_files", {}).duplicate(true)}
	for plan in plans:
		receipt.items.append(_plan_receipt(plan))
	for path in files:
		receipt.new_channel_files.append(files[path].duplicate(true))
	if not errors.is_empty() or not options.has("publish"):
		_finish(0 if errors.is_empty() else 2)
		return
	_publish()
	_finish(0 if errors.is_empty() else 3)

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var key: String = args[index]
		if key in ["--help", "--publish", "--check-baseline", "--self-test"]:
			key = key.trim_prefix("--")
			if options.has(key): errors.append("Duplicate option: " + key)
			options[key] = true
		elif key in ["--selection", "--selection-sha256", "--receipt"]:
			key = key.trim_prefix("--")
			if options.has(key): errors.append("Duplicate option: " + key)
			index += 1
			if index >= args.size() or args[index].begins_with("--"):
				errors.append("Missing value for --" + key)
				break
			options[key] = args[index] if key == "selection-sha256" else _path(args[index])
		else:
			errors.append("Unknown option: " + key)
		index += 1
	if options.has("help"):
		if options.size() != 1: errors.append("--help cannot be combined with other options")
		return
	if options.has("check-baseline"):
		if options.size() != 1: errors.append("--check-baseline cannot be combined with publication options")
		return
	if options.has("self-test"):
		if options.size() != 1: errors.append("--self-test cannot be combined with publication options")
		return
	if not options.has("selection") or not _under(str(options.get("selection", "")), REVIEW):
		errors.append("--selection must name a JSON file under " + REVIEW)
	if not _valid_sha(str(options.get("selection-sha256", ""))):
		errors.append("--selection-sha256 requires the exact 64-character lowercase SHA256 of that file")
	if options.has("receipt") and not options.has("publish"):
		errors.append("Preflight is read-only: --receipt is available only with --publish")
	if options.has("publish"):
		var path: String = options.get("receipt", "")
		if not _under(path, REVIEW) or path.get_extension() != "json" or FileAccess.file_exists(path):
			errors.append("--publish requires a new --receipt JSON path under the review directory")

func _prepare_selection() -> void:
	var selection_path: String = options.selection
	_require_sha(selection_path, str(options["selection-sha256"]), "selection")
	selection = _json(selection_path, "selection")
	if selection.get("schema_version") != 1:
		errors.append("Selection schema_version must be 1")
	if _path(str(selection.get("baseline_inventory_path", ""))) != BASELINE:
		errors.append("Selection must bind the fixed baseline inventory")
	_require_sha(BASELINE, str(selection.get("baseline_inventory_sha256", "")), "selected baseline")
	var visual_path: String = _path(str(selection.get("visual_decision_path", "")))
	if not _under(visual_path, REVIEW):
		errors.append("Visual decision must be under the review directory")
		return
	_require_sha(visual_path, str(selection.get("visual_decision_sha256", "")), "root visual decision")
	visual = _json(visual_path, "root visual decision")
	if visual.get("status") != "passed" or not visual.get("decisions") is Array:
		errors.append("Root visual decision must have status=passed and a decisions array")
	var items: Variant = selection.get("items")
	if not items is Array or items.is_empty() or items.size() > IDS.size():
		errors.append("Selection needs a non-empty subset of the ten material families")
		return
	var seen := {}
	for item in items:
		if not item is Dictionary:
			errors.append("Selection item must be an object")
			continue
		var id: String = str(item.get("id", ""))
		if id not in IDS or seen.has(id): errors.append("Unknown or duplicate selected family: " + id)
		seen[id] = true
		for field in ["candidate_definition", "gpu_report", "recipe"]:
			var path: String = _path(str(item.get(field + "_path", "")))
			var expected: String = str(item.get(field + "_sha256", ""))
			var root: String = CANDIDATES if field == "candidate_definition" else REVIEW
			if field == "recipe": root = "D:/code/rmmo/tools"
			if not _under(path, root): errors.append(id + " " + field + " path is outside " + root)
			_require_sha(path, expected, id + " " + field)

func _check_baseline(allow_published: bool = false) -> void:
	var items: Variant = baseline.get("items")
	if not items is Array or items.size() != IDS.size():
		errors.append("Baseline must contain exactly the ten expected families")
		return
	var seen := {}
	for item in items:
		if not item is Dictionary:
			errors.append("Invalid baseline item")
			continue
		var id: String = str(item.get("id", ""))
		if id not in IDS or seen.has(id):
			errors.append("Invalid/duplicate baseline family: " + id)
			continue
		seen[id] = true
		var path: String = MATERIALS.path_join(id).path_join("material.json")
		if not Paths.allowed(path): errors.append("Definition path is invalid or passes through a link: " + path)
		if _path(str(item.get("definition_path", ""))) != path or item.get("material_id") != "pack:default:" + id + "/material":
			errors.append("Baseline definition identity/path mismatch: " + id)
		var expected: String = str(item.get("definition_sha256", ""))
		if allow_published:
			for plan in plans:
				if plan.id == id: expected = plan.after_sha256
		_require_sha(path, expected, "formal definition " + id)
		_require_sha(REVIEW.path_join("rollback_material_definitions").path_join(id).path_join("material.json"), str(item.get("definition_sha256", "")), "rollback definition " + id)
		if not item.get("definition") is Dictionary or not item.get("channels") is Dictionary:
			errors.append("Missing baseline definition/channels: " + id)
			continue
		var rollback: Dictionary = _json(REVIEW.path_join("rollback_material_definitions").path_join(id).path_join("material.json"), "rollback " + id)
		if rollback != item.definition: errors.append("Baseline definition body differs from rollback: " + id)
		for field in item.channels:
			var channel: Variant = item.channels[field]
			if field not in CHANNELS or not channel is Dictionary:
				errors.append("Invalid baseline channel " + id + " " + str(field))
				continue
			var channel_path: String = _path(str(channel.get("path", "")))
			if not _under(channel_path, MATERIALS): errors.append("Original channel outside material library: " + channel_path)
			_require_sha(channel_path, str(channel.get("sha256", "")), "original channel " + id + " " + str(field))
	var protected: Variant = baseline.get("protected_files")
	if not protected is Dictionary or protected.size() < 2:
		errors.append("Baseline protected_files is missing")
		return
	for path in protected:
		_require_sha(str(path), str(protected[path]), "protected file")

func _prepare_item(item: Dictionary) -> void:
	var id: String = item.id
	var original: Dictionary = {}
	for entry in baseline.items:
		if entry.id == id: original = entry
	if original.is_empty():
		errors.append("No baseline for " + id)
		return
	var candidate_path: String = _path(item.candidate_definition_path)
	var candidate: Dictionary = _json(candidate_path, id + " candidate")
	if not candidate.get("material") is Dictionary:
		errors.append("Candidate has no material: " + id)
		return
	var old_material: Dictionary = original.definition.material
	var material: Dictionary = candidate.material
	if not _normal_fields_explicit(material):
		errors.append(id + ": candidates must explicitly declare normal_format and normal_strength; implicit runtime defaults cannot differ from retained baseline values")
		return
	var allowed: Array = ROOF_CHANGES if id.begins_with("roofs/") else WALL_CHANGES
	# Candidate labels may describe a test variant; the formal label is preserved.
	var fields: Array = old_material.keys()
	for field in material:
		if field not in fields: fields.append(field)
	for field in fields:
		if field in CHANNELS or field == "name" or field in allowed: continue
		if old_material.get(field) != material.get(field): errors.append(id + ": forbidden material change " + str(field))
	var resolved: Dictionary = material.duplicate(true)
	var channels := {}
	for field in CHANNELS:
		var value: Variant = material.get(field, "")
		if not value is String:
			errors.append(id + ": channel path is not text " + field)
			continue
		if value.is_empty():
			if original.channels.has(field): errors.append(id + ": removal of an existing channel is forbidden " + field)
			continue
		var source: String = _resolve(candidate_path, value)
		if not _under(source, CANDIDATES) and not _under(source, MATERIALS):
			errors.append(id + ": channel is outside candidate/material roots " + source)
			continue
		var hash: String = _sha(source)
		var previous: Dictionary = original.channels.get(field, {})
		if not _valid_sha(hash): errors.append(id + ": unreadable channel " + field)
		if field not in allowed and (previous.is_empty() or previous.get("sha256") != hash):
			errors.append(id + ": changed/added forbidden channel " + field)
		var info: Dictionary = _image_info(source)
		info.merge({"source": source, "sha256": hash, "field": field, "changed": previous.is_empty() or previous.get("sha256") != hash})
		channels[field] = info
		resolved[field] = source
	if not Surfaces.material_valid(resolved): errors.append(id + ": candidate fails production material validation")
	if not channels.has("normal_path"): errors.append(id + ": relief candidate must contain a normal map")
	_validate_gpu(item, material, channels)
	_validate_visual(item)
	if not errors.is_empty(): return
	var result: Dictionary = original.definition.duplicate(true)
	var published_material: Dictionary = old_material.duplicate(true)
	var changes := []
	for field in allowed:
		if field in CHANNELS or not material.has(field): continue
		if material[field] != old_material.get(field): changes.append(field)
		published_material[field] = material[field]
	var source_maps := {}
	for field in channels:
		var channel: Dictionary = channels[field]
		var target: String = str(original.channels.get(field, {}).get("path", ""))
		if channel.changed:
			# Deduplicate only within this reviewed selection; old files are never replaced.
			for path in files:
				if files[path].after_sha256 == channel.sha256: target = path
			if target.is_empty() or not files.has(target):
				target = MATERIALS.path_join(id).path_join("relief_20261014").path_join(str(channel.sha256) + "." + str(channel.source).get_extension().to_lower())
			var before: String = _sha(target)
			if not Paths.allowed(target): errors.append("Versioned channel path is invalid or linked: " + target)
			if FileAccess.file_exists(target) and before != channel.sha256: errors.append("Versioned file conflict: " + target)
			if not files.has(target): files[target] = {"path": target, "source": channel.source, "before_sha256": before, "after_sha256": channel.sha256, "bytes": channel.encoded_bytes, "reused_existing": not before.is_empty()}
			published_material[field] = _relative_file(str(original.definition_path).get_base_dir(), target)
			changes.append(field)
		var metadata: Dictionary = channel.duplicate(true)
		metadata.erase("source")
		metadata.erase("changed")
		metadata.erase("field")
		metadata["file"] = published_material[field]
		source_maps[field] = metadata
	result.material = published_material
	var resolved_published: Dictionary = published_material.duplicate(true)
	for field in CHANNELS:
		if str(resolved_published.get(field, "")).is_empty(): continue
		resolved_published[field] = _resolve(str(original.definition_path), str(resolved_published[field]))
		if not _under(str(resolved_published[field]), MATERIALS): errors.append(id + ": published dependency would escape materials")
	if not Surfaces.material_valid(resolved_published): errors.append(id + ": published material fails production validation")
	result["base_source"] = original.definition.get("source", {}).duplicate(true)
	result["source"] = {"type": "project_technical_surface_relief", "date": "2026-10-14", "base_material_id": original.material_id, "base_definition_sha256": original.definition_sha256, "recipe": {"path": item.recipe_path, "sha256": item.recipe_sha256}, "candidate_definition": {"path": candidate_path, "sha256": item.candidate_definition_sha256}, "gpu_review": {"path": item.gpu_report_path, "sha256": item.gpu_report_sha256}, "visual_decision": {"path": selection.visual_decision_path, "sha256": selection.visual_decision_sha256}, "changed_material_fields": changes, "maps": source_maps, "note": "Technical-channel revision with original color bytes and UV scale preserved. Intentionally changed normal data; not a lossless-image claim. RGBA8 mip figures are budgets, not measured RSS/VRAM. Existing frozen maps are not migrated."}
	var bytes: PackedByteArray = (JSON.stringify(result, "\t", true) + "\n").to_utf8_buffer()
	plans.append({"id": id, "material_id": original.material_id, "definition_path": original.definition_path, "before_sha256": original.definition_sha256, "after_sha256": _buffer_sha(bytes), "bytes": bytes, "before_bytes": FileAccess.get_file_as_bytes(original.definition_path), "definition": result, "changed_fields": changes, "selection": item.duplicate(true), "channels": channels, "published": false})

func _validate_gpu(item: Dictionary, material: Dictionary, channels: Dictionary) -> void:
	var report: Dictionary = _json(item.gpu_report_path, item.id + " GPU report")
	if report.get("passed") != true or report.get("http") != true or report.get("id") != item.id:
		errors.append(item.id + ": GPU report must pass the real HTTP/native pipeline for this family")
	var reviewed: Variant = report.get("material")
	if not reviewed is Dictionary:
		errors.append(item.id + ": missing GPU material evidence")
		return
	if reviewed.get("definition_sha256") != item.candidate_definition_sha256 or _path(str(reviewed.get("definition_path", ""))) != _path(item.candidate_definition_path) or reviewed.get("definition") != material:
		errors.append(item.id + ": GPU review is not bound to this exact candidate definition")
	var reviewed_channels: Variant = reviewed.get("channels")
	if not reviewed_channels is Dictionary or reviewed_channels.size() != channels.size():
		errors.append(item.id + ": GPU channel set differs from candidate")
		return
	for field in channels:
		var evidence: Dictionary = reviewed_channels.get(field, {})
		var actual: Dictionary = channels[field]
		if evidence.get("source_sha256") != actual.sha256 or evidence.get("test_sha256") != actual.sha256:
			errors.append(item.id + ": reviewed source/native channel differs: " + field)
		if evidence.get("width") != actual.width or evidence.get("height") != actual.height:
			errors.append(item.id + ": reviewed dimensions differ: " + field)
		_require_sha(str(evidence.get("test_path", "")), actual.sha256, item.id + " imported channel " + field)
	var captures: Variant = report.get("captures")
	if not captures is Array or captures.size() < 3:
		errors.append(item.id + ": GPU evidence must include at least three review captures")
		return
	for capture in captures:
		if not capture is Dictionary:
			errors.append(item.id + ": malformed capture")
			continue
		var path: String = str(capture.get("path", ""))
		_require_sha(path, str(capture.get("sha256", "")), item.id + " WebP capture")
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var header: PackedByteArray = file.get_buffer(12)
		file.close()
		if path.get_extension().to_lower() != "webp" or header.size() != 12 or header.slice(0, 4).get_string_from_ascii() != "RIFF" or header.slice(8, 12).get_string_from_ascii() != "WEBP":
			errors.append(item.id + ": review capture is not actual WebP data")
		else:
			var image := Image.load_from_file(path)
			if image == null or image.is_empty() or image.get_width() != capture.get("width") or image.get_height() != capture.get("height"):
				errors.append(item.id + ": review WebP cannot decode to its reported dimensions")
	_require_sha(str(report.get("map_path", "")), str(report.get("map_sha256", "")), item.id + " saved GPU fixture map")

func _validate_visual(item: Dictionary) -> void:
	var matches := 0
	for decision in visual.get("decisions", []):
		if not decision is Dictionary or decision.get("id") != item.id: continue
		matches += 1
		if decision.get("status") != "passed" or decision.get("candidate_definition_sha256") != item.candidate_definition_sha256 or decision.get("gpu_report_sha256") != item.gpu_report_sha256 or str(decision.get("note", "")).strip_edges().is_empty():
			errors.append(item.id + ": missing matching human/root visual pass with a concrete note")
	if matches != 1: errors.append(item.id + ": exactly one matching visual decision is required")

func _publish() -> void:
	# No write-capable call occurs before every selected item passes preflight.
	_require_sha(BASELINE, selection.baseline_inventory_sha256, "baseline immediately before publication")
	if not errors.is_empty(): return
	for plan in plans: writes[plan.definition_path] = true
	for path in files: writes[path] = true
	writes[options.receipt] = true
	for path in files:
		var item: Dictionary = files[path]
		_require_sha(item.source, item.after_sha256, "candidate channel immediately before copy")
		if not errors.is_empty(): break
		if FileAccess.file_exists(path):
			_require_sha(path, item.after_sha256, "existing versioned channel")
		else:
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(item.source)
			if _buffer_sha(bytes) != item.after_sha256:
				errors.append("Candidate channel changed while read: " + str(item.source))
				break
			if _atomic_write(path, bytes) != OK: break
			receipt.formal_writes = true
		_require_sha(path, item.after_sha256, "published versioned channel")
	if errors.is_empty(): _check_baseline()
	for plan in plans:
		if not errors.is_empty(): break
		_require_sha(plan.definition_path, plan.before_sha256, "definition immediately before replace")
		_require_sha(options.selection, options["selection-sha256"], "selection immediately before replace")
		_require_sha(selection.visual_decision_path, selection.visual_decision_sha256, "visual decision immediately before replace")
		_require_sha(plan.selection.candidate_definition_path, plan.selection.candidate_definition_sha256, "candidate definition immediately before replace")
		_require_sha(plan.selection.gpu_report_path, plan.selection.gpu_report_sha256, "GPU evidence immediately before replace")
		_require_sha(plan.selection.recipe_path, plan.selection.recipe_sha256, "recipe immediately before replace")
		if not errors.is_empty(): break
		if _atomic_write(plan.definition_path, plan.bytes) != OK: break
		plan.published = true
		receipt.formal_writes = true
		_require_sha(plan.definition_path, plan.after_sha256, "published definition")
	if errors.is_empty(): _check_baseline(true)
	_finalize_transaction()

func _finalize_transaction() -> void:
	# Final conservation and durable receipt creation are part of the same
	# success decision as the material definitions, including failure rollback.
	_record_conservation()
	if not errors.is_empty():
		_rollback_definitions()
	_refresh_after_hashes()
	receipt["passed"] = errors.is_empty()
	receipt["errors"] = errors.duplicate()
	receipt["receipt_persisted"] = true
	var err: Error = _atomic_write(options.receipt, (JSON.stringify(receipt, "\t", true) + "\n").to_utf8_buffer())
	if err != OK:
		# A failed receipt cannot leave a successful-looking unpublished transaction.
		# The caller's stdout retains the recovery result even when storage is full.
		receipt["receipt_persisted"] = false
		_rollback_definitions()
		_refresh_after_hashes()
		receipt["passed"] = false
		receipt["errors"] = errors.duplicate()

func _rollback_definitions() -> void:
	# Never overwrite a newer edit. New immutable blobs may remain unreferenced;
	# no original channel or externally edited protected file is removed/restored.
	if not receipt.has("rollback"): receipt["rollback"] = []
	for plan in plans:
		if not plan.published: continue
		var current: String = _sha(plan.definition_path)
		var restored: bool = current == plan.before_sha256
		if current == plan.after_sha256:
			restored = _atomic_write(plan.definition_path, plan.before_bytes) == OK and _sha(plan.definition_path) == plan.before_sha256
		elif not restored:
			errors.append("Rollback refused to overwrite another editor's changed definition: " + str(plan.definition_path))
		if restored: plan.published = false
		receipt.rollback.append({"path": plan.definition_path, "restored": restored, "current_sha256": _sha(plan.definition_path)})

func _record_conservation() -> void:
	receipt["protected_files_after"] = {}
	for path in baseline.protected_files: receipt.protected_files_after[path] = _sha(path)
	receipt["protected_files_unchanged"] = receipt.protected_files_after == receipt.protected_files_before
	receipt["original_channel_files_unchanged"] = _original_channels_unchanged()
	receipt["original_channel_files"] = _original_channel_receipt()
	if not receipt.protected_files_unchanged: errors.append("A protected file changed during publication")
	if not receipt.original_channel_files_unchanged: errors.append("An original channel changed during publication")

func _refresh_after_hashes() -> void:
	for item in receipt.items: item["actual_after_sha256"] = _sha(item.definition_path)
	for item in receipt.new_channel_files: item["actual_after_sha256"] = _sha(item.path)

func _atomic_write(path: String, bytes: PackedByteArray) -> Error:
	if not writes.has(path):
		errors.append("Write refused outside exact publication whitelist: " + path)
		return ERR_UNAUTHORIZED
	var root: String = REVIEW if path == options.receipt else MATERIALS
	if not self_test_root.is_empty(): root = self_test_root
	if not Paths.allowed(path, root):
		errors.append("Write path is invalid or has a linked ancestor: " + path)
		return ERR_UNAUTHORIZED
	if files.has(path) and FileAccess.file_exists(path):
		if _sha(path) == _buffer_sha(bytes): return OK
		errors.append("Refusing to overwrite an existing versioned image: " + path)
		return ERR_ALREADY_EXISTS
	if path == options.receipt and FileAccess.file_exists(path):
		errors.append("Refusing to overwrite an existing receipt: " + path)
		return ERR_ALREADY_EXISTS
	var err: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err == OK: err = Library._write(path, bytes)
	if err != OK: errors.append("Atomic write failed: " + path + ": " + error_string(err))
	return err

func _original_channels_unchanged() -> bool:
	for item in baseline.items:
		for field in item.channels:
			if _sha(item.channels[field].path) != item.channels[field].sha256: return false
	return true

func _original_channel_receipt() -> Array:
	var result := []
	var seen := {}
	for item in baseline.items:
		for field in item.channels:
			var channel: Dictionary = item.channels[field]
			if seen.has(channel.path): continue
			seen[channel.path] = true
			result.append({"path": channel.path, "before_sha256": channel.sha256, "after_sha256": _sha(channel.path)})
	return result

func _normal_fields_explicit(material: Dictionary) -> bool:
	return material.has("normal_format") and material.has("normal_strength")

func _self_test() -> void:
	# Fault injection is confined to new review fixtures, never formal paths.
	self_test_root = REVIEW.path_join("publisher_self_test_" + str(Time.get_ticks_usec()))
	var production_guard := {}
	var inventory: Dictionary = _json(BASELINE, "self-test read-only baseline guard")
	for item in inventory.get("items", []):
		production_guard[item.definition_path] = _sha(item.definition_path)
		for field in item.channels:
			var path: String = item.channels[field].path
			production_guard[path] = _sha(path)
	for path in inventory.get("protected_files", {}): production_guard[path] = _sha(path)
	var results := []
	results.append({"case": "normal_defaults_explicit", "passed": not _normal_fields_explicit({"normal_format": "opengl"}) and not _normal_fields_explicit({"normal_strength": 1.0}) and _normal_fields_explicit({"normal_format": "opengl", "normal_strength": 1.0})})
	for case in ["success", "receipt_write_failure", "late_protected_conflict", "late_original_channel_conflict", "receipt_failure_preserves_newer_edit"]:
		errors.clear()
		plans.clear()
		files.clear()
		writes.clear()
		var directory: String = self_test_root.path_join(case)
		var definition_path: String = directory.path_join("material.json")
		var protected_path: String = directory.path_join("protected.bin")
		var original_path: String = directory.path_join("original.bin")
		var before: PackedByteArray = "{\"version\":\"before\"}\n".to_utf8_buffer()
		var after: PackedByteArray = "{\"version\":\"reviewed\"}\n".to_utf8_buffer()
		var newer: PackedByteArray = "{\"version\":\"another-editor\"}\n".to_utf8_buffer()
		_fixture_write(definition_path, after)
		_fixture_write(protected_path, "protected".to_utf8_buffer())
		_fixture_write(original_path, "original-channel".to_utf8_buffer())
		baseline = {"items": [{"channels": {"normal_path": {"path": original_path, "sha256": _sha(original_path)}}}], "protected_files": {protected_path: _sha(protected_path)}}
		var report_path: String = directory.path_join("receipt.json")
		if case in ["receipt_write_failure", "receipt_failure_preserves_newer_edit"]:
			var blocker: String = directory.path_join("not_a_directory")
			_fixture_write(blocker, "fixture blocker".to_utf8_buffer())
			report_path = blocker.path_join("receipt.json")
		if case == "late_protected_conflict": _fixture_write(protected_path, "external protected edit".to_utf8_buffer())
		if case == "late_original_channel_conflict": _fixture_write(original_path, "external channel edit".to_utf8_buffer())
		if case == "receipt_failure_preserves_newer_edit": _fixture_write(definition_path, newer)
		options = {"receipt": report_path}
		writes[definition_path] = true
		writes[report_path] = true
		plans.append({"id": "fixture", "definition_path": definition_path, "before_sha256": _buffer_sha(before), "after_sha256": _buffer_sha(after), "before_bytes": before, "published": true})
		receipt = {"formal_writes": false, "fixture_writes": true, "items": [{"definition_path": definition_path, "before_sha256": _buffer_sha(before), "planned_after_sha256": _buffer_sha(after)}], "new_channel_files": [], "protected_files_before": baseline.protected_files.duplicate(true)}
		_finalize_transaction()
		var expected: String = _buffer_sha(after if case == "success" else (newer if case == "receipt_failure_preserves_newer_edit" else before))
		var passed: bool = _sha(definition_path) == expected
		if case == "success": passed = passed and errors.is_empty() and FileAccess.file_exists(report_path) and _json(report_path, "fixture success receipt").get("passed") == true
		else: passed = passed and not errors.is_empty() and receipt.get("passed") == false
		if case in ["receipt_write_failure", "receipt_failure_preserves_newer_edit"]: passed = passed and not FileAccess.file_exists(report_path) and receipt.get("receipt_persisted") == false
		if case in ["late_protected_conflict", "late_original_channel_conflict"]: passed = passed and FileAccess.file_exists(report_path) and _json(report_path, "fixture failure receipt").get("passed") == false
		results.append({"case": case, "passed": passed, "expected_definition_sha256": expected, "actual_definition_sha256": _sha(definition_path), "receipt": receipt.duplicate(true)})
	errors.clear()
	var guard_ok := true
	for path in production_guard:
		if _sha(path) != production_guard[path]: guard_ok = false
	results.append({"case": "formal_resources_untouched", "passed": guard_ok, "files_checked": production_guard.size()})
	var passed := true
	for result in results:
		if not result.passed: passed = false
	var report := {"schema_version": 1, "passed": passed, "formal_writes": false, "fixture_root": self_test_root, "tool_path": ProjectSettings.globalize_path(get_script().resource_path), "tool_sha256": _sha(ProjectSettings.globalize_path(get_script().resource_path)), "tests": results}
	var report_path: String = self_test_root.path_join("report.json")
	_fixture_write(report_path, (JSON.stringify(report, "\t", true) + "\n").to_utf8_buffer())
	print(JSON.stringify({"passed": passed and errors.is_empty(), "formal_writes": false, "report_path": report_path, "report_sha256": _sha(report_path), "errors": errors}))
	quit(0 if passed and errors.is_empty() else 4)

func _fixture_write(path: String, bytes: PackedByteArray) -> void:
	if self_test_root.is_empty() or not _under(path, self_test_root) or not Paths.allowed(path, self_test_root):
		errors.append("Fixture setup refused a path outside its isolated root")
		return
	var err: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err == OK: err = Library._write(path, bytes)
	if err != OK: errors.append("Fixture setup write failed: " + path)

func _plan_receipt(plan: Dictionary) -> Dictionary:
	return {"id": plan.id, "material_id": plan.material_id, "definition_path": plan.definition_path, "before_sha256": plan.before_sha256, "planned_after_sha256": plan.after_sha256, "changed_material_fields": plan.changed_fields, "formal_material": plan.definition.material, "evidence": plan.selection}

func _image_info(path: String) -> Dictionary:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		errors.append("Channel image cannot decode: " + path)
		return {"width": 0, "height": 0, "encoded_bytes": 0}
	var file := FileAccess.open(path, FileAccess.READ)
	var size: int = file.get_length() if file != null else 0
	if file != null: file.close()
	var width := image.get_width()
	var height := image.get_height()
	var mip_width := width
	var mip_height := height
	var mip_budget := 0
	while true:
		mip_budget += mip_width * mip_height * 4
		if mip_width == 1 and mip_height == 1: break
		mip_width = maxi(1, mip_width / 2)
		mip_height = maxi(1, mip_height / 2)
	return {"width": width, "height": height, "encoded_bytes": size, "decoded_format": image.get_format(), "decoded_bytes": image.get_data().size(), "rgba8_base_budget_bytes": width * height * 4, "rgba8_full_mips_budget_bytes": mip_budget}

func _json(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append(label + " does not exist: " + path)
		return {}
	var parser := JSON.new()
	var err := parser.parse(FileAccess.get_file_as_string(path))
	if err != OK or not parser.data is Dictionary:
		errors.append(label + " is not a valid JSON object: " + path)
		return {}
	return parser.data

func _require_sha(path: String, expected: String, label: String) -> void:
	if not _valid_sha(expected) or _sha(path) != expected:
		errors.append(label + " SHA conflict or missing file: " + path)

func _sha(path: String) -> String:
	return FileAccess.get_sha256(path) if not path.is_empty() and FileAccess.file_exists(path) else ""

func _buffer_sha(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func _valid_sha(value: String) -> bool:
	return value.length() == 64 and value.to_lower() == value and value.is_valid_hex_number(false)

func _path(path: String) -> String:
	return path.replace("\\", "/").simplify_path() if not path.is_empty() else ""

func _under(path: String, root: String) -> bool:
	return path.is_absolute_path() and _path(path).to_lower().begins_with((_path(root) + "/").to_lower())

func _resolve(definition: String, channel: String) -> String:
	return _path(channel if channel.is_absolute_path() else definition.get_base_dir().path_join(channel))

func _relative_file(directory: String, target: String) -> String:
	var left := _path(directory).split("/", false)
	var right := _path(target).split("/", false)
	var common := 0
	while common < mini(left.size(), right.size()) and left[common].to_lower() == right[common].to_lower(): common += 1
	var parts := PackedStringArray()
	for index in range(common, left.size()): parts.append("..")
	for index in range(common, right.size()): parts.append(right[index])
	return "/".join(parts)

func _finish(code: int) -> void:
	receipt["passed"] = code == 0
	receipt["errors"] = errors
	print(JSON.stringify(receipt))
	quit(code)

func _help() -> void:
	print("Read-only: --selection <absolute JSON> --selection-sha256 <SHA256>")
	print("Publish: add --publish --receipt <new absolute review JSON path>")
	print("Baseline-only, read-only: --check-baseline")
	print("Isolated failure-path fixtures only (no formal writes): --self-test")
	print(JSON.stringify({"schema_version": 1, "baseline_inventory_path": BASELINE, "baseline_inventory_sha256": "<sha256>", "visual_decision_path": REVIEW + "/visual_decision.json", "visual_decision_sha256": "<sha256>", "items": [{"id": "roofs/terracotta_plain", "candidate_definition_path": CANDIDATES + "/roof/balanced/terracotta_plain/material.json", "candidate_definition_sha256": "<sha256>", "gpu_report_path": REVIEW + "/gallery/candidate/balanced/roofs/terracotta_plain/report.json", "gpu_report_sha256": "<sha256>", "recipe_path": "D:/code/rmmo/tools/build_house_roof_relief.py", "recipe_sha256": "<sha256>"}]}, "  "))
	print("Root visual decision schema:")
	print(JSON.stringify({"status": "passed", "decisions": [{"id": "roofs/terracotta_plain", "status": "passed", "candidate_definition_sha256": "<sha256>", "gpu_report_sha256": "<sha256>", "note": "Concrete visual acceptance observations for this exact candidate."}]}, "  "))
