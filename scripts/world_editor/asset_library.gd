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
				if entry is Dictionary and entry.get("asset_path") is String and entry.get("label") is String: entries.append(entry)

func import_file(path: String) -> Dictionary:
	if path.get_extension().to_lower() not in ["gltf", "glb"] or not FileAccess.file_exists(path): return {"ok": false, "error": "请选择存在的 glTF / GLB 文件"}
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state, 0, path.get_base_dir())
	if err != OK: return {"ok": false, "error": "模型或依赖读取失败：" + error_string(err)}
	DirAccess.make_dir_recursive_absolute(directory)
	var staging := directory.path_join("import_%d.glb" % Time.get_ticks_usec())
	Io.preserve_node_morph_defaults(state)
	err = doc.write_to_filesystem(state, staging)
	if err != OK: return {"ok": false, "error": error_string(err)}
	var hash := FileAccess.get_sha256(staging)
	var target := directory.path_join(hash + ".glb")
	if FileAccess.file_exists(target): DirAccess.remove_absolute(staging)
	else:
		err = DirAccess.rename_absolute(staging, target)
		if err != OK: return {"ok": false, "error": error_string(err)}
	for entry in entries:
		if entry.asset_path == target: return {"ok": true, "entry": entry}
	var instance := instantiate(target)
	if instance == null: return {"ok": false, "error": "导入结果无法实例化"}
	var bounds := bounds_of(instance)
	instance.free()
	var entry := {"label": path.get_file().get_basename(), "category": "导入模型", "asset_path": target, "bounds_position": [bounds.position.x, bounds.position.y, bounds.position.z], "bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z]}
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
		file.store_string(JSON.stringify(entries, "\t"))
		file.flush()
		err = file.get_error()
		file.close()
		if err == OK: err = preload("res://scripts/world3d/atomic_file.gd").publish(path + ".tmp", path)
	if err == OK: _revision = FileAccess.get_sha256(path)
	Io._remove_tree(path + ".save-lock")
	return err

func search(query: String) -> Array:
	return entries.filter(func(entry: Dictionary): return query.is_empty() or (str(entry.label) + " " + str(entry.category)).to_lower().contains(query.to_lower()))

static func instantiate(path: String) -> Node3D:
	if not FileAccess.file_exists(path): return null
	if not _scenes.has(path):
		var scene := Io.load_scene(path) as Node3D
		if scene == null: return null
		if not cache_scene(path, scene): return null
	return _scenes[path].instantiate()

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
