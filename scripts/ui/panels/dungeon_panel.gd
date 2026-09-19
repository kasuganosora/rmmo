extends RefCounted
## UI panel: safe-zone and dungeon chips.

const Net = preload("res://scripts/net/net.gd")
const StatusPanel = preload("res://scripts/ui/panels/status_panel.gd")

static func apply_safe_zone(ctrl, action: Dictionary) -> void:
	var inside = bool(action.get("inside", action.get("in_safe_zone", false)))
	ctrl._safe_zone_inside = inside
	ctrl._ensure_safe_zone_chip()
	if ctrl._safe_zone_chip != null:
		ctrl._safe_zone_chip.visible = inside



static func _ensure_safe_zone_chip(ctrl) -> void:
	if ctrl._safe_zone_chip != null and is_instance_valid(ctrl._safe_zone_chip):
		ctrl._safe_zone_chip.visible = ctrl._safe_zone_inside
		return
	var panel = ctrl.get_node_or_null("%StatusPanel") as Control
	ctrl._safe_zone_chip = Label.new()
	ctrl._safe_zone_chip.name = "SafeZoneChip"
	ctrl._safe_zone_chip.text = "安全区"
	ctrl._safe_zone_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._safe_zone_chip.add_theme_font_size_override("font_size", 11)
	ctrl._safe_zone_chip.add_theme_color_override("font_color", Color(0.55, 0.92, 0.7, 1.0))
	ctrl._safe_zone_chip.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.06, 0.9))
	ctrl._safe_zone_chip.add_theme_constant_override("outline_size", 2)
	ctrl._safe_zone_chip.visible = ctrl._safe_zone_inside
	ctrl._safe_zone_chip.z_index = 30
	if panel != null and panel.get_parent() != null:
		var parent_ctl: Node = panel.get_parent()
		parent_ctl.add_child(ctrl._safe_zone_chip)
		# Sit just under the status panel.
		ctrl._safe_zone_chip.position = Vector2(panel.position.x + 6.0, panel.position.y + panel.size.y + 2.0)
		if parent_ctl is Control:
			# Prefer anchors under panel when layout settles.
			ctrl._safe_zone_chip.set_anchors_preset(Control.PRESET_TOP_LEFT)
			ctrl._safe_zone_chip.offset_left = panel.offset_left + 6.0 if "offset_left" in panel else 8.0
			ctrl._safe_zone_chip.offset_top = (panel.offset_bottom if "offset_bottom" in panel else 90.0) + 2.0
	else:
		ctrl.add_child(ctrl._safe_zone_chip)
		ctrl._safe_zone_chip.position = Vector2(12, 100)




static func apply_dungeon_update(ctrl, action: Dictionary) -> void:
	var d: Variant = action.get("dungeon", action)
	if typeof(d) != TYPE_DICTIONARY:
		return
	ctrl._dungeon_state = (d as Dictionary).duplicate(true)
	ctrl._ensure_dungeon_chip()
	ctrl._refresh_dungeon_chip()



static func _refresh_dungeon_chip(ctrl) -> void:
	ctrl._ensure_dungeon_chip()
	if ctrl._dungeon_chip == null:
		return
	var active = bool(ctrl._dungeon_state.get("active", false))
	var completed = bool(ctrl._dungeon_state.get("completed", false))
	if not active and not completed:
		ctrl._dungeon_chip.visible = false
		return
	var kills = int(ctrl._dungeon_state.get("kills", 0))
	var needed = int(ctrl._dungeon_state.get("kills_needed", 2))
	if completed:
		ctrl._dungeon_chip.text = "试炼完成"
	else:
		ctrl._dungeon_chip.text = "试炼 %d/%d" % [kills, needed]
	ctrl._dungeon_chip.visible = true



static func _ensure_dungeon_chip(ctrl) -> void:
	if ctrl._dungeon_chip != null and is_instance_valid(ctrl._dungeon_chip):
		return
	var panel = ctrl.get_node_or_null("%StatusPanel") as Control
	ctrl._dungeon_chip = Label.new()
	ctrl._dungeon_chip.name = "DungeonChip"
	ctrl._dungeon_chip.text = "试炼 0/2"
	ctrl._dungeon_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._dungeon_chip.add_theme_font_size_override("font_size", 11)
	ctrl._dungeon_chip.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45, 1.0))
	ctrl._dungeon_chip.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 0.9))
	ctrl._dungeon_chip.add_theme_constant_override("outline_size", 2)
	ctrl._dungeon_chip.visible = false
	ctrl._dungeon_chip.z_index = 30
	if panel != null and panel.get_parent() != null:
		var parent_ctl: Node = panel.get_parent()
		parent_ctl.add_child(ctrl._dungeon_chip)
		ctrl._dungeon_chip.position = Vector2(panel.position.x + 6.0, panel.position.y + panel.size.y + 16.0)
	else:
		ctrl.add_child(ctrl._dungeon_chip)
		ctrl._dungeon_chip.position = Vector2(12, 116)



static func _on_dungeon_enter_pressed(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_dungeon_enter"):
		ctrl._world_combat.request_dungeon_enter()
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_dungeon_enter"):
		return
	ctrl._apply_dungeon_result_locally(srv.try_dungeon_enter())



static func _on_dungeon_exit_pressed(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_dungeon_exit"):
		ctrl._world_combat.request_dungeon_exit()
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_dungeon_exit"):
		return
	ctrl._apply_dungeon_result_locally(srv.try_dungeon_exit())



static func _apply_dungeon_result_locally(ctrl, result: Dictionary) -> void:
	if typeof(result) != TYPE_DICTIONARY:
		return
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) != TYPE_ARRAY:
		return
	for a in acts_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t = str(a.get("type", ""))
		if t == "dungeon_update":
			ctrl.apply_dungeon_update(a)
		elif t == "system_message":
			var msg = str(a.get("text", "")).strip_edges()
			if msg != "":
				ctrl.append_system(msg)
		elif t == "map_transfer" and ctrl._world_combat != null and ctrl._world_combat.has_method("_on_transfer_requested"):
			if bool(a.get("ok", true)):
				ctrl._world_combat._on_transfer_requested(a)
		elif t == "inventory_update":
			ctrl.apply_inventory_snapshot(a.get("items", []), int(a.get("gold", -1)))
		elif t == "exp_gain":
			ctrl.show_exp_gain_float(int(a.get("amount", 0)))



