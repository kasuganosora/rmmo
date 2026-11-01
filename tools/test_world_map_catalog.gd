extends SceneTree
const Catalog = preload("res://scripts/world_editor/world_map_catalog.gd")
var failures: Array[String] = []
var checks := 0
var fixture := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture = "D:/code/rmmo_runtime/review_artifacts/world_address_d1_20261101/catalog_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_write_json(fixture.path_join("packs/demo/metadata.json"), {"id":"demo","name":"示例包","version":"1"})
	var map_a := fixture.path_join("packs/demo/maps/city/map.gltf")
	var map_b := fixture.path_join("packs/demo/maps/field/map.gltf")
	var map_named := fixture.path_join("packs/demo/maps/Map000007.gltf")
	_write_map(map_a, "legacy/city")
	_write_map(map_b, "demo/field")
	_write_map(map_named, "demo/named")
	var original_sha := FileAccess.get_sha256(map_a)
	var service := Catalog.new(fixture)
	var confined := Catalog.ConfinedDiscovery.new(fixture)
	_check(confined._read_metadata("D:/code/rmmo_runtime/packs/default") == null, "pack metadata outside fixture rejected before discovery")
	var initial: Dictionary = service.list_maps("demo")
	_check(initial.ok and initial.maps.size() == 3, "discover legacy and numeric files")
	var a := _row(initial, map_a)
	var b := _row(initial, map_b)
	var named := _row(initial, map_named)
	var doc: Dictionary = initial.documents[0]
	_check(a.map_number == "" and a.map_ref == "legacy/city", "legacy author identity retained without assignment")
	_check(named.suggested_number == "7" and named.map_number == "", "numeric filename only suggests canonical identity")
	_check(not FileAccess.file_exists(doc.path) and not doc.dirty, "read-only discovery creates no catalogue")
	_expect_reason(service.resolve_address("demo:12:1,2,3"), "map_unregistered", "unregistered resolve fails")
	_expect_reason(service.format_map_address(map_a, [1.0, 2.0, 3.0]), "map_unregistered", "unregistered copy fails")
	_expect_reason(service.register_map(named.entry_id, "8", 0), "filename_number_conflict", "filename number mismatch")
	_expect_reason(service.register_map("fabricated", "1", 0), "unknown_map_entry", "opaque entry lookup cannot invent path")
	var registered: Dictionary = service.register_map(a.entry_id, "00012", 0)
	_check(registered.ok and registered.document.edit_revision == 1 and registered.document.dirty, "register increments own document revision")
	_check(service.cached_documents()[0].undo_count == 1, "catalog history separate from map history")
	var draft: Dictionary = service.resolve_address("demo:12:-0.01,5,100")
	_check(draft.ok and draft.map_ref == "legacy/city" and draft.position_m[0] == -0.01 and not draft.persisted and not draft.can_transfer, "draft resolves double coordinates without granting entry")
	var before_failure: Array = service.cached_documents()
	_expect_reason(service.register_map(b.entry_id, "12", 1), "map_number_conflict", "duplicate number rejected")
	_expect_reason(service.register_map(b.entry_id, "13", 0), "candidate_stale", "stale edit revision rejected")
	_expect_reason(service.register_map(a.entry_id, "13", 1), "map_already_registered", "ordinary registration cannot renumber")
	_check(before_failure == service.cached_documents(), "failed mutations leave document and history unchanged")
	var saved: Dictionary = service.save_catalog(doc.document_id, 1, "")
	_check(saved.ok and not saved.document.dirty and saved.disk_sha.length() == 64, "first catalogue atomic save")
	_check(FileAccess.get_sha256(map_a) == original_sha, "registration/save leave map bytes untouched")
	var reopened := Catalog.new(fixture)
	var restored: Dictionary = reopened.resolve_address("demo:00012:1.25,2,3")
	_check(restored.ok and restored.persisted and restored.map_ref == "legacy/city" and restored.address.begins_with("demo:12:"), "saved numeric identity reopens")
	var formatted: Dictionary = reopened.format_map_address(map_a, [1.25, 2.0, 3.0])
	_check(formatted.ok and formatted.address == restored.address, "format and resolve share mapping")
	var undone: Dictionary = service.undo_catalog(doc.document_id, 1)
	_check(undone.ok and undone.document.edit_revision == 2 and undone.document.dirty, "undo registration changes own document")
	_expect_reason(service.resolve_address("demo:12:1,2,3"), "map_unregistered", "undo removes live binding")
	_expect_reason(service.register_map(b.entry_id, "12", 2), "map_number_conflict", "undo reserves ID as tombstone")
	var redone: Dictionary = service.redo_catalog(doc.document_id, 2)
	_check(redone.ok and redone.document.edit_revision == 3 and not redone.document.dirty, "redo restores exact saved identity")
	undone = service.undo_catalog(doc.document_id, 3)
	saved = service.save_catalog(doc.document_id, 4, saved.disk_sha)
	_check(saved.ok, "tombstone save")
	var tombstone_service := Catalog.new(fixture)
	var tomb_listing: Dictionary = tombstone_service.list_maps("demo")
	_expect_reason(tombstone_service.register_map(_row(tomb_listing, map_b).entry_id, "12", 0), "map_number_conflict", "saved tombstone survives reopen")
	var new_registration: Dictionary = tombstone_service.register_map(_row(tomb_listing, map_b).entry_id, "13", 0)
	_check(new_registration.ok, "another number can register")
	var disk_before := FileAccess.get_file_as_string(doc.path)
	_write_text(doc.path, disk_before + "\n")
	var disk_conflict_sha := FileAccess.get_sha256(doc.path)
	_expect_reason(tombstone_service.save_catalog(doc.document_id, 1, tomb_listing.documents[0].disk_sha), "catalog_conflict", "concurrent disk edit blocks publication")
	_check(FileAccess.get_sha256(doc.path) == disk_conflict_sha and tombstone_service.cached_documents()[0].dirty, "conflict preserves external bytes and unsaved edit")
	_expect_reason(tombstone_service.resolve_address("demo:13:0,0,0"), "catalog_conflict", "stale catalogue cannot silently resolve")
	var discarded: Dictionary = tombstone_service.discard_catalog(doc.document_id, 1)
	_check(discarded.ok and not discarded.document.dirty and discarded.document.undo_count == 0, "explicit discard reloads disk cleanly")
	var relisted: Dictionary = tombstone_service.list_maps("demo")
	_expect_reason(tombstone_service.register_map(_row(relisted, map_b).entry_id, "13", 2), "map_number_conflict", "discard retains session reservations")
	_check(not DirAccess.dir_exists_absolute(str(doc.path) + ".save-lock"), "save lock released after success and conflict")
	_test_shared_and_versions()
	_test_corrupt_and_missing()
	_test_concurrent_new_file()
	_test_source_identity_change()
	_test_metadata_identity_and_orphans()
	_test_writer_limits()
	var report := {"checks":checks,"failed":failures.size(),"failures":failures,"fixture":fixture}
	_write_json(fixture.path_join("result.json"), report)
	print("WORLD_MAP_CATALOG_RESULT " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _test_shared_and_versions() -> void:
	_write_json(fixture.path_join("packs/default/metadata.json"), {"id":"default","name":"默认"})
	var shared := fixture.path_join("maps/legacy_shared/map.gltf")
	_write_map(shared, "prototype/shared")
	var service := Catalog.new(fixture)
	var listed: Dictionary = service.list_maps("default")
	var row := _row(listed, shared)
	var doc: Dictionary = listed.documents[0]
	_check(not row.is_empty() and row.pack_id == "default", "external root/maps belongs to shared pack")
	_check(service.register_map(row.entry_id, "4", 0).ok, "shared map registration")
	_check(service.save_catalog(doc.document_id, 1, "").ok, "shared map catalogue save")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(doc.path))
	_check(raw.maps[0].path_scope == "shared" and raw.maps[0].path == "legacy_shared/map.gltf", "shared path stored within explicit scope without parent traversal")
	_check(Catalog.new(fixture).resolve_address("default:4:0,0,0").path == shared, "shared address reopens original path")
	for version: String in ["v1", "v2"]:
		_write_json(fixture.path_join("packs/dup/" + version + "/metadata.json"), {"id":"dup","version":version})
		_write_map(fixture.path_join("packs/dup/" + version + "/maps/Map001.gltf"), "dup/map1")
	var versions := Catalog.new(fixture)
	_expect_reason(versions.resolve_address("dup:1:0,0,0"), "ambiguous_context", "multiple installed pack versions cannot choose first")
	var selected: Dictionary = versions.list_maps("dup", fixture.path_join("packs/dup/v1"))
	_check(selected.ok and selected.maps.size() == 1, "explicit discovered version selection")
	_check(versions.register_map(selected.maps[0].entry_id, "1", 0).ok, "selected version registration")
	_check(versions.resolve_address("dup:1:0,0,0", fixture.path_join("packs/dup/v1")).ok, "explicit version resolves")
	_expect_reason(versions.resolve_address("dup:1:0,0,0", fixture.path_join("packs/dup/../demo")), "pack_unavailable", "explicit root cannot replace requested pack identity")


func _test_corrupt_and_missing() -> void:
	var base := fixture.path_join("packs/broken")
	_write_json(base.path_join("metadata.json"), {"id":"broken"})
	var source := base.path_join("maps/map.gltf")
	_write_map(source, "broken/map")
	var catalog_path := base.path_join("maps.catalog.json")
	_write_text(catalog_path, "{broken json")
	var service := Catalog.new(fixture)
	var listed: Dictionary = service.list_maps("broken")
	_check(listed.ok and listed.documents[0].read_only and listed.maps[0].status == "catalog_invalid", "corrupt catalogue visible but read-only")
	var before := FileAccess.get_sha256(catalog_path)
	_expect_reason(service.register_map(listed.maps[0].entry_id, "1", 0), "catalog_invalid", "invalid catalogue registration refused")
	_expect_reason(service.save_catalog(listed.documents[0].document_id, 0, ""), "catalog_invalid", "invalid catalogue cannot be overwritten")
	_check(before == FileAccess.get_sha256(catalog_path), "corrupt file preserved")
	_write_json(catalog_path, {"schema_version":1,"pack_id":"broken","maps":[{"map_number":"1","map_ref":"broken/map","path":"../escape.gltf","path_scope":"pack"}],"tombstones":[]})
	_check(Catalog.new(fixture).list_maps("broken").documents[0].read_only, "catalogue traversal path rejected")
	_write_json(catalog_path, {"schema_version":1,"pack_id":"broken","maps":[],"tombstones":["1","1"]})
	_check(Catalog.new(fixture).list_maps("broken").documents[0].read_only, "duplicate tombstones rejected")
	_write_json(catalog_path, {"schema_version":1,"pack_id":"broken","maps":[],"tombstones":[]})
	var repaired: Dictionary = service.discard_catalog(listed.documents[0].document_id, 0)
	_check(repaired.ok and not repaired.document.read_only, "explicit validated reload recovers invalid document")
	_write_map(base.path_join("maps/clone/map.gltf"), "broken/map")
	var collision: Dictionary = Catalog.new(fixture).list_maps("broken")
	_check(collision.maps.size() == 2 and collision.maps[0].reason_code == "map_identity_conflict" and collision.maps[1].reason_code == "map_identity_conflict", "duplicate author references detected before registration")
	var absent_root := fixture.path_join("packs/noid")
	_write_json(absent_root.path_join("metadata.json"), {"id":"noid"})
	_write_json(absent_root.path_join("maps/map.gltf"), {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{}]})
	var missing: Dictionary = Catalog.new(fixture).list_maps("noid")
	_check(missing.maps[0].reason_code == "invalid_map_identity", "missing map_ref is not fabricated")
	_write_map(absent_root.path_join("maps/Map999999999999999999999999999.gltf"), "noid/overflow")
	var overflow: Dictionary = Catalog.new(fixture).list_maps("noid")
	_check(_row(overflow, absent_root.path_join("maps/Map999999999999999999999999999.gltf")).reason_code == "filename_number_conflict", "overflow numeric filename rejected")


func _test_concurrent_new_file() -> void:
	var base := fixture.path_join("packs/concurrent")
	_write_json(base.path_join("metadata.json"), {"id":"concurrent"})
	_write_map(base.path_join("maps/map.gltf"), "concurrent/map")
	var left := Catalog.new(fixture)
	var right := Catalog.new(fixture)
	var a: Dictionary = left.list_maps("concurrent")
	var b: Dictionary = right.list_maps("concurrent")
	_check(left.register_map(a.maps[0].entry_id, "1", 0).ok and right.register_map(b.maps[0].entry_id, "2", 0).ok, "two documents can prepare against absent baseline")
	var lock_path: String = a.documents[0].path + ".save-lock"
	DirAccess.make_dir_absolute(lock_path)
	_expect_reason(left.save_catalog(a.documents[0].document_id, 1, ""), "catalog_busy", "foreign save lock blocks writer")
	_check(DirAccess.dir_exists_absolute(lock_path), "foreign lock is not removed")
	DirAccess.remove_absolute(lock_path)
	_check(left.save_catalog(a.documents[0].document_id, 1, "").ok, "first concurrent writer commits")
	_expect_reason(right.save_catalog(b.documents[0].document_id, 1, ""), "catalog_conflict", "second absent-baseline writer cannot overwrite")
	_check(Catalog.new(fixture).resolve_address("concurrent:1:0,0,0").ok, "first writer mapping preserved")


func _test_source_identity_change() -> void:
	var base := fixture.path_join("packs/changed")
	_write_json(base.path_join("metadata.json"), {"id":"changed"})
	var path := base.path_join("maps/map.gltf")
	_write_map(path, "changed/map")
	var service := Catalog.new(fixture)
	var listed: Dictionary = service.list_maps("changed")
	_check(service.register_map(listed.maps[0].entry_id, "1", 0).ok, "identity-change fixture registered")
	_write_map(path, "changed/replaced")
	_expect_reason(service.save_catalog(listed.documents[0].document_id, 1, ""), "map_revision_changed", "source identity changed before save rejected")
	_expect_reason(service.resolve_address("changed:1:0,0,0"), "map_revision_changed", "changed author identity cannot resolve")
	_check(not FileAccess.file_exists(listed.documents[0].path), "source identity failure creates no catalogue")


func _test_metadata_identity_and_orphans() -> void:
	var base := fixture.path_join("packs/identity")
	_write_json(base.path_join("metadata.json"), {"id":"identity","version":"1"})
	_write_map(base.path_join("maps/map.gltf"), "identity/map")
	var service := Catalog.new(fixture)
	var listed: Dictionary = service.list_maps("identity")
	var doc: Dictionary = listed.documents[0]
	_check(service.register_map(listed.maps[0].entry_id, "1", 0).ok, "metadata identity fixture registered")
	_check(service.save_catalog(doc.document_id, 1, "").ok, "metadata identity fixture saved")
	_write_json(base.path_join("metadata.json"), {"id":"replacement","version":"1"})
	_expect_reason(service.resolve_address("replacement:1:0,0,0"), "catalog_invalid", "warm resolver does not rebind old catalogue to changed pack ID")
	_expect_reason(Catalog.new(fixture).resolve_address("replacement:1:0,0,0"), "catalog_invalid", "cold resolver rejects changed pack ID equally")
	_write_json(base.path_join("metadata.json"), {"id":"identity","version":"2"})
	_expect_reason(service.resolve_address("identity:1:0,0,0"), "pack_revision_changed", "metadata version change invalidates loaded document")
	_expect_reason(service.save_catalog(doc.document_id, 1, ""), "catalog_conflict", "caller baseline must still match saved catalogue")
	var cached: Dictionary = {}
	for row: Dictionary in service.cached_documents():
		if row.document_id == doc.document_id: cached = row
	_expect_reason(service.save_catalog(doc.document_id, 1, cached.disk_sha), "pack_revision_changed", "metadata revision blocks save")
	_check(service.discard_catalog(doc.document_id, 1).ok and service.resolve_address("identity:1:0,0,0").ok, "explicit reload adopts metadata version after validation")
	var orphan_base := fixture.path_join("packs/orphan")
	_write_json(orphan_base.path_join("metadata.json"), {"id":"orphan"})
	_write_map(orphan_base.path_join("maps/map.gltf"), "orphan/map")
	var orphan_service := Catalog.new(fixture)
	var orphan_listing: Dictionary = orphan_service.list_maps("orphan")
	var orphan_doc: Dictionary = orphan_listing.documents[0]
	_check(orphan_service.register_map(orphan_listing.maps[0].entry_id, "8", 0).ok, "orphan draft registered")
	# A missing metadata file removes the pack from discovery without moving
	# any map bytes or exercising destructive recursive filesystem operations.
	DirAccess.remove_absolute(orphan_base.path_join("metadata.json"))
	var orphan_visible: Dictionary = orphan_service.list_maps()
	var orphan_row := _row(orphan_visible, orphan_doc.path)
	_check(orphan_visible.ok and not orphan_row.is_empty() and orphan_row.entry_id == "" and orphan_row.reason_code == "pack_unavailable", "missing pack draft remains visible and unregistrable")
	var abandoned: Dictionary = orphan_service.discard_catalog(orphan_doc.document_id, 1)
	_check(abandoned.ok and abandoned.abandoned and orphan_service.cached_documents().filter(func(value): return value.document_id == orphan_doc.document_id).is_empty(), "explicit missing-pack discard releases dirty close guard")
	_check(not FileAccess.file_exists(orphan_doc.path) and not FileAccess.file_exists(orphan_base.path_join("metadata.json")), "abandon does not recreate external files")
	_write_json(orphan_base.path_join("metadata.json"), {"id":"orphan"})
	var returned: Dictionary = orphan_service.list_maps("orphan")
	_check(returned.documents[0].edit_revision == 2, "reappearing namespace preserves revision generation")
	_expect_reason(orphan_service.register_map(returned.maps[0].entry_id, "8", 2), "map_number_conflict", "reappearing namespace retains session reservations")
	for invalid: Dictionary in [{"folder":"missing_id","metadata":{}},{"folder":"number_id","metadata":{"id":123}}]:
		var invalid_base := fixture.path_join("packs/" + str(invalid.folder))
		_write_json(invalid_base.path_join("metadata.json"), invalid.metadata)
		_write_map(invalid_base.path_join("maps/map.gltf"), "invalid/map")
		var invalid_service := Catalog.new(fixture)
		var inspected: Dictionary = invalid_service.list_maps("", invalid_base)
		_check(inspected.ok and inspected.documents[0].read_only and inspected.documents[0].reason_code == "invalid_pack_identity", "metadata.id must be explicit string: " + str(invalid.folder))
		_expect_reason(invalid_service.register_map(inspected.maps[0].entry_id, "1", 0), "invalid_pack_identity", "invalid metadata namespace cannot register: " + str(invalid.folder))


func _test_writer_limits() -> void:
	var base := fixture.path_join("packs/limits")
	_write_json(base.path_join("metadata.json"), {"id":"limits"})
	_write_map(base.path_join("maps/map.gltf"), "limits/map")
	var service := Catalog.new(fixture)
	var listed: Dictionary = service.list_maps("limits")
	var state: Dictionary = listed.documents[0]
	var internal: Dictionary = service._documents[state.document_id]
	# Fault-inject oversized in-memory states to exercise writer defence without
	# creating ten thousand map files or changing production limits.
	for i in Catalog.MAX_MAPS + 1: internal.tombstones.append(str(i))
	_expect_reason(service.save_catalog(state.document_id, 0, ""), "catalog_limit", "writer rejects tombstone count above reader limit")
	_check(not FileAccess.file_exists(state.path), "over-limit writer creates no visible file")
	internal.tombstones.clear()
	internal.maps.append({"map_number":"1","map_ref":"limits/map","path":"x".repeat(Catalog.MAX_CATALOG_BYTES),"path_scope":"pack"})
	_expect_reason(service.save_catalog(state.document_id, 0, ""), "catalog_limit", "writer rejects serialized bytes above reader limit before source reads")
	internal.maps.clear()
	for i in Catalog.MAX_MAPS: service._reserved[state.document_id][str(i)] = true
	_expect_reason(service.register_map(listed.maps[0].entry_id, "10001", 0), "catalog_limit", "new registrations respect retained-identity budget")
	_check(service.cached_documents()[0].edit_revision == 0 and service.cached_documents()[0].undo_count == 0, "limit failures do not create edits or history")


func _row(listing: Dictionary, path: String) -> Dictionary:
	for row: Dictionary in listing.get("maps", []):
		if row.path == path: return row
	return {}


func _write_map(path: String, reference: String) -> void:
	_write_json(path, {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"rmmo_world","extras":{"map_ref":reference}}]})


func _write_json(path: String, data: Dictionary) -> void:
	_write_text(path, JSON.stringify(data, "\t") + "\n")


func _write_text(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("fixture write failed: " + path)
		return
	file.store_string(value)
	file.close()


func _expect_reason(result: Dictionary, reason: String, label: String) -> void:
	_check(not result.get("ok", false) and result.get("reason_code", "") == reason, label + " [" + str(result.get("reason_code", "")) + "]")


func _check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures.append(label)
		printerr("FAIL: " + label)
