extends RefCounted
## UI module: transient overlay toasts / floats — level-up, AFK warn, EXP gain, item gain.
## State (nodes, ttl, counters) lives on the HUD (ctrl); this module owns the logic.
## Gold float lives in inventory_panel; quest toast in quest_panel.

var ctrl
func _init(c):
	ctrl = c

const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const AfkWarnUtil = preload("res://scripts/game/afk_warn_util.gd")
const LEVEL_TOAST_DURATION := 2.0
const AFK_TOAST_DURATION := 3.0
const EXP_FLOAT_DURATION := 1.2
const ITEM_FLOAT_DURATION := 1.2
const ITEM_FLOAT_MAX_LINES := 3


# ---- Level-up toast ----
func _build_level_toast() -> void:
	if ctrl._level_toast != null and is_instance_valid(ctrl._level_toast):
		return
	ctrl._level_toast = PanelContainer.new()
	ctrl._level_toast.name = "LevelUpToast"
	ctrl._level_toast.visible = false
	ctrl._level_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._level_toast.z_index = 80
	ctrl.add_child(ctrl._level_toast)
	var marg := MarginContainer.new()
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marg.add_theme_constant_override("margin_left", 18)
	marg.add_theme_constant_override("margin_top", 10)
	marg.add_theme_constant_override("margin_right", 18)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._level_toast.add_child(marg)
	ctrl._level_toast_label = Label.new()
	ctrl._level_toast_label.name = "LevelUpToastLabel"
	ctrl._level_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._level_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctrl._level_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ctrl._level_toast_label.add_theme_font_size_override("font_size", 22)
	ctrl._level_toast_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1.0))
	ctrl._level_toast_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 0.95))
	ctrl._level_toast_label.add_theme_constant_override("outline_size", 4)
	ctrl._level_toast_label.text = "升级！"
	marg.add_child(ctrl._level_toast_label)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.12, 0.88)
	sb.border_color = Color(0.85, 0.72, 0.28, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	ctrl._level_toast.add_theme_stylebox_override("panel", sb)


## Public toast API (headless tests + world level_up path).
## sp_gained > 0 appends 「获得技能点」; mouse-filter ignore so input stays free.
func show_level_up_toast(level: int, sp_gained: int = 0) -> void:
	_build_level_toast()
	if ctrl._level_toast == null:
		return
	ctrl._level_toast_level = maxi(level, 1)
	ctrl._level_toast_sp_note = sp_gained > 0
	ctrl._level_toast_armed = true
	ctrl._level_toast_ttl = LEVEL_TOAST_DURATION
	_refresh_level_toast_text()
	ctrl._level_toast.visible = true
	_layout_level_toast()
	ctrl._level_toast.move_to_front()


func hide_level_up_toast() -> void:
	ctrl._level_toast_ttl = 0.0
	ctrl._level_toast_armed = false
	ctrl._level_toast_sp_note = false
	if ctrl._level_toast != null:
		ctrl._level_toast.visible = false


func is_level_up_toast_visible() -> bool:
	return ctrl._level_toast != null and ctrl._level_toast.visible and ctrl._level_toast_ttl > 0.0


func get_level_up_toast_text() -> String:
	if ctrl._level_toast_label == null:
		return ""
	return str(ctrl._level_toast_label.text)


func _set_level_toast_sp_note(on: bool) -> void:
	if not ctrl._level_toast_armed:
		return
	ctrl._level_toast_sp_note = on
	# Refresh TTL slightly so SP note is readable after late skill_book_update.
	ctrl._level_toast_ttl = maxf(ctrl._level_toast_ttl, 1.2)
	_refresh_level_toast_text()
	_layout_level_toast()


func _refresh_level_toast_text() -> void:
	if ctrl._level_toast_label == null:
		return
	var line := "升级！Lv.%d" % ctrl._level_toast_level
	if ctrl._level_toast_sp_note:
		line += "\n获得技能点"
	ctrl._level_toast_label.text = line


func _layout_level_toast() -> void:
	if ctrl._level_toast == null:
		return
	ctrl._level_toast.reset_size()
	var vp: Vector2 = ctrl.get_viewport_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1280, 720)
	var sz: Vector2 = ctrl._level_toast.get_combined_minimum_size()
	if sz.x < 1.0:
		sz = ctrl._level_toast.size
	ctrl._level_toast.position = Vector2((vp.x - sz.x) * 0.5, 56.0)


func _tick_level_toast(delta: float) -> void:
	if ctrl._level_toast_ttl <= 0.0:
		return
	ctrl._level_toast_ttl -= delta
	if ctrl._level_toast_ttl <= 0.0:
		hide_level_up_toast()


# ---- AFK warn toast ----
func _note_player_input() -> void:
	ctrl._last_input_sec = Time.get_ticks_msec() / 1000.0
	ctrl._afk_warned = false


func _tick_afk_warn(_delta: float) -> void:
	_tick_afk_toast(_delta)
	var gs := GameSettingsScript.get_i()
	var minutes: int = 10
	if gs != null and "afk_warn_minutes" in gs:
		minutes = int(gs.afk_warn_minutes)
	var threshold := AfkWarnUtil.threshold_sec_from_minutes(minutes)
	var now := Time.get_ticks_msec() / 1000.0
	var idle: float = now - ctrl._last_input_sec
	if not AfkWarnUtil.should_warn(idle, threshold, ctrl._afk_warned):
		return
	ctrl._afk_warned = true
	show_afk_warn_toast(true)
	ctrl.append_system("你已离开一段时间。建议按 R 坐下休息。")


func _build_afk_toast() -> void:
	if ctrl._afk_toast != null and is_instance_valid(ctrl._afk_toast):
		return
	ctrl._afk_toast = PanelContainer.new()
	ctrl._afk_toast.name = "AfkWarnToast"
	ctrl._afk_toast.visible = false
	ctrl._afk_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._afk_toast.z_index = 80
	ctrl.add_child(ctrl._afk_toast)
	var marg := MarginContainer.new()
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marg.add_theme_constant_override("margin_left", 18)
	marg.add_theme_constant_override("margin_top", 10)
	marg.add_theme_constant_override("margin_right", 18)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._afk_toast.add_child(marg)
	ctrl._afk_toast_label = Label.new()
	ctrl._afk_toast_label.name = "AfkWarnToastLabel"
	ctrl._afk_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._afk_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctrl._afk_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ctrl._afk_toast_label.add_theme_font_size_override("font_size", 18)
	ctrl._afk_toast_label.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0, 1.0))
	ctrl._afk_toast_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 0.95))
	ctrl._afk_toast_label.add_theme_constant_override("outline_size", 4)
	ctrl._afk_toast_label.text = "你已离开一段时间"
	marg.add_child(ctrl._afk_toast_label)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.12, 0.88)
	sb.border_color = Color(0.55, 0.70, 0.95, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	ctrl._afk_toast.add_theme_stylebox_override("panel", sb)


## Non-blocking AFK banner. Optional soft sit line; never locks input / disconnects.
func show_afk_warn_toast(suggest_sit: bool = true) -> void:
	_build_afk_toast()
	if ctrl._afk_toast == null or ctrl._afk_toast_label == null:
		return
	var line := "你已离开一段时间"
	if suggest_sit:
		line += "\n建议坐下休息（R）"
	ctrl._afk_toast_label.text = line
	ctrl._afk_toast_ttl = AFK_TOAST_DURATION
	ctrl._afk_toast.visible = true
	_layout_afk_toast()
	ctrl._afk_toast.move_to_front()


func hide_afk_warn_toast() -> void:
	ctrl._afk_toast_ttl = 0.0
	if ctrl._afk_toast != null:
		ctrl._afk_toast.visible = false


func is_afk_warn_toast_visible() -> bool:
	return ctrl._afk_toast != null and ctrl._afk_toast.visible and ctrl._afk_toast_ttl > 0.0


func get_afk_warn_toast_text() -> String:
	if ctrl._afk_toast_label == null:
		return ""
	return str(ctrl._afk_toast_label.text)


func _layout_afk_toast() -> void:
	if ctrl._afk_toast == null:
		return
	ctrl._afk_toast.reset_size()
	var vp: Vector2 = ctrl.get_viewport_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1280, 720)
	var sz: Vector2 = ctrl._afk_toast.get_combined_minimum_size()
	if sz.x < 1.0:
		sz = ctrl._afk_toast.size
	ctrl._afk_toast.position = Vector2((vp.x - sz.x) * 0.5, 100.0)


func _tick_afk_toast(delta: float) -> void:
	if ctrl._afk_toast_ttl <= 0.0:
		return
	ctrl._afk_toast_ttl -= delta
	if ctrl._afk_toast_ttl <= 0.0:
		hide_afk_warn_toast()


# ---- EXP gain float ----
func _build_exp_float() -> void:
	if ctrl._exp_float != null and is_instance_valid(ctrl._exp_float):
		return
	ctrl._exp_float = Label.new()
	ctrl._exp_float.name = "ExpGainFloat"
	ctrl._exp_float.visible = false
	ctrl._exp_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._exp_float.z_index = 75
	ctrl._exp_float.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ctrl._exp_float.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ctrl._exp_float.add_theme_font_size_override("font_size", 14)
	ctrl._exp_float.add_theme_color_override("font_color", Color(0.45, 0.88, 1.0, 1.0))
	ctrl._exp_float.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.08, 0.9))
	ctrl._exp_float.add_theme_constant_override("outline_size", 3)
	ctrl._exp_float.text = "经验 +0"
	ctrl.add_child(ctrl._exp_float)


## Public EXP float API (headless tests + world exp_gain path).
## Rapid/same-frame gains coalesce into one tip showing the sum.
func show_exp_gain_float(amount: int) -> void:
	amount = int(amount)
	if amount <= 0:
		return
	if not GameSettingsScript.flag("show_exp_floats", true):
		return
	_build_exp_float()
	if ctrl._exp_float == null:
		return
	if ctrl._exp_float_ttl > 0.0:
		ctrl._exp_float_amount += amount
	else:
		ctrl._exp_float_amount = amount
	ctrl._exp_float_ttl = EXP_FLOAT_DURATION
	ctrl._exp_float.text = "经验 +%d" % ctrl._exp_float_amount
	ctrl._exp_float.modulate = Color(1, 1, 1, 1)
	ctrl._exp_float.visible = true
	_layout_exp_float()
	ctrl._exp_float.move_to_front()


func hide_exp_gain_float() -> void:
	ctrl._exp_float_ttl = 0.0
	ctrl._exp_float_amount = 0
	if ctrl._exp_float != null:
		ctrl._exp_float.visible = false
		ctrl._exp_float.modulate = Color(1, 1, 1, 1)


func is_exp_gain_float_visible() -> bool:
	return ctrl._exp_float != null and ctrl._exp_float.visible and ctrl._exp_float_ttl > 0.0


func get_exp_gain_float_text() -> String:
	if ctrl._exp_float == null:
		return ""
	return str(ctrl._exp_float.text)


func get_exp_gain_float_amount() -> int:
	return ctrl._exp_float_amount if ctrl._exp_float_ttl > 0.0 else 0


func _layout_exp_float() -> void:
	if ctrl._exp_float == null:
		return
	ctrl._exp_float.reset_size()
	var pos := Vector2(16.0, 118.0)
	var panel := ctrl.get_node_or_null("%StatusPanel") as Control
	if panel != null and is_instance_valid(panel):
		var pr: Rect2 = panel.get_global_rect()
		# Local to HUD: float just under status / XP bar.
		pos = Vector2(pr.position.x + 8.0, pr.position.y + pr.size.y + 4.0) - ctrl.global_position
	ctrl._exp_float.position = pos


func _tick_exp_float(delta: float) -> void:
	if ctrl._exp_float_ttl <= 0.0:
		return
	ctrl._exp_float_ttl -= delta
	if ctrl._exp_float != null and is_instance_valid(ctrl._exp_float):
		# Fade in last ~0.4s.
		var a: float = 1.0
		if ctrl._exp_float_ttl < 0.4:
			a = clampf(ctrl._exp_float_ttl / 0.4, 0.0, 1.0)
		ctrl._exp_float.modulate = Color(1, 1, 1, a)
		# Slight rise while alive.
		var rise: float = (EXP_FLOAT_DURATION - maxf(ctrl._exp_float_ttl, 0.0)) * 10.0
		# Re-anchor under status; Y drifts up while fading.
		_layout_exp_float()
		ctrl._exp_float.position.y -= rise
	if ctrl._exp_float_ttl <= 0.0:
		hide_exp_gain_float()


# ---- Item gain floats ----
func _emit_item_gain_floats_from_delta(prev_qty: Dictionary, new_qty: Dictionary) -> void:
	var gains: Array = []
	for iid in new_qty.keys():
		var nid := str(iid)
		var delta: int = int(new_qty.get(nid, 0)) - int(prev_qty.get(nid, 0))
		if delta > 0:
			gains.append({"id": nid, "qty": delta})
	if gains.is_empty():
		return
	# Prefer larger stacks first so loot_all keeps useful tips under the cap.
	gains.sort_custom(func(a, b): return int(a.get("qty", 0)) > int(b.get("qty", 0)))
	for g in gains:
		show_item_gain_float(str(g.get("id", "")), int(g.get("qty", 0)))


func _build_item_floats() -> void:
	if ctrl._item_float_host != null and is_instance_valid(ctrl._item_float_host):
		return
	ctrl._item_float_host = VBoxContainer.new()
	ctrl._item_float_host.name = "ItemGainFloats"
	ctrl._item_float_host.visible = false
	ctrl._item_float_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._item_float_host.z_index = 75
	ctrl._item_float_host.add_theme_constant_override("separation", 2)
	ctrl.add_child(ctrl._item_float_host)


func _make_item_float_label() -> Label:
	var lab := Label.new()
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 14)
	# Soft green — distinct from cyan exp / yellow gold.
	lab.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55, 1.0))
	lab.add_theme_color_override("font_outline_color", Color(0.02, 0.12, 0.04, 0.92))
	lab.add_theme_constant_override("outline_size", 3)
	return lab


## Public item float API. Coalesces same item_id while TTL alive; caps concurrent lines.
func show_item_gain_float(item_id: String, qty: int, display_name: String = "") -> void:
	item_id = item_id.strip_edges()
	qty = int(qty)
	if item_id.is_empty() or qty <= 0:
		return
	if not GameSettingsScript.flag("show_item_floats", true):
		return
	_build_item_floats()
	if ctrl._item_float_host == null:
		return
	var dname := display_name.strip_edges()
	if dname.is_empty():
		dname = ctrl._item_label(item_id)
		if dname.is_empty():
			dname = item_id
	dname = ctrl._item_rarity_name_line(item_id, dname)
	# Coalesce into existing active line for same id.
	for entry in ctrl._item_floats:
		if str(entry.get("id", "")) != item_id:
			continue
		entry["qty"] = int(entry.get("qty", 0)) + qty
		entry["ttl"] = ITEM_FLOAT_DURATION
		if not dname.is_empty():
			entry["name"] = dname
		var lab: Label = entry.get("label") as Label
		if lab != null and is_instance_valid(lab):
			lab.text = "获得：%s ×%d" % [str(entry.get("name", dname)), int(entry.get("qty", 0))]
			lab.modulate = Color(1, 1, 1, 1)
		_layout_item_floats()
		return
	# Cap concurrent unique lines (loot_all safety).
	if ctrl._item_floats.size() >= ITEM_FLOAT_MAX_LINES:
		return
	var lab2 := _make_item_float_label()
	lab2.name = "ItemGainFloat_%s" % item_id
	lab2.text = "获得：%s ×%d" % [dname, qty]
	ctrl._item_float_host.add_child(lab2)
	ctrl._item_floats.append({
		"id": item_id,
		"qty": qty,
		"ttl": ITEM_FLOAT_DURATION,
		"label": lab2,
		"name": dname,
	})
	ctrl._item_float_host.visible = true
	_layout_item_floats()
	ctrl._item_float_host.move_to_front()


func hide_item_gain_floats() -> void:
	for entry in ctrl._item_floats:
		var lab: Label = entry.get("label") as Label
		if lab != null and is_instance_valid(lab):
			lab.queue_free()
	ctrl._item_floats.clear()
	if ctrl._item_float_host != null and is_instance_valid(ctrl._item_float_host):
		ctrl._item_float_host.visible = false


func is_item_gain_float_visible() -> bool:
	return not ctrl._item_floats.is_empty()


func get_item_gain_float_count() -> int:
	return ctrl._item_floats.size()


func get_item_gain_float_texts() -> Array:
	var out: Array = []
	for entry in ctrl._item_floats:
		var lab: Label = entry.get("label") as Label
		if lab != null and is_instance_valid(lab):
			out.append(str(lab.text))
		else:
			out.append("获得：%s ×%d" % [str(entry.get("name", entry.get("id", ""))), int(entry.get("qty", 0))])
	return out


func get_item_gain_float_qty(item_id: String) -> int:
	item_id = item_id.strip_edges()
	for entry in ctrl._item_floats:
		if str(entry.get("id", "")) == item_id and float(entry.get("ttl", 0.0)) > 0.0:
			return int(entry.get("qty", 0))
	return 0


func _layout_item_floats() -> void:
	if ctrl._item_float_host == null:
		return
	var pos := Vector2(16.0, 154.0)
	var panel := ctrl.get_node_or_null("%StatusPanel") as Control
	if panel != null and is_instance_valid(panel):
		var pr: Rect2 = panel.get_global_rect()
		# Under gold float band (exp +4, gold +22 → items +40).
		pos = Vector2(pr.position.x + 8.0, pr.position.y + pr.size.y + 40.0) - ctrl.global_position
	ctrl._item_float_host.position = pos


func _tick_item_floats(delta: float) -> void:
	if ctrl._item_floats.is_empty():
		return
	var remain: Array = []
	for entry in ctrl._item_floats:
		var ttl: float = float(entry.get("ttl", 0.0)) - delta
		entry["ttl"] = ttl
		var lab: Label = entry.get("label") as Label
		if lab != null and is_instance_valid(lab):
			var a: float = 1.0
			if ttl < 0.4:
				a = clampf(ttl / 0.4, 0.0, 1.0)
			lab.modulate = Color(1, 1, 1, a)
		if ttl > 0.0:
			remain.append(entry)
		else:
			if lab != null and is_instance_valid(lab):
				lab.queue_free()
	ctrl._item_floats = remain
	_layout_item_floats()
	if ctrl._item_floats.is_empty() and ctrl._item_float_host != null and is_instance_valid(ctrl._item_float_host):
		ctrl._item_float_host.visible = false
