extends RefCounted
## UI panel: shop window (catalog, buy/sell carts, buyback, vendor rep).

var ctrl
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const SHOP_TABS := [
	["买入", "buy"],
	["卖出", "sell"],
	["回购", "buyback"],
]

func show_shop(shop_id: String, title: String, listings: Array, gold: int = 0, vendor_rep: int = -1) -> void:
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



func _add_buyback_row(parent: Node, index: int, label: String, price: int) -> void:
	var btn = Button.new()
	btn.text = "%s   %d" % [label, price]
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	L2Style.style_row_button(btn, false)
	btn.pressed.connect(func():
		if ctrl._world_combat != null and ctrl._world_combat.has_method("request_shop_buyback"):
			ctrl._world_combat.request_shop_buyback(index)
		else:
			var srv = Net.server()
			if srv != null and srv.has_method("try_shop_buyback"):
				ctrl._apply_equip_result_locally(srv.try_shop_buyback(index))
	)
	parent.add_child(btn)



func hide_shop() -> void:
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
	panel.set_script(HudDrag)
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
	gold_l.text = "Adena 0"
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
	var buy_root = _make_shop_tab_page("BuyPage", "BuyCatalog", "BuyCart", "商品列表", "我的选择")
	vbox.add_child(buy_root)
	var sell_root = _make_shop_tab_page("SellPage", "SellCatalog", "SellCart", "背包可出售", "我的选择")
	vbox.add_child(sell_root)
	var back_root = _make_shop_tab_page("BuybackPage", "BuybackCatalog", "BuybackCart", "最近卖出", "回购")
	vbox.add_child(back_root)
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
	cancel_btn.text = "取消"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.pressed.connect(hide_shop)
	L2Style.style_action_button(cancel_btn)
	bottom.add_child(cancel_btn)
	var ok_btn = Button.new()
	ok_btn.text = "确定"
	ok_btn.focus_mode = Control.FOCUS_NONE
	ok_btn.pressed.connect(_on_shop_confirm)
	L2Style.style_action_button(ok_btn)
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
	ctrl._add_label(col, heading, 11, L2Style.COL_MUTED)
	var scroll = ScrollContainer.new()
	scroll.name = list_name + "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list = VBoxContainer.new()
	list.name = list_name
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
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
		btn.custom_minimum_size = Vector2(140, 30)
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



func _place_shop_panel() -> void:
	if ctrl._shop_panel == null:
		return
	var vp = ctrl.get_viewport().get_visible_rect().size
	ctrl._shop_panel.size = Vector2(580, 460)
	ctrl._shop_panel.global_position = Vector2(maxi(8, int(vp.x * 0.2)), maxi(40, int(vp.y * 0.12)))



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
		gold_l.text = "Adena  %d" % maxi(ctrl._server_gold, 0)
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
	var buy_cat = ctrl._shop_panel.find_child("BuyCatalog", true, false) as VBoxContainer
	var buy_cart = ctrl._shop_panel.find_child("BuyCart", true, false) as VBoxContainer
	var sell_cat = ctrl._shop_panel.find_child("SellCatalog", true, false) as VBoxContainer
	var sell_cart = ctrl._shop_panel.find_child("SellCart", true, false) as VBoxContainer
	ctrl._clear_container(buy_cat)
	ctrl._clear_container(buy_cart)
	ctrl._clear_container(sell_cat)
	ctrl._clear_container(sell_cart)
	# Buy catalog
	if buy_cat != null:
		if ctrl._shop_listings.is_empty():
			ctrl._add_label(buy_cat, "（无商品）", 12, L2Style.COL_MUTED)
		else:
			for it in ctrl._shop_listings:
				if typeof(it) != TYPE_DICTIONARY:
					continue
				var iid = str(it.get("item_id", ""))
				var iname = str(it.get("name", iid))
				var price: int = int(it.get("buy_price", 0))
				_add_shop_catalog_row(buy_cat, iname, price, true, iid, iname, price)
	# Buy cart
	_fill_cart_list(buy_cart, ctrl._shop_buy_cart, true)
	# Sell catalog from bag
	if sell_cat != null:
		var sellables: Array = _shop_sellable_bag_rows()
		if sellables.is_empty():
			ctrl._add_label(sell_cat, "（无可出售物品）", 12, L2Style.COL_MUTED)
		else:
			for it2 in sellables:
				var iid2 = str(it2.get("id", ""))
				var iname2 = str(it2.get("name", iid2))
				var sprice: int = int(it2.get("sell_price", 0))
				var have_q: int = int(it2.get("qty", 1))
				_add_shop_catalog_row(sell_cat, "%s×%d" % [iname2, have_q], sprice, false, iid2, iname2, sprice)
	_fill_cart_list(sell_cart, ctrl._shop_sell_cart, false)
	var back_cat = ctrl._shop_panel.find_child("BuybackCatalog", true, false) as VBoxContainer
	ctrl._clear_container(back_cat)
	if back_cat != null:
		if ctrl._shop_buyback.is_empty():
			ctrl._add_label(back_cat, "（无回购）", 12, L2Style.COL_MUTED)
		else:
			for i in range(ctrl._shop_buyback.size()):
				var row: Variant = ctrl._shop_buyback[i]
				if typeof(row) != TYPE_DICTIONARY:
					continue
				var iid3 = str(row.get("item_id", ""))
				var nm3 = str(row.get("name", iid3))
				var q3: int = int(row.get("qty", 1))
				var p3: int = int(row.get("unit_price", 0))
				_add_buyback_row(back_cat, i, "%s×%d" % [nm3, q3], p3)



func _add_shop_catalog_row(parent: VBoxContainer, label_text: String, price: int, is_buy: bool, item_id: String, display_name: String, unit_price: int) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var btn = Button.new()
	btn.text = "%s    %d Adena" % [label_text, price]
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 30)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.tooltip_text = ctrl._equip_compare_tip(item_id, "%s\n%d Adena\n点击加入选择" % [ctrl._item_rarity_name_line(item_id, display_name), unit_price])
	L2Style.style_row_button(btn, false)
	btn.pressed.connect(_on_shop_catalog_add.bind(is_buy, item_id, display_name, unit_price))
	row.add_child(btn)
	var add_btn = Button.new()
	add_btn.text = "+"
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.custom_minimum_size = Vector2(28, 28)
	L2Style.style_compact_button(add_btn)
	add_btn.pressed.connect(_on_shop_catalog_add.bind(is_buy, item_id, display_name, unit_price))
	row.add_child(add_btn)



func _fill_cart_list(parent: VBoxContainer, cart: Array, is_buy: bool) -> void:
	if parent == null:
		return
	if cart.is_empty():
		ctrl._add_label(parent, "（未选择）", 12, L2Style.COL_MUTED)
		return
	var total = 0
	for line in cart:
		if typeof(line) != TYPE_DICTIONARY:
			continue
		var iid = str(line.get("item_id", ""))
		var q: int = int(line.get("qty", 1))
		var up: int = int(line.get("unit_price", 0))
		var nm = str(line.get("name", iid))
		var line_gold: int = up * q
		total += line_gold
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		parent.add_child(row)
		var lab = Button.new()
		lab.text = "%s ×%d    %d Adena" % [nm, q, line_gold]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.focus_mode = Control.FOCUS_NONE
		lab.custom_minimum_size = Vector2(0, 30)
		lab.tooltip_text = "点击移除"
		L2Style.style_row_button(lab, true)
		lab.pressed.connect(_on_shop_cart_remove.bind(is_buy, iid))
		row.add_child(lab)
		var minus = Button.new()
		minus.text = "−"
		minus.focus_mode = Control.FOCUS_NONE
		minus.custom_minimum_size = Vector2(28, 28)
		L2Style.style_compact_button(minus)
		minus.pressed.connect(_on_shop_cart_adjust.bind(is_buy, iid, -1))
		row.add_child(minus)
	ctrl._add_label(parent, "合计  %d Adena" % total, 12, L2Style.COL_GOLD)



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
		ctrl.append_system("点选回购列表中的物品即可买回。")
	else:
		_confirm_buy_cart()



func _confirm_buy_cart() -> void:
	if ctrl._shop_id.is_empty():
		return
	if ctrl._shop_buy_cart.is_empty():
		ctrl.append_system("请先选择要购买的物品。")
		return
	if ctrl._world_combat == null or not ctrl._world_combat.has_method("request_shop_buy"):
		ctrl.append_system("无法购买。")
		return
	var lines: Array = ctrl._shop_buy_cart.duplicate(true)
	ctrl._shop_buy_cart.clear()
	_fill_shop_panel()
	for line in lines:
		if typeof(line) != TYPE_DICTIONARY:
			continue
		var iid = str(line.get("item_id", ""))
		var q: int = maxi(int(line.get("qty", 1)), 1)
		if iid.is_empty():
			continue
		# Server system_message reports gold/bag/stack failures per line.
		ctrl._world_combat.request_shop_buy(ctrl._shop_id, iid, q)



func _confirm_sell_cart() -> void:
	if ctrl._shop_sell_cart.is_empty():
		ctrl.append_system("请先选择要出售的物品。")
		return
	if ctrl._world_combat == null or not ctrl._world_combat.has_method("request_shop_sell"):
		ctrl.append_system("无法出售。")
		return
	var lines: Array = ctrl._shop_sell_cart.duplicate(true)
	ctrl._shop_sell_cart.clear()
	_fill_shop_panel()
	for line in lines:
		if typeof(line) != TYPE_DICTIONARY:
			continue
		var iid = str(line.get("item_id", ""))
		var q: int = maxi(int(line.get("qty", 1)), 1)
		if iid.is_empty():
			continue
		ctrl._world_combat.request_shop_sell(iid, q)



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


