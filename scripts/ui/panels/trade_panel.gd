extends RefCounted
## UI panel: trade window with item/gold exchange.

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

static func _on_trade_open_with(ctrl, partner_name: String) -> void:
	partner_name = str(partner_name).strip_edges()
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_open"):
		ctrl._world_combat.request_trade_open(partner_name)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_open"):
		ctrl._apply_trade_result_locally(srv.try_trade_open(partner_name))

static func _build_trade_panel(ctrl) -> void:
	ctrl._trade_panel = PanelContainer.new()
	ctrl._trade_panel.name = "TradePanel"
	ctrl._trade_panel.set_script(HudDrag)
	ctrl._trade_panel.screen_margin = 4.0
	ctrl._trade_panel.min_size = Vector2(360, 260)
	ctrl._trade_panel.default_size = Vector2(520, 400)
	ctrl._trade_panel.initial_dock = "none"
	ctrl._trade_panel.drag_anywhere = true
	ctrl.add_child(ctrl._trade_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._trade_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "TradeTitle"
	title.text = "交易"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(ctrl._on_trade_cancel)
	head.add_child(close_btn)
	ctrl._trade_body = VBoxContainer.new()
	ctrl._trade_body.name = "TradeBody"
	ctrl._trade_body.add_theme_constant_override("separation", 6)
	ctrl._trade_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(ctrl._trade_body)
	ctrl._trade_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._trade_panel)
	ctrl._refresh_trade_panel()
	ctrl.call_deferred("_nudge_trade")

static func _nudge_trade(ctrl) -> void:
	if ctrl._trade_panel:
		ctrl._trade_panel.size = Vector2(520, 400)
		var vp = ctrl.get_viewport_rect().size
		ctrl._trade_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 260)), 80)

static func _toggle_trade_panel(ctrl) -> void:
	## Legacy no-op for callers; trade is started only via player right-click.
	if ctrl._trade_panel == null:
		return
	if not bool(ctrl._trade_state.get("active", false)):
		ctrl.append_system("交易请右键玩家发起。")
		ctrl.hide_trade()
		return
	ctrl._trade_panel.visible = not ctrl._trade_panel.visible
	if ctrl._trade_panel.visible:
		ctrl._refresh_trade_panel()
		ctrl.call_deferred("_nudge_trade")

static func apply_trade_update(ctrl, action: Dictionary) -> void:
	var trade_v: Variant = action.get("trade", action)
	if typeof(trade_v) != TYPE_DICTIONARY:
		return
	var trade: Dictionary = trade_v
	if not bool(trade.get("active", true)) and str(trade.get("session_id", "")).is_empty():
		ctrl._trade_state = {"active": false}
		ctrl.hide_trade()
		return
	ctrl._trade_state = trade.duplicate(true)
	ctrl._trade_state["active"] = true
	if ctrl._trade_panel != null:
		ctrl._trade_panel.visible = true
		ctrl._refresh_trade_panel()
		ctrl.call_deferred("_nudge_trade")

static func hide_trade(ctrl) -> void:
	ctrl._trade_state = {"active": false}
	if ctrl._trade_panel != null:
		ctrl._trade_panel.visible = false

static func _refresh_trade_panel(ctrl) -> void:
	if ctrl._trade_body == null:
		return
	for c in ctrl._trade_body.get_children():
		c.queue_free()
	ctrl._trade_gold_spin = null
	if not bool(ctrl._trade_state.get("active", false)):
		ctrl._add_label(ctrl._trade_body, "未在交易。右键玩家 →「交易」发起。", 11, L2Style.COL_MUTED)
		# Keep panel hidden when idle — no HUD button / stub open.
		if ctrl._trade_panel != null:
			ctrl._trade_panel.visible = false
		return
	var pname = str(ctrl._trade_state.get("partner_name", "对方"))
	var title_l = ctrl._trade_panel.find_child("TradeTitle", true, false) as Label
	if title_l != null:
		title_l.text = "交易 · %s" % pname
		L2Style.style_title(title_l)
	ctrl._add_label(ctrl._trade_body, "对方：%s" % pname, 12, L2Style.COL_TITLE)
	var cols = GridContainer.new()
	cols.columns = 2
	cols.add_theme_constant_override("h_separation", 10)
	cols.add_theme_constant_override("v_separation", 4)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ctrl._trade_body.add_child(cols)
	var my_wrap = PanelContainer.new()
	my_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	my_wrap.custom_minimum_size = Vector2(180, 120)
	my_wrap.add_theme_stylebox_override("panel", L2Style.inner_box())
	cols.add_child(my_wrap)
	var their_wrap = PanelContainer.new()
	their_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	their_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	their_wrap.custom_minimum_size = Vector2(180, 120)
	their_wrap.add_theme_stylebox_override("panel", L2Style.inner_box())
	cols.add_child(their_wrap)
	var my_col = VBoxContainer.new()
	my_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_col.add_theme_constant_override("separation", 4)
	my_wrap.add_child(my_col)
	var their_col = VBoxContainer.new()
	their_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	their_col.add_theme_constant_override("separation", 4)
	their_wrap.add_child(their_col)
	ctrl._add_label(my_col, "你的报价", 11, L2Style.COL_MUTED)
	ctrl._add_label(their_col, "对方报价", 11, L2Style.COL_MUTED)
	ctrl._fill_trade_item_list(my_col, ctrl._trade_state.get("my_items", []), true)
	ctrl._fill_trade_item_list(their_col, ctrl._trade_state.get("their_items", []), false)
	ctrl._add_label(my_col, "Adena  %d" % int(ctrl._trade_state.get("my_gold", 0)), 12, L2Style.COL_GOLD)
	ctrl._add_label(their_col, "Adena  %d" % int(ctrl._trade_state.get("their_gold", 0)), 12, L2Style.COL_GOLD)
	var ready_me = bool(ctrl._trade_state.get("my_ready", false))
	var ready_them = bool(ctrl._trade_state.get("their_ready", false))
	ctrl._add_label(
		ctrl._trade_body,
		"锁定：你[%s] / 对方[%s]" % ["是" if ready_me else "否", "是" if ready_them else "否"],
		11,
		L2Style.COL_TEXT
	)
	if not ready_me:
		# Put items from bag (first few stacks as quick buttons)
		ctrl._add_label(ctrl._trade_body, "从背包放入（×1）：", 10, L2Style.COL_MUTED)
		var bag_row = HFlowContainer.new()
		bag_row.add_theme_constant_override("h_separation", 4)
		bag_row.add_theme_constant_override("v_separation", 4)
		ctrl._trade_body.add_child(bag_row)
		var added = 0
		for it in ctrl._server_inventory:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var iid = str(it.get("id", "")).strip_edges()
			var q: int = int(it.get("qty", 0))
			if iid.is_empty() or q <= 0:
				continue
			var b = Button.new()
			b.text = "%s×%d" % [ctrl._item_label(iid), q]
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(ctrl._on_trade_put_item.bind(iid))
			L2Style.style_compact_button(b)
			bag_row.add_child(b)
			added += 1
			if added >= 8:
				break
		if added == 0:
			ctrl._add_label(bag_row, "（背包为空）", 10, L2Style.COL_MUTED)
		var gold_row = HBoxContainer.new()
		gold_row.add_theme_constant_override("separation", 6)
		ctrl._trade_body.add_child(gold_row)
		ctrl._add_label(gold_row, "放入 Adena", 11, L2Style.COL_TEXT)
		var spin = SpinBox.new()
		spin.min_value = 0
		spin.max_value = maxi(ctrl._server_gold + int(ctrl._trade_state.get("my_gold", 0)), 0)
		spin.value = int(ctrl._trade_state.get("my_gold", 0))
		spin.rounded = true
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gold_row.add_child(spin)
		ctrl._trade_gold_spin = spin
		var setg = Button.new()
		setg.text = "设定"
		setg.focus_mode = Control.FOCUS_NONE
		setg.pressed.connect(ctrl._on_trade_set_gold)
		L2Style.style_compact_button(setg)
		gold_row.add_child(setg)
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	ctrl._trade_body.add_child(btn_row)
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(ctrl._on_trade_cancel)
	L2Style.style_action_button(cancel)
	btn_row.add_child(cancel)
	var ready_btn = Button.new()
	ready_btn.text = "取消锁定" if ready_me else "锁定"
	ready_btn.focus_mode = Control.FOCUS_NONE
	ready_btn.pressed.connect(ctrl._on_trade_ready.bind(not ready_me))
	L2Style.style_action_button(ready_btn)
	btn_row.add_child(ready_btn)
	var conf = Button.new()
	conf.text = "确认交易"
	conf.focus_mode = Control.FOCUS_NONE
	conf.disabled = not (ready_me and ready_them)
	conf.pressed.connect(ctrl._on_trade_confirm)
	L2Style.style_action_button(conf)
	btn_row.add_child(conf)

static func _fill_trade_item_list(ctrl, parent: Node, items_v: Variant, mine: bool) -> void:
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	if items.is_empty():
		ctrl._add_label(parent, "（空）", 10, L2Style.COL_MUTED)
		return
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = it
		var iid = str(md.get("item_id", ""))
		var nm = str(md.get("name", "")).strip_edges()
		if nm.is_empty():
			nm = ctrl._item_label(iid)
		var q: int = int(md.get("qty", 0))
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		parent.add_child(row)
		var lab = Button.new()
		lab.text = "%s ×%d" % [nm, q]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.focus_mode = Control.FOCUS_NONE
		lab.custom_minimum_size = Vector2(0, 28)
		L2Style.style_row_button(lab, false)
		row.add_child(lab)
		if mine and not bool(ctrl._trade_state.get("my_ready", false)):
			var rm = Button.new()
			rm.text = "−"
			rm.focus_mode = Control.FOCUS_NONE
			rm.custom_minimum_size = Vector2(28, 28)
			rm.pressed.connect(ctrl._on_trade_take_item.bind(iid))
			L2Style.style_compact_button(rm)
			row.add_child(rm)

static func _on_trade_open(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_open"):
		ctrl._world_combat.request_trade_open("")
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_open"):
		ctrl._apply_trade_result_locally(srv.try_trade_open(""))

static func _on_trade_cancel(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_cancel"):
		ctrl._world_combat.request_trade_cancel()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_cancel"):
		ctrl._apply_trade_result_locally(srv.try_trade_cancel())

static func _on_trade_put_item(ctrl, item_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_put_item"):
		ctrl._world_combat.request_trade_put_item(item_id, 1)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_put_item"):
		ctrl._apply_trade_result_locally(srv.try_trade_put_item(item_id, 1))

static func _on_trade_take_item(ctrl, item_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_take_item"):
		ctrl._world_combat.request_trade_take_item(item_id, 1)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_take_item"):
		ctrl._apply_trade_result_locally(srv.try_trade_take_item(item_id, 1))

static func _on_trade_set_gold(ctrl) -> void:
	var amount: int = 0
	if ctrl._trade_gold_spin != null:
		amount = int(ctrl._trade_gold_spin.value)
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_set_gold"):
		ctrl._world_combat.request_trade_set_gold(amount)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_set_gold"):
		ctrl._apply_trade_result_locally(srv.try_trade_set_gold(amount))

static func _on_trade_confirm(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_confirm"):
		ctrl._world_combat.request_trade_confirm()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_confirm"):
		ctrl._apply_trade_result_locally(srv.try_trade_confirm())

static func _apply_trade_result_locally(ctrl, result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"trade_update":
				ctrl.apply_trade_update(action)
			"trade_close":
				ctrl.hide_trade()
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				ctrl.apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)

static func _on_trade_open_with(ctrl, partner_name: String) -> void:
	partner_name = str(partner_name).strip_edges()
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_open"):
		ctrl._world_combat.request_trade_open(partner_name)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_open"):
		ctrl._apply_trade_result_locally(srv.try_trade_open(partner_name))

static func _build_trade_panel(ctrl) -> void:
	ctrl._trade_panel = PanelContainer.new()
	ctrl._trade_panel.name = "TradePanel"
	ctrl._trade_panel.set_script(HudDrag)
	ctrl._trade_panel.screen_margin = 4.0
	ctrl._trade_panel.min_size = Vector2(360, 260)
	ctrl._trade_panel.default_size = Vector2(520, 400)
	ctrl._trade_panel.initial_dock = "none"
	ctrl._trade_panel.drag_anywhere = true
	ctrl.add_child(ctrl._trade_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._trade_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "TradeTitle"
	title.text = "交易"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(ctrl._on_trade_cancel)
	head.add_child(close_btn)
	ctrl._trade_body = VBoxContainer.new()
	ctrl._trade_body.name = "TradeBody"
	ctrl._trade_body.add_theme_constant_override("separation", 6)
	ctrl._trade_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(ctrl._trade_body)
	ctrl._trade_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._trade_panel)
	ctrl._refresh_trade_panel()
	ctrl.call_deferred("_nudge_trade")

static func _nudge_trade(ctrl) -> void:
	if ctrl._trade_panel:
		ctrl._trade_panel.size = Vector2(520, 400)
		var vp = ctrl.get_viewport_rect().size
		ctrl._trade_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 260)), 80)

static func _toggle_trade_panel(ctrl) -> void:
	## Legacy no-op for callers; trade is started only via player right-click.
	if ctrl._trade_panel == null:
		return
	if not bool(ctrl._trade_state.get("active", false)):
		ctrl.append_system("交易请右键玩家发起。")
		ctrl.hide_trade()
		return
	ctrl._trade_panel.visible = not ctrl._trade_panel.visible
	if ctrl._trade_panel.visible:
		ctrl._refresh_trade_panel()
		ctrl.call_deferred("_nudge_trade")

static func apply_trade_update(ctrl, action: Dictionary) -> void:
	var trade_v: Variant = action.get("trade", action)
	if typeof(trade_v) != TYPE_DICTIONARY:
		return
	var trade: Dictionary = trade_v
	if not bool(trade.get("active", true)) and str(trade.get("session_id", "")).is_empty():
		ctrl._trade_state = {"active": false}
		ctrl.hide_trade()
		return
	ctrl._trade_state = trade.duplicate(true)
	ctrl._trade_state["active"] = true
	if ctrl._trade_panel != null:
		ctrl._trade_panel.visible = true
		ctrl._refresh_trade_panel()
		ctrl.call_deferred("_nudge_trade")

static func hide_trade(ctrl) -> void:
	ctrl._trade_state = {"active": false}
	if ctrl._trade_panel != null:
		ctrl._trade_panel.visible = false

static func _refresh_trade_panel(ctrl) -> void:
	if ctrl._trade_body == null:
		return
	for c in ctrl._trade_body.get_children():
		c.queue_free()
	ctrl._trade_gold_spin = null
	if not bool(ctrl._trade_state.get("active", false)):
		ctrl._add_label(ctrl._trade_body, "未在交易。右键玩家 →「交易」发起。", 11, L2Style.COL_MUTED)
		# Keep panel hidden when idle — no HUD button / stub open.
		if ctrl._trade_panel != null:
			ctrl._trade_panel.visible = false
		return
	var pname = str(ctrl._trade_state.get("partner_name", "对方"))
	var title_l = ctrl._trade_panel.find_child("TradeTitle", true, false) as Label
	if title_l != null:
		title_l.text = "交易 · %s" % pname
		L2Style.style_title(title_l)
	ctrl._add_label(ctrl._trade_body, "对方：%s" % pname, 12, L2Style.COL_TITLE)
	var cols = GridContainer.new()
	cols.columns = 2
	cols.add_theme_constant_override("h_separation", 10)
	cols.add_theme_constant_override("v_separation", 4)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ctrl._trade_body.add_child(cols)
	var my_wrap = PanelContainer.new()
	my_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	my_wrap.custom_minimum_size = Vector2(180, 120)
	my_wrap.add_theme_stylebox_override("panel", L2Style.inner_box())
	cols.add_child(my_wrap)
	var their_wrap = PanelContainer.new()
	their_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	their_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	their_wrap.custom_minimum_size = Vector2(180, 120)
	their_wrap.add_theme_stylebox_override("panel", L2Style.inner_box())
	cols.add_child(their_wrap)
	var my_col = VBoxContainer.new()
	my_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_col.add_theme_constant_override("separation", 4)
	my_wrap.add_child(my_col)
	var their_col = VBoxContainer.new()
	their_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	their_col.add_theme_constant_override("separation", 4)
	their_wrap.add_child(their_col)
	ctrl._add_label(my_col, "你的报价", 11, L2Style.COL_MUTED)
	ctrl._add_label(their_col, "对方报价", 11, L2Style.COL_MUTED)
	ctrl._fill_trade_item_list(my_col, ctrl._trade_state.get("my_items", []), true)
	ctrl._fill_trade_item_list(their_col, ctrl._trade_state.get("their_items", []), false)
	ctrl._add_label(my_col, "Adena  %d" % int(ctrl._trade_state.get("my_gold", 0)), 12, L2Style.COL_GOLD)
	ctrl._add_label(their_col, "Adena  %d" % int(ctrl._trade_state.get("their_gold", 0)), 12, L2Style.COL_GOLD)
	var ready_me = bool(ctrl._trade_state.get("my_ready", false))
	var ready_them = bool(ctrl._trade_state.get("their_ready", false))
	ctrl._add_label(
		ctrl._trade_body,
		"锁定：你[%s] / 对方[%s]" % ["是" if ready_me else "否", "是" if ready_them else "否"],
		11,
		L2Style.COL_TEXT
	)
	if not ready_me:
		# Put items from bag (first few stacks as quick buttons)
		ctrl._add_label(ctrl._trade_body, "从背包放入（×1）：", 10, L2Style.COL_MUTED)
		var bag_row = HFlowContainer.new()
		bag_row.add_theme_constant_override("h_separation", 4)
		bag_row.add_theme_constant_override("v_separation", 4)
		ctrl._trade_body.add_child(bag_row)
		var added = 0
		for it in ctrl._server_inventory:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var iid = str(it.get("id", "")).strip_edges()
			var q: int = int(it.get("qty", 0))
			if iid.is_empty() or q <= 0:
				continue
			var b = Button.new()
			b.text = "%s×%d" % [ctrl._item_label(iid), q]
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(ctrl._on_trade_put_item.bind(iid))
			L2Style.style_compact_button(b)
			bag_row.add_child(b)
			added += 1
			if added >= 8:
				break
		if added == 0:
			ctrl._add_label(bag_row, "（背包为空）", 10, L2Style.COL_MUTED)
		var gold_row = HBoxContainer.new()
		gold_row.add_theme_constant_override("separation", 6)
		ctrl._trade_body.add_child(gold_row)
		ctrl._add_label(gold_row, "放入 Adena", 11, L2Style.COL_TEXT)
		var spin = SpinBox.new()
		spin.min_value = 0
		spin.max_value = maxi(ctrl._server_gold + int(ctrl._trade_state.get("my_gold", 0)), 0)
		spin.value = int(ctrl._trade_state.get("my_gold", 0))
		spin.rounded = true
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gold_row.add_child(spin)
		ctrl._trade_gold_spin = spin
		var setg = Button.new()
		setg.text = "设定"
		setg.focus_mode = Control.FOCUS_NONE
		setg.pressed.connect(ctrl._on_trade_set_gold)
		L2Style.style_compact_button(setg)
		gold_row.add_child(setg)
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	ctrl._trade_body.add_child(btn_row)
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(ctrl._on_trade_cancel)
	L2Style.style_action_button(cancel)
	btn_row.add_child(cancel)
	var ready_btn = Button.new()
	ready_btn.text = "取消锁定" if ready_me else "锁定"
	ready_btn.focus_mode = Control.FOCUS_NONE
	ready_btn.pressed.connect(ctrl._on_trade_ready.bind(not ready_me))
	L2Style.style_action_button(ready_btn)
	btn_row.add_child(ready_btn)
	var conf = Button.new()
	conf.text = "确认交易"
	conf.focus_mode = Control.FOCUS_NONE
	conf.disabled = not (ready_me and ready_them)
	conf.pressed.connect(ctrl._on_trade_confirm)
	L2Style.style_action_button(conf)
	btn_row.add_child(conf)

static func _fill_trade_item_list(ctrl, parent: Node, items_v: Variant, mine: bool) -> void:
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	if items.is_empty():
		ctrl._add_label(parent, "（空）", 10, L2Style.COL_MUTED)
		return
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = it
		var iid = str(md.get("item_id", ""))
		var nm = str(md.get("name", "")).strip_edges()
		if nm.is_empty():
			nm = ctrl._item_label(iid)
		var q: int = int(md.get("qty", 0))
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		parent.add_child(row)
		var lab = Button.new()
		lab.text = "%s ×%d" % [nm, q]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.focus_mode = Control.FOCUS_NONE
		lab.custom_minimum_size = Vector2(0, 28)
		L2Style.style_row_button(lab, false)
		row.add_child(lab)
		if mine and not bool(ctrl._trade_state.get("my_ready", false)):
			var rm = Button.new()
			rm.text = "−"
			rm.focus_mode = Control.FOCUS_NONE
			rm.custom_minimum_size = Vector2(28, 28)
			rm.pressed.connect(ctrl._on_trade_take_item.bind(iid))
			L2Style.style_compact_button(rm)
			row.add_child(rm)

static func _on_trade_open(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_open"):
		ctrl._world_combat.request_trade_open("")
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_open"):
		ctrl._apply_trade_result_locally(srv.try_trade_open(""))

static func _on_trade_cancel(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_cancel"):
		ctrl._world_combat.request_trade_cancel()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_cancel"):
		ctrl._apply_trade_result_locally(srv.try_trade_cancel())

static func _on_trade_put_item(ctrl, item_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_put_item"):
		ctrl._world_combat.request_trade_put_item(item_id, 1)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_put_item"):
		ctrl._apply_trade_result_locally(srv.try_trade_put_item(item_id, 1))

static func _on_trade_take_item(ctrl, item_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_take_item"):
		ctrl._world_combat.request_trade_take_item(item_id, 1)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_take_item"):
		ctrl._apply_trade_result_locally(srv.try_trade_take_item(item_id, 1))

static func _on_trade_set_gold(ctrl) -> void:
	var amount: int = 0
	if ctrl._trade_gold_spin != null:
		amount = int(ctrl._trade_gold_spin.value)
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_set_gold"):
		ctrl._world_combat.request_trade_set_gold(amount)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_set_gold"):
		ctrl._apply_trade_result_locally(srv.try_trade_set_gold(amount))

static func _on_trade_confirm(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_confirm"):
		ctrl._world_combat.request_trade_confirm()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_confirm"):
		ctrl._apply_trade_result_locally(srv.try_trade_confirm())

static func _apply_trade_result_locally(ctrl, result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"trade_update":
				ctrl.apply_trade_update(action)
			"trade_close":
				ctrl.hide_trade()
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				ctrl.apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)

