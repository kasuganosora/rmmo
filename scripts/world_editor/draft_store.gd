extends RefCounted
## A bounded header + checksummed JSON snapshot; never exports or replaces a map.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Atomic = preload("res://scripts/world3d/atomic_file.gd")
const MAX_BYTES := 33554432
const MAX_HEADER := 16384
var directory: String
var session_id := Crypto.new().generate_random_bytes(16).hex_encode()
var write_fault: Callable # Fault injection only; production leaves empty.

func _init(root: String = "") -> void:
	directory = root if not root.is_empty() else Paths.cache_directory("editor_recovery")

static func fail(message: String) -> Dictionary: return {"ok": false, "error": message}

static func canonical(path: String) -> String:
	return path.replace("\\", "/").simplify_path()

func own_id(map_path: String) -> String:
	var key := canonical(map_path)
	if OS.get_name() == "Windows": key = key.to_lower()
	return key.sha256_text() + "_" + session_id

func file_for(id: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{64}_[0-9a-f]{32}$")
	if pattern.search(id) == null: return ""
	var path := directory.path_join(id + ".draft")
	return path if Paths.allowed(path) and Paths.allowed(path + ".previous") else ""

func write(map_path: String, doc) -> Dictionary:
	map_path = canonical(map_path)
	if not Paths.allowed(map_path) or map_path.get_extension().to_lower() != "gltf": return fail("草稿地图必须位于工程外内容目录")
	var state: Dictionary = doc.recovery_snapshot()
	# A never-saved document still expects an absent destination on recovery.
	state.disk_path = map_path
	var issue := validate(state)
	if not issue.is_empty(): return fail(issue)
	var body := JSON.stringify(state, "", true, true)
	if body.to_utf8_buffer().size() > MAX_BYTES - MAX_HEADER: return fail("草稿超过 32 MiB，未写入")
	var id := own_id(map_path)
	var path := file_for(id)
	if path.is_empty(): return fail("草稿目录不可用或包含链接")
	var previous := header(id)
	if previous.ok and previous.header.checksum == body.sha256_text() and read(id).ok:
		return {"ok": true, "draft_id": id, "unchanged": true, "saved_at": previous.header.saved_at}
	var metadata := {"format": "rmmo_editor_draft", "version": 1, "draft_id": id, "map_path": map_path, "saved_at": Time.get_unix_time_from_system(), "object_count": doc.records.size(), "checksum": body.sha256_text(), "source_signature": doc._disk_signature}
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK: return fail("无法创建草稿目录：" + error_string(err))
	var temporary := path + ".tmp_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return fail("无法写入草稿：" + error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(metadata) + "\n" + body)
	file.flush()
	err = file.get_error()
	file.close()
	if write_fault.is_valid() and write_fault.call("before_publish"): err = ERR_FILE_CANT_WRITE
	if err == OK: err = Atomic.publish(temporary, path)
	if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
	if err != OK: return fail("草稿保存失败，上一份草稿仍保留：" + error_string(err))
	return {"ok": true, "draft_id": id, "saved_at": metadata.saved_at}

func header(id: String) -> Dictionary:
	var path := file_for(id)
	if path.is_empty() or not FileAccess.file_exists(path): return fail("草稿不存在或路径无效")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return fail("草稿不可读或过大")
	var bytes := file.get_buffer(mini(MAX_HEADER, file.get_length()))
	file.close()
	var newline := bytes.find(10)
	if newline < 0: return fail("草稿头损坏")
	var value: Variant = JSON.parse_string(bytes.slice(0, newline).get_string_from_utf8())
	if not value is Dictionary or value.get("format") != "rmmo_editor_draft" or value.get("version") != 1 or value.get("draft_id") != id: return fail("草稿格式不支持")
	if not value.get("map_path") is String or not Paths.allowed(value.map_path) or value.map_path.get_extension().to_lower() != "gltf": return fail("草稿地图路径无效")
	for field in ["checksum", "source_signature"]:
		if not value.get(field) is String: return fail("草稿签名损坏")
	for field in ["saved_at", "object_count"]:
		if not (value.get(field) is int or value.get(field) is float) or not is_finite(float(value[field])): return fail("草稿信息损坏")
	return {"ok": true, "header": value, "body_offset": newline + 1}

func list_drafts(offset: int = 0, limit: int = 50) -> Dictionary:
	if not Paths.allowed(directory): return fail("草稿目录不可用")
	var folder := DirAccess.open(directory)
	if folder == null: return {"ok": true, "drafts": [], "total": 0}
	var files: Array = []
	for file in folder.get_files():
		if file.ends_with(".draft") and not file_for(file.trim_suffix(".draft")).is_empty(): files.append(file)
	files.sort_custom(func(a, b): return FileAccess.get_modified_time(directory.path_join(a)) > FileAccess.get_modified_time(directory.path_join(b)))
	var rows: Array = []
	for file in files.slice(offset, mini(offset + limit, files.size())):
		var id: String = file.trim_suffix(".draft")
		var result := header(id)
		if not result.ok: rows.append({"draft_id": id, "recoverable": false, "error": result.error}); continue
		var item: Dictionary = result.header.duplicate()
		item.erase("format"); item.erase("version"); item.erase("checksum")
		item.recoverable = true
		item.source_changed = FileAccess.get_sha256(item.map_path) != item.source_signature
		rows.append(item)
	return {"ok": true, "drafts": rows, "total": files.size()}

func read(id: String) -> Dictionary:
	var result := header(id)
	if not result.ok: return result
	var file := FileAccess.open(file_for(id), FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES or file.get_length() < result.body_offset: return fail("草稿不可读或过大")
	file.seek(result.body_offset)
	var body := file.get_buffer(file.get_length() - result.body_offset).get_string_from_utf8()
	file.close()
	if body.sha256_text() != result.header.checksum: return fail("草稿校验失败，当前地图未修改")
	var state: Variant = JSON.parse_string(body)
	var issue := validate(state)
	if not issue.is_empty(): return fail(issue)
	if canonical(state.disk_path) != canonical(result.header.map_path) or state.disk_signature != result.header.source_signature: return fail("草稿来源不一致")
	return {"ok": true, "header": result.header, "state": state}

func discard(id: String) -> Dictionary:
	var path := file_for(id)
	if path.is_empty(): return fail("草稿 ID 无效")
	for target in [path, path + ".previous"]:
		if FileAccess.file_exists(target):
			var err := DirAccess.remove_absolute(target)
			if err != OK: return fail("无法删除草稿：" + error_string(err))
	return {"ok": true, "draft_id": id}

static func vector_valid(value: Variant, positive: bool = false) -> bool:
	if not value is Array or value.size() != 3: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or (positive and number <= 0): return false
	return true

static func validate(state: Variant) -> String:
	if not state is Dictionary or not state.get("records") is Array or not state.get("map_meta") is Dictionary: return "草稿文档损坏"
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_meta(state.map_meta): return "草稿建筑蓝图损坏"
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_ownership(state.map_meta,state.records): return "草稿建筑归属损坏"
	if not preload("res://scripts/world3d/environment_settings.gd").valid(state.map_meta): return "草稿环境配置损坏"
	if not preload("res://scripts/world3d/editor_view_settings.gd").valid(state.map_meta): return "草稿楼层/出生点配置损坏"
	if not state.get("disk_path") is String or not Paths.allowed(state.disk_path) or not state.get("disk_signature") is String: return "草稿来源无效"
	if not (state.get("next") is int or state.get("next") is float) or not is_finite(float(state.next)) or state.next < 1 or state.next > 2147483647 or state.next != floor(state.next): return "草稿物件计数损坏"
	if state.records.size() > 100000: return "草稿超过 100000 件物件"
	var ids := {}
	for record in state.records:
		if not record is Dictionary or record.get("kind") not in ["box", "asset", "npc", "gather", "warp", "seat", "event"]: return "草稿物件类型无效"
		if not preload("res://scripts/world3d/building_blueprint.gd").valid_record(record): return "草稿建筑构件损坏"
		if not record.get("uuid") is String: return "草稿物件标识无效"
		var id: String = record.uuid
		if id.is_empty() or id != id.validate_node_name() or ids.has(id): return "草稿物件标识无效"
		if id.begins_with("obj_") and id.trim_prefix("obj_").is_valid_int() and int(id.trim_prefix("obj_")) >= state.next: return "草稿物件计数与标识冲突"
		ids[id] = true
		if not preload("res://scripts/world3d/auto_tile_rules.gd").valid(record): return "草稿自动瓦片损坏"
		if not preload("res://scripts/world3d/surface_materials.gd").valid(record): return "草稿表面材质损坏"
		if not preload("res://scripts/world3d/event_templates.gd").valid_record(record): return "草稿事件模板损坏"
		for field in ["position", "rotation", "size"]:
			if not vector_valid(record.get(field), field == "size"): return "草稿物件变换无效"
		for field in ["spawn", "bounds_position", "bounds_size"]:
			if record.has(field) and not vector_valid(record[field]): return "草稿模型或传送参数无效"
		if record.has("color"):
			if not record.color is Array: return "草稿颜色无效"
			for value in record.color:
				if not (value is int or value is float) or not is_finite(float(value)): return "草稿颜色无效"
		if record.has("skills"):
			if not record.skills is Array: return "草稿技能列表无效"
			for skill in record.skills:
				if not skill is String: return "草稿技能列表无效"
		if record.kind == "asset" and (not record.get("asset_path") is String or not Paths.allowed(record.asset_path)): return "草稿模型引用超出内容目录"
	return ""
