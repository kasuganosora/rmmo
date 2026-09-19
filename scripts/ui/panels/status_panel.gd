extends RefCounted
## UI panel: player status bar, HP/MP/CP, XP, buff chips.

var ctrl
func _init(c):
	ctrl = c

const StatusIconBar = preload("res://scripts/ui/status_icon_bar.gd")

func _compact_status_panel() -> void:
	## Lean top-left status: value text overlaid on bars (white, high contrast).
	var panel = ctrl.get_node_or_null("%StatusPanel") as PanelContainer
	if panel != null:
		panel.min_size = Vector2(160, 72)
		panel.default_size = Vector2(200, 88)
		panel.custom_minimum_size = Vector2(160, 72)
		panel.size = Vector2(200, 88)
	if ctrl.name_label != null:
		ctrl.name_label.add_theme_font_size_override("font_size", 12)
	if ctrl.level_label != null:
		ctrl.level_label.add_theme_font_size_override("font_size", 11)
	for lab in [ctrl.cp_text, ctrl.hp_text, ctrl.mp_text]:
		if lab != null:
			lab.visible = false
	# Color the fill via StyleBox (not modulate) so overlay Labels stay white.
	_style_status_bar(ctrl.cp_bar, Color(0.92, 0.78, 0.22, 1.0))
	_style_status_bar(ctrl.hp_bar, Color(0.82, 0.22, 0.22, 1.0))
	_style_status_bar(ctrl.mp_bar, Color(0.28, 0.42, 0.9, 1.0))
	_ensure_status_overlays()
	_ensure_xp_bar()
	_ensure_status_chip_row()
	ctrl._ensure_title_under_name()
	ctrl._ensure_cast_bar()



func _style_status_bar(bar: ProgressBar, fill: Color) -> void:
	if bar == null:
		return
	bar.custom_minimum_size = Vector2(0, 12)
	bar.modulate = Color(1, 1, 1, 1)  # never tint children
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	bg.set_corner_radius_all(3)
	bg.content_margin_left = 2
	bg.content_margin_right = 2
	bg.content_margin_top = 1
	bg.content_margin_bottom = 1
	var fg = StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)



func _ensure_status_overlays() -> void:
	ctrl._ensure_bar_overlay(ctrl.cp_bar, "CpOverlay")
	ctrl._ensure_bar_overlay(ctrl.hp_bar, "HpOverlay")
	ctrl._ensure_bar_overlay(ctrl.mp_bar, "MpOverlay")



func _ensure_xp_bar() -> void:
	## Thin EXP track under MP; created in code so tscn stays optional.
	if ctrl.mp_bar == null:
		return
	var vbox = ctrl.mp_bar.get_parent() as VBoxContainer
	if vbox == null:
		return
	if ctrl._xp_bar != null and is_instance_valid(ctrl._xp_bar):
		return
	var existing = vbox.get_node_or_null("XpBar") as ProgressBar
	if existing != null:
		ctrl._xp_bar = existing
	else:
		ctrl._xp_bar = ProgressBar.new()
		ctrl._xp_bar.name = "XpBar"
		ctrl._xp_bar.show_percentage = false
		ctrl._xp_bar.mouse_filter = Control.MOUSE_FILTER_STOP
		vbox.add_child(ctrl._xp_bar)
		vbox.move_child(ctrl._xp_bar, ctrl.mp_bar.get_index() + 1)
	ctrl._xp_bar.custom_minimum_size = Vector2(0, 5)
	ctrl._xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_status_bar(ctrl._xp_bar, Color(0.35, 0.78, 0.92, 1.0))
	ctrl._xp_bar.custom_minimum_size = Vector2(0, 5)



func _ensure_status_chip_row() -> void:
	## L2/FF14 icon strip under the CP/HP/MP panel (buffs then debuffs).
	var panel = ctrl.get_node_or_null("%StatusPanel") as PanelContainer
	if panel == null:
		return
	if ctrl._status_chip_row != null and is_instance_valid(ctrl._status_chip_row):
		return
	var existing = panel.get_parent().get_node_or_null("StatusIconBar") if panel.get_parent() else null
	if existing != null:
		ctrl._status_chip_row = existing
		_wire_player_status_bar(ctrl._status_chip_row)
		return
	var parent_ctl = panel.get_parent() as Control
	var bar = StatusIconBar.new()
	bar.name = "StatusIconBar"
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parent_ctl != null:
		parent_ctl.add_child(bar)
		parent_ctl.move_child(bar, panel.get_index() + 1)
	else:
		panel.add_child(bar)
	ctrl._status_chip_row = bar
	_wire_player_status_bar(bar)
	if bar.has_method("apply_statuses"):
		bar.apply_statuses(ctrl._player_statuses)



func _status_kind_color(kind: String) -> Color:
	match kind.strip_edges().to_lower():
		"buff":
			return Color(0.35, 0.85, 0.45, 1.0)
		"debuff":
			return Color(0.75, 0.4, 0.9, 1.0)
		"dot":
			return Color(0.95, 0.35, 0.3, 1.0)
		"hot":
			return Color(0.35, 0.8, 0.95, 1.0)
		_:
			return Color(0.75, 0.75, 0.8, 1.0)



func _rebuild_status_chips(row: HBoxContainer, statuses: Array) -> void:
	if row == null:
		return
	for c in row.get_children():
		c.queue_free()
	for s in statuses:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = s
		var n = str(d.get("name", d.get("id", "?"))).strip_edges()
		var rem: float = float(d.get("remaining_sec", 0.0))
		var txt = "%s %.0fs" % [n, rem] if rem >= 1.0 else "%s %.1fs" % [n, rem]
		var col = _status_kind_color(str(d.get("kind", "")))
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, 0.92)
		sb.set_border_width_all(1)
		sb.border_color = col
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		var chip = PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.add_theme_stylebox_override("panel", sb)
		var inner = Label.new()
		inner.text = txt
		inner.add_theme_font_size_override("font_size", 10)
		inner.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(inner)
		var desc = str(d.get("desc", d.get("description", ""))).strip_edges()
		var kind = str(d.get("kind", ""))
		chip.tooltip_text = "%s\n剩余 %.1f 秒%s%s" % [n, rem, ("\n" + kind) if kind != "" else "", ("\n" + desc) if desc != "" else ""]
		row.add_child(chip)



func apply_status_chips(statuses: Array) -> void:
	ctrl._player_statuses = statuses.duplicate(true)
	_ensure_status_chip_row()
	if ctrl._status_chip_row != null and ctrl._status_chip_row.has_method("apply_statuses"):
		ctrl._status_chip_row.apply_statuses(ctrl._player_statuses)
	elif ctrl._status_chip_row != null:
		_rebuild_status_chips(ctrl._status_chip_row, ctrl._player_statuses)
	# Soft-refresh expanded self row in party panel when statuses change.
	if ctrl._party_in_party():
		ctrl._sync_party_self_statuses_from_player()
		if ctrl._party_panel != null and ctrl._party_panel.visible:
			ctrl._refresh_party_panel()



func _wire_player_status_bar(bar: Control) -> void:
	if bar == null:
		return
	if "allow_cancel" in bar:
		bar.allow_cancel = true
	if bar.has_signal("cancel_requested"):
		if not bar.cancel_requested.is_connected(ctrl._on_status_cancel_requested):
			bar.cancel_requested.connect(ctrl._on_status_cancel_requested)



func _refresh_xp_bar() -> void:
	_ensure_xp_bar()
	if ctrl._xp_bar == null:
		return
	var exp_cur: int = maxi(int(ctrl._server_combat.get("exp", 0)), 0)
	var exp_next: int = int(ctrl._server_combat.get("exp_to_next", 0))
	var rested: int = maxi(int(ctrl._server_combat.get("rested_exp", 0)), 0)
	var tip = ""
	if exp_next <= 0:
		ctrl._xp_bar.max_value = 1.0
		ctrl._xp_bar.value = 1.0
		tip = "经验 %d" % exp_cur
	else:
		ctrl._xp_bar.max_value = float(exp_next)
		ctrl._xp_bar.value = float(mini(exp_cur, exp_next))
		tip = "经验 %d / %d" % [exp_cur, exp_next]
	if rested > 0:
		tip += "
休息 %d" % rested
		var rmax: int = int(ctrl._server_combat.get("rested_exp_max", 0))
		if rmax > 0:
			tip += " / %d" % rmax
	ctrl._xp_bar.tooltip_text = tip
	_refresh_rested_label(rested)



func _tick_status_icon_bars(delta: float) -> void:
	## Advance pie timers on player/target StatusIconBar strips (no-op if absent).
	if ctrl._status_chip_row != null and is_instance_valid(ctrl._status_chip_row) and ctrl._status_chip_row.has_method("tick"):
		ctrl._status_chip_row.tick(delta)
	if ctrl._target_status_chip_row != null and is_instance_valid(ctrl._target_status_chip_row) and ctrl._target_status_chip_row.has_method("tick"):
		ctrl._target_status_chip_row.tick(delta)



func apply_rested_update(action: Dictionary) -> void:
	## Snapshot / tick opcode: refresh rested pool on XP bar HUD.
	if action.has("rested_exp"):
		ctrl._server_combat["rested_exp"] = maxi(int(action.get("rested_exp", 0)), 0)
	if action.has("rested_exp_max"):
		ctrl._server_combat["rested_exp_max"] = maxi(int(action.get("rested_exp_max", 0)), 0)
	_refresh_xp_bar()



func _refresh_rested_label(rested: int = -1) -> void:
	_ensure_xp_bar()
	if ctrl._xp_bar == null:
		return
	if rested < 0:
		rested = maxi(int(ctrl._server_combat.get("rested_exp", 0)), 0)
	if ctrl._rested_label == null or not is_instance_valid(ctrl._rested_label):
		ctrl._rested_label = Label.new()
		ctrl._rested_label.name = "RestedLabel"
		ctrl._rested_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl._rested_label.add_theme_font_size_override("font_size", 10)
		ctrl._rested_label.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0, 1.0))
		ctrl._rested_label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 0.9))
		ctrl._rested_label.add_theme_constant_override("outline_size", 2)
		ctrl._rested_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ctrl._rested_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		ctrl._rested_label.offset_left = 2.0
		ctrl._rested_label.offset_right = -2.0
		ctrl._rested_label.offset_top = -1.0
		ctrl._rested_label.offset_bottom = 0.0
		ctrl._xp_bar.add_child(ctrl._rested_label)
	ctrl._rested_label.text = "休息 %d" % rested if rested > 0 else ""
	ctrl._rested_label.visible = rested > 0


