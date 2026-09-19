extends RefCounted
## UI panel: ground drop zone and drop-qty dialog.

var ctrl
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

func _ensure_ground_drop_zone() -> void:
	if ctrl._ground_drop_zone != null and is_instance_valid(ctrl._ground_drop_zone):
		return
	var z = preload("res://scripts/ui/ground_drop_zone.gd").new()
	z.name = "GroundDropZone"
	ctrl.add_child(z)
	ctrl.move_child(z, 0)
	z.ground_drop_item.connect(ctrl._on_inventory_item_drop)
	z.ground_drop_equipped.connect(ctrl._on_equip_slot_drop)
	ctrl._ground_drop_zone = z



func _tick_ground_drop_zone() -> void:
	## Arm full-screen drop sink only while dragging bag/equip items (not window/skill drags).
	var want = false
	if ctrl.get_viewport().gui_is_dragging():
		var data = ctrl.get_viewport().gui_get_drag_data()
		if typeof(data) == TYPE_DICTIONARY:
			var kind = str(data.get("kind", ""))
			want = kind == "item" or kind == "equipped"
	if want == ctrl._ground_drop_armed:
		return
	ctrl._ground_drop_armed = want
	_ensure_ground_drop_zone()
	if ctrl._ground_drop_zone != null and ctrl._ground_drop_zone.has_method("set_active"):
		ctrl._ground_drop_zone.set_active(want)



func _ensure_ground_tip() -> void:
	if ctrl._ground_tip != null and is_instance_valid(ctrl._ground_tip):
		return
	var tip = PanelContainer.new()
	tip.name = "GroundItemTip"
	tip.visible = false
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.z_index = 80
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.10, 0.92)
	sb.border_color = Color(0.55, 0.5, 0.35, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	tip.add_theme_stylebox_override("panel", sb)
	var lab = Label.new()
	lab.name = "Text"
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	tip.add_child(lab)
	ctrl.add_child(tip)
	ctrl._ground_tip = tip
	ctrl._ground_tip_label = lab



func show_ground_tip(text: String, screen_pos: Vector2) -> void:
	_ensure_ground_tip()
	if ctrl._ground_tip == null or ctrl._ground_tip_label == null:
		return
	ctrl._ground_tip_label.text = text.strip_edges()
	ctrl._ground_tip.visible = not ctrl._ground_tip_label.text.is_empty()
	move_ground_tip(screen_pos)



func move_ground_tip(screen_pos: Vector2) -> void:
	if ctrl._ground_tip == null or not ctrl._ground_tip.visible:
		return
	# Offset so tip does not sit under the cursor.
	var pos = screen_pos + Vector2(16, 18)
	var vp = ctrl.get_viewport_rect().size
	var sz = ctrl._ground_tip.get_combined_minimum_size()
	if ctrl._ground_tip.size.x > 1.0:
		sz = ctrl._ground_tip.size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - sz.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - sz.y - 4.0))
	ctrl._ground_tip.position = pos



func hide_ground_tip() -> void:
	if ctrl._ground_tip != null:
		ctrl._ground_tip.visible = false



func _show_drop_qty_dialog(item_id: String, max_qty: int) -> void:
	_ensure_drop_qty_dialog()
	ctrl._drop_qty_item_id = item_id
	max_qty = maxi(max_qty, 1)
	if ctrl._qty_mode != "split":
		ctrl._qty_mode = "drop"
	if ctrl._drop_qty_label != null:
		if ctrl._qty_mode == "split":
			ctrl._drop_qty_label.text = "拆分：%s（最多 %d）" % [ctrl._item_label(item_id), max_qty]
		else:
			ctrl._drop_qty_label.text = "丢掉：%s（最多 %d）" % [ctrl._item_label(item_id), max_qty]
	if ctrl._drop_qty_spin != null:
		ctrl._drop_qty_spin.min_value = 1
		ctrl._drop_qty_spin.max_value = max_qty
		ctrl._drop_qty_spin.value = 1
	if ctrl._drop_qty_panel != null:
		ctrl._drop_qty_panel.visible = true
		ctrl._drop_qty_panel.reset_size()
		var vp = ctrl.get_viewport_rect().size
		var sz = ctrl._drop_qty_panel.get_combined_minimum_size()
		if ctrl._drop_qty_panel.size.x > 1.0:
			sz = ctrl._drop_qty_panel.size
		ctrl._drop_qty_panel.position = Vector2(
			(vp.x - sz.x) * 0.5,
			(vp.y - sz.y) * 0.5
		)
		var parent = ctrl._drop_qty_panel.get_parent()
		if parent != null:
			parent.move_child(ctrl._drop_qty_panel, parent.get_child_count() - 1)



func _ensure_drop_qty_dialog() -> void:
	if ctrl._drop_qty_panel != null and is_instance_valid(ctrl._drop_qty_panel):
		return
	var panel = PanelContainer.new()
	panel.name = "DropQtyDialog"
	panel.visible = false
	panel.z_index = 90
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	L2Style.apply_panel(panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 28)
	marg.add_theme_constant_override("margin_top", 24)
	marg.add_theme_constant_override("margin_right", 28)
	marg.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(marg)
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	marg.add_child(root)
	var title = Label.new()
	title.text = "丢弃数量"
	L2Style.style_title(title)
	root.add_child(title)
	var info = Label.new()
	info.name = "Info"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(220, 0)
	info.add_theme_color_override("font_color", L2Style.COL_TEXT)
	root.add_child(info)
	ctrl._drop_qty_label = info
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	var qty_lab = Label.new()
	qty_lab.text = "数量"
	qty_lab.add_theme_color_override("font_color", L2Style.COL_MUTED)
	row.add_child(qty_lab)
	var spin = SpinBox.new()
	spin.name = "Qty"
	spin.min_value = 1
	spin.max_value = 99
	spin.value = 1
	spin.rounded = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	ctrl._drop_qty_spin = spin
	var btns = HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(btns)
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(_on_drop_qty_cancel)
	L2Style.style_action_button(cancel)
	btns.add_child(cancel)
	var ok = Button.new()
	ok.text = "确定"
	ok.pressed.connect(_on_drop_qty_confirm)
	L2Style.style_action_button(ok)
	btns.add_child(ok)
	panel.custom_minimum_size = Vector2(340, 220)
	ctrl.add_child(panel)
	ctrl._drop_qty_panel = panel



func _on_drop_qty_cancel() -> void:
	ctrl._drop_qty_item_id = ""
	ctrl._qty_mode = "drop"
	if ctrl._drop_qty_panel != null:
		ctrl._drop_qty_panel.visible = false



func _on_drop_qty_confirm() -> void:
	var iid = ctrl._drop_qty_item_id.strip_edges()
	var q: int = 1
	if ctrl._drop_qty_spin != null:
		q = int(ctrl._drop_qty_spin.value)
	var mode = ctrl._qty_mode
	_on_drop_qty_cancel()
	if iid.is_empty():
		return
	var have: int = ctrl._inventory_qty(iid)
	if have > 0:
		q = clampi(q, 1, have)
	else:
		q = maxi(q, 1)
	if mode == "split":
		if ctrl._world_combat != null and ctrl._world_combat.has_method("request_inventory_split"):
			ctrl._world_combat.request_inventory_split(iid, q)
		else:
			var srv = Net.server()
			if srv != null and srv.has_method("try_inventory_split"):
				ctrl._apply_equip_result_locally(srv.try_inventory_split(iid, q))
		return
	ctrl._commit_drop_item(iid, q)



