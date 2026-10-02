extends RefCounted
## UI panel: warehouse storage and gold.

var ctrl
var _selected := ""
var _deposit := true
var _item_quantity: SpinBox
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const GameWindow = preload("res://scripts/ui/game_window.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

func _build_warehouse_panel() -> void:
	ctrl._warehouse_panel = PanelContainer.new()
	ctrl._warehouse_panel.name = "WarehousePanel"
	ctrl._warehouse_panel.set_script(GameWindow)
	ctrl._warehouse_panel.screen_margin = 4.0
	ctrl._warehouse_panel.min_size = Vector2(420, 320)
	ctrl._warehouse_panel.default_size = Vector2(560, 420)
	ctrl._warehouse_panel.initial_dock = "none"
	ctrl._warehouse_panel.drag_anywhere = true
	ctrl.add_child(ctrl._warehouse_panel)
	var outer = GameWindow.build_body(ctrl._warehouse_panel, "仓库", func(): ctrl._warehouse_panel.visible = false, "WarehouseTitle")
	ctrl._warehouse_body = VBoxContainer.new()
	ctrl._warehouse_body.name = "WarehouseBody"
	ctrl._warehouse_body.add_theme_constant_override("separation", 6)
	ctrl._warehouse_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(ctrl._warehouse_body)
	ctrl._warehouse_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._warehouse_panel)
	_refresh_warehouse_panel()
	ctrl.call_deferred("_nudge_warehouse")



func _nudge_warehouse() -> void:
	if ctrl._warehouse_panel == null:
		return
	ctrl._warehouse_panel.size = Vector2(560, 420)
	var vp = ctrl.get_viewport_rect().size
	ctrl._window_manager_logic.place_at(ctrl._warehouse_panel, Vector2(maxi(8, int(vp.x * 0.5 - 280)), 72))



func _toggle_warehouse_panel(force_open: bool = false) -> void:
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
				_apply_warehouse_result_locally(srv.try_warehouse_open())
		_refresh_warehouse_panel()
		ctrl._warehouse_panel.move_to_front()
		ctrl.call_deferred("_nudge_warehouse")



func apply_warehouse_update(action: Dictionary) -> void:
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
		_refresh_warehouse_panel()



func _refresh_warehouse_panel() -> void:
	var previous_quantity := _item_quantity.value if is_instance_valid(_item_quantity) else 1.0
	if ctrl._warehouse_body == null:
		return
	for c in ctrl._warehouse_body.get_children():
		ctrl._warehouse_body.remove_child(c)
		c.queue_free()
	ctrl._warehouse_gold_spin = null
	var used: int = int(ctrl._warehouse_state.get("used_slots", 0))
	var cap: int = int(ctrl._warehouse_state.get("max_slots", 60))
	ctrl._add_label(ctrl._warehouse_body, "容量 %d / %d" % [used, cap], 11, L2Style.COL_MUTED)
	ctrl._add_label(ctrl._warehouse_body, "背包金币 %d    仓库金币 %d" % [ctrl._server_gold, int(ctrl._warehouse_state.get("gold", 0))], 12, L2Style.COL_TITLE)

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
	ctrl._add_label(bag_wrap, "背包 → 存入仓库", 11, L2Style.COL_MUTED)
	var bag_items: Array = ctrl._server_inventory
	var wh_items: Array = ctrl._warehouse_state.get("items", [])
	var bag_grid = ItemGrid.create(ctrl, bag_wrap, "WarehouseBag", 170)
	bag_grid.set_items(bag_items)
	bag_grid.select_key(_selected if _deposit else "", false)
	bag_grid.item_selected.connect(func(item): _select_item(str(item.get("item_id", "")), true))
	var wh_wrap := VBoxContainer.new()
	wh_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(wh_wrap)
	ctrl._add_label(wh_wrap, "仓库 → 取回背包", 11, L2Style.COL_MUTED)
	var storage_grid = ItemGrid.create(ctrl, wh_wrap, "WarehouseStorage", 170)
	storage_grid.set_items(wh_items)
	storage_grid.select_key(_selected if not _deposit else "", false)
	storage_grid.item_selected.connect(func(item): _select_item(str(item.get("item_id", "")), false))

	ctrl._warehouse_body.add_child(L2Style.hairline())
	var selected_qty := 0
	for entry in (bag_items if _deposit else wh_items):
		if str(entry.get("id", "")) == _selected: selected_qty += int(entry.get("qty", 0))
	ctrl._add_label(ctrl._warehouse_body, "选择左侧或右侧的物品" if selected_qty == 0 else ctrl._item_label(_selected), 12, L2Style.COL_TEXT)
	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 8)
	ctrl._warehouse_body.add_child(item_row)
	ctrl._add_label(item_row, "数量", 12, L2Style.COL_MUTED)
	_item_quantity = SpinBox.new()
	_item_quantity.min_value = 1
	_item_quantity.max_value = maxi(1, selected_qty)
	_item_quantity.value = previous_quantity
	_item_quantity.editable = selected_qty > 0
	_item_quantity.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_item_quantity.custom_minimum_size.x = 100
	item_row.add_child(_item_quantity)
	var all := Button.new()
	all.text = "全部"
	all.disabled = selected_qty == 0
	all.pressed.connect(func(): _item_quantity.value = _item_quantity.max_value)
	item_row.add_child(all)
	var transfer := Button.new()
	transfer.text = "存入物品 →" if _deposit else "← 取出物品"
	transfer.disabled = selected_qty == 0
	transfer.custom_minimum_size.x = 108
	transfer.pressed.connect(func(): _transfer(_selected, int(_item_quantity.value), _deposit))
	item_row.add_child(transfer)
	ctrl._warehouse_body.add_child(L2Style.hairline())
	var gold_row = HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 6)
	ctrl._warehouse_body.add_child(gold_row)
	ctrl._add_label(gold_row, "金币", 12, L2Style.COL_TEXT)
	ctrl._warehouse_gold_spin = SpinBox.new()
	ctrl._warehouse_gold_spin.min_value = 1
	ctrl._warehouse_gold_spin.max_value = 999999999
	ctrl._warehouse_gold_spin.value = 1
	ctrl._warehouse_gold_spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ctrl._warehouse_gold_spin.custom_minimum_size.x = 100
	gold_row.add_child(ctrl._warehouse_gold_spin)
	var dep_g = Button.new()
	dep_g.text = "存金币"
	dep_g.disabled = ctrl._server_gold <= 0
	dep_g.focus_mode = Control.FOCUS_NONE
	dep_g.pressed.connect(_on_warehouse_deposit_gold)
	gold_row.add_child(dep_g)
	var wd_g = Button.new()
	wd_g.text = "取金币"
	wd_g.disabled = int(ctrl._warehouse_state.get("gold", 0)) <= 0
	wd_g.focus_mode = Control.FOCUS_NONE
	wd_g.pressed.connect(_on_warehouse_withdraw_gold)
	gold_row.add_child(wd_g)



func _select_item(id: String, deposit: bool) -> void:
	if is_instance_valid(_item_quantity): _item_quantity.value = 1
	_selected = id
	_deposit = deposit
	_refresh_warehouse_panel()


func _on_warehouse_deposit_pressed(item_id: String, stack_qty: int) -> void:
	_transfer(item_id, stack_qty if Input.is_key_pressed(KEY_SHIFT) else 1, true)


func _on_warehouse_withdraw_pressed(item_id: String, stack_qty: int) -> void:
	_transfer(item_id, stack_qty if Input.is_key_pressed(KEY_SHIFT) else 1, false)


func _transfer(id: String, qty: int, deposit: bool) -> void:
	var operation := "warehouse_deposit" if deposit else "warehouse_withdraw"
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_" + operation):
		ctrl._world_combat.call("request_" + operation, id, qty)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_" + operation):
			_apply_warehouse_result_locally(srv.call("try_" + operation, id, qty))


func _on_warehouse_deposit_gold() -> void:
	var amount: int = int(ctrl._warehouse_gold_spin.value) if ctrl._warehouse_gold_spin else 1
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_warehouse_deposit_gold"):
		ctrl._world_combat.request_warehouse_deposit_gold(amount)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_warehouse_deposit_gold"):
			_apply_warehouse_result_locally(srv.try_warehouse_deposit_gold(amount))



func _on_warehouse_withdraw_gold() -> void:
	var amount: int = int(ctrl._warehouse_gold_spin.value) if ctrl._warehouse_gold_spin else 1
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_warehouse_withdraw_gold"):
		ctrl._world_combat.request_warehouse_withdraw_gold(amount)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_warehouse_withdraw_gold"):
			_apply_warehouse_result_locally(srv.try_warehouse_withdraw_gold(amount))



func _apply_warehouse_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"warehouse_update":
				apply_warehouse_update(action)
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				ctrl.apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)



