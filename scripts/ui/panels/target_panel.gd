extends RefCounted
## UI panel: target portrait, status chips, threat.

const StatusIconBar = preload("res://scripts/ui/status_icon_bar.gd")

static func apply_target_status_chips(ctrl, statuses: Array) -> void:
	if ctrl.target_panel == null:
		return
	ctrl._ensure_target_chrome()
	if ctrl._target_status_chip_row == null or not is_instance_valid(ctrl._target_status_chip_row):
		var vbox = ctrl.target_panel.find_child("TargetVBox", true, false) as VBoxContainer
		if vbox == null:
			return
		var existing = vbox.get_node_or_null("TargetStatusIconBar")
		if existing != null:
			ctrl._target_status_chip_row = existing
		else:
			var bar = StatusIconBar.new()
			bar.name = "TargetStatusIconBar"
			bar.icon_size = 28.0
			bar.allow_cancel = false
			vbox.add_child(bar)
			ctrl._target_status_chip_row = bar
	if ctrl._target_status_chip_row.has_method("apply_statuses"):
		ctrl._target_status_chip_row.apply_statuses(statuses)
	else:
		ctrl._rebuild_status_chips(ctrl._target_status_chip_row, statuses)



static func clear_target(ctrl) -> void:
	ctrl.target_panel.visible = false
	ctrl.target_name.text = ""
	ctrl.target_hp.value = 0
	ctrl.target_hp.visible = false
	if ctrl._target_mp != null:
		ctrl._target_mp.value = 0
		ctrl._target_mp.visible = false
	ctrl._target_world_pos = null
	ctrl._threat_visible = false
	ctrl._threat_you = false
	if ctrl._threat_chip != null and is_instance_valid(ctrl._threat_chip):
		ctrl._threat_chip.visible = false
	if ctrl._target_status_chip_row != null and is_instance_valid(ctrl._target_status_chip_row):
		ctrl._rebuild_status_chips(ctrl._target_status_chip_row, [])
	if ctrl._radar and ctrl._radar.has_method("clear_target_angle"):
		ctrl._radar.clear_target_angle()



static func _ensure_target_chrome(ctrl) -> void:
	## Name + × close on one row; HP bar below (monster only).
	if ctrl.target_panel == null:
		return
	var vbox = ctrl.target_panel.find_child("TargetVBox", true, false) as VBoxContainer
	if vbox == null:
		return
	var head = vbox.get_node_or_null("TargetHead") as HBoxContainer
	if head == null:
		head = HBoxContainer.new()
		head.name = "TargetHead"
		head.add_theme_constant_override("separation", 6)
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(head)
		vbox.move_child(head, 0)
		if ctrl.target_name.get_parent() != head:
			ctrl.target_name.reparent(head)
		ctrl.target_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctrl.target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var close_btn = Button.new()
		close_btn.name = "TargetClose"
		close_btn.text = "×"
		close_btn.focus_mode = Control.FOCUS_NONE
		close_btn.custom_minimum_size = Vector2(28, 22)
		close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		close_btn.pressed.connect(ctrl._on_target_close_pressed)
		head.add_child(close_btn)
	# Keep HP under the head row; MP under HP.
	if ctrl.target_hp.get_parent() == vbox:
		vbox.move_child(ctrl.target_hp, mini(1, vbox.get_child_count() - 1))
	if ctrl._target_mp == null or not is_instance_valid(ctrl._target_mp):
		ctrl._target_mp = vbox.get_node_or_null("TargetMp") as ProgressBar
	if ctrl._target_mp == null:
		ctrl._target_mp = ProgressBar.new()
		ctrl._target_mp.name = "TargetMp"
		ctrl._target_mp.custom_minimum_size = Vector2(0, 10)
		ctrl._target_mp.show_percentage = false
		ctrl._target_mp.modulate = Color(0.28, 0.48, 0.95, 1)
		ctrl._target_mp.max_value = 100.0
		ctrl._target_mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(ctrl._target_mp)
	if ctrl._target_mp.get_parent() == vbox:
		vbox.move_child(ctrl._target_mp, mini(2, vbox.get_child_count() - 1))
	ctrl._ensure_threat_chip()



static func apply_threat_chip(ctrl, show: bool, threat_you: bool = false) -> void:
	ctrl._threat_visible = ctrl.show
	ctrl._threat_you = threat_you
	ctrl._ensure_threat_chip()
	if ctrl._threat_chip == null:
		return
	if not ctrl.show:
		ctrl._threat_chip.visible = false
		return
	var ThreatUtil = preload("res://scripts/ui/threat_hud_util.gd")
	ctrl._threat_chip.text = ThreatUtil.chip_text(threat_you)
	ctrl._threat_chip.add_theme_color_override("font_color", ThreatUtil.chip_color(threat_you))
	ctrl._threat_chip.visible = true



static func apply_threat_update(ctrl, action: Dictionary) -> void:
	## From threat_update / set_stat piggyback while a hostile target is shown.
	if not ctrl._threat_visible and not bool(action.get("force", false)):
		# Only refresh when chip already armed for a hostile target.
		if ctrl.target_panel == null or not ctrl.target_panel.visible:
			return
	var ThreatUtil = preload("res://scripts/ui/threat_hud_util.gd")
	var n: Dictionary = ThreatUtil.normalize(action)
	ctrl.apply_threat_chip(true, bool(n.get("threat_you", false)))



static func _ensure_threat_chip(ctrl) -> void:
	if ctrl.target_panel == null:
		return
	if ctrl._threat_chip != null and is_instance_valid(ctrl._threat_chip):
		ctrl._threat_chip.visible = ctrl._threat_visible
		return
	var vbox = ctrl.target_panel.find_child("TargetVBox", true, false) as VBoxContainer
	if vbox == null:
		return
	var head = vbox.get_node_or_null("TargetHead") as HBoxContainer
	ctrl._threat_chip = Label.new()
	ctrl._threat_chip.name = "ThreatChip"
	ctrl._threat_chip.text = "无仇恨"
	ctrl._threat_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._threat_chip.add_theme_font_size_override("font_size", 11)
	ctrl._threat_chip.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58, 1.0))
	ctrl._threat_chip.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.9))
	ctrl._threat_chip.add_theme_constant_override("outline_size", 2)
	ctrl._threat_chip.visible = ctrl._threat_visible
	if head != null:
		# Insert before close button (last child) when possible.
		head.add_child(ctrl._threat_chip)
		var close = head.get_node_or_null("TargetClose")
		if close != null:
			head.move_child(ctrl._threat_chip, close.get_index())
	else:
		vbox.add_child(ctrl._threat_chip)
		vbox.move_child(ctrl._threat_chip, 0)



static func _on_target_close_pressed(ctrl) -> void:
	## × clears HUD target and world selection / foot ring.
	if ctrl._world_combat != null and ctrl._world_combat.has_method("clear_target_selection"):
		ctrl._world_combat.clear_target_selection()
	else:
		ctrl.clear_target()



static func show_target(ctrl, 
	p_name: String,
	hp_ratio: float = 1.0,
	world_pos: Variant = null,
	show_hp_bar: bool = true,
	mp_ratio: float = -1.0,
	show_threat: bool = false,
	threat_you: bool = false
) -> void:
	ctrl._ensure_target_chrome()
	ctrl.target_panel.visible = true
	ctrl.target_name.text = p_name
	ctrl.target_hp.visible = show_hp_bar
	if show_hp_bar:
		ctrl.target_hp.max_value = 100.0
		ctrl.target_hp.value = clampf(hp_ratio, 0.0, 1.0) * 100.0
	else:
		ctrl.target_hp.value = 0
	var show_mp = show_hp_bar and mp_ratio >= 0.0
	if ctrl._target_mp != null:
		ctrl._target_mp.visible = show_mp
		if show_mp:
			ctrl._target_mp.max_value = 100.0
			ctrl._target_mp.value = clampf(mp_ratio, 0.0, 1.0) * 100.0
		else:
			ctrl._target_mp.value = 0
	if typeof(world_pos) == TYPE_VECTOR2:
		ctrl._target_world_pos = world_pos
		ctrl._update_target_angle()
	else:
		ctrl._target_world_pos = null
		if ctrl._radar and ctrl._radar.has_method("clear_target_angle"):
			ctrl._radar.clear_target_angle()
	ctrl.apply_threat_chip(show_threat, threat_you)


static func _update_target_angle(ctrl) -> void:
	if ctrl._radar == null:
		return
	if typeof(ctrl._target_world_pos) != TYPE_VECTOR2 or ctrl._radar_player == null:
		return
	var delta: Vector2 = (ctrl._target_world_pos as Vector2) - ctrl._radar_player.global_position
	if delta.length_squared() < 0.0001:
		if ctrl._radar.has_method("clear_target_angle"):
			ctrl._radar.clear_target_angle()
		return
	if ctrl._radar.has_method("set_target_angle"):
		ctrl._radar.set_target_angle(atan2(delta.y, delta.x))


