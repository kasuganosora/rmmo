@tool
extends EditorPlugin
## Stops editor Output spam: Index p_gutter = -1 (gutters.size() = 4).
## Root cause is Highlight Type Safe Lines coloring unloaded script tabs.

const SETTING := "text_editor/appearance/gutters/highlight_type_safe_lines"


func _enter_tree() -> void:
	var es := EditorInterface.get_editor_settings()
	if es == null:
		return
	if bool(es.get_setting(SETTING)):
		es.set_setting(SETTING, false)
		print("silence_type_safe_gutter: disabled Highlight Type Safe Lines (stops p_gutter=-1 spam)")


func _exit_tree() -> void:
	pass
