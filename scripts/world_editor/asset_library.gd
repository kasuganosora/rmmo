extends RefCounted
## Imports become self-contained, immutable GLBs outside the source repository.
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
var entries: Array = []
var directory := ""
var _revision := ""
static var _scenes := {}

func _init(folder: String = "") -> void:
	directory = folder if not folder.is_empty() else preload("res://scripts/world3d/map_paths.gd").cache_directory("asset_library")
	var path := directory.path_join("library.json")
	if FileAccess.file_exists(path):
		_revision = FileAccess.get_sha256(path)
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if raw is Array:
			for entry in raw:
				if entry is Dictionary and (entry.get("asset_path") is String or entry.get("prefab_path") is String) and entry.get("label") is String:
					for key in ["asset_path", "prefab_path", "thumbnail_path"]:
						if entry.get(key) is String and not str(entry[key]).is_absolute_path():
							entry[key] = directory.path_join(str(entry[key])).simplify_path()
					entries.append(entry)

func import_file(path: String) -> Dictionary:
	if path.get_extension().to_lower() not in ["gltf", "glb"] or not FileAccess.file_exists(path): return {"ok": false, "error": "请选择存在的 glTF / GLB 文件"}
	# Prefab capture may re-import the exact immutable model just added here.
	# Only reuse a catalogued, content-addressed file after verifying its bytes.
	var normalized:=path.simplify_path().replace("\\","/")
	if normalized.get_base_dir()==directory.simplify_path().replace("\\","/") and normalized.get_extension()=="glb":
		for entry in entries:
			if str(entry.get("asset_path","")).simplify_path().replace("\\","/")==normalized and FileAccess.get_sha256(path)==normalized.get_file().get_basename():
				return {"ok":true,"entry":entry}
	DirAccess.make_dir_recursive_absolute(directory)
	var staging := directory.path_join("import_%d.glb" % Time.get_ticks_usec())
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err: Error
	if preload("res://scripts/world3d/embedded_glb.gd").can_copy(path):
		# Validate the copy, not an earlier version of a concurrently replaced source.
		err = DirAccess.copy_absolute(path, staging)
		if err == OK and not preload("res://scripts/world3d/embedded_glb.gd").can_copy(staging): err = ERR_FILE_CORRUPT
		if err == OK: err = doc.append_from_file(staging, state, 0, staging.get_base_dir())
		# Godot can report OK while an embedded PNG failed to decode. Never
		# publish that partially loaded model with a missing material texture.
		if err == OK:
			if state.images.size() != state.json.get("images", []).size(): err = ERR_FILE_CORRUPT
			for texture in state.images:
				if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0: err = ERR_FILE_CORRUPT
	else:
		err = doc.append_from_file(path, state, 0, path.get_base_dir())
		if err == OK:
			Io.preserve_node_morph_defaults(state)
			err = doc.write_to_filesystem(state, staging)
	if err != OK:
		if FileAccess.file_exists(staging): DirAccess.remove_absolute(staging)
		return {"ok": false, "error": "模型或依赖读取失败：" + error_string(err)}
	var hash := FileAccess.get_sha256(staging)
	var target := directory.path_join(hash + ".glb")
	if FileAccess.file_exists(target): DirAccess.remove_absolute(staging)
	else:
		err = DirAccess.rename_absolute(staging, target)
		if err != OK: return {"ok": false, "error": error_string(err)}
	for entry in entries:
		if entry.get("asset_path") == target:
			if not entry.has("thumbnail_path"):
				entry.thumbnail_path = directory.path_join("thumbnails").path_join(hash + ".png")
				var saved := save()
				if saved != OK:
					entry.erase("thumbnail_path")
					return {"ok": false, "error": "缩略图信息保存失败"}
			return {"ok": true, "entry": entry}
	var instance := instantiate_preview(target)
	if instance == null: return {"ok": false, "error": "导入结果无法实例化"}
	var bounds := bounds_of(instance)
	instance.free()
	var entry := {"label": path.get_file().get_basename(), "category": "导入模型", "asset_path": target, "thumbnail_path": directory.path_join("thumbnails").path_join(hash + ".png"), "bounds_position": [bounds.position.x, bounds.position.y, bounds.position.z], "bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z]}
	entries.append(entry)
	err = save()
	if err != OK:
		entries.pop_back()
		return {"ok": false, "error": "素材库写入失败：" + error_string(err)}
	return {"ok": true, "entry": entry}

func save() -> Error:
	var path := directory.path_join("library.json")
	var err := Io._acquire_save_lock(path)
	if err != OK: return err
	var current := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	if current != _revision:
		Io._remove_tree(path + ".save-lock")
		return ERR_BUSY
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		err = FileAccess.get_open_error()
	else:
		var stored: Array = entries.duplicate(true)
		for entry in stored:
			for key in ["asset_path", "prefab_path", "thumbnail_path"]:
				if entry.get(key) is String and str(entry[key]).begins_with(directory.trim_suffix("/") + "/"):
					entry[key] = str(entry[key]).trim_prefix(directory.trim_suffix("/") + "/")
		file.store_string(JSON.stringify(stored, "\t"))
		file.flush()
		err = file.get_error()
		file.close()
		if err == OK: err = preload("res://scripts/world3d/atomic_file.gd").publish(path + ".tmp", path)
	if err == OK: _revision = FileAccess.get_sha256(path)
	Io._remove_tree(path + ".save-lock")
	return err

func search(query: String) -> Array:
	var needle := query.strip_edges().to_lower()
	if needle.is_empty(): return entries
	return entries.filter(func(entry: Dictionary): return (str(entry.get("label", "")) + " " + str(entry.get("category", ""))).to_lower().contains(needle))

static func instantiate(path: String) -> Node3D:
	if not FileAccess.file_exists(path): return null
	if not _scenes.has(path):
		var scene := Io.load_scene(path) as Node3D
		if scene == null: return null
		if not cache_scene(path, scene): return null
	return _scenes[path].instantiate()

## Preview/import owns one scene and frees it; it must not grow the runtime scene cache.
static func instantiate_preview(path: String) -> Node3D:
	if not FileAccess.file_exists(path): return null
	if _scenes.has(path): return _scenes[path].instantiate()
	return Io.load_scene(path) as Node3D

static func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child, root)

static func bounds_of(node: Node3D, transform_: Transform3D = Transform3D.IDENTITY) -> AABB:
	var transform := transform_ * node.transform
	var bounds := AABB()
	if node is MeshInstance3D and node.mesh != null: bounds = transform * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var box := bounds_of(child, transform)
			if box.has_surface(): bounds = bounds.merge(box) if bounds.has_surface() else box
	return bounds


static func cache_scene(path: String, scene: Node) -> bool:
	if scene == null: return false
	_own(scene, scene)
	var packed := PackedScene.new()
	var err := packed.pack(scene)
	scene.free()
	if err != OK: return false
	_scenes[path] = packed
	return true
