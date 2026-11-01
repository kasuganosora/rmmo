extends SceneTree
const Catalog = preload("res://scripts/world_editor/world_map_catalog.gd")
const Store = preload("res://scripts/world_editor/world_layout_store.gd")
var checks := 0
var failures: Array[String] = []
var fixture := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture = "D:/code/rmmo_runtime/review_artifacts/world_layout_d2_20261101/store_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var source := _fixture("lifecycle")
	var catalog := Catalog.new(source)
	var service := Store.new(catalog)
	var listed := service.list_worlds("demo")
	_check(listed.ok and listed.worlds.is_empty() and listed.packs.size() == 1, "discovery lists owner without creating worlds")
	_check(not DirAccess.dir_exists_absolute(source.path_join("packs/demo/worlds")), "discovery performs no filesystem writes")
	var args := _create_args()
	var candidate := service.preview(args)
	_reason(candidate, "catalog_not_persisted", "unregistered catalogue cannot feed layout")
	_register(catalog,"demo",["1","2"])
	candidate = service.preview(args)
	_check(candidate.ok and candidate.bindings.size() == 2 and candidate.bindings[0].source_sha.length() == 64, "preview resolves persisted map sources")
	if not candidate.ok: _finish(); return
	_check(service.cached_documents().is_empty() and not DirAccess.dir_exists_absolute(source.path_join("packs/demo/worlds")), "preview creates only ephemeral candidate")
	var exposed: Dictionary = candidate.layout
	exposed.spaces[0].placements[0].origin_m[0] = 5000.0
	var applied := service.apply(candidate.candidate_id,candidate.base_edit_revision)
	_check(applied.ok and applied.layout.spaces[0].placements[0].origin_m[0] == 0.0, "caller mutation cannot alter immutable candidate")
	if not applied.ok: _finish(); return
	var id: String = applied.document.document_id
	_check(service.owns(id) and applied.document.dirty and applied.document.undo_count == 1 and applied.document.edit_revision == 1, "apply owns one independent dirty history transaction")
	_reason(service.apply(candidate.candidate_id,0), "unknown_candidate", "candidate consumed once")
	var undone := service.undo(id,1)
	_check(undone.ok and undone.layout.is_empty() and not undone.document.dirty and undone.document.redo_count == 1, "undo creation is clean and redoable without files")
	_reason(service.save(id,2,""), "empty_layout", "undone creation cannot publish invalid empty layout")
	var redone := service.redo(id,2)
	_check(redone.ok and redone.document.dirty and redone.document.edit_revision == 3, "redo restores exact candidate")
	var before := service.cached_documents()
	_reason(service.save(id,2,""), "candidate_stale", "save rejects stale edit revision")
	_reason(service.save(id,3,"stale"), "layout_conflict", "save rejects wrong disk SHA")
	_check(before == service.cached_documents(), "rejected save preserves history and draft")
	var map_hash := FileAccess.get_sha256(source.path_join("packs/demo/maps/Map1.gltf"))
	var saved := service.save(id,3,"")
	_check(saved.ok and not saved.document.dirty and saved.document.edit_revision == 3 and FileAccess.file_exists(saved.path), "first atomic save publishes without changing edit revision")
	if not saved.ok: _finish(); return
	var first_sha: String = saved.disk_sha
	var clean_save := service.save(id,3,first_sha)
	_check(clean_save.ok and clean_save.unchanged and clean_save.disk_sha == first_sha, "clean save does not rewrite")
	_check(FileAccess.get_sha256(source.path_join("packs/demo/maps/Map1.gltf")) == map_hash, "layout lifecycle does not modify map bytes")
	var fresh := Store.new(Catalog.new(source))
	var fresh_list := fresh.list_worlds("demo")
	var clean_fresh := fresh.save(fresh_list.documents[0].document_id,0,fresh_list.documents[0].disk_sha)
	_check(clean_fresh.ok and clean_fresh.unchanged, "discovered clean layout can save unchanged without prior get")
	var reopened := fresh.get_layout(fresh_list.worlds[0].document_id)
	_check(reopened.ok and reopened.layout == saved.layout and reopened.bindings.size() == 2 and not reopened.document.read_only, "saved layout reopens with verified source bindings")
	var updated := _layout(); updated.spaces[0].placements[1].origin_m[0] = 1200.0
	updated.spaces[0].seams = []
	var update := service.preview({"mode":"update","document_id":id,"expected_edit_revision":3,"layout":updated})
	_check(update.ok, "update previews full replacement")
	var edit := service.apply(update.candidate_id,3)
	_check(edit.ok and edit.document.edit_revision == 4 and edit.document.dirty, "update applies one edit")
	undone = service.undo(id,4)
	_check(undone.ok and undone.layout == saved.layout and not undone.document.dirty, "undo returns to persisted layout")
	redone = service.redo(id,5)
	_check(redone.ok and redone.layout == updated and redone.document.dirty, "redo restores replacement")
	var replaced := service.save(id,6,first_sha)
	_check(replaced.ok and replaced.disk_sha != first_sha and FileAccess.file_exists(saved.path + ".previous"), "replacement save retains atomic recovery version")
	_check(not DirAccess.dir_exists_absolute(saved.path + ".save-lock"), "save releases lock")
	_test_stale_sources()
	_test_external_layout_and_orphan()
	_test_dependencies_and_versions()
	_test_invalid_files_and_limits()
	_finish()


func _test_stale_sources() -> void:
	var source := _fixture("sources")
	var catalog := Catalog.new(source); _register(catalog,"demo",["1","2"])
	var service := Store.new(catalog)
	var candidate := service.preview(_create_args())
	var map_path := source.path_join("packs/demo/maps/Map1.gltf")
	var original := FileAccess.get_file_as_string(map_path)
	_write_text(map_path,original + "\n")
	_reason(service.apply(candidate.candidate_id,0), "candidate_stale", "map content change invalidates preview")
	_check(service.cached_documents().is_empty(), "stale candidate cannot create a document")
	candidate = service.preview(_create_args())
	var applied := service.apply(candidate.candidate_id,0)
	var id: String = applied.document.document_id
	_write_text(map_path,original + "\n\n")
	_reason(service.save(id,1,""), "layout_inputs_changed", "map content change invalidates save")
	var current := service.get_layout(id)
	_check(current.document.read_only and current.bindings.is_empty() and current.document.dirty, "stale inputs visible but cannot resolve addresses")
	var refreshed := service.preview({"mode":"update","document_id":id,"expected_edit_revision":1,"layout":_layout()})
	_check(refreshed.ok, "explicit preview can adopt changed map source")
	applied = service.apply(refreshed.candidate_id,1)
	_check(applied.ok and applied.document.edit_revision == 2, "source refresh applies as one edit")
	var catalog_state: Dictionary = catalog.cached_documents()[0]
	var bytes := FileAccess.get_file_as_string(catalog_state.path)
	_write_text(catalog_state.path,bytes + "\n")
	_reason(service.save(id,2,""), "catalog_conflict", "external catalogue change blocks layout save")
	var keep := service.cached_documents()
	_reason(service.undo(id,2), "catalog_conflict", "history cannot restore stale source bindings")
	_check(keep == service.cached_documents(), "failed history preserves stacks")
	catalog.discard_catalog(catalog_state.document_id,catalog_state.edit_revision)
	var after_catalog := service.preview({"mode":"update","document_id":id,"expected_edit_revision":2,"layout":_layout()})
	_check(after_catalog.ok, "explicit catalogue reload allows a fresh proof")
	var metadata := source.path_join("packs/demo/metadata.json")
	_write_json(metadata,{"id":"demo","name":"Changed","version":"2"})
	_reason(service.apply(after_catalog.candidate_id,2), "pack_revision_changed", "owner metadata change invalidates candidate")
	_check(service.get_layout(id).document.read_only, "owner metadata drift is not silently rebound")
	var discarded := service.discard(id,2)
	_check(discarded.ok and discarded.abandoned and service.cached_documents().is_empty(), "unsaved draft can be discarded after metadata drift")


func _test_external_layout_and_orphan() -> void:
	var source := _fixture("conflict")
	var catalog := Catalog.new(source); _register(catalog,"demo",["1","2"])
	var service := Store.new(catalog)
	var p := service.preview(_create_args()); var a := service.apply(p.candidate_id,0)
	var id: String = a.document.document_id
	var saved := service.save(id,1,"")
	var text := FileAccess.get_file_as_string(saved.path)
	_write_text(saved.path,text + "\n")
	var listing := service.list_worlds("demo")
	_check(listing.documents[0].read_only and listing.documents[0].disk_conflict, "clean external layout changes are explicit conflicts")
	var read := service.get_layout(id)
	_check(read.ok and read.document.read_only and read.document.disk_sha == saved.disk_sha and read.bindings.is_empty(), "get retains cached baseline until explicit reload")
	_reason(service.preview({"mode":"update","document_id":id,"expected_edit_revision":1,"layout":_layout()}), "layout_conflict", "external file change blocks editing old baseline")
	var discarded := service.discard(id,1)
	_check(discarded.ok and discarded.document.edit_revision == 2 and discarded.document.disk_sha != saved.disk_sha and not discarded.document.dirty, "discard explicitly reloads disk")
	var changed := _layout(); changed.spaces[0].seams = []
	p = service.preview({"mode":"update","document_id":id,"expected_edit_revision":2,"layout":changed}); a = service.apply(p.candidate_id,2)
	var moved := source + "_orphaned_demo"
	_check(DirAccess.rename_absolute(source.path_join("packs/demo"),moved) == OK, "fixture owner moved away")
	listing = service.list_worlds("demo")
	_check(listing.ok and listing.documents.size() == 1 and listing.documents[0].dirty and listing.documents[0].read_only, "orphan draft remains selectable")
	_reason(service.save(id,3,discarded.document.disk_sha), "pack_unavailable", "orphan save cannot recreate missing pack")
	discarded = service.discard(id,3)
	_check(discarded.ok and discarded.abandoned and service.cached_documents().is_empty() and not DirAccess.dir_exists_absolute(source.path_join("packs/demo")), "orphan discard clears only memory")
	_check(DirAccess.rename_absolute(moved,source.path_join("packs/demo")) == OK, "fixture owner restored")
	listing = service.list_worlds("demo")
	_check(listing.documents[0].edit_revision > 3, "reappearing document cannot reuse stale edit revision")
	var new_source := _fixture("new_conflict"); var new_catalog := Catalog.new(new_source); _register(new_catalog,"demo",["1","2"])
	var new_store := Store.new(new_catalog); p = new_store.preview(_create_args()); a = new_store.apply(p.candidate_id,0)
	_write_json(a.document.path,_layout())
	var concurrent_sha := FileAccess.get_sha256(a.document.path)
	_reason(new_store.save(a.document.document_id,1,""), "layout_conflict", "first-save cannot overwrite concurrent creator")
	_check(FileAccess.get_sha256(a.document.path) == concurrent_sha and new_store.cached_documents()[0].dirty, "concurrent creator bytes and own draft retained")


func _test_dependencies_and_versions() -> void:
	var source := _fixture("dependencies")
	_write_json(source.path_join("packs/other/metadata.json"),{"id":"other","version":"1"})
	_write_map(source.path_join("packs/other/maps/Map1.gltf"),"other/a")
	_write_json(source.path_join("packs/default/v1/metadata.json"),{"id":"default","version":"1"})
	_write_map(source.path_join("packs/default/v1/maps/Map1.gltf"),"default/a")
	_write_json(source.path_join("packs/default/v2/metadata.json"),{"id":"default","version":"2"})
	_write_map(source.path_join("packs/default/v2/maps/Map1.gltf"),"default/a")
	var catalog := Catalog.new(source); _register(catalog,"demo",["1","2"])
	_register(catalog,"other",["1"])
	_register(catalog,"default",["1"],source.path_join("packs/default/v1"))
	_register(catalog,"default",["1"],source.path_join("packs/default/v2"))
	var service := Store.new(catalog)
	var layout := _layout(); layout.spaces[0].seams = []; layout.spaces[0].placements.resize(1)
	layout.spaces[0].placements[0].pack_id = "other"
	var args := _create_args(); args.layout = layout
	_reason(service.preview(args), "pack_dependency_unavailable", "ordinary foreign packs cannot be referenced")
	layout.spaces[0].placements[0].pack_id = "default"
	_reason(service.preview(args), "ambiguous_context", "shared version ambiguity requires explicit selector")
	layout.spaces[0].placements[0].pack_version = "2"
	var p := service.preview(args)
	_check(p.ok and p.bindings[0].pack_root.ends_with("/default/v2") and p.layout.spaces[0].placements[0].pack_version == "2", "portable version selector resolves exact shared installation")
	if p.ok:
		var a := service.apply(p.candidate_id,0); var s := service.save(a.document.document_id,1,"")
		_check(s.ok and not FileAccess.get_file_as_string(s.path).contains(source), "world author file contains no absolute installation paths")
	layout.spaces[0].placements[0].pack_version = "99"
	_reason(service.preview(args), "world_exists", "create cannot replace existing world")
	args.world_key = "second"; args.layout.world_key = "second"
	_reason(service.preview(args), "pack_dependency_unavailable", "missing version does not silently select another")


func _test_invalid_files_and_limits() -> void:
	var source := _fixture("invalid")
	var catalog := Catalog.new(source); _register(catalog,"demo",["1","2"])
	var path := source.path_join("packs/demo/worlds/broken/world.json")
	_write_text(path,"{ broken")
	var service := Store.new(catalog); var listing := service.list_worlds("demo")
	_check(listing.ok and listing.documents[0].read_only, "malformed JSON stays visible read-only")
	var id: String = listing.documents[0].document_id
	var bad_sha := FileAccess.get_sha256(path)
	_reason(service.save(id,0,bad_sha), "invalid_layout", "malformed file cannot be overwritten")
	_check(service.discard(id,0).ok and FileAccess.get_sha256(path) == bad_sha, "explicit malformed reload is clean and never writes")
	var args := _create_args(); args.world_key = "../escape"; args.layout.world_key = "../escape"
	_check(not service.preview(args).ok, "world path traversal rejected")
	args = _create_args(); args.world_key = "CON"; args.layout.world_key = "CON"
	_reason(service.preview(args), "invalid_world_key", "Windows device world directory rejected")
	args = _create_args(); args.expected_edit_revision = 0.5
	_reason(service.preview(args), "invalid_arguments", "fractional revision rejected by shared service")
	_reason(service.get_layout("layout:invented"), "unknown_document", "arbitrary document path is not accepted")
	args = _create_args(); args.pack_root = source.path_join("packs/demo/../other")
	_reason(service.preview(args), "pack_unavailable", "root selector must match discovered owner")
	args = _create_args(); var first := service.preview(args)
	for index in Store.MAX_CANDIDATES: service.preview(args)
	_reason(service.apply(first.candidate_id,0), "unknown_candidate", "candidate cache bounded and evicts oldest")
	var active := service.preview(args); var a := service.apply(active.candidate_id,0)
	var saved := service.save(a.document.document_id,1,"")
	var revision := 1
	for index in Store.MAX_HISTORY + 3:
		var layout := _layout(); layout.spaces[0].seams = []; layout.spaces[0].placements[1].origin_m[0] = 1100.0 + index
		var p := service.preview({"mode":"update","document_id":a.document.document_id,"expected_edit_revision":revision,"layout":layout})
		var result := service.apply(p.candidate_id,revision)
		if not result.ok: _check(false,"history fixture edit failed"); break
		revision += 1
	_check(service._documents[a.document.document_id].undo.size() == Store.MAX_HISTORY, "history bounded independently of map document")
	var internal: Dictionary = service._documents[a.document.document_id]
	var prior: Dictionary = internal.layout.duplicate(true)
	internal.layout["padding"] = "x".repeat(Store.MAX_BYTES)
	var before: String = FileAccess.get_sha256(saved.path)
	_check(not service.save(a.document.document_id,revision,saved.disk_sha).ok and FileAccess.get_sha256(saved.path) == before, "invalid oversized internal payload cannot be published")
	internal.layout = prior
	var discarded := service.discard(a.document.document_id,revision)
	_check(discarded.ok and not discarded.document.dirty and discarded.document.undo_count == 0, "discard clears bounded draft history")
	var drafts := Store.new(Catalog.new(source))
	args = _create_args(); args.world_key = "another"; args.layout.world_key = "another"
	var lower := drafts.preview(args)
	args.world_key = "ANOTHER"; args.layout.world_key = "ANOTHER"
	var upper := drafts.preview(args)
	var lower_applied := drafts.apply(lower.candidate_id,lower.base_edit_revision)
	_check(lower_applied.ok, "case-alias fixture draft applied")
	if OS.get_name() == "Windows":
		_reason(drafts.apply(upper.candidate_id,upper.base_edit_revision), "candidate_stale", "case aliases cannot create competing draft documents")
		_reason(drafts.preview(args), "world_exists", "case-alias duplicate creation rejected in preview")
	var abandoned := drafts.discard(lower_applied.document.document_id,lower_applied.document.edit_revision)
	args.world_key = "another"; args.layout.world_key = "another"
	var recreated := drafts.preview(args)
	_check(abandoned.ok and recreated.ok and recreated.base_edit_revision > lower_applied.document.edit_revision, "new create request zero receives monotonic revision after abandon")
	_check(drafts.apply(recreated.candidate_id,recreated.base_edit_revision).ok, "recreated draft uses returned base revision")


func _fixture(name_: String) -> String:
	var source := fixture.path_join(name_)
	_write_json(source.path_join("packs/demo/metadata.json"),{"id":"demo","name":"Demo","version":"1"})
	_write_map(source.path_join("packs/demo/maps/Map1.gltf"),"demo/city")
	_write_map(source.path_join("packs/demo/maps/Map2.gltf"),"demo/field")
	return source


func _register(catalog: RefCounted, pack_id: String, numbers: Array, pack_root: String = "") -> void:
	var listing: Dictionary = catalog.list_maps(pack_id,pack_root)
	if not listing.ok: _check(false,"fixture catalogue discovery " + pack_id); return
	var doc: Dictionary = listing.documents[0]
	var revision: int = doc.edit_revision
	for number: String in numbers:
		for row: Dictionary in listing.maps:
			if str(row.path).get_file() == "Map" + number + ".gltf":
				var registered: Dictionary = catalog.register_map(row.entry_id,number,revision)
				if not registered.ok: _check(false,"fixture registration " + str(registered)); return
				revision += 1
	var saved: Dictionary = catalog.save_catalog(doc.document_id,revision,doc.disk_sha)
	_check(saved.ok,"fixture catalogue saved " + pack_id)


func _create_args() -> Dictionary:
	return {"mode":"create","pack_id":"demo","world_key":"demo_world","expected_edit_revision":0,"layout":_layout()}


func _layout() -> Dictionary:
	return {"schema_version":1,"world_key":"demo_world","units":"meters","up_axis":"Y","spaces":[{"id":"outdoor","placements":[
		{"id":"city","pack_id":"demo","map_number":"1","origin_m":[0.0,0.0,0.0],"ownership_xz_m":[0.0,0.0,1000.0,800.0]},
		{"id":"field","pack_id":"demo","map_number":"2","origin_m":[1000.0,0.0,0.0],"ownership_xz_m":[0.0,0.0,2400.0,800.0]}],
		"seams":[{"id":"city_field","a":{"placement_id":"city","edge":"x_max","interval_m":[0.0,800.0]},"b":{"placement_id":"field","edge":"x_min","interval_m":[0.0,800.0]},"mode":"continuous"}]}]}


func _write_map(path: String, map_ref: String) -> void:
	_write_json(path,{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"Map","extras":{"map_ref":map_ref}}]})


func _write_json(path: String, value: Dictionary) -> void:
	_write_text(path,JSON.stringify(value,"\t",true,true) + "\n")


func _write_text(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: _check(false,"fixture write " + path); return
	file.store_string(value); file.close()


func _reason(result: Dictionary, reason: String, label: String) -> void:
	_check(not result.get("ok",false) and result.get("reason_code","") == reason,label + " [" + str(result.get("reason_code","ok")) + "]")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS " + label)
	else: failures.append(label); print("FAIL " + label)


func _finish() -> void:
	var result := {"checks":checks,"failed":failures.size(),"failures":failures,"fixture":fixture}
	_write_json(fixture.path_join("result.json"),result)
	print("WORLD_LAYOUT_STORE_RESULT " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
