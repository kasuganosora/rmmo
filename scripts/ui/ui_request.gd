extends RefCounted
## UI submissions share the existing sync/async request correlation boundary.
const Pipeline = preload("res://scripts/net/request_pipeline.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

static func dispatch(hud: Node, method: String, args: Array, local_apply: Callable, finished: Callable) -> void:
	var owner_ref: WeakRef = weakref(hud)
	var delivered := [false]
	var complete := func(result: Dictionary):
		if delivered[0]: return
		delivered[0] = true
		var owner = owner_ref.get_ref()
		if owner == null: return
		var world = owner._world_combat
		if is_instance_valid(world) and world.has_method("_apply_server_actions"):
			world._apply_server_actions(result.get("actions", []))
		elif is_instance_valid(world) and world.has_method("apply_actions"):
			# The 3D bridge handles inventory, appearance and messages. Panel-only
			# snapshots still need their own handlers (mail/auction/skill book).
			var world_actions: Array = []
			var panel_actions: Array = []
			for action in result.get("actions", []):
				if str(action.get("type", "")) in ["mail_update", "auction_update", "skill_book_update", "skill_respec"]: panel_actions.append(action)
				else: world_actions.append(action)
			world.apply_actions(world_actions)
			local_apply.call({"actions": panel_actions})
		else:
			local_apply.call(result)
		finished.call(result)
	var result := Pipeline.dispatch(null, method, args, complete)
	# Pipeline returns validation errors without invoking its applier.
	if not delivered[0] and not result.get("deferred", false): complete.call(result)

static func message(result: Dictionary, success: String = "操作成功") -> String:
	if bool(result.get("ok", false)): return success
	for action in result.get("actions", []):
		if action.get("type", "") == "system_message": return str(action.get("text", "操作失败，请重试。"))
	return "暂时无法完成，请稍后重试。"

static func status(parent: Node, node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 18
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", L2Style.COL_MUTED)
	parent.add_child(label)
	return label

static func set_status(label: Label, text: String, failed: bool = false) -> void:
	label.text = text
	label.add_theme_color_override("font_color", Color("e1a28f") if failed else L2Style.COL_TEXT)

static func lock_form(node: Node, locked: bool) -> void:
	for child in node.get_children():
		if child is LineEdit or child is TextEdit:
			if locked and not child.has_meta("was_editable"): child.set_meta("was_editable", child.editable)
			child.editable = false if locked else bool(child.get_meta("was_editable", true))
		elif child is BaseButton:
			if locked and not child.has_meta("was_disabled"): child.set_meta("was_disabled", child.disabled)
			child.disabled = true if locked else bool(child.get_meta("was_disabled", false))
		elif child is SpinBox:
			if locked and not child.has_meta("was_editable"): child.set_meta("was_editable", child.editable)
			child.editable = false if locked else bool(child.get_meta("was_editable", true))
		if not locked:
			child.remove_meta("was_editable") if child.has_meta("was_editable") else null
			child.remove_meta("was_disabled") if child.has_meta("was_disabled") else null
		if child is SpinBox: continue
		if child.has_method("set_interaction_locked"): child.set_interaction_locked(locked)
		else: lock_form(child, locked)
