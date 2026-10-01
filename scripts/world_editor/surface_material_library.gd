extends RefCounted
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const Atomic = preload("res://scripts/world3d/atomic_file.gd")
var directory: String

func _init(folder: String = "") -> void:
	directory = folder if not folder.is_empty() else Paths.cache_directory("surface_materials")

func entries() -> Array:
	var result: Array = [
		{"material_id": "builtin:white", "material": {"name": "白色", "color": [1, 1, 1, 1], "roughness": 0.9}},
		{"material_id": "builtin:checker", "material": {"name": "棋盘格 · 检查比例", "pattern": "checker", "color": [1, 1, 1, 1], "roughness": 0.9}}]
	if not Paths.allowed(directory): return result
	var dir := DirAccess.open(directory)
	if dir == null: return result
	for file in dir.get_files():
		if not file.ends_with(".json") or not Paths.allowed(directory.path_join(file)): continue
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(file)))
		if not value is Dictionary or not value.get("material") is Dictionary: continue
		if value.material.get("texture_path") is String: value.material.texture_path = directory.path_join(str(value.material.texture_path)).simplify_path()
		if Paint.material_valid(value.material): result.append({"material_id": file.get_basename(), "material": value.material})
	return result

func find(id: String) -> Dictionary:
	for entry in entries():
		if entry.material_id == id: return entry.material.duplicate(true)
	return {}

func import_texture(path: String, label: String = "") -> Dictionary:
	if not Paths.allowed(path) or path.get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp"] or not FileAccess.file_exists(path): return Paint.fail("请选择内容目录内的 PNG / JPEG / WebP 贴图")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 16777216: return Paint.fail("贴图文件不可读或超过 16 MiB")
	file.close()
	var image := Image.load_from_file(path)
	if image == null or image.is_empty() or image.get_width() > 4096 or image.get_height() > 4096: return Paint.fail("贴图无效，最大支持 4096 × 4096")
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
