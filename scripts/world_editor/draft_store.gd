extends RefCounted
## A bounded header + checksummed JSON snapshot; never exports or replaces a map.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Atomic = preload("res://scripts/world3d/atomic_file.gd")
const MAX_BYTES := 268435456
const COMPRESS_ABOVE := 33554432
const MAX_HEADER := 16384
const MAX_RAW_BYTES := 536870912
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

func file_for(id: String, content_root: String = "") -> String:
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{64}_[0-9a-f]{32}$")
	if pattern.search(id) == null: return ""
	var path := directory.path_join(id + ".draft")
	return path if Paths.allowed(path,content_root) and Paths.allowed(path + ".previous",content_root) else ""

func write(map_path: String, doc) -> Dictionary:
	var prepared:=prepare(map_path,doc)
	if not prepared.ok: return prepared
	return publish_snapshot(prepared,encode(prepared.state))

func prepare(map_path: String, doc) -> Dictionary:
	var prepared:=snapshot(map_path,doc)
	if not prepared.ok: return prepared
	var issue:=validate(prepared.state)
	return fail(issue) if not issue.is_empty() else prepared

func snapshot(map_path: String, doc) -> Dictionary:
	map_path = canonical(map_path)
	if not Paths.allowed(map_path) or map_path.get_extension().to_lower() != "gltf": return fail("草稿地图必须位于工程外内容目录")
	var state: Dictionary = doc.recovery_snapshot()
	# A never-saved document still expects an absent destination on recovery.
	state.disk_path = map_path
	return {"ok":true,"state":state,"map_path":map_path,"object_count":doc.records.size(),"source_signature":doc._disk_signature}

static func encode(state: Dictionary) -> Dictionary:
	# Pure CPU work on an immutable snapshot; safe for the autosave worker.
	var body:=JSON.stringify(state,"",true,true)
	var bytes:=body.to_utf8_buffer()
	if bytes.size()>MAX_RAW_BYTES: return fail("草稿原始数据超过 512 MiB，未写入")
	var result:={"ok":true,"version":1,"checksum":body.sha256_text(),"uncompressed_bytes":bytes.size()}
	if bytes.size()>COMPRESS_ABOVE-MAX_HEADER:
		bytes=bytes.compress(FileAccess.COMPRESSION_ZSTD); result.version=2
	if bytes.is_empty() or bytes.size()>MAX_BYTES-MAX_HEADER: return fail("草稿压缩后超过 256 MiB，未写入")
	result.bytes=bytes
	if result.version==2: result.compressed_checksum=byte_checksum(bytes)
	return result

static func byte_checksum(bytes: PackedByteArray) -> String:
	var context:=HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()

func encode_and_publish(prepared: Dictionary, content_root: String) -> Dictionary:
	# The root string is captured on main; worker path checks never query nodes.
	return publish_snapshot(prepared,encode(prepared.state),false,content_root)

func publish_snapshot(prepared: Dictionary, encoded: Dictionary, reuse: bool = true, content_root: String = "") -> Dictionary:
	if not encoded.ok: return encoded
	var map_path: String=prepared.map_path
	var id := own_id(map_path)
	var path := file_for(id,content_root)
	if path.is_empty(): return fail("草稿目录不可用或包含链接")
	if reuse:
		var previous := header(id)
		if previous.ok and previous.header.checksum == encoded.checksum and read(id).ok:
			return {"ok": true, "draft_id": id, "unchanged": true, "saved_at": previous.header.saved_at}
	var metadata := {"format": "rmmo_editor_draft", "version": encoded.version, "draft_id": id, "map_path": map_path, "saved_at": Time.get_unix_time_from_system(), "object_count": prepared.object_count, "checksum": encoded.checksum, "source_signature": prepared.source_signature}
	if encoded.version==2:
		metadata.encoding="zstd"; metadata.uncompressed_bytes=encoded.uncompressed_bytes
		metadata.compressed_checksum=encoded.compressed_checksum
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK: return fail("无法创建草稿目录：" + error_string(err))
	var temporary := path + ".tmp_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return fail("无法写入草稿：" + error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(metadata) + "\n")
	file.store_buffer(encoded.bytes)
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
	if not value is Dictionary or value.get("format") != "rmmo_editor_draft" or (value.get("version")!=1 and value.get("version")!=2) or value.get("draft_id") != id: return fail("草稿格式不支持")
	if value.version==2:
		if not value.get("compressed_checksum") is String or value.compressed_checksum.length()!=64: return fail("草稿压缩签名损坏")
		var length_: Variant=value.get("uncompressed_bytes")
		if value.get("encoding")!="zstd" or not (length_ is int or length_ is float): return fail("草稿压缩头损坏")
		if not is_finite(float(length_)) or length_!=floor(length_) or length_<1 or length_>MAX_RAW_BYTES: return fail("草稿解压大小无效")
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
	var bytes:=file.get_buffer(file.get_length() - result.body_offset)
	file.close()
	if result.header.version==2:
		if byte_checksum(bytes)!=result.header.compressed_checksum: return fail("草稿压缩数据校验失败，当前地图未修改")
		bytes=bytes.decompress(int(result.header.uncompressed_bytes),FileAccess.COMPRESSION_ZSTD)
		if bytes.size()!=int(result.header.uncompressed_bytes): return fail("草稿解压失败，当前地图未修改")
	var body:=bytes.get_string_from_utf8()
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
	var issue:=validate_meta(state)
	if not issue.is_empty(): return issue
	var ids:={}
	for record in state.records:
		issue=validate_record(record,state,ids)
		if not issue.is_empty(): return issue
	return validate_ownership(state)

static func validate_ownership(state: Dictionary) -> String:
	return "" if preload("res://scripts/world3d/building_blueprint.gd").valid_ownership(state.map_meta,state.records,true) else "草稿建筑归属损坏"

static func validate_meta(state: Variant) -> String:
	if not state is Dictionary or not state.get("records") is Array or not state.get("map_meta") is Dictionary: return "草稿文档损坏"
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_meta(state.map_meta): return "草稿建筑蓝图损坏"
	if not preload("res://scripts/world3d/environment_settings.gd").valid(state.map_meta): return "草稿环境配置损坏"
	if not preload("res://scripts/world3d/editor_view_settings.gd").valid(state.map_meta): return "草稿楼层/出生点配置损坏"
	if not preload("res://scripts/world3d/city_layout.gd").valid(state.map_meta): return "草稿城镇布局损坏"
	if not state.get("disk_path") is String or not Paths.allowed(state.disk_path) or not state.get("disk_signature") is String: return "草稿来源无效"
	if not (state.get("next") is int or state.get("next") is float) or not is_finite(float(state.next)) or state.next < 1 or state.next > 2147483647 or state.next != floor(state.next): return "草稿物件计数损坏"
	if state.records.size() > 100000: return "草稿超过 100000 件物件"
	return ""

static func validate_record(record: Variant, state: Dictionary, ids: Dictionary) -> String:
	if not record is Dictionary or record.get("kind") not in ["box", "asset", "npc", "gather", "warp", "seat", "event"]: return "草稿物件类型无效"
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_record(record): return "草稿建筑构件损坏"
	if not record.get("uuid") is String: return "草稿物件标识无效"
	var id: String = record.uuid
	if id.is_empty() or id != id.validate_node_name() or ids.has(id): return "草稿物件标识无效"
	if id.begins_with("obj_") and id.trim_prefix("obj_").is_valid_int() and int(id.trim_prefix("obj_")) >= state.next: return "草稿物件计数与标识冲突"
	ids[id] = true
	if not preload("res://scripts/world3d/auto_tile_rules.gd").valid(record): return "草稿自动瓦片损坏"
	if not preload("res://scripts/world3d/road_surface.gd").valid(record): return "草稿表面材质损坏"
	if not preload("res://scripts/world3d/terrain_surface.gd").valid(record): return "草稿地形网格损坏"
	if not preload("res://scripts/world3d/channel_surface.gd").valid(record): return "草稿河道网格损坏"
	if not preload("res://scripts/world3d/fortification_data.gd").valid_record(record): return "草稿城墙构件损坏"
	if not preload("res://scripts/world3d/surface_materials.gd").valid(record): return "草稿表面材质损坏"
	if not preload("res://scripts/world3d/event_templates.gd").valid_record(record): return "草稿事件模板损坏"
	if not preload("res://scripts/world3d/wind_response.gd").valid(record): return "草稿受风配置损坏"
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
