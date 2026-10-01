extends SceneTree
## Current 3D editor MCP host. Headless supports all tools except preview_map.


func _init() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var port := 18766
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			var value := arg.trim_prefix("--port=")
			if not value.is_valid_int(): push_error("Invalid MCP port"); quit(1); return
			port = int(value)
		elif arg.begins_with("--map="): path = arg.trim_prefix("--map=")
	if not path.is_empty():
		var validator := preload("res://scripts/world_editor/mcp_ops.gd").new()
		if not validator.allowed_path(path) or path.get_extension().to_lower() != "gltf" or not FileAccess.file_exists(path):
			push_error("Map must be an existing glTF inside the content root"); quit(1); return
		var issue := validator.validate_map_file(path)
		if not issue.is_empty(): push_error(issue); quit(1); return
		preload("res://scripts/net/net.gd").session().world3d_editor_path = path
	var editor := preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false
	root.add_child(editor)
	var result := editor.start_mcp(port)
	if not result.ok:
		push_error("editor_mcp_host: " + str(result.error)); quit(1); return
	print("MCP_READY editor=world3d url=%s map=%s" % [result.url, editor._path])
