extends RefCounted
## Author-owned world placement documents. Candidates and history never write maps.
const Catalog = preload("res://scripts/world_editor/world_map_catalog.gd")
const Geometry = preload("res://scripts/world3d/world_layout_geometry.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Location = preload("res://scripts/world3d/world_location.gd")
const Atomic = preload("res://scripts/world3d/atomic_file.gd")
const MAX_BYTES := 8 * 1024 * 1024
const MAX_HISTORY := 32
const MAX_CANDIDATES := 32
const MAX_WORLDS := 1024

var root: String
var catalog: RefCounted
var _documents: Dictionary = {}
var _candidates: Dictionary = {}
var _candidate_order: Array[String] = []
var _revision_seeds: Dictionary = {}


func _init(map_catalog: RefCounted) -> void:
	catalog = map_catalog
	root = _normal(str(catalog.root))


func owns(document_id: String) -> bool:
	return _documents.has(document_id)


## No filesystem work: this is also used by the editor's dirty-exit guard.
func cached_documents() -> Array:
	var result: Array = []
	for doc: Dictionary in _documents.values(): result.append(_state(doc))
	return result


func list_worlds(pack_id: String = "", pack_root: String = "") -> Dictionary:
	var selected := _packs(pack_id, pack_root)
	if not selected.ok and selected.reason_code != "pack_unavailable": return selected
	var worlds: Array = []; var documents: Array = []; var packs: Array = []
	var seen := {}
	for pack: Dictionary in selected.get("packs", []):
		packs.append({"id":pack.id,"name":pack.name,"root":pack.root,"version":pack.version,"shared":pack.shared})
		var base: String = str(pack.root).path_join("worlds")
		if not _allowed(base): continue
		var directory := DirAccess.open(base)
		if directory == null: continue
		for folder: String in directory.get_directories():
			if not _world_key_ok(folder) or directory.is_link(folder): continue
			var path := base.path_join(folder).path_join("world.json")
			if not _allowed(path) or not FileAccess.file_exists(path): continue
			if seen.size() >= MAX_WORLDS: return _fail("layout_limit_exceeded", "世界布局数量超过目录上限。")
			var id := _document_id(pack, folder)
			if not _documents.has(id): _documents[id] = _load_document(pack, folder)
			var doc: Dictionary = _documents[id]
			var view := _view_state(doc)
			documents.append(view); worlds.append(_row(doc, view)); seen[id] = true
	for doc: Dictionary in _documents.values():
		if seen.has(doc.id): continue
		if not pack_id.is_empty() and doc.pack_id != pack_id: continue
		if not pack_root.is_empty() and _key(doc.pack_root) != _key(pack_root): continue
		# Keep unsaved/undone drafts and orphan documents selectable for discard.
		var view := _view_state(doc)
		documents.append(view); worlds.append(_row(doc, view))
	worlds.sort_custom(func(a: Dictionary, b: Dictionary): return (str(a.pack_id)+"/"+str(a.path)).naturalnocasecmp_to(str(b.pack_id)+"/"+str(b.path)) < 0)
	return {"ok":true,"worlds":worlds,"documents":documents,"packs":packs}


func get_layout(document_id: String) -> Dictionary:
	if not _documents.has(document_id): return _fail("unknown_document", "请先从世界布局目录选择文档。")
	var doc: Dictionary = _documents[document_id]
	var view := _view_state(doc)
	var bindings: Array = []
	var diagnostics: Array = doc.diagnostics.duplicate(true)
	if not view.read_only and not doc.layout.is_empty():
		var bound := _bind(doc.layout, doc.pack_id, doc.pack_root)
		if not bound.ok:
			view.read_only = true; view.reason_code = bound.reason_code; view.message = bound.message
		elif not doc.inputs.is_empty() and _fingerprint(bound.inputs) != _fingerprint(doc.inputs):
			view.read_only = true; view.reason_code = "layout_inputs_changed"; view.message = "引用的包、编号目录或地图已变化，请重新预览或重新载入布局。"
		else:
			if doc.inputs.is_empty():
				doc.inputs = bound.inputs.duplicate(true); doc.bindings = bound.bindings.duplicate(true)
			bindings = doc.bindings.duplicate(true)
	if view.read_only:
		diagnostics.append({"code":view.reason_code,"severity":"error","message":view.message})
	return {"ok":true,"document":view,"layout":doc.layout.duplicate(true),"bindings":bindings,"diagnostics":diagnostics,"inputs":doc.inputs.duplicate(true)}


func preview(args: Dictionary) -> Dictionary:
	for field: Variant in args:
		if field not in ["mode","pack_id","pack_root","world_key","document_id","layout","expected_edit_revision"]:
			return _fail("invalid_arguments", "存在未知的布局预览参数。")
	if not args.get("layout") is Dictionary or not _revision_ok(args.get("expected_edit_revision")):
		return _fail("invalid_arguments", "预览需要完整布局与非负整数编辑修订。")
	for field: String in ["mode","pack_id","pack_root","world_key","document_id"]:
		if args.has(field) and not args[field] is String: return _fail("invalid_arguments", "布局上下文参数必须为字符串。")
	var mode: String = args.get("mode", "")
	if mode not in ["create", "update"]: return _fail("invalid_arguments", "布局预览方式必须为 create 或 update。")
	var checked := Geometry.validate(args.layout)
	if not checked.ok: return checked
	if not _world_key_ok(checked.layout.world_key): return _fail("invalid_world_key", "世界标识不能作为安全目录名使用。")
	if _serialized(checked.layout).to_utf8_buffer().size() > MAX_BYTES: return _fail("layout_limit_exceeded", "世界布局超过读取字节上限。")
	var doc: Dictionary
	if mode == "create":
		if args.get("world_key", "") != checked.layout.world_key or str(args.get("pack_id", "")).is_empty():
			return _fail("invalid_arguments", "新建需要所属资源包与匹配的 world_key。")
		if args.has("document_id"): return _fail("invalid_arguments", "新建不能指定已有文档。")
		var owner := _owner(args.pack_id, args.get("pack_root", ""))
		if not owner.ok: return owner
		doc = _blank(owner.pack, checked.layout.world_key)
		if int(args.expected_edit_revision) != 0: return _fail("candidate_stale", "新建布局的预览修订必须为零。")
		if _path_in_use(doc.path) or FileAccess.file_exists(doc.path) or DirAccess.dir_exists_absolute(doc.path):
			return _fail("world_exists", "此世界布局已经存在，请选择后更新。")
		if not _allowed(doc.path): return _fail("path_not_allowed", "新世界路径不在安全资源根中。")
	else:
		if args.has("pack_id") or args.has("pack_root") or args.has("world_key"):
			return _fail("invalid_arguments", "更新通过文档句柄确定所属包与世界标识。")
		var editable := _editable(args.get("document_id", ""), int(args.expected_edit_revision))
		if not editable.ok: return editable
		doc = editable.document
		if checked.layout.world_key != doc.world_key: return _fail("world_identity_changed", "普通编辑不能修改世界稳定标识。")
	var bound := _bind(checked.layout, doc.pack_id, doc.pack_root)
	if not bound.ok: return bound
	# Check the owner and disk again after source scans, before issuing the proof.
	var current := _context(doc)
	if not current.ok: return current
	var candidate := {"mode":mode,"document_id":doc.id,"base_edit_revision":doc.edit_revision,
		"disk_sha":doc.disk_sha,"metadata_sha":doc.metadata_sha,"pack_id":doc.pack_id,"pack_root":doc.pack_root,"world_key":doc.world_key,
		"layout":checked.layout.duplicate(true),"bindings":bound.bindings.duplicate(true),"inputs":bound.inputs.duplicate(true),"diagnostics":checked.diagnostics.duplicate(true)}
	candidate.fingerprint = _fingerprint(candidate)
	var id := "layout-candidate:" + Crypto.new().generate_random_bytes(16).hex_encode()
	_candidates[id] = candidate; _candidate_order.append(id)
	while _candidate_order.size() > MAX_CANDIDATES: _candidates.erase(_candidate_order.pop_front())
	return {"ok":true,"candidate_id":id,"document_id":doc.id,"document":_state(doc),"base_edit_revision":doc.edit_revision,
		"layout":candidate.layout.duplicate(true),"bindings":candidate.bindings.duplicate(true),"diagnostics":candidate.diagnostics.duplicate(true),"inputs":candidate.inputs.duplicate(true)}


func apply(candidate_id: String, expected_edit_revision: int) -> Dictionary:
	if not _candidates.has(candidate_id): return _fail("unknown_candidate", "布局候选不存在或已过期，请重新预览。")
	var candidate: Dictionary = _candidates[candidate_id]
	var proof := candidate.duplicate(true); proof.erase("fingerprint")
	if _fingerprint(proof) != candidate.fingerprint: return _fail("candidate_stale", "布局候选校验不一致。")
	if expected_edit_revision != candidate.base_edit_revision: return _fail("candidate_stale", "候选编辑修订不匹配。")
	var doc: Dictionary
	if candidate.mode == "create":
		if _documents.has(candidate.document_id): return _fail("candidate_stale", "此世界布局已由另一个候选创建。")
		var owner := _owner(candidate.pack_id, candidate.pack_root)
		if not owner.ok: return owner
		doc = _blank(owner.pack, candidate.world_key)
		if _path_in_use(doc.path): return _fail("candidate_stale", "此布局路径已由另一个草稿占用。")
		if doc.edit_revision != expected_edit_revision or doc.metadata_sha != candidate.metadata_sha: return _fail("candidate_stale", "新建候选的所属资源包或会话修订已变化。")
	else:
		var editable := _editable(candidate.document_id, expected_edit_revision)
		if not editable.ok: return editable
		doc = editable.document
	if doc.disk_sha != candidate.disk_sha: return _fail("layout_conflict", "候选的布局磁盘基线已变化。")
	var context := _context(doc)
	if not context.ok: return context
	var bound := _bind(candidate.layout, doc.pack_id, doc.pack_root)
	if not bound.ok: return bound
	if _fingerprint(bound.inputs) != _fingerprint(candidate.inputs): return _fail("candidate_stale", "候选引用的包、目录或地图修订已变化。")
	context = _context(doc)
	if not context.ok: return context
	# A discovered document may not have been opened before this update. Capture
	# its old reference proof now so undo restores a verified authored state.
	if not doc.layout.is_empty() and doc.inputs.is_empty():
		var old_bound := _bind(doc.layout, doc.pack_id, doc.pack_root)
		if old_bound.ok:
			doc.inputs = old_bound.inputs.duplicate(true); doc.bindings = old_bound.bindings.duplicate(true)
	_push(doc.undo, _snapshot(doc)); doc.redo.clear()
	_restore(doc, candidate)
	doc.edit_revision += 1
	_documents[doc.id] = doc
	_candidates.erase(candidate_id); _candidate_order.erase(candidate_id)
	return _changed(doc, {"applied":true,"candidate_id":candidate_id})


func save(document_id: String, expected_edit_revision: int, expected_disk_sha: String) -> Dictionary:
	var editable := _editable(document_id, expected_edit_revision)
	if not editable.ok: return editable
	var doc: Dictionary = editable.document
	if expected_disk_sha != doc.disk_sha: return _fail("layout_conflict", "调用者的世界布局磁盘基线已过期。")
	if doc.layout.is_empty(): return _fail("empty_layout", "新建已撤销；可重做或放弃该草稿。")
	var checked := _check_snapshot(doc, _snapshot(doc))
	if not checked.ok: return checked
	var serialized := _serialized(doc.layout)
	if serialized.to_utf8_buffer().size() > MAX_BYTES: return _fail("layout_limit_exceeded", "布局超过可读取字节上限。")
	if not _dirty(doc): return _changed(doc, {"saved":true,"unchanged":true,"path":doc.path,"disk_sha":doc.disk_sha})
	var lock: String = doc.path + ".save-lock"
	var staged: String = doc.path + ".layout.%d.%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	for path: String in [doc.path, doc.path.get_base_dir(), lock, staged, doc.path + ".previous"]:
		if not _allowed(path): return _fail("path_not_allowed", "布局保存路径超出安全资源根。")
	if FileAccess.file_exists(staged) or DirAccess.dir_exists_absolute(staged): return _fail("layout_busy", "布局暂存文件已存在。")
	checked = _context(doc)
	if not checked.ok: return checked
	# Create only these two children. Recursive mkdir could recreate a pack
	# removed by another session after the owner check.
	for directory: String in [str(doc.pack_root).path_join("worlds"), doc.path.get_base_dir()]:
		if not _allowed(directory): return _fail("path_not_allowed", "世界布局目录已不可用。")
		if not DirAccess.dir_exists_absolute(directory):
			var error := DirAccess.make_dir_absolute(directory)
			if error != OK and not DirAccess.dir_exists_absolute(directory): return _fail("layout_write_failed", "不能创建世界布局目录。")
	if not _allowed(lock) or DirAccess.make_dir_absolute(lock) != OK: return _fail("layout_busy", "另一个保存操作持有布局锁。")
	var result := _save_locked(doc, staged, serialized)
	if _allowed(staged) and FileAccess.file_exists(staged): DirAccess.remove_absolute(staged)
	if _allowed(lock): DirAccess.remove_absolute(lock)
	return result


func undo(document_id: String, expected_edit_revision: int) -> Dictionary:
	return _history(document_id, expected_edit_revision, false)


func redo(document_id: String, expected_edit_revision: int) -> Dictionary:
	return _history(document_id, expected_edit_revision, true)


func discard(document_id: String, expected_edit_revision: int) -> Dictionary:
	if not _documents.has(document_id): return _fail("unknown_document", "世界布局文档不存在。")
	var previous: Dictionary = _documents[document_id]
	if previous.edit_revision != expected_edit_revision: return _fail("candidate_stale", "布局编辑修订已变化。")
	var owner := _owner(previous.pack_id, previous.pack_root)
	if not owner.ok or not _allowed(previous.path) or not FileAccess.file_exists(previous.path):
		# Explicit abandonment frees memory only; unavailable packs are never recreated.
		var state := _state(previous)
		state.dirty = false; state.undo_count = 0; state.redo_count = 0; state.edit_revision += 1
		state.read_only = true; state.reason_code = "pack_unavailable" if not owner.ok else "layout_unavailable"
		_revision_seeds[document_id] = state.edit_revision
		_documents.erase(document_id); _drop_candidates(document_id)
		return {"ok":true,"discarded":true,"abandoned":true,"document":state,"documents":cached_documents()}
	var fresh := _load_document(owner.pack, previous.world_key)
	fresh.edit_revision = previous.edit_revision + 1
	_documents[document_id] = fresh; _drop_candidates(document_id)
	return _changed(fresh, {"discarded":true,"reloaded":true})


## Public read-only resolver for source metadata, never a grant to load/transfer.
func resolve_inputs(layout: Dictionary, pack_id: String, pack_root: String = "") -> Dictionary:
	var checked := Geometry.validate(layout)
	return checked if not checked.ok else _bind(checked.layout, pack_id, pack_root)


func _save_locked(doc: Dictionary, staged: String, serialized: String) -> Dictionary:
	var checked := _context(doc)
	if not checked.ok: return checked
	checked = _check_snapshot(doc, _snapshot(doc))
	if not checked.ok: return checked
	if not _allowed(staged): return _fail("path_not_allowed", "布局暂存路径不可用。")
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null: return _fail("layout_write_failed", "不能创建世界布局暂存文件。")
	file.store_string(serialized); file.flush()
	var error := file.get_error(); file.close()
	if error != OK or not _allowed(staged) or FileAccess.get_sha256(staged) != serialized.sha256_text():
		return _fail("layout_write_failed", "世界布局暂存校验失败。")
	checked = _context(doc)
	if not checked.ok: return checked
	checked = _check_snapshot(doc, _snapshot(doc))
	if not checked.ok: return checked
	checked = _context(doc)
	if not checked.ok: return checked
	for path: String in [doc.path, staged, doc.path + ".previous"]:
		if not _allowed(path): return _fail("path_not_allowed", "发布前布局路径已变化。")
	error = Atomic.publish_new(staged, doc.path) if str(doc.disk_sha).is_empty() else Atomic.publish(staged, doc.path)
	if error != OK: return _fail("layout_write_failed", "布局原子发布失败；保留原磁盘文件和编辑历史。")
	doc.disk_sha = serialized.sha256_text(); doc.saved_layout = doc.layout.duplicate(true); doc.disk_conflict = false
	return _changed(doc, {"saved":true,"path":doc.path,"disk_sha":doc.disk_sha})


func _history(document_id: String, expected: int, redoing: bool) -> Dictionary:
	var editable := _editable(document_id, expected)
	if not editable.ok: return editable
	var doc: Dictionary = editable.document
	var source: Array = doc.redo if redoing else doc.undo
	var target: Array = doc.undo if redoing else doc.redo
	if source.is_empty(): return _fail("history_empty", "没有可重做的布局操作。" if redoing else "没有可撤销的布局操作。")
	var snapshot: Dictionary = source.back()
	var checked := _check_snapshot(doc, snapshot)
	if not checked.ok: return checked
	_push(target, _snapshot(doc)); source.pop_back(); _restore(doc, snapshot); doc.edit_revision += 1
	return _changed(doc, {"redone":redoing,"undone":not redoing})


func _editable(document_id: String, expected: int) -> Dictionary:
	if not _documents.has(document_id): return _fail("unknown_document", "请先读取世界布局文档。")
	var doc: Dictionary = _documents[document_id]
	if doc.edit_revision != expected: return _fail("candidate_stale", "布局编辑修订已变化，请刷新后重试。")
	if doc.read_only: return _fail(doc.reason_code, doc.message)
	var checked := _context(doc)
	return checked if not checked.ok else {"ok":true,"document":doc}


func _check_snapshot(doc: Dictionary, snapshot: Dictionary) -> Dictionary:
	if snapshot.layout.is_empty(): return {"ok":true}
	var checked := Geometry.validate(snapshot.layout)
	if not checked.ok: return checked
	if _serialized(checked.layout).to_utf8_buffer().size() > MAX_BYTES: return _fail("layout_limit_exceeded", "布局超过读取字节上限。")
	var bound := _bind(checked.layout, doc.pack_id, doc.pack_root)
	if not bound.ok: return bound
	if _fingerprint(bound.inputs) != _fingerprint(snapshot.inputs): return _fail("layout_inputs_changed", "包、目录或地图来源已变化；请重新预览后应用。")
	return {"ok":true}


func _context(doc: Dictionary) -> Dictionary:
	var owner := _owner(doc.pack_id, doc.pack_root)
	if not owner.ok: return owner
	if owner.pack.metadata.get("_catalog_source_sha", "") != doc.metadata_sha:
		return _fail("pack_revision_changed", "所属资源包元数据已变化，请显式重新载入布局。")
	if not _allowed(doc.path): return _fail("path_not_allowed", "世界布局路径已不在安全资源根中。")
	var sha := _disk_sha(doc.path)
	if not sha.ok: return sha
	if sha.sha != doc.disk_sha:
		doc.disk_conflict = true
		return _fail("layout_conflict", "布局磁盘文件已变化；请显式重新载入，保留当前草稿供检查。")
	doc.disk_conflict = false
	return {"ok":true,"pack":owner.pack}


func _bind(layout: Dictionary, pack_id: String, pack_root: String) -> Dictionary:
	var owner := _owner(pack_id, pack_root)
	if not owner.ok: return owner
	var all := _packs()
	if not all.ok: return all
	var bindings: Array = []; var packs := {}; var maps := {}
	var inputs := {"owner":{"pack_id":owner.pack.id,"pack_root":owner.pack.root,"metadata_sha":owner.pack.metadata._catalog_source_sha},"packs":[],"maps":[]}
	for space: Dictionary in layout.spaces:
		for placement: Dictionary in space.placements:
			var selected: Array = []
			for pack: Dictionary in all.packs:
				if pack.id != placement.pack_id: continue
				if pack.id == owner.pack.id and _key(pack.root) != _key(owner.pack.root): continue
				if pack.id != owner.pack.id and not pack.shared: continue
				if placement.has("pack_version") and placement.pack_version != pack.version: continue
				selected.append(pack)
			if selected.size() != 1:
				return _fail("ambiguous_context" if selected.size() > 1 else "pack_dependency_unavailable", "引用只能来自所属资源包或可唯一选择版本的共享资源包。")
			var pack: Dictionary = selected[0]
			var pack_key := _key(pack.root)
			if not packs.has(pack_key):
				var listing: Dictionary = catalog.list_maps(pack.id, pack.root)
				if not listing.ok: return listing
				if listing.documents.size() != 1: return _fail("ambiguous_context", "编号目录文档不唯一。")
				var state: Dictionary = listing.documents[0]
				if state.read_only: return _fail(state.reason_code, state.message)
				if state.disk_conflict: return _fail("catalog_conflict", "引用的地图编号目录磁盘版本已变化。")
				if state.dirty or str(state.disk_sha).is_empty(): return _fail("catalog_not_persisted", "请先单独保存引用地图的编号目录。")
				packs[pack_key] = {"listing":listing,"state":state,"pack":pack}
				inputs.packs.append({"pack_id":pack.id,"pack_root":pack.root,"pack_version":pack.version,"metadata_sha":pack.metadata._catalog_source_sha,
					"catalog_path":state.path,"catalog_sha":state.disk_sha,"catalog_edit_revision":state.edit_revision,"catalog_document_id":state.document_id})
			var item: Dictionary = packs[pack_key]
			var row := {}
			for found: Dictionary in item.listing.maps:
				if found.map_number == placement.map_number: row = found; break
			if row.is_empty(): return _fail("map_unregistered", "世界布局引用的地图编号未登记。")
			if not str(row.reason_code).is_empty(): return _fail(row.reason_code, row.message)
			if not row.persisted: return _fail("catalog_not_persisted", "引用的地图身份尚未持久化。")
			var map_key := _key(row.path)
			if not maps.has(map_key):
				# The identity and SHA must describe the same bytes, not separate
				# observations around a concurrent map save.
				var identity: Dictionary = catalog._map_identity(row.path)
				if not identity.ok: return identity
				if identity.map_ref != row.map_ref: return _fail("map_revision_changed", "读取期间地图身份已变化。")
				maps[map_key] = identity.source_sha
				inputs.maps.append({"path":row.path,"source_sha":identity.source_sha,"pack_id":pack.id,"map_number":row.map_number,"map_ref":row.map_ref})
			bindings.append({"space_id":space.id,"placement_id":placement.id,"path":row.path,"pack_root":pack.root,"pack_id":pack.id,
				"pack_version":pack.version,"map_number":row.map_number,"map_ref":row.map_ref,"source_sha":maps[map_key],
				"catalog_revision":item.state.disk_sha,"catalog_edit_revision":item.state.edit_revision})
	inputs.packs.sort_custom(func(a: Dictionary, b: Dictionary): return _key(a.pack_root) < _key(b.pack_root))
	inputs.maps.sort_custom(func(a: Dictionary, b: Dictionary): return _key(a.path) < _key(b.path))
	# Observe all source versions again so a scan cannot issue a mixed-version proof.
	var owner_sha := _disk_sha(str(owner.pack.root).path_join("metadata.json"))
	if not owner_sha.ok or owner_sha.sha != inputs.owner.metadata_sha: return _fail("pack_revision_changed", "读取期间所属资源包元数据已变化。")
	for input: Dictionary in inputs.packs:
		var metadata := _disk_sha(str(input.pack_root).path_join("metadata.json"))
		var catalogue := _disk_sha(input.catalog_path)
		if not metadata.ok or metadata.sha != input.metadata_sha: return _fail("pack_revision_changed", "读取期间引用资源包元数据已变化。")
		if not catalogue.ok or catalogue.sha != input.catalog_sha: return _fail("catalog_conflict", "读取期间地图编号目录已变化。")
	for input: Dictionary in inputs.maps:
		var source := _disk_sha(input.path, Catalog.MAX_MAP_BYTES)
		if not source.ok or source.sha != input.source_sha: return _fail("map_revision_changed", "读取期间地图源文件已变化。")
	return {"ok":true,"bindings":bindings,"inputs":inputs}


func _packs(pack_id: String = "", pack_root: String = "") -> Dictionary:
	if not _allowed(root) or not DirAccess.dir_exists_absolute(root): return _fail("pack_unavailable", "外部资源根不可用。")
	var result: Array = []
	for pack: Dictionary in Catalog.ConfinedDiscovery.new(root).packs():
		pack.root = _normal(pack.root)
		if not pack_id.is_empty() and pack.id != pack_id: continue
		if not pack_root.is_empty() and _key(pack.root) != _key(pack_root): continue
		if not pack.metadata.get("id") is String or not _id_ok(pack.metadata.id):
			if not pack_id.is_empty() or not pack_root.is_empty(): return _fail("invalid_pack_identity", "所属资源包需要明确有效的字符串 ID。")
			continue
		if not _allowed(pack.root): continue
		result.append(pack)
	if result.is_empty() and (not pack_id.is_empty() or not pack_root.is_empty()): return _fail("pack_unavailable", "指定资源包不在当前安全目录中。")
	if result.size() > 1 and not pack_id.is_empty() and pack_root.is_empty(): return _fail("ambiguous_context", "资源包存在多个安装版本，请选择明确的包根。")
	return {"ok":true,"packs":result}


func _owner(pack_id: String, pack_root: String) -> Dictionary:
	if not _id_ok(pack_id): return _fail("invalid_pack_identity", "资源包 ID 无效。")
	var selected := _packs(pack_id, pack_root)
	if not selected.ok: return selected
	if selected.packs.size() != 1: return _fail("ambiguous_context", "不能唯一确定世界布局所属资源包。")
	return {"ok":true,"pack":selected.packs[0]}


func _blank(pack: Dictionary, world_key: String) -> Dictionary:
	var id := _document_id(pack, world_key)
	return {"id":id,"pack_id":pack.id,"pack_root":pack.root,"world_key":world_key,"path":str(pack.root).path_join("worlds").path_join(world_key).path_join("world.json"),
		"metadata_sha":pack.metadata.get("_catalog_source_sha", ""),"edit_revision":_revision_seeds.get(id, 0),"disk_sha":"","layout":{},"saved_layout":{},
		"inputs":{},"bindings":[],"diagnostics":[],"undo":[],"redo":[],"dirty":false,"read_only":false,"disk_conflict":false,"reason_code":"","message":""}


func _load_document(pack: Dictionary, world_key: String) -> Dictionary:
	var doc := _blank(pack, world_key)
	var read := _read_layout(doc.path)
	if read.ok and read.layout.world_key != world_key: read = _fail("world_identity_changed", "world.json 中的标识与所属目录不一致。").merged({"sha":read.sha}, true)
	doc.disk_sha = read.get("sha", "")
	if not read.ok:
		doc.read_only = true; doc.reason_code = read.reason_code; doc.message = read.message
		return doc
	doc.layout = read.layout.duplicate(true); doc.saved_layout = read.layout.duplicate(true); doc.diagnostics = read.diagnostics.duplicate(true)
	# Discovery establishes a source baseline as well as a world.json baseline.
	# A later get must not silently adopt a different map version.
	var bound := _bind(doc.layout, doc.pack_id, doc.pack_root)
	if bound.ok:
		doc.inputs = bound.inputs.duplicate(true); doc.bindings = bound.bindings.duplicate(true)
	return doc


func _read_layout(path: String) -> Dictionary:
	if not _allowed(path): return _fail("path_not_allowed", "布局路径不可用。")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _fail("layout_unavailable", "无法读取世界布局。")
	if file.get_length() > MAX_BYTES: file.close(); return _fail("layout_limit_exceeded", "世界布局文件超过读取上限。")
	var bytes := file.get_buffer(file.get_length()); file.close()
	if not _allowed(path): return _fail("path_not_allowed", "读取期间布局路径已变化。")
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	var sha := hash.finish().hex_encode()
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return _fail("invalid_layout", "世界布局不是有效 JSON 对象。").merged({"sha":sha}, true)
	return Geometry.validate(parser.data).merged({"sha":sha}, true)


func _view_state(doc: Dictionary) -> Dictionary:
	var view := _state(doc)
	var context := _context(doc)
	view.disk_conflict = doc.disk_conflict
	if not context.ok:
		view.read_only = true; view.reason_code = context.reason_code; view.message = context.message
	return view


func _state(doc: Dictionary) -> Dictionary:
	return {"document_id":doc.id,"kind":"world_layout","pack_id":doc.pack_id,"pack_root":doc.pack_root,"world_key":doc.world_key,"path":doc.path,
		"edit_revision":doc.edit_revision,"disk_sha":doc.disk_sha,"dirty":_dirty(doc),"undo_count":doc.undo.size(),"redo_count":doc.redo.size(),
		"read_only":doc.read_only,"disk_conflict":doc.disk_conflict,"reason_code":doc.reason_code,"message":doc.message}


func _row(doc: Dictionary, state: Dictionary) -> Dictionary:
	return {"document_id":doc.id,"world_key":doc.world_key,"pack_id":doc.pack_id,"pack_root":doc.pack_root,"path":doc.path,
		"status":"conflict" if state.read_only else ("draft" if str(doc.disk_sha).is_empty() else ("modified" if state.dirty else "saved")),
		"reason_code":state.reason_code,"message":state.message}


func _changed(doc: Dictionary, extra: Dictionary) -> Dictionary:
	doc.dirty = _fingerprint(doc.layout) != _fingerprint(doc.saved_layout)
	return {"ok":true,"document":_state(doc),"layout":doc.layout.duplicate(true),"bindings":doc.bindings.duplicate(true),"diagnostics":doc.diagnostics.duplicate(true),"documents":cached_documents()}.merged(extra, true)


func _snapshot(doc: Dictionary) -> Dictionary:
	return {"layout":doc.layout.duplicate(true),"inputs":doc.inputs.duplicate(true),"bindings":doc.bindings.duplicate(true),"diagnostics":doc.diagnostics.duplicate(true)}


func _restore(doc: Dictionary, snapshot: Dictionary) -> void:
	for field: String in ["layout","inputs","bindings","diagnostics"]: doc[field] = snapshot[field].duplicate(true)


func _push(history: Array, snapshot: Dictionary) -> void:
	history.append(snapshot)
	while history.size() > MAX_HISTORY: history.pop_front()


func _drop_candidates(document_id: String) -> void:
	for id: String in _candidates.keys():
		if _candidates[id].document_id == document_id: _candidates.erase(id); _candidate_order.erase(id)


func _dirty(doc: Dictionary) -> bool:
	return doc.get("dirty", false)


func _document_id(pack: Dictionary, world_key: String) -> String:
	return "layout:" + (str(pack.id)+"\n"+_key(pack.root)+"\n"+world_key).sha256_text().substr(0, 32)


func _path_in_use(path: String) -> bool:
	for doc: Dictionary in _documents.values():
		if _key(doc.path) == _key(path): return true
	return false


func _allowed(path: String) -> bool:
	var project := _key(ProjectSettings.globalize_path("res://"))
	var normalized := _key(path)
	return normalized != project and not normalized.begins_with(project + "/") and Paths.allowed(path, root)


func _disk_sha(path: String, limit: int = MAX_BYTES) -> Dictionary:
	if not _allowed(path): return _fail("path_not_allowed", "引用路径不在安全资源根中。")
	if DirAccess.dir_exists_absolute(path): return _fail("layout_conflict", "预期文件路径已经是文件夹。")
	if not FileAccess.file_exists(path): return {"ok":true,"sha":""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _fail("source_unavailable", "来源文件不可读。")
	var length := file.get_length(); file.close()
	if length > limit: return _fail("layout_limit_exceeded", "来源文件超过读取上限。")
	var sha := FileAccess.get_sha256(path)
	if not _allowed(path) or sha.is_empty(): return _fail("source_unavailable", "来源文件版本不可读取。")
	return {"ok":true,"sha":sha}


func _id_ok(value: String) -> bool:
	return not value.is_empty() and value.length() <= 128 and Location.id_ok(value)


func _world_key_ok(value: String) -> bool:
	if not _id_ok(value): return false
	var upper := value.to_upper()
	return upper not in ["CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9","LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9"]


func _revision_ok(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= 9007199254740991.0 and floor(float(value)) == float(value)


func _normal(value: String) -> String:
	return value.replace("\\", "/").simplify_path().trim_suffix("/")


func _key(value: String) -> String:
	return _normal(value).to_lower() if OS.get_name() == "Windows" else _normal(value)


func _serialized(value: Dictionary) -> String:
	return JSON.stringify(value, "\t", true, true) + "\n"


func _fingerprint(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()


func _fail(code: String, message: String) -> Dictionary:
	return {"ok":false,"reason_code":code,"message":message}
