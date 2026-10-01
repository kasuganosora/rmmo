extends RefCounted
## External map directories. These paths are storage, not a map_ref.

const ArtPaths = preload("res://scripts/asset/art_paths.gd")
const WorldLocation = preload("res://scripts/world3d/world_location.gd")


static func external_root() -> String:
	return ArtPaths.external_root()


static func allowed(value: String, content_root: String = "") -> bool:
	if value.is_empty() or not value.is_absolute_path() or value.contains("://"): return false
	for index in value.length():
		if value.unicode_at(index) == 0: return false
	var base := (external_root() if content_root.is_empty() else content_root).replace("\\", "/").simplify_path().trim_suffix("/")
	if base.is_empty(): return false
	var path := value.replace("\\", "/").simplify_path().trim_suffix("/")
	if path.to_lower() != base.to_lower() and not path.to_lower().begins_with(base.to_lower() + "/"): return false
	for i in 128:
		var parent := path.get_base_dir()
		if parent == path or path.is_empty(): break
		var directory := DirAccess.open(parent)
		if directory != null and directory.is_link(path.get_file()): return false
		path = parent
	return true


static func map_directory(pack_id: String, map_id: String) -> String:
	if not WorldLocation.id_ok(pack_id) or not WorldLocation.id_ok(map_id):
		push_error("World map id must be letters, digits, or underscore")
		return ""
	var root := external_root()
	if root.is_empty():
		return ""
	return _confine(root, root.path_join("packs").path_join(pack_id).path_join("maps").path_join(map_id))


static func cache_directory(name: String) -> String:
	if not WorldLocation.id_ok(name):
		push_error("World cache name must be letters, digits, or underscore")
		return ""
	var root := external_root()
	if root.is_empty():
		return ""
	return _confine(root, root.path_join("cache").path_join("world3d").path_join(name))


static func _confine(root: String, candidate: String) -> String:
	var base := root.replace("\\", "/").simplify_path().trim_suffix("/")
	var path := candidate.replace("\\", "/").simplify_path().trim_suffix("/")
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/")
	if path == project or path.to_lower().begins_with(project.to_lower() + "/"):
		push_error("World files must stay outside the Godot project")
		return ""
	if path != base and not path.to_lower().begins_with(base.to_lower() + "/"):
		push_error("World path escaped the content root")
		return ""
	return path
