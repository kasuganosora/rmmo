extends RefCounted
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const Atomic = preload("res://scripts/world3d/atomic_file.gd")
var directory: String
var include_shared := true

func _init(folder: String = "") -> void:
	directory = folder if not folder.is_empty() else Paths.cache_directory("surface_materials")
	include_shared = folder.is_empty()

func entries(content_root: String = "") -> Array:
	if content_root.is_empty(): content_root = Paths.external_root()
	var result: Array = _builtins()
	_collect(directory, directory, "", "导入材质", result, content_root)
	if include_shared:
		for pack in preload("res://scripts/world_editor/resource_pack_catalog.gd").new(content_root).packs():
			if not pack.shared: continue
			var base: String = str(pack.root).path_join("assets/materials")
			_collect(base, base, "pack:" + str(pack.id) + ":", "默认资源包", result, content_root)
	return result

static func _builtins() -> Array:
	return [
		{"material_id": "builtin:white", "material": {"name": "白色", "color": [1, 1, 1, 1], "roughness": 0.9}},
		{"material_id": "builtin:checker", "material": {"name": "棋盘格 · 检查比例", "pattern": "checker", "color": [1, 1, 1, 1], "roughness": 0.9}}]

func _collect(path: String, base: String, prefix: String, origin: String, result: Array, content_root: String, depth: int = 0) -> void:
	# Keep the existing depth-first order while avoiding recursive stack growth
	# and never silently dropping later directories or deeply nested materials.
	var pending:Array[String]=[path]
	while not pending.is_empty():
		var current:String=pending.pop_back()
		if not Paths.allowed(current,content_root):continue
		var dir:=DirAccess.open(current)
		if dir==null:continue
		for file:String in dir.get_files():
			var full:=current.path_join(file)
			if not file.ends_with(".json") or dir.is_link(file) or not Paths.allowed(full,content_root):continue
			# Producer metadata is not a material descriptor. Skip these reserved
			# compound suffixes before opening/decoding every sidecar in the catalog.
			if file.ends_with(".dds.source.json") or file.ends_with(".png.thumbnail.json"):continue
			var entry:=_read_entry(full,current,base,prefix,origin,content_root)
			if not entry.is_empty():result.append(entry)
		var folders:=dir.get_directories()
		for index in range(folders.size()-1,-1,-1):
			var folder:String=folders[index]
			if folder.begins_with(".") or dir.is_link(folder):continue
			pending.append(current.path_join(folder))

static func _read_entry(full: String, path: String, base: String, prefix: String, origin: String, content_root: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(full))
	if not value is Dictionary or not value.get("material") is Dictionary: return {}
	for field in Paint.MAP_FIELDS:
		if value.material.get(field) is String and not str(value.material[field]).is_empty():
			var texture_path: String = value.material[field]
			if not texture_path.is_absolute_path(): texture_path = path.path_join(texture_path).simplify_path()
			# Pack descriptors cannot reach sibling packs or their sources folder.
			if not prefix.is_empty() and not texture_path.replace("\\", "/").begins_with(base.replace("\\", "/").trim_suffix("/") + "/"): value.material[field] = "invalid:outside-material-library"
			else: value.material[field] = texture_path
	if not Paint.material_valid(value.material, false, content_root): return {}
	var relative := full.replace("\\", "/").trim_prefix(base.replace("\\", "/").trim_suffix("/") + "/").get_basename()
	var category := str(value.get("category", "导入材质"))
	return {"material_id": prefix + relative, "material": value.material, "category": category, "origin": origin, "source": value.get("source", {})}

func categories() -> Array:
	var result: Array = []
	for entry in entries():
		var category := str(entry.get("category", "内置"))
		if not result.has(category): result.append(category)
	result.sort()
	return result

func search(query: String = "", category: String = "") -> Array:
	return entries().filter(func(entry):
		return (category.is_empty() or entry.get("category", "内置") == category) and (query.is_empty() or (str(entry.material.name) + " " + str(entry.get("category", "内置")) + " " + str(entry.material_id)).to_lower().contains(query.to_lower()))
	)

func find(id: String) -> Dictionary:
	for entry in entries():
		if entry.material_id == id: return entry.material.duplicate(true)
	return {}

func find_many(ids: Array) -> Dictionary:
	if ids.is_empty(): return {}
	# Subclasses can provide virtual catalogs or override collection. Retain
	# that contract rather than inspecting only the native on-disk directory.
	if get_script() != load("res://scripts/world_editor/surface_material_library.gd"):
		return _find_many_entries(ids)
	var result: Dictionary = {}
	for entry in _builtins():
		if entry.material_id in ids: result[entry.material_id] = entry.material
	if ids.all(func(id):return result.has(id)): return result
	var content_root := Paths.external_root()
	var candidates := _lookup_candidates(ids, content_root)
	if not candidates.complete: return _find_many_entries(ids)
	for candidate in candidates.paths:
		if result.has(candidate.id): continue
		# Recheck selected leaves and ancestors before reading their definition.
		if not Paths.allowed(candidate.full, content_root): continue
		var entry := _read_entry(candidate.full, candidate.path, candidate.base, candidate.prefix, candidate.origin, content_root)
		if not entry.is_empty(): result[entry.material_id] = entry.material.duplicate(true)
	return result

func _find_many_entries(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	if ids.is_empty(): return result
	for entry in entries():
		if entry.material_id in ids and not result.has(entry.material_id):
			result[entry.material_id] = entry.material.duplicate(true)
	return result

func _lookup_candidates(ids: Array, content_root: String) -> Dictionary:
	# Count every JSON name for diagnostics. Listing has no material-count or
	# depth cap, so those values cannot turn a valid requested ID into a miss.
	var state := {"complete":true, "count":2, "directories":0, "paths":[]}
	_candidate_paths(directory, directory, "", "导入材质", ids, content_root, state)
	if include_shared and state.complete:
		for pack in preload("res://scripts/world_editor/resource_pack_catalog.gd").new(content_root).packs():
			if not pack.shared: continue
			var base: String = str(pack.root).path_join("assets/materials")
			_candidate_paths(base, base, "pack:" + str(pack.id) + ":", "默认资源包", ids, content_root, state)
			if not state.complete: break
	return state

func _candidate_paths(path: String, base: String, prefix: String, origin: String, ids: Array, content_root: String, state: Dictionary, depth: int = 0) -> void:
	var pending:Array[String]=[path]
	while not pending.is_empty() and state.complete:
		var current:String=pending.pop_back()
		if not Paths.allowed(current,content_root):continue
		var dir:=DirAccess.open(current)
		if dir==null:continue
		state.directories+=1
		for file:String in dir.get_files():
			if not file.ends_with(".json"):continue
			state.count+=1
			var full:=current.path_join(file)
			var relative:=full.replace("\\","/").trim_prefix(base.replace("\\","/").trim_suffix("/")+"/").get_basename()
			if prefix+relative in ids and not dir.is_link(file):
				state.paths.append({"id":prefix+relative,"full":full,"path":current,"base":base,"prefix":prefix,"origin":origin})
		var folders:=dir.get_directories()
		for index in range(folders.size()-1,-1,-1):
			var folder:String=folders[index]
			if folder.begins_with(".") or dir.is_link(folder):continue
			pending.append(current.path_join(folder))

func import_texture(path: String, label: String = "") -> Dictionary:
	if not Paths.allowed(path) or path.get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp"] or not FileAccess.file_exists(path): return Paint.fail("请选择内容目录内的 PNG / JPEG / WebP 贴图")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0: return Paint.fail("贴图文件不可读或为空")
	file.close()
	var image := Image.load_from_file(path)
	if image == null or image.is_empty(): return Paint.fail("贴图无效或引擎无法解码")
	var png := image.save_png_to_buffer()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256); hash.update(png)
	var content_id := hash.finish().hex_encode()
	var name := label.strip_edges() if not label.strip_edges().is_empty() else path.get_file().get_basename()
	var id := (content_id + name).sha256_text()
	var texture_path := directory.path_join(content_id + ".png")
	var metadata := directory.path_join(id + ".json")
	for target in [texture_path, metadata, texture_path + ".previous", metadata + ".previous"]:
		if not Paths.allowed(target): return Paint.fail("材质库路径无效")
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK: return Paint.fail("无法创建材质库")
	if not FileAccess.file_exists(texture_path):
		err = _write(texture_path, png)
		if err != OK: return Paint.fail("贴图写入失败：" + error_string(err))
	var material := {"name": name, "texture_path": texture_path.get_file(), "color": [1, 1, 1, 1], "roughness": 0.9}
	err = _write(metadata, JSON.stringify({"material": material}).to_utf8_buffer())
	if err != OK: return Paint.fail("材质写入失败：" + error_string(err))
	material.texture_path = texture_path
	return {"ok": true, "material_id": id, "material": material}

static func _write(path: String, bytes: PackedByteArray) -> Error:
	var staging := path + ".tmp_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var file := FileAccess.open(staging, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(bytes); file.flush()
	var err := file.get_error()
	file.close()
	if err == OK: err = Atomic.publish(staging, path)
	if FileAccess.file_exists(staging): DirAccess.remove_absolute(staging)
	return err
