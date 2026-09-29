extends RefCounted
## A resource pack owns maps, NPCs, settings and assets. Default is shared.
var root: String

func _init(content_root: String = "") -> void:
	root = content_root if not content_root.is_empty() else preload("res://scripts/world3d/map_paths.gd").external_root()

func packs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	# Direct project/A packs plus the layouts already used by AssetManager.
	for base in [root, root.path_join("packs"), root.path_join("packs/map_pack")]:
		var directory := DirAccess.open(base)
		if directory == null: continue
		for folder in directory.get_directories():
			if folder.begins_with(".") or directory.is_link(folder): continue
			var path: String = base.path_join(folder)
			if _is_pack(path):
				_append(result, seen, path, folder)
			elif base != root:
				# Versioned storage is supported only with metadata.json in the version root.
				var versions := DirAccess.open(path)
				if versions == null: continue
				for version in versions.get_directories():
					if not versions.is_link(version) and _is_pack(path.path_join(version)):
						_append(result, seen, path.path_join(version), folder, version)
	result.sort_custom(func(a, b):
		if a.shared != b.shared: return a.shared
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
	)
	return result

func _is_pack(path: String) -> bool:
	return _read_metadata(path) is Dictionary

func _read_metadata(path: String) -> Variant:
	var file := FileAccess.open(path.path_join("metadata.json"), FileAccess.READ)
	if file == null: return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary: return null
	return parser.data

func _append(result: Array[Dictionary], seen: Dictionary, path: String, folder: String, version: String = "") -> void:
	if seen.has(path): return
	seen[path] = true
	var metadata: Variant = _read_metadata(path)
	if not metadata is Dictionary: return
	var id := str(metadata.get("id", folder))
	var name := str(metadata.get("name", folder))
	var shared := folder in ["default", "默认"] or id in ["default", "默认"] or name == "默认"
	result.append({"id": id, "name": "默认" if shared else name, "root": path, "version": str(metadata.get("version", version)), "shared": shared, "metadata": metadata})

func maps_in(pack: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for folder in ["maps", "地图"]:
		var base: String = str(pack.root).path_join(folder)
		_collect_maps(base, base, pack, result, 0)
	return result

func _collect_maps(path: String, base: String, pack: Dictionary, result: Array[Dictionary], depth: int) -> void:
	if depth > 32: return
	var directory := DirAccess.open(path)
	if directory == null: return
	for file in directory.get_files():
		if file.get_extension().to_lower() != "gltf" or directory.is_link(file): continue
		var full := path.path_join(file)
		var relative := full.trim_prefix(base + "/")
		var name := relative.get_base_dir() if file == "map.gltf" and relative.contains("/") else relative.get_basename()
		result.append({"name": name, "path": full, "pack": pack})
	for folder in directory.get_directories():
		if folder.begins_with(".") or directory.is_link(folder): continue
		_collect_maps(path.path_join(folder), base, pack, result, depth + 1)

func available_maps(pack: Dictionary, all_packs: Array[Dictionary]) -> Array[Dictionary]:
	var result := maps_in(pack)
	if not bool(pack.shared):
		for shared_pack in all_packs:
			if bool(shared_pack.shared): result.append_array(maps_in(shared_pack))
	return result

func owner_of(path: String, all_packs: Array[Dictionary]) -> int:
	var normalized := path.replace("\\", "/").simplify_path()
	for index in all_packs.size():
		if normalized.begins_with(str(all_packs[index].root).trim_suffix("/") + "/"): return index
	return -1
