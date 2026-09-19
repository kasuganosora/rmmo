extends RefCounted
## UI panel: warehouse storage and gold.

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

static func _build_warehouse_panel(ctrl) -> void:
	ctrl._warehouse_panel = PanelContainer.new()
	ctrl._warehouse_panel.name = "WarehousePanel"
	ctrl._warehouse_panel.set_script(HudDrag)
	ctrl._warehouse_panel.screen_margin = 4.0
	ctrl._warehouse_panel.min_size = Vector2(420, 320)
	ctrl._warehouse_panel.default_size = Vector2(560, 420)
	ctrl._warehouse_panel.initial_dock = "none"
	ctrl._warehouse_panel.drag_anywhere = true
	ctrl.add_child(ctrl._warehouse_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._warehouse_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "WarehouseTitle"
	title.text = "仓库"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._warehouse_panel.visible = false)
	head.add_child(close_btn)
	ctrl._warehouse_body = VBoxContainer.new()
	ctrl._warehouse_body.name = "WarehouseBody"
	ctrl._warehouse_body.add_theme_constant_override("separation", 6)
	ctrl._warehouse_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(ctrl._warehouse_body)
	ctrl._warehouse_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._warehouse_panel)
	ctrl._refresh_warehouse_panel()
	ctrl.call_deferred("_nudge_warehouse")

static func _nudge_warehouse(ctrl) -> void:
	if ctrl._warehouse_panel == null:
		return
	ctrl._warehouse_panel.size = Vector2(560, 420)
	var vp = ctrl.get_viewport_rect().size
	ctrl._warehouse_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 280)), 72)

static func _toggle_warehouse_panel(ctrl, force_open: bool = false) -> void:
	if ctrl._warehouse_panel == null:
		return
	if force_open:
		ctrl._warehouse_panel.visible = true
	else:
		ctrl._warehouse_panel.visible = not ctrl._warehouse_panel.visible
	if ctrl._warehouse_panel.visible:
		if ctrl._world_combat != null and ctrl._world_combat.has_method("request_warehouse_open"):
			ctrl._world_combat.request_warehouse_open()
		else:
			var srv = Net.server()
			if srv != null and srv.has_method("try_warehouse_open"):
				ctrl._apply_warehouse_result_locally(srv.try_warehouse_open())
		ctrl._refresh_warehouse_panel()
		ctrl._warehouse_panel.move_to_front()
		ctrl.call_deferred("_nudge_warehouse")

static func apply_warehouse_update(ctrl, action: Dictionary) -> void:
	var wh_v: Variant = action.get("warehouse", action)
	if typeof(wh_v) != TYPE_DICTIONARY:
		return
	var wh: Dictionary = wh_v
	ctrl._warehouse_state = {
		"items": [],
		"gold": int(wh.get("gold", 0)),
		"max_slots": int(wh.get("max_slots", 60)),
		"used_slots": int(wh.get("used_slots", 0)),
	}
	var items_v: Variant = wh.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for it in items_v:
			if typeof(it) == TYPE_DICTIONARY:
				cleaned.append((it as Dictionary).duplicate(true))
		ctrl._warehouse_state["items"] = cleaned
		ctrl._warehouse_state["used_slots"] = cleaned.size()
	if ctrl._warehouse_panel != null and ctrl._warehouse_panel.visible:
		ctrl._refresh_warehouse_panel()

static func _refresh_warehouse_panel(ctrl) -> void:
	if ctrl._warehouse_body == null:
		return
	for c in ctrl._warehouse_body.get_children():
		c.queue_free()
	ctrl._warehouse_gold_spin = null
	var used: int = int(ctrl._warehouse_state.get("used_slots", 0))
	var cap: int = int(ctrl._warehouse_state.get("max_slots", 60))
	ctrl._add_label(ctrl._warehouse_body, "容量 %d / %d" % [used, cap], 11, L2Style.COL_MUTED)
	ctrl._add_label(ctrl._warehouse_body, "金币 %d" % int(ctrl._warehouse_state.get("gold", 0)), 12, L2Style.COL_TITLE)

	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ctrl._warehouse_body.add_child(cols)

	var bag_wrap = VBoxContainer.new()
	bag_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_wrap.add_theme_constant_override("separation", 4)
	cols.add_child(bag_wrap)
	ctrl._add_label(bag_wrap, "背包（双击存入）", 11, L2Style.COL_MUTED)
	var bag_scroll = ScrollContainer.new()
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_scroll.custom_minimum_size = Vector2(0, 180)
	bag_wrap.add_child(bag_scroll)
	var bag_list = VBoxContainer.new()
	bag_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_list.add_theme_constant_override("separation", 2)
	bag_scroll.add_child(bag_list)
	var bag_items: Array = ctrl._server_inventory
	if bag_items.is_empty():
		ctrl._add_label(bag_list, "（空）", 11, L2Style.COL_MUTED)
	else:
		for it in bag_items:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var iid = str(it.get("id", "")).strip_edges()
			var q: int = int(it.get("qty", 0))
			if iid.is_empty() or q <= 0:
				continue
			var row = Button.new()
			row.text = "%s ×%d" % [ctrl._item_label(iid), q]
			row.focus_mode = Control.FOCUS_NONE
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.tooltip_text = "存入 1 个（Shift+点击存入全部）"
			row.pressed.connect(ctrl._on_warehouse_deposit_pressed.bind(iid, q))
			bag_list.add_child(row)

	var wh_wrap = VBoxContainer.new()
	wh_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wh_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wh_wrap.add_theme_constant_override("separation", 4)
	cols.add_child(wh_wrap)
	ctrl._add_label(wh_wrap, "仓库（双击取出）", 11, L2Style.COL_MUTED)
	var wh_scroll = ScrollContainer.new()
	wh_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wh_scroll.custom_minimum_size = Vector2(0, 180)
	wh_wrap.add_child(wh_scroll)
	var wh_list = VBoxContainer.new()
	wh_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wh_list.add_theme_constant_override("separation", 2)
	wh_scroll.add_child(wh_list)
	var wh_items: Array = ctrl._warehouse_state.get("items", [])
	if wh_items.is_empty():
		ctrl._add_label(wh_list, "（空）", 11, L2Style.COL_MUTED)
	else:
		for it2 in wh_items:
			if typeof(it2) != TYPE_DICTIONARY:
				continue
			var wid = str(it2.get("id", "")).strip_edges()
			var wq: int = int(it2.get("qty", 0))
			if wid.is_empty() or wq <= 0:
				continue
			var wrow = Button.new()
			wrow.text = "%s ×%d" % [ctrl._item_label(wid), wq]
			wrow.focus_mode = Control.FOCUS_NONE
			wrow.alignment = HORIZONTAL_ALIGNMENT_LEFT
			wrow.tooltip_text = "取出 1 个（Shift+点击取出全部）"
			wrow.pressed.connect(ctrl._on_warehouse_withdraw_pressed.bind(wid, wq))
			wh_list.add_child(wrow)

	var gold_row = HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 6)
	ctrl._warehouse_body.add_child(gold_row)
	ctrl._add_label(gold_row, "金币", 12, L2Style.COL_TEXT)
	ctrl._warehouse_gold_spin = SpinBox.new()
	ctrl._warehouse_gold_spin.min_value = 1
	ctrl._warehouse_gold_spin.max_value = 999999999
	ctrl._warehouse_gold_spin.value = 1
	ctrl._warehouse_gold_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_row.add_child(ctrl._warehouse_gold_spin)
	var dep_g = Button.new()
	dep_g.text = "存入"
	dep_g.focus_mode = Control.FOCUS_NONE
	dep_g.pressed.connect(ctrl._on_warehouse_deposit_gold)
	gold_row.add_child(dep_g)
	var wd_g = Button.new()
	wd_g.text = "取出"
	wd_g.focus_mode = Control.FOCUS_NONE
	wd_g.pressed.connect(ctrl._on_warehouse_withdraw_gold)
	gold_row.add_child(wd_g)

static func _on_warehouse_deposit_pressed(ctrl, item_id: String, stack_qty: int) -> void:
	var qty = stack_qty if Input.is_key_pressed(KEY_SHIFT) else 1
	qty = clampi(qty, 1, maxi(stack_qty, 1))
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_warehouse_deposit"):
		ctrl._world_combat.request_warehouse_deposit(item_id, qty)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_warehouse_deposit"):
			ctrl._apply_warehouse_result_locally(srv.try_warehouse_deposit(item_id, qty))

static func _on_warehouse_withdraw_pressed(ctrl, item_id: String, stack_qty: int) -> void:
	var qty = stack_qty if Input.is_key_pressed(KEY_SHIFT) else 1
	qty = clampi(qty, 1, maxi(stack_qty, 1))
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_warehouse_withdraw"):
		ctrl._world_combat.request_warehouse_withdraw(item_id, qty)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_warehouse_withdraw"):
			ctrl._apply_warehouse_result_locally(srv.try_warehouse_withdraw(item_id, qty))

static func _on_warehouse_deposit_gold(ctrl) -> void:
	var amount: int = int(ctrl._warehouse_gold_spin.value) if ctrl._warehouse_gold_spin else 1
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_warehouse_deposit_gold"):
		ctrl._world_combat.request_warehouse_deposit_gold(amount)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_warehouse_deposit_gold"):
			ctrl._apply_warehouse_result_locally(srv.try_warehouse_deposit_gold(amount))

static func _on_warehouse_withdraw_gold(ctrl) -> void:
	var amount: int = int(ctrl._warehouse_gold_spin.value) if ctrl._warehouse_gold_spin else 1
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_warehouse_withdraw_gold"):
		ctrl._world_combat.request_warehouse_withdraw_gold(amount)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_warehouse_withdraw_gold"):
			ctrl._apply_warehouse_result_locally(srv.try_warehouse_withdraw_gold(amount))

static func _apply_warehouse_result_locally(ctrl, result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"warehouse_update":
				ctrl.apply_warehouse_update(action)
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				ctrl.apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)

