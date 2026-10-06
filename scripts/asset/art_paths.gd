extends RefCounted
## Game art lives only in the external content pack, including authoring sources.
static func external_root()->String:
	var root:String=preload("res://scripts/util/json_util.gd").content_root()
	if root.is_empty():
		push_error("External content_root is not configured")
		return ""
	var absolute:=ProjectSettings.globalize_path(root).replace("\\","/").simplify_path().trim_suffix("/")
	var project:=ProjectSettings.globalize_path("res://").replace("\\","/").simplify_path().trim_suffix("/")
	if absolute.to_lower()==project.to_lower() or absolute.to_lower().begins_with(project.to_lower()+"/"):
		push_error("Game art content_root must be outside the project")
		return ""
	return absolute

static func path(relative:String)->String:
	var root:=external_root()
	return root.path_join("assets").path_join(relative) if not root.is_empty() else ""

## Screenshots and review frames must not enter Godot's res:// import scan.
static func review_path(relative:String)->String:
	var root:=external_root()
	if root.is_empty():return ""
	var output:=root.path_join("review_artifacts").path_join(relative)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	return output
