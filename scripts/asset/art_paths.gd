extends RefCounted
## Game art lives only in the external content pack, including authoring sources.
static func path(relative:String)->String:
	var root:String=preload("res://scripts/util/json_util.gd").content_root()
	if root.is_empty():
		push_error("External content_root is not configured")
		return ""
	var absolute:=ProjectSettings.globalize_path(root).replace("\\","/").simplify_path().trim_suffix("/")
	var project:=ProjectSettings.globalize_path("res://").replace("\\","/").simplify_path().trim_suffix("/")
	if absolute.to_lower()==project.to_lower() or absolute.to_lower().begins_with(project.to_lower()+"/"):
		push_error("Game art content_root must be outside the project")
		return ""
	return root.path_join("assets").path_join(relative)
