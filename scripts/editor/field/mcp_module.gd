extends RefCounted
## Domain module: MCP integration (autostart, toggle, refresh).

var ctrl
func _init(c):
	ctrl = c

const EditorMcp = preload("res://scripts/editor/adapters/editor_mcp.gd")

func _want_mcp_autostart() -> bool:
	var env = OS.get_environment("RMMO_EDITOR_MCP").strip_edges().to_lower()
	if env in ["1", "true", "yes", "on"]:
		return true
	for a in OS.get_cmdline_user_args():
		if str(a) == "--mcp":
			return true
	return false



func _toggle_mcp() -> void:
	if ctrl._mcp != null and bool(ctrl._mcp.running):
		ctrl._mcp.stop()
		if ctrl._mcp_popup:
			ctrl._mcp_popup.set_item_checked(ctrl._mcp_popup.get_item_index(ctrl.MENU_MCP_TOGGLE), false)
		ctrl._status.text = "MCP 已关闭"
		return
	if ctrl._mcp == null:
		ctrl._mcp = EditorMcp.new()
		ctrl._mcp.editor = ctrl
		ctrl.add_child(ctrl._mcp)
	var info: Dictionary = ctrl._mcp.start()
	var on = bool(info.get("ok", false))
	if ctrl._mcp_popup:
		ctrl._mcp_popup.set_item_checked(ctrl._mcp_popup.get_item_index(ctrl.MENU_MCP_TOGGLE), on)
	if on:
		var url = str(info.get("url", ""))
		DisplayServer.clipboard_set(url)
		ctrl._status.text = "MCP 已启用 · %s（已复制）" % url
	else:
		ctrl._status.text = "MCP 启动失败：%s" % str(info.get("error", "未知"))



func mcp_refresh(cell: Vector2i = Vector2i(-1, -1)) -> void:
	if cell.x >= 0:
		ctrl._cursor = cell
	if ctrl._inspector:
		ctrl._inspector.bind_pack(ctrl.pack)
		if ctrl.doc:
			ctrl._inspector.load_cell(ctrl.doc, ctrl._cursor)
	ctrl._reload_field()
	if ctrl._tree:
		ctrl._refresh_tree()


