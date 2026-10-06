extends RefCounted
## UI panel: trade window with item/gold exchange.

var ctrl
var _selected_item := ""
var _selected_source := "bag"
var _quantity: SpinBox
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const GameWindow = preload("res://scripts/ui/game_window.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

func _on_trade_open_with(partner_name: String) -> void:
	partner_name = str(partner_name).strip_edges()
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_open"):
		ctrl._world_combat.request_trade_open(partner_name)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_open"):
		_apply_trade_result_locally(srv.try_trade_open(partner_name))




func _build_trade_panel() -> void:
	ctrl._trade_panel = PanelContainer.new()
	ctrl._trade_panel.name = "TradePanel"
	ctrl._trade_panel.set_script(GameWindow)
	ctrl._trade_panel.screen_margin = 4.0
	ctrl._trade_panel.min_size = Vector2(360, 260)
	ctrl._trade_panel.default_size = Vector2(520, 490)
	ctrl._trade_panel.initial_dock = "none"
	ctrl._trade_panel.drag_anywhere = true
	ctrl.add_child(ctrl._trade_panel)
	var outer = GameWindow.build_body(ctrl._trade_panel, "交易", _on_trade_cancel, "TradeTitle")
	ctrl._trade_body = VBoxContainer.new()
	ctrl._trade_body.name = "TradeBody"
	ctrl._trade_body.add_theme_constant_override("separation", 6)
	ctrl._trade_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(ctrl._trade_body)
	ctrl._trade_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._trade_panel)
	_refresh_trade_panel()
	ctrl.call_deferred("_nudge_trade")



func _nudge_trade() -> void:
	if ctrl._trade_panel:
		ctrl._trade_panel.size = Vector2(520, 490)
		var vp = ctrl.get_viewport_rect().size
		ctrl._window_manager_logic.place_at(ctrl._trade_panel, Vector2(maxi(8, int(vp.x * 0.5 - 260)), 80))



func _toggle_trade_panel() -> void:
	## Legacy no-op for callers; trade is started only via player right-click.
	if ctrl._trade_panel == null:
		return
	if not bool(ctrl._trade_state.get("active", false)):
		ctrl.append_system("交易请右键玩家发起。")
		hide_trade()
		return
	ctrl._trade_panel.visible = not ctrl._trade_panel.visible
	if ctrl._trade_panel.visible:
		_refresh_trade_panel()
		ctrl.call_deferred("_nudge_trade")



func apply_trade_update(action: Dictionary) -> void:
	var trade_v: Variant = action.get("trade", action)
	if typeof(trade_v) != TYPE_DICTIONARY:
		return
	var trade: Dictionary = trade_v
	if not bool(trade.get("active", true)) and str(trade.get("session_id", "")).is_empty():
		ctrl._trade_state = {"active": false}
		hide_trade()
		return
	ctrl._trade_state = trade.duplicate(true)
	ctrl._trade_state["active"] = true
	if ctrl._trade_panel != null:
		ctrl._trade_panel.visible = true
		_refresh_trade_panel()
		ctrl.call_deferred("_nudge_trade")



func hide_trade() -> void:
	ctrl._trade_state = {"active": false}
	if ctrl._trade_panel != null:
		ctrl._trade_panel.visible = false



func _refresh_trade_panel() -> void:
	var previous_quantity := _quantity.value if is_instance_valid(_quantity) else 1.0
	if ctrl._trade_body == null:
		return
	for c in ctrl._trade_body.get_children():
		ctrl._trade_body.remove_child(c)
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
	_fill_trade_item_list(my_col, ctrl._trade_state.get("my_items", []), true)
	_fill_trade_item_list(their_col, ctrl._trade_state.get("their_items", []), false)
	ctrl._add_label(my_col, "金币  %d" % int(ctrl._trade_state.get("my_gold", 0)), 12, L2Style.COL_GOLD)
	ctrl._add_label(their_col, "金币  %d" % int(ctrl._trade_state.get("their_gold", 0)), 12, L2Style.COL_GOLD)
	var ready_me = bool(ctrl._trade_state.get("my_ready", false))
	var ready_them = bool(ctrl._trade_state.get("their_ready", false))
	ctrl._add_label(
		ctrl._trade_body,
		"你：%s    对方：%s" % ["已锁定" if ready_me else "调整报价中", "已锁定" if ready_them else "调整报价中"],
		11,
		L2Style.COL_TEXT
	)
	if not ready_me:
		ctrl._add_label(ctrl._trade_body, "从背包选择物品", 11, L2Style.COL_MUTED)
		var bag = ItemGrid.create(ctrl, ctrl._trade_body, "TradeBag", 80)
		bag.size_flags_vertical = Control.SIZE_FILL
		bag.fill_inventory(ctrl._server_inventory)
		bag.select_key(_selected_item if _selected_source == "bag" else "", false)
		bag.item_selected.connect(func(item): _select_trade_item(item, "bag"))
		var selected_qty := 0
		var source: Array = ctrl._server_inventory if _selected_source == "bag" else ctrl._trade_state.get("my_items", [])
		for item in source:
			if _selected_source == "bag" and (item.get("locked", false) or item.get("bound", false)): continue
			if str(item.get("item_id", item.get("id", ""))) == _selected_item: selected_qty += int(item.get("qty", 0))
		var item_actions := HBoxContainer.new()
		item_actions.add_theme_constant_override("separation", 6)
		ctrl._trade_body.add_child(item_actions)
		ctrl._add_label(item_actions, "数量", 11, L2Style.COL_MUTED)
		_quantity = SpinBox.new()
		_quantity.min_value = 1
		_quantity.max_value = maxi(1, selected_qty)
		_quantity.value = previous_quantity
		_quantity.editable = selected_qty > 0
		_quantity.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_quantity.custom_minimum_size.x = 100
		item_actions.add_child(_quantity)
		var all := Button.new()
		all.text = "全部"
		all.disabled = selected_qty == 0
		all.pressed.connect(func(): _quantity.value = _quantity.max_value)
		item_actions.add_child(all)
		var transfer := Button.new()
		transfer.text = "放入报价" if _selected_source == "bag" else "移回背包"
		transfer.disabled = selected_qty == 0
		transfer.pressed.connect(func():
			if _selected_source == "bag": _on_trade_put_item(_selected_item)
			else: _on_trade_take_item(_selected_item)
		)
		item_actions.add_child(transfer)
		var gold_row = HBoxContainer.new()
		gold_row.add_theme_constant_override("separation", 6)
		ctrl._trade_body.add_child(gold_row)
		ctrl._add_label(gold_row, "放入金币", 11, L2Style.COL_TEXT)
		var spin = SpinBox.new()
		spin.min_value = 0
		spin.max_value = maxi(ctrl._server_gold + int(ctrl._trade_state.get("my_gold", 0)), 0)
		spin.value = int(ctrl._trade_state.get("my_gold", 0))
		spin.rounded = true
		spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		spin.custom_minimum_size.x = 100
		gold_row.add_child(spin)
		ctrl._trade_gold_spin = spin
		var setg = Button.new()
		setg.text = "设定"
		setg.focus_mode = Control.FOCUS_NONE
		setg.pressed.connect(_on_trade_set_gold)
		L2Style.style_compact_button(setg)
		gold_row.add_child(setg)
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	ctrl._trade_body.add_child(btn_row)
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_on_trade_cancel)
	L2Style.style_action_button(cancel)
	btn_row.add_child(cancel)
	var ready_btn = Button.new()
	ready_btn.text = "修改报价" if ready_me else "锁定报价"
	ready_btn.focus_mode = Control.FOCUS_NONE
	ready_btn.pressed.connect(ctrl._on_trade_ready.bind(not ready_me))
	L2Style.style_action_button(ready_btn)
	btn_row.add_child(ready_btn)
	var conf = Button.new()
	conf.text = "确认交易"
	conf.focus_mode = Control.FOCUS_NONE
	conf.disabled = not (ready_me and ready_them)
	conf.tooltip_text = "双方锁定报价后才能确认交易"
	conf.pressed.connect(_on_trade_confirm)
	L2Style.style_action_button(conf)
	btn_row.add_child(conf)



func _select_trade_item(item: Dictionary, source: String) -> void:
	if is_instance_valid(_quantity): _quantity.value = 1
	_selected_item = str(item.get("item_id", ""))
	_selected_source = source
	_refresh_trade_panel()


func _fill_trade_item_list(parent: Node, items_v: Variant, mine: bool) -> void:
	var grid = ItemGrid.create(ctrl, parent, "TradeMyOffer" if mine else "TradeTheirOffer", 104)
	grid.set_items(items_v if items_v is Array else [])
	grid.select_key(_selected_item if mine and _selected_source == "offer" else "", false)
	if mine and not ctrl._trade_state.get("my_ready", false):
		grid.item_selected.connect(func(item): _select_trade_item(item, "offer"))


func _on_trade_open() -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_open"):
		ctrl._world_combat.request_trade_open("")
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_open"):
		_apply_trade_result_locally(srv.try_trade_open(""))



func _on_trade_cancel() -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_cancel"):
		ctrl._world_combat.request_trade_cancel()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_cancel"):
		_apply_trade_result_locally(srv.try_trade_cancel())



func _on_trade_put_item(item_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_put_item"):
		ctrl._world_combat.request_trade_put_item(item_id, int(_quantity.value) if _quantity else 1)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_put_item"):
		_apply_trade_result_locally(srv.try_trade_put_item(item_id, int(_quantity.value) if _quantity else 1))



func _on_trade_take_item(item_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_take_item"):
		ctrl._world_combat.request_trade_take_item(item_id, int(_quantity.value) if _quantity else 1)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_take_item"):
		_apply_trade_result_locally(srv.try_trade_take_item(item_id, int(_quantity.value) if _quantity else 1))



func _on_trade_set_gold() -> void:
	var amount: int = 0
	if ctrl._trade_gold_spin != null:
		amount = int(ctrl._trade_gold_spin.value)
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_set_gold"):
		ctrl._world_combat.request_trade_set_gold(amount)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_set_gold"):
		_apply_trade_result_locally(srv.try_trade_set_gold(amount))



func _on_trade_confirm() -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_trade_confirm"):
		ctrl._world_combat.request_trade_confirm()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_trade_confirm"):
		_apply_trade_result_locally(srv.try_trade_confirm())



func _apply_trade_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"trade_update":
				apply_trade_update(action)
			"trade_close":
				hide_trade()
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				ctrl.apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)
