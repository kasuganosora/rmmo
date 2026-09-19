extends RefCounted
## UI panel: auction house.

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

static func _build_auction_panel(ctrl) -> void:
	ctrl._auction_panel = PanelContainer.new()
	ctrl._auction_panel.name = "AuctionPanel"
	ctrl._auction_panel.set_script(HudDrag)
	ctrl._auction_panel.screen_margin = 4.0
	ctrl._auction_panel.min_size = Vector2(420, 320)
	ctrl._auction_panel.default_size = Vector2(540, 500)
	ctrl._auction_panel.initial_dock = "none"
	ctrl._auction_panel.drag_anywhere = true
	ctrl.add_child(ctrl._auction_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._auction_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "AuctionTitle"
	title.text = "拍卖行"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._auction_panel.visible = false)
	head.add_child(close_btn)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 220)
	outer.add_child(scroll)
	ctrl._auction_body = VBoxContainer.new()
	ctrl._auction_body.name = "AuctionBody"
	ctrl._auction_body.add_theme_constant_override("separation", 4)
	ctrl._auction_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ctrl._auction_body)
	ctrl._add_label(outer, "上架", 12, L2Style.COL_TITLE)
	var list_row = HBoxContainer.new()
	list_row.add_theme_constant_override("separation", 6)
	outer.add_child(list_row)
	ctrl._add_label(list_row, "物品ID", 11, L2Style.COL_MUTED)
	ctrl._auction_item_id_input = LineEdit.new()
	ctrl._auction_item_id_input.placeholder_text = "如 potion_hp_small"
	ctrl._auction_item_id_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_row.add_child(ctrl._auction_item_id_input)
	ctrl._add_label(list_row, "数量", 11, L2Style.COL_MUTED)
	ctrl._auction_qty_spin = SpinBox.new()
	ctrl._auction_qty_spin.min_value = 1
	ctrl._auction_qty_spin.max_value = 99
	ctrl._auction_qty_spin.value = 1
	ctrl._auction_qty_spin.custom_minimum_size = Vector2(70, 0)
	list_row.add_child(ctrl._auction_qty_spin)
	ctrl._add_label(list_row, "售价", 11, L2Style.COL_MUTED)
	ctrl._auction_price_spin = SpinBox.new()
	ctrl._auction_price_spin.min_value = 1
	ctrl._auction_price_spin.max_value = 999999
	ctrl._auction_price_spin.value = 10
	ctrl._auction_price_spin.custom_minimum_size = Vector2(90, 0)
	list_row.add_child(ctrl._auction_price_spin)
	var list_btn = Button.new()
	list_btn.text = "上架"
	list_btn.focus_mode = Control.FOCUS_NONE
	list_btn.pressed.connect(ctrl._on_auction_list)
	outer.add_child(list_btn)
	ctrl._auction_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._auction_panel)
	ctrl._refresh_auction_panel()
	ctrl.call_deferred("_nudge_auction")

static func _nudge_auction(ctrl) -> void:
	if ctrl._auction_panel == null:
		return
	ctrl._auction_panel.size = Vector2(540, 500)
	var vp = ctrl.get_viewport_rect().size
	ctrl._auction_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 270)), 64)

static func _toggle_auction_panel(ctrl, force_open: bool = false) -> void:
	if ctrl._auction_panel == null:
		return
	if force_open:
		ctrl._auction_panel.visible = true
	else:
		ctrl._auction_panel.visible = not ctrl._auction_panel.visible
	if ctrl._auction_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_auction"):
			ctrl.apply_auction_update({"type": "auction_update", "auction": srv.snapshot_auction()})
		ctrl._refresh_auction_panel()
		ctrl._auction_panel.move_to_front()
		ctrl.call_deferred("_nudge_auction")

static func apply_auction_update(ctrl, action: Dictionary) -> void:
	var ah_v: Variant = action.get("auction", action)
	if typeof(ah_v) != TYPE_DICTIONARY:
		if typeof(ah_v) == TYPE_ARRAY:
			ctrl._auction_state = {"listings": [], "count": 0, "max_listings": 50}
			var cleaned0: Array = []
			for e0 in ah_v:
				if typeof(e0) == TYPE_DICTIONARY:
					cleaned0.append((e0 as Dictionary).duplicate(true))
			ctrl._auction_state["listings"] = cleaned0
			ctrl._auction_state["count"] = cleaned0.size()
			if ctrl._auction_panel != null and ctrl._auction_panel.visible:
				ctrl._refresh_auction_panel()
		return
	var ad: Dictionary = ah_v
	ctrl._auction_state = {
		"listings": [],
		"count": int(ad.get("count", 0)),
		"max_listings": int(ad.get("max_listings", 50)),
	}
	var list_v: Variant = ad.get("listings", [])
	if typeof(list_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for e in list_v:
			if typeof(e) == TYPE_DICTIONARY:
				cleaned.append((e as Dictionary).duplicate(true))
		ctrl._auction_state["listings"] = cleaned
		ctrl._auction_state["count"] = cleaned.size()
	if ctrl._auction_panel != null and ctrl._auction_panel.visible:
		ctrl._refresh_auction_panel()

static func _refresh_auction_panel(ctrl) -> void:
	if ctrl._auction_body == null:
		return
	for c in ctrl._auction_body.get_children():
		c.queue_free()
	var listings_v: Variant = ctrl._auction_state.get("listings", [])
	var listings: Array = listings_v if typeof(listings_v) == TYPE_ARRAY else []
	var cap = int(ctrl._auction_state.get("max_listings", 50))
	ctrl._add_label(ctrl._auction_body, "在售 %d / %d" % [listings.size(), cap], 11, L2Style.COL_MUTED)
	if listings.is_empty():
		ctrl._add_label(ctrl._auction_body, "（暂无拍卖品）", 12, L2Style.COL_MUTED)
		return
	var self_id = ""
	var srv = Net.server()
	if srv != null and srv.has_method("_party_self_id"):
		self_id = str(srv._party_self_id())
	elif srv != null:
		var sid: Variant = srv.get("_session_character_id")
		if sid != null and str(sid) != "":
			self_id = str(sid)
	for e in listings:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var lid = str(e.get("id", ""))
		var seller_id = str(e.get("seller_id", ""))
		var seller = str(e.get("seller_name", "?"))
		var iid = str(e.get("item_id", ""))
		var iname = str(e.get("item_name", ""))
		if iname.is_empty():
			iname = ctrl._item_label(iid)
		var qty = int(e.get("qty", 0))
		var price = int(e.get("price_gold", 0))
		var is_own = (self_id != "" and seller_id == self_id) or seller_id == "player"
		var row = VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		ctrl._auction_body.add_child(row)
		var nl = Label.new()
		nl.text = "%s ×%d — %d 金币（%s）" % [iname, qty, price, seller]
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", L2Style.COL_TEXT)
		row.add_child(nl)
		var btn_row = HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 4)
		row.add_child(btn_row)
		if is_own:
			var cancel_btn = Button.new()
			cancel_btn.text = "下架"
			cancel_btn.focus_mode = Control.FOCUS_NONE
			cancel_btn.custom_minimum_size = Vector2(56, 24)
			cancel_btn.pressed.connect(ctrl._on_auction_cancel.bind(lid))
			btn_row.add_child(cancel_btn)
			ctrl._add_label(btn_row, "（我的）", 10, L2Style.COL_MUTED)
		else:
			var buy_btn = Button.new()
			buy_btn.text = "购买"
			buy_btn.focus_mode = Control.FOCUS_NONE
			buy_btn.custom_minimum_size = Vector2(56, 24)
			buy_btn.pressed.connect(ctrl._on_auction_buy.bind(lid))
			btn_row.add_child(buy_btn)

static func _on_auction_list(ctrl) -> void:
	var item_id = ctrl._auction_item_id_input.text.strip_edges() if ctrl._auction_item_id_input else ""
	var qty = int(ctrl._auction_qty_spin.value) if ctrl._auction_qty_spin else 1
	var price = int(ctrl._auction_price_spin.value) if ctrl._auction_price_spin else 1
	if item_id.is_empty():
		ctrl.append_system("请填写要上架的物品 ID。")
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_auction_list"):
		ctrl._world_combat.request_auction_list(item_id, qty, price)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_auction_list"):
			ctrl._apply_auction_result_locally(srv.try_auction_list(item_id, qty, price))
		else:
			ctrl.append_system("无法上架。")
			return
	if ctrl._auction_item_id_input:
		ctrl._auction_item_id_input.text = ""
	if ctrl._auction_qty_spin:
		ctrl._auction_qty_spin.value = 1
	if ctrl._auction_price_spin:
		ctrl._auction_price_spin.value = 10

static func _on_auction_buy(ctrl, listing_id: String) -> void:
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_auction_buy"):
		ctrl._world_combat.request_auction_buy(listing_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_auction_buy"):
		ctrl._apply_auction_result_locally(srv.try_auction_buy(listing_id))

static func _on_auction_cancel(ctrl, listing_id: String) -> void:
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_auction_cancel"):
		ctrl._world_combat.request_auction_cancel(listing_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_auction_cancel"):
		ctrl._apply_auction_result_locally(srv.try_auction_cancel(listing_id))

static func _apply_auction_result_locally(ctrl, result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"auction_update":
				ctrl.apply_auction_update(action)
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				ctrl.apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)

