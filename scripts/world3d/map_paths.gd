extends RefCounted
## External map directories. These paths are storage, not a map_ref.

const ArtPaths = preload("res://scripts/asset/art_paths.gd")
const WorldLocation = preload("res://scripts/world3d/world_location.gd")


static func external_root() -> String:
	return ArtPaths.external_root()


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
