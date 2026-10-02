extends RefCounted
## UI panel: auction house.

var ctrl
var _tabs: HBoxContainer
var _sell_form: VBoxContainer
var _listing_scroll: ScrollContainer
var _page := 0
var _list_button: Button
var _listing := false
var _feedback: Label
func _init(c):
	ctrl = c

const UIRequest = preload("res://scripts/ui/ui_request.gd")
const Net = preload("res://scripts/net/net.gd")
const GameWindow = preload("res://scripts/ui/game_window.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

func _build_auction_panel() -> void:
	ctrl._auction_panel = PanelContainer.new()
	ctrl._auction_panel.name = "AuctionPanel"
	ctrl._auction_panel.set_script(GameWindow)
	ctrl._auction_panel.screen_margin = 4.0
	ctrl._auction_panel.min_size = Vector2(420, 320)
	ctrl._auction_panel.default_size = Vector2(540, 500)
	ctrl._auction_panel.initial_dock = "none"
	ctrl._auction_panel.drag_anywhere = true
	ctrl.add_child(ctrl._auction_panel)
	var outer = GameWindow.build_body(ctrl._auction_panel, "拍卖行", func(): ctrl._auction_panel.hide(), "AuctionTitle")
	_tabs = GameWindow.add_tabs(outer, ["购买", "我的出售", "上架物品"], _select_page)
	var scroll := ScrollContainer.new()
	_listing_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 120
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	ctrl._auction_body = VBoxContainer.new()
	ctrl._auction_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl._auction_body.add_theme_constant_override("separation", 10)
	scroll.add_child(ctrl._auction_body)
	_sell_form = VBoxContainer.new()
	_sell_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sell_form.add_theme_constant_override("separation", 8)
	outer.add_child(_sell_form)
	_sell_form.add_child(L2Style.hairline())
	ctrl._add_label(_sell_form, "出售物品 · 从背包选择", 11, L2Style.COL_MUTED)
	ctrl._auction_item_id_input = ItemGrid.create(ctrl, _sell_form, "AuctionItemPicker", 160)
	ctrl._auction_item_id_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ctrl._auction_qty_spin = SpinBox.new()
	ctrl._auction_qty_spin.min_value = 1
	ctrl._auction_qty_spin.value = 1
	GameWindow.field(_sell_form, "数量", ctrl._auction_qty_spin)
	ctrl._auction_price_spin = SpinBox.new()
	ctrl._auction_price_spin.min_value = 1
	ctrl._auction_price_spin.max_value = 999999
	ctrl._auction_price_spin.value = 10
	ctrl._auction_price_spin.suffix = "金币"
	GameWindow.field(_sell_form, "整组售价", ctrl._auction_price_spin)
	_feedback = UIRequest.status(_sell_form, "AuctionStatus")
	ctrl._auction_qty_spin.value_changed.connect(func(_value): _clear_feedback_on_edit())
	ctrl._auction_price_spin.value_changed.connect(func(_value): _clear_feedback_on_edit())
	ctrl._auction_item_id_input.item_selected.connect(func(_item): _clear_feedback_on_edit())
	_list_button = Button.new()
	_list_button.text = "上架出售"
	_list_button.custom_minimum_size = Vector2(112, 30)
	L2Style.style_primary_button(_list_button)
	_list_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_list_button.pressed.connect(_on_auction_list)
	_sell_form.add_child(_list_button)
	ctrl._auction_item_id_input.item_selected.connect(func(_i): _sync_listing_quantity())
	_select_page(0)
	ctrl._auction_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._auction_panel)
	_refresh_auction_panel()
	ctrl.call_deferred("_nudge_auction")



func _nudge_auction() -> void:
	if ctrl._auction_panel == null:
		return
	ctrl._auction_panel.size = Vector2(540, 500)
	var vp = ctrl.get_viewport_rect().size
	ctrl._window_manager_logic.place_at(ctrl._auction_panel, Vector2(maxi(8, int(vp.x * 0.5 - 270)), 64))



func _toggle_auction_panel(force_open: bool = false) -> void:
	if ctrl._auction_panel == null:
		return
	if force_open:
		ctrl._auction_panel.visible = true
	else:
		ctrl._auction_panel.visible = not ctrl._auction_panel.visible
	if ctrl._auction_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_auction"):
			apply_auction_update({"type": "auction_update", "auction": srv.snapshot_auction()})
		_refresh_auction_panel()
		ctrl._auction_panel.move_to_front()
		ctrl.call_deferred("_nudge_auction")



func apply_auction_update(action: Dictionary) -> void:
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
				_refresh_auction_panel()
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
		_refresh_auction_panel()



func _refresh_auction_panel() -> void:
	if ctrl._auction_body == null:
		return
	for c in ctrl._auction_body.get_children():
		ctrl._auction_body.remove_child(c)
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
	var shown := 0
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
		if (_page == 1) != is_own: continue
		shown += 1
		var row = HBoxContainer.new()
		row.name = "AuctionListing"
		row.add_theme_constant_override("separation", 10)
		ctrl._auction_body.add_child(row)
		ItemGrid.display_cell(ctrl, row, {"item_id": iid, "name": iname, "qty": qty})
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var nl = Label.new()
		nl.text = "%s ×%d" % [iname, qty]
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", L2Style.COL_TEXT)
		info.add_child(nl)
		ctrl._add_label(info, "卖家：%s" % seller, 11, L2Style.COL_MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ctrl._add_label(row, "%d 金币\n整组" % price, 11, L2Style.COL_GOLD)
		var btn_row = HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 4)
		row.add_child(btn_row)
		if is_own:
			var cancel_btn = Button.new()
			cancel_btn.text = "下架"
			cancel_btn.focus_mode = Control.FOCUS_NONE
			cancel_btn.custom_minimum_size = Vector2(56, 24)
			cancel_btn.pressed.connect(_on_auction_cancel.bind(lid))
			btn_row.add_child(cancel_btn)
			ctrl._add_label(btn_row, "（我的）", 10, L2Style.COL_MUTED)
		else:
			var buy_btn = Button.new()
			buy_btn.text = "购买这组"
			buy_btn.disabled = ctrl._server_gold < price
			buy_btn.tooltip_text = "金币不足" if buy_btn.disabled else "购买整组物品"
			buy_btn.focus_mode = Control.FOCUS_NONE
			buy_btn.custom_minimum_size = Vector2(56, 24)
			buy_btn.pressed.connect(_on_auction_buy.bind(lid))
			btn_row.add_child(buy_btn)

	if shown == 0: ctrl._add_label(ctrl._auction_body, "你还没有上架物品。" if _page == 1 else "暂无可购买的物品。", 12, L2Style.COL_MUTED)



func _on_auction_list() -> void:
	if _listing: return
	var item_id = str(ctrl._auction_item_id_input.selected_item().get("item_id", ""))
	var qty = int(ctrl._auction_qty_spin.value) if ctrl._auction_qty_spin else 1
	var price = int(ctrl._auction_price_spin.value) if ctrl._auction_price_spin else 1
	if item_id.is_empty():
		ctrl.append_system("请从背包选择要出售的物品。")
		return
	_listing = true
	UIRequest.lock_form(_sell_form, true)
	_list_button.text = "上架中…"
	UIRequest.set_status(_feedback, "正在上架，请等待结果…")
	UIRequest.dispatch(ctrl, "try_auction_list", [item_id, qty, price], _apply_auction_result_locally, _auction_list_finished)


func _auction_list_finished(result: Dictionary) -> void:
	_listing = false
	UIRequest.lock_form(_sell_form, false)
	_list_button.text = "上架出售"
	UIRequest.set_status(_feedback, UIRequest.message(result, "物品已上架"), not result.get("ok", false))
	ctrl._auction_item_id_input.fill_inventory(ctrl._server_inventory)
	if not result.get("ok", false):
		_sync_listing_quantity()
		UIRequest.set_status(_feedback, UIRequest.message(result), true)
		return
	if ctrl._auction_item_id_input:
		ctrl._auction_item_id_input.select_key("")
		_sync_listing_quantity()
	if ctrl._auction_qty_spin:
		ctrl._auction_qty_spin.value = 1
	if ctrl._auction_price_spin:
		ctrl._auction_price_spin.value = 10
	UIRequest.set_status(_feedback, "物品已上架")


func _clear_feedback_on_edit() -> void:
	if not _listing: _feedback.text = ""



func _on_auction_buy(listing_id: String) -> void:
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_auction_buy"):
		ctrl._world_combat.request_auction_buy(listing_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_auction_buy"):
		_apply_auction_result_locally(srv.try_auction_buy(listing_id))



func _on_auction_cancel(listing_id: String) -> void:
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_auction_cancel"):
		ctrl._world_combat.request_auction_cancel(listing_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_auction_cancel"):
		_apply_auction_result_locally(srv.try_auction_cancel(listing_id))



func _apply_auction_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"auction_update":
				apply_auction_update(action)
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				ctrl.apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)



func _select_page(index: int) -> void:
	_page = index
	GameWindow.highlight_tabs(_tabs, index)
	_sell_form.visible = index == 2
	_listing_scroll.visible = index != 2
	if not _listing: ctrl._auction_item_id_input.fill_inventory(ctrl._server_inventory)
	_sync_listing_quantity()
	_refresh_auction_panel()


func _sync_listing_quantity() -> void:
	if _listing: return
	ctrl._auction_item_id_input.sync_quantity(ctrl._auction_qty_spin)
	_list_button.disabled = str(ctrl._auction_item_id_input.selected_item().get("item_id", "")).is_empty()
