extends SceneTree
## Headless content-editor MCP host. Stays up until killed.


func _init() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var Editor = load("res://scripts/editor/content_editor.gd")
	var ed = Editor.new()
	root.add_child(ed)
	if ed.get("_mcp") == null or not bool(ed._mcp.running):
		ed._toggle_mcp()
	var mcp = ed.get("_mcp")
	if mcp == null or not bool(mcp.running):
		push_error("editor_mcp_host: failed to start MCP")
		quit(1)
		return
	print("MCP_READY url=%s pack=%s map=%s" % [
		str(mcp.url()),
		str(ed.pack.pack_id) if ed.pack else "",
		str(ed.current_map_id),
	])
