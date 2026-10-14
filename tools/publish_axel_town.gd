extends SceneTree
## Explicit publication helper; never invoked by the terrain builder or runtime review.
## Uses native reference-map saving and refuses any existing formal map.
const Doc = preload("res://scripts/world3d/world_document.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Catalog = preload("res://scripts/world_editor/resource_pack_catalog.gd")
const CANDIDATE := "D:/code/rmmo_runtime/cache/world3d/axel_town_terrain_20261014/map.gltf"
const FORMAL := "D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const PACK_ROOT := "D:/code/rmmo_runtime/packs/default"
const REPORT := "D:/code/rmmo_runtime/review_artifacts/axel_town_terrain_20261014/publication.json"
const MAP_NAME := "阿克塞尔新城镇 · 地形"
const MAP_REF := "default/axel_town"
var failures := 0
var report := {"candidate_path":CANDIDATE, "formal_path":FORMAL, "published":false,
	"startup_configuration_changed":false, "checks":[]}


func _initialize() -> void:
	call_deferred("run")


func canonical(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path().to_lower()


func check(passed: bool, label: String, details: Dictionary = {}) -> bool:
	report.checks.append({"name":label, "passed":passed, "details":details})
	if not passed: failures += 1
	print("PASS " if passed else "FAIL ", label)
	return passed


func finish() -> void:
	report.failures = failures
	report.status = "passed" if failures == 0 else "failed"
	if FileAccess.file_exists(FORMAL): report.formal_sha256 = FileAccess.get_sha256(FORMAL)
	if Paths.allowed(REPORT) and DirAccess.make_dir_recursive_absolute(REPORT.get_base_dir()) == OK:
		var file := FileAccess.open(REPORT, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))
			file.flush()
			if file.get_error() != OK: failures += 1
			file.close()
		else:
			failures += 1
			push_error("Unable to write publication report")
	else:
		failures += 1
		push_error("Unable to create publication report directory")
	print("AXEL_TOWN_PUBLICATION ", REPORT, " failures=", failures)
	quit(1 if failures else 0)


func json_identity(value: Variant) -> String:
	# Native reopen normalizes numeric JSON types; compare all values after the
	# same JSON normalization, with sorted keys and full floating-point precision.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func vector_matches(value: Variant, wanted: Vector3) -> bool:
	return value is Array and value.size() == 3 and Vector3(float(value[0]), float(value[1]), float(value[2])).distance_to(wanted) < .0001


func audit(document, label: String) -> void:
	var meta: Dictionary = document.map_meta
	check(meta.get("name") == MAP_NAME, label + " map name")
	check(meta.get("map_ref") == MAP_REF, label + " stable map identity")
	check(vector_matches(meta.get("spawn"), Vector3(156, 8.4, 209)), label + " formal spawn center")
	check(vector_matches(meta.get("editor_view", {}).get("spawn"), Vector3(156, 7.5, 209)), label + " editor spawn feet")
	var terrains: Array = document.records.filter(func(record): return record.has("terrain_mesh"))
	var water: Array = document.records.filter(func(record): return record.get("surface_id") == "water")
	var rivers: Array = meta.get("terrain_rivers", [])
	var river_ids: Array = rivers.map(func(river): return str(river.get("id", "")))
	river_ids.sort()
	check(terrains.size() == 63, label + " 63 editable terrain records", {"count":terrains.size()})
	check(rivers.size() == 2 and river_ids == ["axel_main_river", "axel_s12_stream"], label + " main river and separate shallow stream", {"ids":river_ids})
	check(not water.is_empty() and terrains.size() + water.size() == document.records.size(), label + " terrain and water only")
	report[label + "_counts"] = {"records":document.records.size(), "terrains":terrains.size(), "water_records":water.size(), "river_definitions":rivers.size()}


func run() -> void:
	if not check(Paths.allowed(CANDIDATE) and Paths.allowed(FORMAL), "publication paths stay in external content root"):
		finish()
		return
	if not check(not FileAccess.file_exists(FORMAL) and not DirAccess.dir_exists_absolute(FORMAL), "formal target does not exist; overwrite forbidden"):
		finish()
		return
	if not check(FileAccess.file_exists(CANDIDATE), "candidate map exists"):
		finish()
		return
	report.candidate_sha256 = FileAccess.get_sha256(CANDIDATE)
	var catalog = Catalog.new()
	var packs: Array[Dictionary] = catalog.packs()
	var defaults: Array[Dictionary] = packs.filter(func(pack): return pack.id == "default" and canonical(pack.root) == canonical(PACK_ROOT))
	if not check(defaults.size() == 1 and bool(defaults[0].shared), "expected shared default resource pack exists"):
		finish()
		return
	var document = Doc.open_file(CANDIDATE)
	if not check(document != null, "candidate opens through native document reader"):
		finish()
		return
	audit(document, "candidate")
	check(FileAccess.get_sha256(CANDIDATE) == report.candidate_sha256, "candidate remained unchanged during open")
	if failures > 0:
		finish()
		return
	var source_records := json_identity(document.records)
	var source_metadata := json_identity(document.map_meta)
	report.content_sha256 = {"records":source_records.sha256_text(), "metadata":source_metadata.sha256_text()}
	if not check(not FileAccess.file_exists(FORMAL), "formal target still absent before save"):
		finish()
		return
	# Pin the expected target signature to absence. The native writer checks this
	# under its save lock, so a competing creator cannot be silently overwritten.
	document.accept_save(FORMAL, "")
	var error: Error = document.save(FORMAL)
	report.save_error = error_string(error)
	report.save_mode = document.last_save_metrics.get("export", {}).get("mode", "")
	if not check(error == OK, "native atomic publication", {"error":error_string(error)}):
		finish()
		return
	report.published = true
	report.formal_sha256 = FileAccess.get_sha256(FORMAL)
	var reopened = Doc.open_file(FORMAL)
	if not check(reopened != null, "formal map reopens through native reader"):
		finish()
		return
	audit(reopened, "formal")
	check(json_identity(reopened.records) == source_records, "all reopened records match candidate content")
	check(json_identity(reopened.map_meta) == source_metadata, "all reopened metadata matches candidate content")
	check(FileAccess.get_sha256(CANDIDATE) == report.candidate_sha256, "candidate source remains unchanged")
	check(FileAccess.get_sha256(FORMAL) == report.formal_sha256, "formal map remains unchanged during reopen")
	var maps: Array[Dictionary] = catalog.available_maps(defaults[0], packs)
	var matches: Array[Dictionary] = maps.filter(func(row): return canonical(row.path) == canonical(FORMAL))
	check(matches.size() == 1, "default pack catalog lists formal map exactly once")
	if matches.size() == 1:
		var row: Dictionary = matches[0]
		report.catalog_entry = {"name":row.name, "path":row.path, "pack_id":row.pack.id,
			"pack_name":row.pack.name, "pack_root":row.pack.root, "shared":row.pack.shared,
			"authored_name":reopened.map_meta.name, "map_ref":reopened.map_meta.map_ref}
		check(row.name == "axel_town" and row.pack.id == "default", "catalog name and ownership correct")
		print("AXEL_TOWN_CATALOG ", JSON.stringify(report.catalog_entry))
	finish()
