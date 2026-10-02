extends RefCounted
## UI panel: shop window (catalog, buy/sell carts, buyback, vendor rep).

var ctrl
var _submitting := false
var _batch: Array = []
var _batch_index := 0
var _batch_buy := true
var _batch_errors: Array[String] = []
var _feedback: Label
func _init(c):
	ctrl = c

const UIRequest = preload("res://scripts/ui/ui_request.gd")
const Net = preload("res://scripts/net/net.gd")
const GameWindow = preload("res://scripts/ui/game_window.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const SHOP_TABS := [
	["买入", "buy"],
	["卖出", "sell"],
	["回购", "buyback"],
]

func show_shop(shop_id: String, title: String, listings: Array, gold: int = 0, vendor_rep: int = -1) -> void:
	if _submitting: return
	ctrl._shop_id = shop_id.strip_edges()
	ctrl._shop_title = title.strip_edges() if title.strip_edges() != "" else "商店"
	ctrl._shop_listings = listings.duplicate(true) if listings != null else []
	ctrl._shop_vendor_rep = vendor_rep
	if gold >= 0:
		ctrl._server_gold = gold
	_ensure_shop_panel()
	_fill_shop_panel()
	if ctrl._shop_panel != null:
		ctrl._shop_panel.visible = true
		ctrl._shop_panel.move_to_front()



func apply_shop_buyback(rows: Variant) -> void:
	if typeof(rows) != TYPE_ARRAY:
		ctrl._shop_buyback = []
	else:
		ctrl._shop_buyback = (rows as Array).duplicate(true)
	if ctrl._shop_panel != null and ctrl._shop_panel.visible:
		_fill_shop_panel()



func hide_shop() -> void:
	if _submitting: return
	if ctrl._shop_panel != null:
		ctrl._shop_panel.visible = false
	ctrl._shop_id = ""
	ctrl._shop_vendor_rep = -1
	ctrl._shop_buyback = []
	_clear_shop_carts()
	# Server drops buyback list for this shop session.
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_shop_close"):
		ctrl._world_combat.request_shop_close()
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_shop_close"):
			srv.try_shop_close()



func _clear_shop_carts() -> void:
	ctrl._shop_buy_cart.clear()
	ctrl._shop_sell_cart.clear()



func _ensure_shop_panel() -> void:
	if ctrl._shop_panel != null and is_instance_valid(ctrl._shop_panel):
		if bool(ctrl._shop_panel.get_meta("shop_v4", false)):
			return
		ctrl._shop_panel.queue_free()
		ctrl._shop_panel = null
	var panel = PanelContainer.new()
	panel.set_script(GameWindow)
	panel.name = "ShopWindow"
	panel.screen_margin = 4.0
	panel.min_size = Vector2(520, 400)
	panel.default_size = Vector2(580, 460)
	panel.initial_dock = "none"
	panel.drag_anywhere = true
	panel.visible = false
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(520, 400)
	panel.set_meta("fixed_size", true)
	panel.set_meta("base_size", Vector2(580, 460))
	panel.set_meta("shop_v4", true)
	ctrl.add_child(panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(marg)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marg.add_child(vbox)
	var head = HBoxContainer.new()
	vbox.add_child(head)
	var title_l = Label.new()
	title_l.name = "ShopTitle"
	title_l.text = "商店"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_l)
	var gold_l = Label.new()
	gold_l.name = "ShopGold"
	gold_l.text = "金币 0"
	head.add_child(gold_l)
	var rep_l = Label.new()
	rep_l.name = "ShopRep"
	rep_l.text = ""
	head.add_child(rep_l)
	var close_btn = Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(hide_shop)
	head.add_child(close_btn)
	var tabs = HBoxContainer.new()
	tabs.name = "ShopTabs"
	tabs.add_theme_constant_override("separation", 4)
	tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(tabs)
	var buy_root = _make_shop_tab_page("BuyPage", "BuyCatalog", "BuyCart", "商品", "购物篮")
	vbox.add_child(buy_root)
	var sell_root = _make_shop_tab_page("SellPage", "SellCatalog", "SellCart", "背包可出售", "待出售")
	vbox.add_child(sell_root)
	var back_root = _make_shop_tab_page("BuybackPage", "BuybackCatalog", "BuybackCart", "最近卖出", "回购")
	vbox.add_child(back_root)
	_feedback = UIRequest.status(vbox, "ShopStatus")
	var footer = HBoxContainer.new()
	footer.name = "ShopFooter"
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)
	var footer_rep = Label.new()
	footer_rep.name = "ShopRepFooter"
	footer_rep.text = ""
	footer_rep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_rep)
	var bottom = HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)
	var junk_btn = Button.new()
	junk_btn.name = "SellJunkBtn"
	junk_btn.text = "出售垃圾"
	junk_btn.focus_mode = Control.FOCUS_NONE
	junk_btn.pressed.connect(_on_shop_sell_junk)
	L2Style.style_action_button(junk_btn)
	bottom.add_child(junk_btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "关闭"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.pressed.connect(hide_shop)
	L2Style.style_action_button(cancel_btn)
	bottom.add_child(cancel_btn)
	var ok_btn = Button.new()
	ok_btn.name = "ConfirmShopSelection"
	ok_btn.text = "购买所选"
	ok_btn.focus_mode = Control.FOCUS_NONE
	ok_btn.pressed.connect(_on_shop_confirm)
	L2Style.style_action_button(ok_btn)
	L2Style.style_primary_button(ok_btn)
	bottom.add_child(ok_btn)
	panel.set_meta("shop_tabs", tabs)
	ctrl._apply_l2_chrome(panel)
	_rebuild_shop_tab_bar(panel)
	_show_shop_tab_pages()
	panel.set_meta("tabs", tabs)
	panel.set_meta("gold_label", gold_l)
	ctrl._shop_panel = panel
	ctrl.call_deferred("_place_shop_panel")



func _make_shop_tab_page(page_name: String, catalog_name: String, cart_name: String, cat_title: String, cart_title: String) -> HBoxContainer:
	var root = HBoxContainer.new()
	root.name = page_name
	root.add_theme_constant_override("separation", 8)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left = _make_shop_list_pane(catalog_name, cat_title)
	left.size_flags_stretch_ratio = 1.35
	root.add_child(left)
	if page_name == "BuybackPage": return root
	var right = _make_shop_list_pane(cart_name, cart_title)
	right.size_flags_stretch_ratio = 1.0
	root.add_child(right)
	return root



func _make_shop_list_pane(list_name: String, heading: String) -> PanelContainer:
	var pane = PanelContainer.new()
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_theme_stylebox_override("panel", L2Style.inner_box())
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_child(col)
	var title = ctrl._add_label(col, heading, 11, L2Style.COL_MUTED)
	title.name = list_name + "Heading"
	var grid = ItemGrid.create(ctrl, col, list_name, 150)
	grid.minimum_cells = 0
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	col.add_child(actions)
	var quantity := SpinBox.new()
	quantity.name = list_name + "Quantity"
	quantity.min_value = 1
	quantity.max_value = 1
	quantity.editable = false
	quantity.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quantity.custom_minimum_size.x = 100
	actions.add_child(quantity)
	var action := Button.new()
	action.name = list_name + "Action"
	var is_cart := list_name.ends_with("Cart")
	var is_back := list_name == "BuybackCatalog"
	action.text = "移除" if is_cart else ("回购所选" if is_back else "加入")
	action.disabled = true
	actions.add_child(action)
	quantity.visible = not is_back
	grid.item_selected.connect(func(item):
		action.disabled = item.is_empty() or (is_back and int(item.get("unit_price", 0)) * int(item.get("qty", 1)) > ctrl._server_gold)
		quantity.editable = not item.is_empty()
		quantity.max_value = _shop_selection_limit(list_name, item)
	)
	action.pressed.connect(func():
		var item: Dictionary = grid.selected_item()
		if item.is_empty(): return
		var is_buy := list_name.begins_with("Buy")
		if is_back:
			_request_buyback(int(item.get("key", -1)))
		elif is_cart:
			_on_shop_cart_adjust(is_buy, str(item.item_id), -int(quantity.value))
		else:
			_add_selected_shop_item(is_buy, item, int(quantity.value))
	)
	return pane



func _rebuild_shop_tab_bar(panel: PanelContainer) -> void:
	var tabs: HBoxContainer = panel.get_meta("shop_tabs", null) if panel else null
	if tabs == null or not is_instance_valid(tabs):
		return
	while tabs.get_child_count() > 0:
		var c: Node = tabs.get_child(0)
		tabs.remove_child(c)
		c.queue_free()
	for item in SHOP_TABS:
		var btn = Button.new()
		btn.text = str(item[0])
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(100, L2Style.TAB_HEIGHT)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_on_shop_tab.bind(str(item[1])))
		tabs.add_child(btn)
	_highlight_shop_tabs(tabs)



func _on_shop_tab(tab_id: String) -> void:
	tab_id = tab_id.strip_edges()
	if tab_id.is_empty():
		return
	ctrl._shop_tab = tab_id
	_show_shop_tab_pages()
	if ctrl._shop_panel != null:
		_highlight_shop_tabs(ctrl._shop_panel.get_meta("shop_tabs", null) as HBoxContainer)
		_fill_shop_panel()



func _highlight_shop_tabs(tabs: HBoxContainer) -> void:
	if tabs == null:
		return
	for i in range(tabs.get_child_count()):
		var btn = tabs.get_child(i) as Button
		if btn == null or i >= SHOP_TABS.size():
			continue
		L2Style.style_tab_button(btn, str(SHOP_TABS[i][1]) == ctrl._shop_tab)



func _show_shop_tab_pages() -> void:
	if ctrl._shop_panel == null:
		return
	var buy = ctrl._shop_panel.find_child("BuyPage", true, false) as Control
	var sell = ctrl._shop_panel.find_child("SellPage", true, false) as Control
	if buy != null:
		buy.visible = ctrl._shop_tab == "buy"
	if sell != null:
		sell.visible = ctrl._shop_tab == "sell"
	var back = ctrl._shop_panel.find_child("BuybackPage", true, false) as Control
	if back != null:
		back.visible = ctrl._shop_tab == "buyback"
	var junk: Button = ctrl._shop_panel.find_child("SellJunkBtn", true, false)
	if junk: junk.visible = ctrl._shop_tab == "sell"
	var confirm: Button = ctrl._shop_panel.find_child("ConfirmShopSelection", true, false)
	if confirm:
		confirm.visible = ctrl._shop_tab != "buyback"
		confirm.text = "出售所选" if ctrl._shop_tab == "sell" else "购买所选"
		confirm.disabled = (ctrl._shop_sell_cart if ctrl._shop_tab == "sell" else ctrl._shop_buy_cart).is_empty()



func _place_shop_panel() -> void:
	if ctrl._shop_panel == null:
		return
	var vp = ctrl.get_viewport().get_visible_rect().size
	ctrl._shop_panel.size = Vector2(580, 460)
	ctrl._window_manager_logic.place_at(ctrl._shop_panel, Vector2(maxi(8, int(vp.x * 0.2)), maxi(40, int(vp.y * 0.12))))



func _fill_shop_panel() -> void:
	_ensure_shop_panel()
	if ctrl._shop_panel == null:
		return
	var title_l = ctrl._shop_panel.find_child("ShopTitle", true, false) as Label
	if title_l != null:
		if ctrl._shop_vendor_rep >= 0:
			title_l.text = "%s  声望 %d" % [ctrl._shop_title if ctrl._shop_title != "" else "商店", ctrl._shop_vendor_rep]
		else:
			title_l.text = ctrl._shop_title if ctrl._shop_title != "" else "商店"
	var gold_l = ctrl._shop_panel.get_meta("gold_label") as Label
	if gold_l != null:
		gold_l.text = "金币  %d" % maxi(ctrl._server_gold, 0)
		L2Style.style_gold_amount(gold_l)
	var rep_l = ctrl._shop_panel.find_child("ShopRep", true, false) as Label
	if rep_l != null:
		if ctrl._shop_vendor_rep >= 0:
			rep_l.text = "声望 %d" % ctrl._shop_vendor_rep
			rep_l.visible = true
		else:
			rep_l.text = ""
			rep_l.visible = false
	var footer_rep = ctrl._shop_panel.find_child("ShopRepFooter", true, false) as Label
	if footer_rep != null:
		if ctrl._shop_vendor_rep >= 0:
			footer_rep.text = "声望 %d" % ctrl._shop_vendor_rep
			footer_rep.visible = true
		else:
			footer_rep.text = ""
			footer_rep.visible = false
	_show_shop_tab_pages()
	var buy_items: Array = []
	for entry in ctrl._shop_listings:
		if not entry is Dictionary: continue
		var item: Dictionary = entry.duplicate(true)
		item["qty"] = 1
		item["unit_price"] = int(item.get("buy_price", 0))
		item["hint"] = "单价 %d 金币" % item.unit_price
		buy_items.append(item)
	var sell_items: Array = []
	for entry in _shop_sellable_bag_rows():
		var item: Dictionary = entry.duplicate(true)
		item["unit_price"] = int(item.get("sell_price", 0))
		item["hint"] = "单价 %d 金币" % item.unit_price
		sell_items.append(item)
	_set_shop_grid("BuyCatalog", buy_items)
	_set_shop_grid("SellCatalog", sell_items)
	_fill_buy_cart_slots()
	_set_shop_grid("SellCart", ctrl._shop_sell_cart)
	var back_items: Array = []
	for index in ctrl._shop_buyback.size():
		var item: Dictionary = ctrl._shop_buyback[index].duplicate(true)
		item["key"] = str(index)
		item["hint"] = "整组 %d 金币" % (int(item.get("unit_price", 0)) * int(item.get("qty", 1)))
		back_items.append(item)
	_set_shop_grid("BuybackCatalog", back_items)
	var total := 0
	for line in (ctrl._shop_sell_cart if ctrl._shop_tab == "sell" else ctrl._shop_buy_cart): total += int(line.get("qty", 1)) * int(line.get("unit_price", 0))
	footer_rep.text = "合计 %d 金币" % total
	footer_rep.visible = ctrl._shop_tab != "buyback"
	if _submitting: UIRequest.lock_form(ctrl._shop_panel, true)


func _set_shop_grid(node_name: String, items: Array) -> void:
	var grid = ctrl._shop_panel.find_child(node_name, true, false)
	grid.set_items(items)
	# Refresh both selection and quantity limits after stock/cart updates.
	grid.item_selected.emit(grid.selected_item())


func _fill_buy_cart_slots() -> void:
	# Forecast on an isolated bag using the same stacking rules as shop purchases.
	# The real inventory and the submitted shopping list are never mutated here.
	var bag = Inventory.new()
	var srv = Net.server()
	bag.catalog = srv.get("item_catalog") if srv != null else null
	var capacity := Inventory.MAX_SLOTS
	if srv != null and srv.get("inventory") != null:
		capacity = maxi(int(srv.inventory.max_slots), 1)
	bag.restore_session_state({"stacks": ctrl._server_inventory, "gold": 0, "max_slots": capacity})
	var free_before := maxi(0, capacity - bag.slot_count())
	var display: Array = []
	for entry in ctrl._shop_buy_cart:
		var item: Dictionary = entry.duplicate(true)
		var occupied: int = bag.slot_count()
		var result: Dictionary = bag.try_add_item(str(item.item_id), int(item.qty))
		var used: int = bag.slot_count() - occupied
		item["hint"] = "占用 %d 个空位" % used if used > 0 else "叠入背包已有物品"
		if int(result.get("added", 0)) < int(item.qty):
			item["hint"] = "空间不足，仅可装入 %d 件" % int(result.get("added", 0))
		display.append(item)
	var free_after := maxi(0, capacity - bag.slot_count())
	var grid = ctrl._shop_panel.find_child("BuyCart", true, false)
	grid.minimum_cells = display.size() + free_after
	grid.empty_text = "背包已满" if free_before == 0 else "选择商品加入购物篮"
	var title: Label = ctrl._shop_panel.find_child("BuyCartHeading", true, false)
	title.text = "购物篮 · 空位 %d" % free_after
	title.tooltip_text = "背包当前有 %d 个空位，本次购买预计占用 %d 个。可叠加到已有物品的数量不占新格。" % [free_before, free_before - free_after]
	_set_shop_grid("BuyCart", display)


func _shop_selection_limit(node_name: String, item: Dictionary) -> int:
	if item.is_empty(): return 1
	if node_name == "BuyCatalog":
		var price := int(item.get("unit_price", 0))
		return maxi(1, mini(999, int(ctrl._server_gold / price))) if price > 0 else 999
	return maxi(1, int(item.get("qty", 1)))


func _add_selected_shop_item(is_buy: bool, item: Dictionary, count: int) -> void:
	var cart: Array = ctrl._shop_buy_cart if is_buy else ctrl._shop_sell_cart
	var id := str(item.item_id)
	var existing := 0
	for line in cart:
		if str(line.get("item_id", "")) == id: existing = int(line.get("qty", 0))
	var maximum := _shop_selection_limit("BuyCatalog" if is_buy else "SellCatalog", item)
	var desired := mini(existing + count, maximum)
	if desired <= existing: return
	for line in cart:
		if str(line.get("item_id", "")) == id:
			line["qty"] = desired
			_fill_shop_panel()
			return
	cart.append({"item_id": id, "name": item.name, "qty": desired, "unit_price": int(item.get("unit_price", 0))})
	_fill_shop_panel()


func _request_buyback(index: int) -> void:
	if index < 0 or index >= ctrl._shop_buyback.size(): return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_shop_buyback"):
		ctrl._world_combat.request_shop_buyback(index)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_shop_buyback"):
			ctrl._apply_equip_result_locally(srv.try_shop_buyback(index))



func _on_shop_catalog_add(is_buy: bool, item_id: String, display_name: String, unit_price: int) -> void:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return
	var cart: Array = ctrl._shop_buy_cart if is_buy else ctrl._shop_sell_cart
	# Cap sell qty by bag amount
	if not is_buy:
		var have = 0
		for it in ctrl._server_inventory:
			if typeof(it) == TYPE_DICTIONARY and str(it.get("id", "")) == item_id:
				have = int(it.get("qty", 0))
				break
		var cur = 0
		for line in cart:
			if typeof(line) == TYPE_DICTIONARY and str(line.get("item_id", "")) == item_id:
				cur = int(line.get("qty", 0))
				break
		if cur >= have:
			ctrl.append_system("选择数量已达背包上限。")
			return
	var found = false
	for i in range(cart.size()):
		var line: Dictionary = cart[i]
		if str(line.get("item_id", "")) == item_id:
			line["qty"] = int(line.get("qty", 0)) + 1
			cart[i] = line
			found = true
			break
	if not found:
		cart.append({"item_id": item_id, "qty": 1, "unit_price": unit_price, "name": display_name})
	_fill_shop_panel()



func _on_shop_cart_adjust(is_buy: bool, item_id: String, delta: int) -> void:
	item_id = item_id.strip_edges()
	var cart: Array = ctrl._shop_buy_cart if is_buy else ctrl._shop_sell_cart
	for i in range(cart.size()):
		var line: Dictionary = cart[i]
		if str(line.get("item_id", "")) != item_id:
			continue
		var q: int = int(line.get("qty", 0)) + delta
		if q <= 0:
			cart.remove_at(i)
		else:
			line["qty"] = q
			cart[i] = line
		break
	_fill_shop_panel()



func _on_shop_cart_remove(is_buy: bool, item_id: String) -> void:
	item_id = item_id.strip_edges()
	var cart: Array = ctrl._shop_buy_cart if is_buy else ctrl._shop_sell_cart
	for i in range(cart.size() - 1, -1, -1):
		if typeof(cart[i]) == TYPE_DICTIONARY and str(cart[i].get("item_id", "")) == item_id:
			cart.remove_at(i)
	_fill_shop_panel()



func _on_shop_confirm() -> void:
	if ctrl._shop_panel == null:
		return
	if ctrl._shop_tab == "sell":
		_confirm_sell_cart()
	elif ctrl._shop_tab == "buyback":
		ctrl.append_system("选择回购物品，再点击回购所选。")
	else:
		_confirm_buy_cart()



func _confirm_buy_cart() -> void:
	_submit_cart(true)


func _confirm_sell_cart() -> void:
	_submit_cart(false)


func _submit_cart(is_buy: bool) -> void:
	if _submitting: return
	var cart: Array = ctrl._shop_buy_cart if is_buy else ctrl._shop_sell_cart
	if cart.is_empty() or (is_buy and ctrl._shop_id.is_empty()): return
	_submitting = true
	_batch_buy = is_buy
	_batch = cart.duplicate(true)
	_batch_index = 0
	_batch_errors.clear()
	UIRequest.lock_form(ctrl._shop_panel, true)
	_submit_next_cart_line()


func _apply_shop_result(result: Dictionary) -> void:
	ctrl._apply_equip_result_locally(result)
	for action in result.get("actions", []):
		if action.get("type", "") == "shop_buyback": apply_shop_buyback(action.get("buyback", []))


func _submit_next_cart_line() -> void:
	if _batch_index >= _batch.size():
		_submitting = false
		UIRequest.lock_form(ctrl._shop_panel, false)
		_fill_shop_panel()
		var text := "交易完成" if _batch_errors.is_empty() else _batch_errors[0] + ("（另有 %d 项未完成）" % (_batch_errors.size() - 1) if _batch_errors.size() > 1 else "")
		UIRequest.set_status(_feedback, text, not _batch_errors.is_empty())
		_feedback.tooltip_text = "\n".join(_batch_errors)
		return
	UIRequest.set_status(_feedback, "处理中 %d / %d，请等待结果…" % [_batch_index + 1, _batch.size()])
	var line: Dictionary = _batch[_batch_index]
	var args: Array = [ctrl._shop_id, str(line.item_id), int(line.qty)] if _batch_buy else [str(line.item_id), int(line.qty)]
	UIRequest.dispatch(ctrl, "try_shop_buy" if _batch_buy else "try_shop_sell", args, _apply_shop_result, _cart_line_finished)


func _cart_line_finished(result: Dictionary) -> void:
	var line: Dictionary = _batch[_batch_index]
	if result.get("ok", false):
		var cart: Array = ctrl._shop_buy_cart if _batch_buy else ctrl._shop_sell_cart
		for i in range(cart.size() - 1, -1, -1):
			if str(cart[i].get("item_id", "")) == str(line.item_id): cart.remove_at(i)
	else:
		_batch_errors.append("%s：%s" % [line.get("name", line.item_id), UIRequest.message(result)])
	_batch_index += 1
	_submit_next_cart_line()


func _shop_sellable_bag_rows() -> Array:
	var out: Array = []
	var cat = null
	var srv = Net.server()
	if srv != null:
		cat = srv.get("item_catalog")
	for it in ctrl._server_inventory:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var iid = str(it.get("id", "")).strip_edges()
		var qty: int = int(it.get("qty", 0))
		if iid.is_empty() or qty <= 0:
			continue
		if bool(it.get("locked", false)):
			continue
		var sell_price = 0
		var iname = iid
		if cat != null and cat.has_method("get_item"):
			var def: Dictionary = cat.get_item(iid)
			if not def.is_empty():
				sell_price = maxi(int(def.get("sell_price", 0)), 0)
				iname = str(def.get("name", iid))
		if sell_price <= 0:
			continue
		out.append({"id": iid, "qty": qty, "name": iname, "sell_price": sell_price})
	return out



func _on_shop_buy(item_id: String) -> void:
	## Legacy single-buy (kept for compatibility); prefer cart + confirm.
	if ctrl._shop_id.is_empty() or item_id.strip_edges().is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_shop_buy"):
		ctrl._world_combat.request_shop_buy(ctrl._shop_id, item_id, 1)



func _on_shop_sell(item_id: String) -> void:
	## Legacy single-sell (kept for compatibility); prefer cart + confirm.
	if item_id.strip_edges().is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_shop_sell"):
		ctrl._world_combat.request_shop_sell(item_id, 1)



func _on_shop_sell_junk() -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_shop_sell_junk"):
		ctrl._world_combat.request_shop_sell_junk()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_shop_sell_junk"):
		var result: Dictionary = srv.try_shop_sell_junk()
		ctrl._apply_equip_result_locally(result)


