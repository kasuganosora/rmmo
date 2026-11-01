extends RefCounted
## Stable numeric identities are explicitly registered; discovery never writes.
## One catalogue document owns its own edit history and optimistic save baseline.
const Discovery = preload("res://scripts/world_editor/resource_pack_catalog.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Location = preload("res://scripts/world3d/world_location.gd")
const Address = preload("res://scripts/world3d/world_address.gd")
const Atomic = preload("res://scripts/world3d/atomic_file.gd")
const CATALOG_FILE := "maps.catalog.json"
const MAX_CATALOG_BYTES := 8 * 1024 * 1024
const MAX_MAP_BYTES := 256 * 1024 * 1024
const MAX_MAPS := 10000

## Discovery's virtual metadata reader is confined before opening the file.
## Keep the established pack layouts without reading symlinked metadata first.
class ConfinedDiscovery extends "res://scripts/world_editor/resource_pack_catalog.gd":
	const Policy = preload("res://scripts/world3d/map_paths.gd")
	func _read_metadata(path: String) -> Variant:
		var source := path.path_join("metadata.json")
		var project := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
		var normalized := source.replace("\\", "/").simplify_path().to_lower()
		if normalized.begins_with(project + "/") or not Policy.allowed(source, root): return null
		var file := FileAccess.open(source, FileAccess.READ)
		if file == null: return null
		if file.get_length() > 8 * 1024 * 1024: file.close(); return null
		var bytes := file.get_buffer(file.get_length())
		file.close()
		if not Policy.allowed(source, root): return null
		var parser := JSON.new()
		if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary: return null
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256); hashing.update(bytes)
		parser.data["_catalog_source_sha"] = hashing.finish().hex_encode()
		return parser.data

var root: String
var _documents: Dictionary = {}
var _entries: Dictionary = {}
var _reserved: Dictionary = {}
var _revision_seeds: Dictionary = {}


func _init(content_root: String = "") -> void:
	root = _normal(Paths.external_root() if content_root.is_empty() else content_root)


func list_maps(pack_id: String = "", pack_root: String = "") -> Dictionary:
	var selected := _select_packs(pack_id, pack_root)
	if not selected.ok: return selected
	var maps: Array = []
	var documents: Array = []
	var packs: Array = []
	var listed_documents: Dictionary = {}
	for pack: Dictionary in selected.packs:
		var doc := _document(pack)
		doc.disk_conflict = not _allowed(doc.path) or _disk_sha(doc.path) != doc.disk_sha
		var view_doc: Dictionary = doc
		if doc.pack_id != pack.id or doc.metadata_sha != pack.metadata.get("_catalog_source_sha", ""):
			view_doc = doc.duplicate(true)
			view_doc.read_only = true
			view_doc.reason_code = "pack_identity_changed" if doc.pack_id != pack.id else "pack_revision_changed"
			view_doc.message = "资源包元数据已变化，请先重新载入目录，不能重绑定旧目录身份。"
		var found: Array = Discovery.new(root).maps_in(pack)
		if found.size() > MAX_MAPS: return _fail("catalog_limit", "地图数量超出目录上限。")
		var seen: Dictionary = {}
		var identities: Dictionary = {}
		var pack_rows: Array = []
		for source: Dictionary in found:
			var path := _normal(str(source.path))
			if seen.has(_path_key(path)): continue
			seen[_path_key(path)] = true
			var row := _map_row(pack, source, view_doc)
			pack_rows.append(row)
			if row.reason_code.is_empty():
				var refs: Array = identities.get(row.map_ref, [])
				refs.append(row)
				identities[row.map_ref] = refs
		for reference: String in identities:
			if identities[reference].size() < 2: continue
			for row: Dictionary in identities[reference]:
				row.status = "conflict"
				row.reason_code = "map_identity_conflict"
				row.message = "多个入口具有相同 map_ref；请先解决地图身份冲突。"
		for row: Dictionary in pack_rows:
			_entries[row.entry_id] = row.duplicate(true)
			maps.append(row)
		for record: Dictionary in doc.maps:
			var path := _record_path(pack, record)
			if not path.is_empty() and not seen.has(_path_key(path)):
				maps.append({"entry_id":"", "document_id":doc.id, "name":record.path,
					"path":path, "pack_id":pack.id, "pack_root":pack.root,
					"map_ref":record.map_ref, "map_number":record.map_number,
					"status":"missing", "suggested_number":"", "reason_code":"map_unavailable",
					"message":"登记的地图入口不在当前地图目录中。", "persisted":_persisted(view_doc, record)})
		doc.discovered_rows = pack_rows.duplicate(true)
		documents.append(_document_state(view_doc))
		listed_documents[doc.id] = true
		packs.append({"id":pack.id,"name":pack.name,"root":pack.root,"version":pack.version,"shared":pack.shared,"document_id":doc.id})
	for doc: Dictionary in _documents.values():
		if listed_documents.has(doc.id) or not _dirty(doc): continue
		if not pack_id.is_empty() and doc.pack_id != pack_id: continue
		if not pack_root.is_empty() and _path_key(doc.pack_root) != _path_key(pack_root): continue
		documents.append(_document_state(doc).merged({"read_only":true,"reason_code":"pack_unavailable","message":"所属资源包不可用；可显式放弃此未保存目录。"}, true))
		maps.append({"entry_id":"","document_id":doc.id,"name":"未保存目录 · " + str(doc.pack_id),
			"path":doc.path,"pack_id":doc.pack_id,"pack_root":doc.pack_root,"map_ref":"","map_number":"",
			"status":"missing","suggested_number":"","reason_code":"pack_unavailable","message":"所属资源包不可用；放弃只清理内存草稿。","persisted":false})
	maps.sort_custom(func(a: Dictionary, b: Dictionary): return (str(a.pack_id) + "/" + str(a.path)).naturalnocasecmp_to(str(b.pack_id) + "/" + str(b.path)) < 0)
	return {"ok":true,"packs":packs,"maps":maps,"documents":documents}


## Cheap status for editor_state/close guards. No scans or source-file reads.
func cached_documents() -> Array:
	var result: Array = []
	for doc: Dictionary in _documents.values(): result.append(_document_state(doc))
	return result


func register_map(entry_id: String, map_number: String, expected_edit_revision: int) -> Dictionary:
	if not _entries.has(entry_id): return _fail("unknown_map_entry", "请先从地图目录选择有效入口。")
	var entry: Dictionary = _entries[entry_id]
	var check := _editable(entry.document_id, expected_edit_revision)
	if not check.ok: return check
	var doc: Dictionary = check.document
	var current := list_maps(str(doc.pack_id), str(doc.pack_root))
	if not current.ok: return current
	var refreshed: Dictionary = {}
	for row: Dictionary in current.maps:
		if row.entry_id == entry_id: refreshed = row; break
	if refreshed.is_empty(): return _fail("map_unavailable", "地图入口已经移动或删除。")
	if not str(refreshed.reason_code).is_empty(): return _fail(refreshed.reason_code, refreshed.message)
	var number := Address.normalize_number(map_number)
	if not number.ok: return number
	if not str(refreshed.map_number).is_empty(): return _fail("map_already_registered", "地图已登记，不能用普通登记操作修改稳定编号。")
	if not str(refreshed.suggested_number).is_empty() and refreshed.suggested_number != number.map_number:
		return _fail("filename_number_conflict", "Map 数字文件名与拟登记编号不一致。")
	if _used_number(doc, number.map_number): return _fail("map_number_conflict", "编号已经登记、保留或成为墓碑，不能重复使用。")
	if _reserved[doc.id].size() >= MAX_MAPS: return _fail("catalog_limit", "目录编号与本会话保留编号已达到上限。")
	var identity := _map_identity(refreshed.path)
	if not identity.ok: return identity
	if identity.map_ref != refreshed.map_ref: return _fail("map_revision_changed", "地图身份已变化，请刷新目录。")
	var record := _make_record(doc.pack, refreshed.path, number.map_number, identity.map_ref)
	if record.is_empty(): return _fail("path_not_allowed", "地图入口超出所属资源包或共享地图根。")
	for existing: Dictionary in doc.maps:
		if existing.map_ref == record.map_ref or _path_key(_record_path(doc.pack, existing)) == _path_key(refreshed.path):
			return _fail("map_identity_conflict", "该地图身份或入口已经登记。")
	var prospective := _edit_snapshot(doc)
	prospective.pack_id = doc.pack_id
	prospective.maps.append(record)
	if not _payload_fits(prospective): return _fail("catalog_limit", "登记后目录会超出可读取的数量或字节上限。")
	doc.undo.append(_edit_snapshot(doc))
	doc.redo.clear()
	doc.maps.append(record)
	_reserved[doc.id][number.map_number] = true
	doc.edit_revision += 1
	return _changed(doc, {"map_number":number.map_number,"map_ref":record.map_ref,"entry_id":entry_id})


func undo_catalog(document_id: String, expected_edit_revision: int) -> Dictionary:
	return _history(document_id, expected_edit_revision, false)


func redo_catalog(document_id: String, expected_edit_revision: int) -> Dictionary:
	return _history(document_id, expected_edit_revision, true)


func discard_catalog(document_id: String, expected_edit_revision: int) -> Dictionary:
	if not _documents.has(document_id): return _fail("unknown_document", "目录文档不存在。")
	var previous: Dictionary = _documents[document_id]
	if expected_edit_revision != previous.edit_revision: return _fail("candidate_stale", "目录编辑修订已变化。")
	var checked := _select_packs(previous.pack_id, previous.pack_root)
	if not checked.ok:
		if checked.reason_code in ["pack_unavailable", "path_not_allowed"]: return _abandon_document(previous)
		return checked
	var fresh := _read_document(checked.packs[0])
	if fresh.read_only:
		# Explicit discard may release an unsaved draft even when the external
		# file is malformed. Keep a read-only last-saved view; never overwrite it.
		fresh.maps = previous.saved_payload.get("maps", []).duplicate(true)
		fresh.tombstones = previous.saved_payload.get("tombstones", []).duplicate()
		fresh.saved_payload = _payload(fresh)
	fresh.edit_revision = previous.edit_revision + 1
	_documents[document_id] = fresh
	_reserve_saved(fresh)
	return _changed(fresh, {"discarded":true,"session_reservations_retained":true})


func _abandon_document(previous: Dictionary) -> Dictionary:
	var id: String = previous.id
	var state := _document_state(previous)
	state.dirty = false; state.undo_count = 0; state.redo_count = 0
	state.edit_revision = int(previous.edit_revision) + 1
	state.read_only = true; state.reason_code = "pack_unavailable"
	_revision_seeds[id] = state.edit_revision
	_documents.erase(id)
	for key: String in _entries.keys():
		if _entries[key].document_id == id: _entries.erase(key)
	return {"ok":true,"discarded":true,"abandoned":true,"session_reservations_retained":true,"document":state,"documents":cached_documents()}


func save_catalog(document_id: String, expected_edit_revision: int, expected_disk_sha: String) -> Dictionary:
	var check := _editable(document_id, expected_edit_revision)
	if not check.ok: return check
	var doc: Dictionary = check.document
	if expected_disk_sha != doc.disk_sha: return _fail("catalog_conflict", "调用者的目录磁盘基线已过期。")
	var selected := _select_packs(doc.pack_id, doc.pack_root)
	if not selected.ok: return selected
	var pack: Dictionary = selected.packs[0]
	if pack.metadata.get("_catalog_source_sha", "") != doc.metadata_sha: return _fail("pack_revision_changed", "资源包元数据已变化，不能保存旧目录文档。")
	if not _payload_fits(doc): return _fail("catalog_limit", "目录超出可读取的数量或字节上限，未写入文件。")
	var validated := _validate_sources(pack, doc.maps)
	if not validated.ok: return validated
	var destination: String = doc.path
	var lock_path := destination + ".save-lock"
	var staged := destination + ".catalog.%d.%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	for path: String in [destination, lock_path, staged, destination + ".previous"]:
		if not _allowed(path): return _fail("path_not_allowed", "目录保存路径不在安全资源根中。")
	if FileAccess.file_exists(staged) or DirAccess.dir_exists_absolute(staged): return _fail("catalog_busy", "目录暂存文件已存在。")
	if DirAccess.make_dir_absolute(lock_path) != OK: return _fail("catalog_busy", "另一个保存操作持有目录锁。")
	var result := _save_locked(doc, pack, staged, destination, expected_disk_sha)
	if _allowed(staged) and FileAccess.file_exists(staged): DirAccess.remove_absolute(staged)
	if _allowed(lock_path): DirAccess.remove_absolute(lock_path)
	return result


func resolve_address(value: String, pack_root: String = "") -> Dictionary:
	var parsed := Address.parse(value)
	if not parsed.ok: return parsed
	var selected := _select_packs(parsed.pack_id, pack_root, true)
	if not selected.ok: return selected
	var listing := list_maps(parsed.pack_id, str(selected.packs[0].root))
	if not listing.ok: return listing
	var doc: Dictionary = _documents[listing.documents[0].document_id]
	var view_doc: Dictionary = listing.documents[0]
	if view_doc.read_only: return _fail(view_doc.reason_code, view_doc.message)
	if doc.disk_conflict: return _fail("catalog_conflict", "目录磁盘版本已变化，请先重新载入目录。")
	for row: Dictionary in listing.maps:
		if row.map_number != parsed.map_number: continue
		if not str(row.reason_code).is_empty(): return _fail(row.reason_code, row.message)
		return parsed.merged({"map_ref":row.map_ref,"path":row.path,"entry_id":row.entry_id,
			"document_id":row.document_id,"pack_root":row.pack_root,"persisted":row.persisted,
			"catalog_dirty":_dirty(doc),"catalog_revision":doc.disk_sha,"edit_revision":doc.edit_revision,
			"validation":"resolved_only","surface_id":null,"world_position_m":null,
			"can_transfer":false,"message":"已解析地图内位置；未执行表面、世界布局或入场验证。"})
	return _fail("map_unregistered", "数字编号未登记，不能据文件发现顺序推断地图身份。")


func format_map_address(path: String, position_m: Array, pack_root: String = "") -> Dictionary:
	var listing := list_maps("", pack_root)
	if not listing.ok: return listing
	var candidates: Array = []
	for row: Dictionary in listing.maps:
		if _path_key(str(row.path)) == _path_key(path): candidates.append(row)
	if candidates.size() != 1: return _fail("ambiguous_context" if candidates.size() > 1 else "map_unavailable", "不能唯一确定地图所属资源包。")
	var row: Dictionary = candidates[0]
	if not str(row.reason_code).is_empty(): return _fail(row.reason_code, row.message)
	if str(row.map_number).is_empty(): return _fail("map_unregistered", "请先为当前地图显式登记稳定编号。")
	var formatted := Address.format_address(row.pack_id, row.map_number, position_m)
	if not formatted.ok: return formatted
	return resolve_address(formatted.address, row.pack_root)


func _save_locked(doc: Dictionary, pack: Dictionary, staged: String, destination: String, expected: String) -> Dictionary:
	var metadata_path: String = str(pack.root).path_join("metadata.json")
	if not _allowed(metadata_path) or FileAccess.get_sha256(metadata_path) != doc.metadata_sha: return _fail("pack_revision_changed", "保存期间资源包元数据已变化。")
	if not _allowed(destination) or _disk_sha(destination) != expected:
		doc.disk_conflict = true
		return _fail("catalog_conflict", "目录磁盘文件已被其他会话修改；保留未保存编辑。")
	if DirAccess.dir_exists_absolute(destination): return _fail("catalog_conflict", "目录目标是文件夹，不能覆盖。")
	var validated := _validate_sources(pack, doc.maps)
	if not validated.ok: return validated
	var payload := _payload(doc)
	var serialized := JSON.stringify(payload, "\t") + "\n"
	if not _payload_fits(doc) or serialized.to_utf8_buffer().size() > MAX_CATALOG_BYTES: return _fail("catalog_limit", "目录暂存数据超过读取上限。")
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null: return _fail("catalog_write_failed", "不能创建目录暂存文件。")
	file.store_string(serialized)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return _fail("catalog_write_failed", "目录暂存写入失败。")
	if FileAccess.get_file_as_string(staged) != serialized: return _fail("catalog_write_failed", "目录暂存校验失败。")
	if not _allowed(destination) or not _allowed(staged) or _disk_sha(destination) != expected:
		doc.disk_conflict = true
		return _fail("catalog_conflict", "保存期间目录磁盘基线发生变化。")
	if not _allowed(metadata_path) or FileAccess.get_sha256(metadata_path) != doc.metadata_sha: return _fail("pack_revision_changed", "发布前资源包元数据已变化。")
	error = Atomic.publish_new(staged, destination) if expected.is_empty() else Atomic.publish(staged, destination)
	if error != OK: return _fail("catalog_write_failed", "目录原子发布失败；保留编辑和原磁盘文件。")
	doc.disk_sha = FileAccess.get_sha256(destination)
	doc.saved_payload = payload.duplicate(true)
	doc.disk_conflict = false
	return _changed(doc, {"saved":true,"path":destination,"disk_sha":doc.disk_sha})


func _history(document_id: String, expected_edit_revision: int, redo: bool) -> Dictionary:
	var check := _editable(document_id, expected_edit_revision)
	if not check.ok: return check
	var doc: Dictionary = check.document
	var source: Array = doc.redo if redo else doc.undo
	var target: Array = doc.undo if redo else doc.redo
	if source.is_empty(): return _fail("history_empty", "没有可重做的目录操作。" if redo else "没有可撤销的目录操作。")
	var restored: Dictionary = source.back().duplicate(true)
	for number: String in _reserved[doc.id]:
		var active := false
		for record: Dictionary in restored.maps:
			if record.map_number == number: active = true; break
		if not active and not restored.tombstones.has(number): restored.tombstones.append(number)
	for record: Dictionary in restored.maps: restored.tombstones.erase(record.map_number)
	restored.pack_id = doc.pack_id
	if not _payload_fits(restored): return _fail("catalog_limit", "撤销或重做结果超过目录读取上限。")
	target.append(_edit_snapshot(doc))
	source.pop_back()
	doc.maps = restored.maps
	doc.tombstones = restored.tombstones
	doc.edit_revision += 1
	return _changed(doc, {"redone":redo,"undone":not redo})


func _editable(document_id: String, expected_edit_revision: int) -> Dictionary:
	if not _documents.has(document_id): return _fail("unknown_document", "目录文档不存在，请先读取地图目录。")
	var doc: Dictionary = _documents[document_id]
	if doc.read_only: return _fail(doc.reason_code, doc.message)
	if expected_edit_revision != doc.edit_revision: return _fail("candidate_stale", "目录编辑修订已变化，请刷新后重试。")
	return {"ok":true,"document":doc}


func _select_packs(pack_id: String, pack_root: String, unique: bool = false) -> Dictionary:
	if not _allowed(root) or not DirAccess.dir_exists_absolute(root): return _fail("path_not_allowed", "外部资源根不可用。")
	var selected: Array = []
	for pack: Dictionary in ConfinedDiscovery.new(root).packs():
		pack.root = _normal(str(pack.root))
		if not _allowed(pack.root) or not _allowed(str(pack.root).path_join("metadata.json")): continue
		if not pack_id.is_empty() and pack.id != pack_id: continue
		if not pack_root.is_empty() and _path_key(pack.root) != _path_key(pack_root): continue
		pack.identity_valid = pack.metadata.get("id") is String and _strict_id(str(pack.metadata.get("id", "")))
		selected.append(pack)
	if selected.is_empty() and (not pack_id.is_empty() or not pack_root.is_empty()): return _fail("pack_unavailable", "指定资源包不存在或不在允许的资源根中。")
	if unique and selected.size() != 1: return _fail("ambiguous_context", "发现同一包 ID 的多个安装版本，请指定目录中已发现的 pack_root。")
	return {"ok":true,"packs":selected}


func _document(pack: Dictionary) -> Dictionary:
	var id := _document_id(pack.root, pack.id)
	if not _documents.has(id):
		_documents[id] = _read_document(pack)
		if not _reserved.has(id): _reserved[id] = {}
		_reserve_saved(_documents[id])
	return _documents[id]


func _read_document(pack: Dictionary) -> Dictionary:
	var path := str(pack.root).path_join(CATALOG_FILE)
	var id := _document_id(pack.root, pack.id)
	var doc: Dictionary = {"id":id,"pack_id":pack.id,"pack_root":pack.root,"pack":pack,
		"path":path,"edit_revision":_revision_seeds.get(id, 0),"disk_sha":"","maps":[],"tombstones":[],"undo":[],"redo":[],
		"read_only":false,"reason_code":"","message":"","disk_conflict":false,"dirty":false,"saved_payload":{},
		"metadata_sha":pack.metadata.get("_catalog_source_sha", "")}
	if not pack.get("identity_valid", false): return _invalid_document(doc, "invalid_pack_identity", "稳定编号要求 metadata.id 为非空 ASCII 身份字符串，不能由目录名称或数字字段推断。")
	if not _allowed(path) or DirAccess.dir_exists_absolute(path): return _invalid_document(doc, "path_not_allowed", "地图目录路径不可用。")
	if FileAccess.file_exists(path):
		var raw := _read_json(path, MAX_CATALOG_BYTES)
		if not raw.ok: return _invalid_document(doc, raw.reason_code, raw.message)
		doc.disk_sha = raw.sha
		var parsed: Dictionary = raw.data
		if parsed.get("schema_version") != 1 or parsed.get("pack_id") != pack.id or not parsed.get("maps") is Array or not parsed.get("tombstones", []) is Array:
			return _invalid_document(doc, "catalog_invalid", "地图目录版本、包身份或字段格式无效。")
		if parsed.maps.size() > MAX_MAPS or parsed.get("tombstones", []).size() > MAX_MAPS:
			return _invalid_document(doc, "catalog_limit", "地图目录数量超出上限。")
		var numbers: Dictionary = {}
		var paths: Dictionary = {}
		var refs: Dictionary = {}
		for value: Variant in parsed.maps:
			if not value is Dictionary: return _invalid_document(doc, "catalog_invalid", "地图目录条目必须为对象。")
			var record: Dictionary = value
			for field: String in ["map_number", "map_ref", "path", "path_scope"]:
				if not record.get(field) is String: return _invalid_document(doc, "catalog_invalid", "地图目录条目缺少有效字符串字段。")
			var number := Address.normalize_number(record.map_number)
			var resolved := _record_path(pack, record)
			if not number.ok or number.map_number != record.map_number or not _strict_ref(record.map_ref) or resolved.is_empty():
				return _invalid_document(doc, "catalog_invalid", "地图编号、引用或受约束路径无效。")
			if numbers.has(record.map_number) or paths.has(_path_key(resolved)) or refs.has(record.map_ref):
				return _invalid_document(doc, "map_identity_conflict", "目录包含重复编号、地图引用或路径。")
			numbers[record.map_number] = true; paths[_path_key(resolved)] = true; refs[record.map_ref] = true
			doc.maps.append({"map_number":record.map_number,"map_ref":record.map_ref,"path":record.path,"path_scope":record.path_scope})
		for value: Variant in parsed.get("tombstones", []):
			if not value is String: return _invalid_document(doc, "catalog_invalid", "墓碑编号必须为字符串。")
			var number := Address.normalize_number(value)
			if not number.ok or number.map_number != value or numbers.has(value): return _invalid_document(doc, "catalog_invalid", "墓碑编号重复、非法或与活动地图冲突。")
			numbers[value] = true; doc.tombstones.append(value)
	doc.saved_payload = _payload(doc)
	return doc


func _map_row(pack: Dictionary, source: Dictionary, doc: Dictionary) -> Dictionary:
	var path := _normal(str(source.path))
	var identity := _map_identity(path)
	var row: Dictionary = {"entry_id":"map:" + str(doc.id + "\n" + path).sha256_text(),"document_id":doc.id,
		"name":source.name,"path":path,"pack_id":pack.id,"pack_root":pack.root,"map_ref":identity.get("map_ref", ""),
		"map_number":"","status":"unregistered","suggested_number":_filename_number(path),"reason_code":"","message":"","persisted":false}
	if doc.read_only:
		row.status = "catalog_invalid"; row.reason_code = doc.reason_code; row.message = doc.message
	elif not identity.ok:
		row.status = "invalid"; row.reason_code = identity.reason_code; row.message = identity.message
	elif _invalid_filename_number(path):
		row.status = "conflict"; row.reason_code = "filename_number_conflict"; row.message = "地图文件名中的数字超出稳定编号范围。"
	for record: Dictionary in doc.maps:
		if _path_key(_record_path(pack, record)) != _path_key(path): continue
		row.map_number = record.map_number
		row.persisted = _persisted(doc, record)
		if row.reason_code.is_empty():
			if identity.map_ref != record.map_ref:
				row.status = "conflict"; row.reason_code = "map_revision_changed"; row.message = "地图作者引用与目录登记不一致。"
			elif not row.suggested_number.is_empty() and row.suggested_number != record.map_number:
				row.status = "conflict"; row.reason_code = "filename_number_conflict"; row.message = "地图文件名数字与稳定编号冲突。"
			else: row.status = "registered"
	return row


func _map_identity(path: String) -> Dictionary:
	var parsed := _read_json(path, MAX_MAP_BYTES)
	if not parsed.ok: return parsed
	var data: Dictionary = parsed.data
	if not data.get("nodes") is Array or not data.get("scenes") is Array: return _fail("invalid_map_identity", "地图缺少 glTF 场景根信息。")
	var nodes: Array = data.nodes
	var scenes: Array = data.scenes
	var scene_value: Variant = data.get("scene", 0)
	if not (scene_value is int or scene_value is float) or not is_finite(float(scene_value)) or float(scene_value) != floorf(float(scene_value)):
		return _fail("invalid_map_identity", "地图默认场景编号无效。")
	var scene_index := int(scene_value)
	if scene_index < 0 or scene_index >= scenes.size() or not scenes[scene_index] is Dictionary or not scenes[scene_index].get("nodes") is Array:
		return _fail("invalid_map_identity", "地图默认场景不存在。")
	var references: Array[String] = []
	for value: Variant in scenes[scene_index].nodes:
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)): return _fail("invalid_map_identity", "地图根节点索引无效。")
		var index := int(value)
		if index < 0 or index >= nodes.size() or not nodes[index] is Dictionary: return _fail("invalid_map_identity", "地图根节点不存在。")
		var extras: Variant = nodes[index].get("extras", {})
		if not extras is Dictionary or not extras.has("map_ref"): continue
		if not extras.map_ref is String or not _strict_ref(extras.map_ref): return _fail("invalid_map_identity", "地图作者 map_ref 无效。")
		references.append(extras.map_ref)
	if references.size() != 1: return _fail("invalid_map_identity", "地图必须有唯一的作者根 map_ref；不能用路径哈希替代稳定编号。")
	return {"ok":true,"map_ref":references[0],"source_sha":parsed.sha}


func _validate_sources(pack: Dictionary, records: Array) -> Dictionary:
	for record: Dictionary in records:
		var path := _record_path(pack, record)
		if path.is_empty(): return _fail("path_not_allowed", "登记地图路径不再有效。")
		var identity := _map_identity(path)
		if not identity.ok: return identity
		if identity.map_ref != record.map_ref: return _fail("map_revision_changed", "地图作者身份发生变化，目录未保存。")
		var filename_number := _filename_number(path)
		if _invalid_filename_number(path): return _fail("filename_number_conflict", "地图文件名数字超出稳定编号范围。")
		if not filename_number.is_empty() and filename_number != record.map_number: return _fail("filename_number_conflict", "文件名编号与登记身份不一致。")
	return {"ok":true}


func _read_json(path: String, limit: int) -> Dictionary:
	if not _allowed(path): return _fail("path_not_allowed", "文件路径不在允许的外部资源根中。")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _fail("file_unavailable", "不能读取地图或目录文件。")
	if file.get_length() > limit: file.close(); return _fail("catalog_limit", "地图或目录文件超出读取上限。")
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if not _allowed(path): return _fail("path_not_allowed", "读取期间资源路径已变化。")
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary: return _fail("catalog_invalid", "地图或目录不是有效 JSON 对象。")
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256); hashing.update(bytes)
	return {"ok":true,"data":parser.data,"sha":hashing.finish().hex_encode()}


func _make_record(pack: Dictionary, path: String, number: String, reference: String) -> Dictionary:
	var base: String = _normal(pack.root)
	var scope := "pack"
	if not _path_key(path).begins_with(_path_key(base) + "/"):
		base = root.path_join("maps"); scope = "shared"
		if not pack.shared or not _path_key(path).begins_with(_path_key(base) + "/"): return {}
	return {"map_number":number,"map_ref":reference,"path":path.substr(base.length() + 1),"path_scope":scope}


func _record_path(pack: Dictionary, record: Dictionary) -> String:
	var relative: String = record.get("path", "")
	if not _relative_ok(relative): return ""
	var scope: String = record.get("path_scope", "")
	var base: String = pack.root
	if scope == "shared":
		if not pack.shared: return ""
		base = root.path_join("maps")
	elif scope != "pack": return ""
	var result := _normal(base.path_join(relative))
	return result if _allowed(result) else ""


func _relative_ok(value: String) -> bool:
	if value.is_empty() or value.length() > 2048 or value.is_absolute_path() or value.contains(":") or value.contains("\\") or value.get_extension().to_lower() != "gltf": return false
	for part: String in value.split("/", true):
		if part.is_empty() or part == "." or part == "..": return false
	for index in value.length():
		if value.unicode_at(index) == 0: return false
	return true


func _filename_number(path: String) -> String:
	var expression := RegEx.new()
	expression.compile("^Map([0-9]+)\\.gltf$")
	var matched := expression.search(path.get_file())
	if matched == null: return ""
	var result := Address.normalize_number(matched.get_string(1))
	return str(result.get("map_number", "")) if result.ok else ""


func _invalid_filename_number(path: String) -> bool:
	var expression := RegEx.new()
	expression.compile("^Map([0-9]+)\\.gltf$")
	var matched := expression.search(path.get_file())
	return matched != null and not Address.normalize_number(matched.get_string(1)).ok


func _payload(doc: Dictionary) -> Dictionary:
	var maps: Array = doc.maps.duplicate(true)
	maps.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.map_number).length() < str(b.map_number).length() if str(a.map_number).length() != str(b.map_number).length() else str(a.map_number) < str(b.map_number))
	var tombstones: Array = doc.tombstones.duplicate()
	tombstones.sort()
	return {"schema_version":1,"pack_id":doc.pack_id,"maps":maps,"tombstones":tombstones}


func _payload_fits(doc: Dictionary) -> bool:
	if doc.maps.size() > MAX_MAPS or doc.tombstones.size() > MAX_MAPS: return false
	return (JSON.stringify(_payload(doc), "\t") + "\n").to_utf8_buffer().size() <= MAX_CATALOG_BYTES


func _edit_snapshot(doc: Dictionary) -> Dictionary:
	return {"maps":doc.maps.duplicate(true),"tombstones":doc.tombstones.duplicate()}


func _dirty(doc: Dictionary) -> bool:
	return bool(doc.get("dirty", false))


func _document_state(doc: Dictionary) -> Dictionary:
	return {"document_id":doc.id,"pack_id":doc.pack_id,"pack_root":doc.pack_root,"path":doc.path,
		"edit_revision":doc.edit_revision,"disk_sha":doc.disk_sha,"dirty":_dirty(doc),"undo_count":doc.undo.size(),
		"redo_count":doc.redo.size(),"read_only":doc.read_only,"reason_code":doc.reason_code,"message":doc.message,
		"disk_conflict":doc.disk_conflict,"session_reserved_count":_reserved.get(doc.id, {}).size()}


func _changed(doc: Dictionary, extra: Dictionary = {}) -> Dictionary:
	doc.dirty = not doc.read_only and _payload(doc) != doc.saved_payload
	return {"ok":true,"document":_document_state(doc),"documents":cached_documents()}.merged(extra)


func _persisted(doc: Dictionary, record: Dictionary) -> bool:
	return not doc.disk_conflict and not doc.read_only and doc.saved_payload.get("maps", []).has(record)


func _used_number(doc: Dictionary, number: String) -> bool:
	if _reserved.get(doc.id, {}).has(number): return true
	for record: Dictionary in doc.maps:
		if record.map_number == number: return true
	return doc.tombstones.has(number)


func _reserve_saved(doc: Dictionary) -> void:
	if not _reserved.has(doc.id): _reserved[doc.id] = {}
	for record: Dictionary in doc.maps: _reserved[doc.id][record.map_number] = true
	for number: String in doc.tombstones: _reserved[doc.id][number] = true


func _invalid_document(doc: Dictionary, reason: String, message: String) -> Dictionary:
	doc.read_only = true; doc.reason_code = reason; doc.message = message
	doc.maps.clear(); doc.tombstones.clear()
	return doc


func _allowed(path: String) -> bool:
	var project := _normal(ProjectSettings.globalize_path("res://"))
	var key := _path_key(path)
	return key != _path_key(project) and not key.begins_with(_path_key(project) + "/") and Paths.allowed(path, root)


func _disk_sha(path: String) -> String:
	return FileAccess.get_sha256(path) if _allowed(path) and FileAccess.file_exists(path) else ""


static func _strict_id(value: String) -> bool:
	return value.length() <= 128 and Location.id_ok(value)


static func _strict_ref(value: String) -> bool:
	var parts := value.split("/", true)
	return parts.size() == 2 and _strict_id(parts[0]) and _strict_id(parts[1])


static func _normal(value: String) -> String:
	return value.replace("\\", "/").simplify_path().trim_suffix("/")


static func _path_key(value: String) -> String:
	var path := _normal(value)
	return path.to_lower() if OS.get_name() == "Windows" else path


static func _document_id(path: String, pack_id: String) -> String:
	return "catalog:" + (pack_id + "\n" + _path_key(path)).sha256_text()


static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok":false,"reason_code":reason,"message":message}
