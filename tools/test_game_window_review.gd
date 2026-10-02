extends SceneTree
## Game-only visual and pointer regression suite. Run GPU via private desktop runner.
class RequestSpy extends Node:
	var calls: Array = []
	var item_catalog
	var recipe_catalog
	var combat_stats
	var equipment
	var inventory = preload("res://scripts/net/combat/inventory.gd").new()
	var _session_character_id := "review"
	var owner_hud
	var source_server
	func item_display_name(id): return source_server.item_display_name(id)
	func try_mail_send(to, subject, body, gold, item, qty):
		request_mail_send(to, subject, body, gold, item, qty)
		return {"ok": true, "actions": []}
	func try_auction_list(id, qty, price):
		request_auction_list(id, qty, price)
		return {"ok": true, "actions": []}
	func try_shop_buy(shop, id, qty):
		request_shop_buy(shop, id, qty)
		return {"ok": true, "actions": []}
	func try_shop_sell(id, qty):
		request_shop_sell(id, qty)
		return {"ok": true, "actions": []}
	func request_mail_send(to, subject, body, gold, item, qty): calls.append(["mail", to, subject, body, gold, item, qty])
	func request_mail_read(id): calls.append(["read", id])
	func request_auction_list(id, qty, price): calls.append(["auction", id, qty, price])
	func request_warehouse_deposit(id, qty): calls.append(["deposit", id, qty])
	func request_warehouse_withdraw(id, qty): calls.append(["withdraw", id, qty])
	func request_trade_cancel(): owner_hud._trade_panel.hide()
	func request_shop_close(): pass
	func request_event_choice(id, index): calls.append(["choice", id, index])
	func request_craft(id, qty): calls.append(["craft", id, qty])
	func request_use_skill(id): calls.append(["skill", id])
	func request_trade_put_item(id, qty): calls.append(["trade_put", id, qty])
	func request_trade_take_item(id, qty): calls.append(["trade_take", id, qty])
	func request_shop_buy(shop, id, qty): calls.append(["shop_buy", shop, id, qty])
	func request_shop_sell(id, qty): calls.append(["shop_sell", id, qty])
	func request_shop_buyback(index): calls.append(["buyback", index])
	func request_auction_buy(id): calls.append(["auction_buy", id])
	func request_loot_take(id, qty): calls.append(["loot", id, qty])
	func request_loot_close(): owner_hud._loot_panel.hide()

var requests: RequestSpy
var hud
var gs
var failures := 0
var checks := 0
var panels := {}
var out_dir: String
var capture := false

func _init() -> void:
	call_deferred("_run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + message)

func settle() -> void:
	for i in 5: await process_frame

func _run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	gs = root.get_node("GameSettings")
	gs.persist_enabled = false
	gs.window_layouts = {}
	gs.ui_scale = 1.0
	gs.hud_locked = false
	root.gui_embed_subwindows = true
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 800)
	if capture: DisplayServer.window_set_size(root.size)
	out_dir = preload("res://scripts/asset/art_paths.gd").review_path("game_windows")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var bg := ColorRect.new()
	bg.color = Color("34433b")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	hud = load("res://scenes/ui/game_hud.tscn").instantiate()
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await settle()
	requests = RequestSpy.new()
	requests.owner_hud = hud
	root.add_child(requests)
	hud._world_combat = requests
	hud._character = {"name": "艾琳", "class_id": "warrior", "level": 12}
	hud._server_inventory = [{"id": "wooden_sword", "qty": 1}, {"id": "potion_hp_small", "qty": 8}]
	hud._server_gold = 12840
	hud._server_quests = [{"id": "q1", "title": "新手的第一步", "status": "in_progress", "desc": "在训练场击败假人，向教官复命。", "objectives": [{"text": "训练假人", "cur": 1, "max": 3}]}]
	hud._server_skills = [{"id": "power_strike", "name": "强力斩击", "category": "active"}]
	for id in hud._windows:
		hud._fill_window(id)
		panels[id] = hud._windows[id]
	for id in ["friends", "mail", "guild", "auction", "warehouse", "craft", "emote", "titles", "daily", "achievements", "combat_log", "party", "trade"]:
		panels[id] = hud.get("_" + id + "_panel")
		await settle()
	# Long but valid display text exposes layouts that only work with empty data.
	hud._trade_state = {"active": true, "partner_name": "测试商人", "my_items": [], "their_items": [], "my_gold": 10, "their_gold": 15, "my_ready": false, "their_ready": true}
	for i in 12:
		hud._trade_state.my_items.append({"item_id": "potion_hp_small", "name": "小型生命药水", "qty": i + 1})
		hud._trade_state.their_items.append({"item_id": "potion_mp_small", "name": "小型魔法药水", "qty": i + 1})
	hud._party_state = {"party_id": "review", "leader": "p0", "members": []}
	for i in 8: hud._party_state.members.append({"id": "p%d" % i, "name": "冒险者 %d" % i, "hp": 100, "hp_max": 200, "online": true})
	hud._daily_state = {"daily_date": "2026-10-02", "daily": [{"id": "d1", "title": "训练场的日常委托", "state": "available"}, {"id": "d2", "title": "在森林中采集药草", "state": "accepted"}]}
	hud._friends_state = {"friends": [{"id": "f1", "name": "来自北方的冒险者", "online": true}, {"id": "f2", "name": "艾琳", "online": false}]}
	hud._mail_state = {"mails": [{"id": "m1", "subject": "一起探索失落遗迹的邀请", "from": "来自北方的冒险者", "body": "集合后一起前往训练场。请带好药水和装备，这是用于检查长正文换行的一封邮件。", "gold": 100, "items": [{"id": "potion_hp_small", "qty": 2}]}]}
	hud._auction_state = {"listings": [{"id": "a1", "item_id": "wooden_sword", "item_name": "新手训练长剑", "seller_name": "来自北方的冒险者", "qty": 1, "price_gold": 12500}]}
	hud._guild_state = {"id": "g1", "name": "星光旅团", "leader_id": "g1", "members": [{"id": "g1", "name": "来自北方的冒险者", "rank": "leader"}, {"id": "g2", "name": "艾琳", "rank": "member"}]}
	for id in ["friends", "mail", "guild", "auction", "warehouse", "craft", "emote", "titles", "daily", "achievements", "combat_log", "party", "trade"]:
		hud.call("_refresh_" + id + "_panel")
	await settle()
	hud.show_shop("review", "杂货商", [{"item_id": "potion_hp_small", "name": "小型生命药水", "buy_price": 20}], 12840)
	panels["shop"] = hud._shop_panel
	hud.show_npc_dialogue("训练教官", "欢迎来到训练场。击败假人，再来向我复命。", ["接受任务", "打听村庄", "离开"])
	panels["npc"] = hud._npc_chat
	hud.show_loot("review", "npc", [{"item_id": "potion_hp_small", "name": "小型生命药水", "qty": 3}])
	panels["loot"] = hud._loot_panel
	hud._show_inspect("review", "测试玩家")
	panels["inspect"] = hud._inspect_panel
	hud.show_death_dialog()
	panels["death"] = hud._death_panel
	hud._show_drop_qty_dialog("potion_hp_small", 8)
	panels["quantity"] = hud._drop_qty_panel
	hud._show_invite_dialog("review", "来自北方的冒险者")
	panels["invite"] = hud._invite_panel
	hud.show_loot_roll({"roll_id": "review", "item_id": "wooden_sword", "name": "新手训练长剑", "qty": 1})
	panels["loot_roll"] = hud._loot_roll_panel
	hud._ensure_menu_popup()
	panels["menu"] = hud._menu_popup
	await settle()
	for p in panels.values(): p.hide()
	for id in panels:
		var p: Control = panels[id]
		p.show()
		p.move_to_front()
		p.global_position = Vector2(180, 80)
		await settle()
		expect(_fits_horizontally(p), id + " content has no horizontal overflow")
		expect(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(p.get_global_rect()), id + " fits normal viewport")
		await shot(id, p)
		var title: Control = p.find_child("TitleBar", true, false)
		if title != null and p.has_method("_clamp_on_screen"):
			expect(title.get_theme_stylebox("panel") is StyleBoxEmpty, id + " uses the shared unboxed title")
			expect(p.get_script().resource_path == "res://scripts/ui/game_window.gd", id + " uses GameWindow component")
			var start := p.global_position
			var point := title.get_global_rect().position + Vector2(45, 14)
			await pointer(point, true)
			var motion := InputEventMouseMotion.new()
			motion.position = point + Vector2(35, 20)
			motion.global_position = motion.position
			motion.relative = Vector2(35, 20)
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(motion)
			await process_frame
			await pointer(motion.position, false)
			expect(p.global_position.distance_to(start) > 15, id + " title drag responds")
			var placed := p.global_position
			if hud._windows.has(id):
				p.hide()
				hud._toggle_window(id)
			else:
				hud._window_manager_logic.place_at(p, Vector2(20, 20))
			await settle()
			expect(p.global_position.distance_to(placed) < 1, id + " preserves dragged position on reopen")
			var close: Button = title.get_child(0).get_child(title.get_child(0).get_child_count() - 1)
			await pointer(close.get_global_rect().get_center(), true)
			await pointer(close.get_global_rect().get_center(), false)
			expect(not p.visible, id + " close button responds")
		p.hide()
	var net = preload("res://scripts/net/net.gd")
	requests.source_server = net.server()
	requests.item_catalog = net.server().item_catalog
	requests.recipe_catalog = net.server().recipe_catalog
	requests.combat_stats = net.server().combat_stats
	requests.equipment = net.server().equipment
	net._server_override = requests
	await review_interactions()
	net.clear_server_override()
	await review_grid_refresh()
	root.size = Vector2i(900, 700)
	if capture: DisplayServer.window_set_size(root.size)
	gs.set_ui_scale(1.3)
	await settle()
	for id in panels:
		var p: Control = panels[id]
		p.show()
		p.move_to_front()
		# Placement through the same shared path used by game windows.
		hud._window_manager_logic.place_at(p, Vector2(8, 8))
		await settle()
		expect(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(p.get_global_rect()), id + " fits 900x700 at 130%")
		expect(_fits_horizontally(p), id + " content fits at 130%")
		await shot("compact_" + id, p)
		p.hide()
	for id in ["mail", "auction"]:
		var p: Control = await show_only(id)
		await click(button_named(p, "写信" if id == "mail" else "上架物品"))
		expect(_fits_horizontally(p), id + " form fits at 130%")
		var action: Button = button_named(p, "发送邮件" if id == "mail" else "上架出售")
		expect(p.get_global_rect().encloses(action.get_global_rect()), id + " form action stays inside window at 130%")
		await shot("compact_form_" + id, p)
		p.hide()
	var settings: Control = await show_only("system")
	await click(settings.find_child("ResetAllSettings", true, false))
	var confirmation: Control = settings.find_child("InlineConfirmation", true, false)
	expect(confirmation != null and settings.get_global_rect().encloses(confirmation.get_global_rect()), "reset confirmation fits at 130%")
	await shot("compact_reset_confirmation", settings)
	await click(button_named(settings, "取消"))
	expect(settings.find_child("InlineConfirmation", true, false) == null, "pointer cancels visible reset confirmation")
	settings.hide()
	var map_panel: Control = await show_only("map")
	map_panel.global_position = Vector2(8, 8)
	await settle()
	var width_before := map_panel.get_global_rect().size.x
	var edge := map_panel.get_global_rect().position + Vector2(width_before - 2, 100)
	await pointer(edge, true)
	var resize_motion := InputEventMouseMotion.new()
	resize_motion.position = edge + Vector2(39, 0)
	resize_motion.global_position = resize_motion.position
	resize_motion.relative = Vector2(39, 0)
	resize_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(resize_motion)
	await settle()
	await pointer(resize_motion.position, false)
	expect(absf(map_panel.get_global_rect().size.x - width_before - 39) < 2, "scaled window edge follows pointer exactly")
	map_panel.hide()
	# Scale changes also constrain already open windows.
	var inv: Control = panels["inventory"]
	inv.show()
	inv.global_position = Vector2(800, 650)
	gs.set_ui_scale(1.2)
	await settle()
	expect(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(inv.get_global_rect()), "scale change clamps existing game windows")
	inv.global_position = Vector2(450, 100)
	root.size = Vector2i(800, 680)
	await settle()
	expect(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(inv.get_global_rect()), "viewport resize clamps visible game windows")
	hud.queue_free()
	await settle()
	print("test_game_window_review: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _fits_horizontally(panel: Control) -> bool:
	var bounds := panel.get_global_rect().grow(1)
	for c in panel.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree() or c.get_viewport() != panel.get_viewport(): continue
		if c is BaseButton or c is LineEdit or c is Label:
			var r: Rect2 = c.get_global_rect()
			if r.position.x < bounds.position.x or r.end.x > bounds.end.x:
				print("OVERFLOW ", panel.name, " / ", c.name, " ", c.get("text"), " ", r)
				return false
	return true

func pointer(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func shot(id: String, p: Control) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var region := Rect2i(p.get_global_rect().grow(3)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(region).save_png(out_dir.path_join(id + ".png"))


func button_named(panel: Control, text: String) -> Button:
	for b in panel.find_children("*", "Button", true, false):
		if not b is OptionButton and b.text == text and b.is_visible_in_tree(): return b
	return null

func click(button: Control) -> void:
	if button == null:
		expect(false, "interaction target exists")
		return
	var at := button.get_global_rect().get_center()
	await pointer(at, true)
	await pointer(at, false)
	await settle()

func show_only(id: String) -> Control:
	for p in panels.values(): p.hide()
	var p: Control = panels[id]
	p.show()
	p.move_to_front()
	p.global_position = Vector2(150, 60)
	await settle()
	return p

func review_interactions() -> void:
	hud._server_inventory = [{"id": "wooden_sword", "qty": 1}, {"id": "potion_hp_small", "qty": 8}]
	hud._server_gold = 12840
	var p: Control = await show_only("mail")
	await click(button_named(p, "写信"))
	expect(hud._mail_body_input.is_visible_in_tree(), "mail compose opens independently of inbox")
	hud._mail_to_input.text = "艾琳"
	hud._mail_to_input.text_changed.emit("艾琳")
	hud._mail_subject_input.text = "测试草稿"
	hud._mail_body_input.text = "切换页后保留草稿。"
	await click(button_named(p, "收件箱"))
	await click(button_named(p, "写信"))
	expect(hud._mail_subject_input.text == "测试草稿", "switching mail pages preserves draft")
	var picker = hud._mail_item_id_input
	await click_grid(picker, "potion_hp_small")
	expect(hud._mail_item_qty_spin.max_value == 8, "mail attachment quantity is capped by selected stack")
	hud._mail_item_qty_spin.value = 3
	await shot("mail_compose", p)
	await click(button_named(p, "发送邮件"))
	expect(requests.calls.back() == ["mail", "艾琳", "测试草稿", "切换页后保留草稿。", 0, "potion_hp_small", 3], "mail picker sends item ID and quantity through existing request")
	await click(button_named(p, "收件箱"))
	var mail_button: Button
	for b in p.find_children("*", "Button", true, false):
		if b.text.contains("一起探索"): mail_button = b
	await click(mail_button)
	expect(requests.calls.back() == ["read", "m1"] and button_named(p, "收取附件") != null, "opening a mail reveals its own attachment actions")
	await shot("mail_read", p)
	p = await show_only("auction")
	await click(button_named(p, "上架物品"))
	picker = hud._auction_item_id_input
	expect(picker.scroll.size.y >= 130 and not hud._auction_panel_logic._listing_scroll.visible, "auction listing form provides a full-height item picker")
	await click_grid(picker, "potion_hp_small")
	expect(hud._auction_qty_spin.max_value == 8, "auction quantity is capped by selected stack")
	hud._auction_qty_spin.value = 2
	hud._auction_price_spin.value = 50
	await shot("auction_sell", p)
	await click(button_named(p, "上架出售"))
	expect(requests.calls.back() == ["auction", "potion_hp_small", 2, 50], "auction selection sends ID, quantity and whole-stack price")
	p = await show_only("warehouse")
	hud._refresh_warehouse_panel()
	await settle()
	var before := requests.calls.size()
	await click_grid(p.find_child("WarehouseBag", true, false), "potion_hp_small")
	expect(requests.calls.size() == before, "selecting warehouse item never transfers it")
	await click(button_named(p, "全部"))
	await shot("warehouse_selected", p)
	await click(button_named(p, "存入物品 →"))
	expect(requests.calls.back() == ["deposit", "potion_hp_small", 8], "warehouse explicit transfer uses chosen quantity")
	p = await show_only("shop")
	hud.show_shop("grid_review", "杂货商", [{"item_id": "potion_hp_small", "name": "小型生命药水", "buy_price": 20}], 12840)
	await settle()
	before = requests.calls.size()
	await click_grid(p.find_child("BuyCatalog", true, false), "potion_hp_small")
	expect(requests.calls.size() == before, "selecting shop cell never buys")
	p.find_child("BuyCatalogQuantity", true, false).value = 3
	await click(p.find_child("BuyCatalogAction", true, false))
	expect(hud._shop_buy_cart.size() == 1 and hud._shop_buy_cart[0].qty == 3, "shop adds chosen quantity to grid cart")
	await shot("shop_cart", p)
	await click(p.find_child("ConfirmShopSelection", true, false))
	expect(requests.calls.back() == ["shop_buy", "grid_review", "potion_hp_small", 3], "shop grid purchase uses correct quantity")
	hud.apply_shop_buyback([{"item_id": "potion_hp_small", "name": "小型生命药水", "qty": 2, "unit_price": 20}, {"item_id": "potion_hp_small", "name": "小型生命药水", "qty": 5, "unit_price": 30}])
	await click(button_named(p, "回购"))
	await click_grid(p.find_child("BuybackCatalog", true, false), "1")
	await shot("shop_buyback", p)
	await click(button_named(p, "回购所选"))
	expect(requests.calls.back() == ["buyback", 1], "duplicate buyback item selects exact original index")
	await review_shop_slots(p)
	p = await show_only("trade")
	before = requests.calls.size()
	await click_grid(p.find_child("TradeBag", true, false), "potion_hp_small")
	expect(requests.calls.size() == before, "selecting trade item never changes quote")
	await click(button_named(p, "全部"))
	await shot("trade_selected", p)
	await click(button_named(p, "放入报价"))
	expect(requests.calls.back() == ["trade_put", "potion_hp_small", 8], "trade puts chosen full stack")
	await click_grid(p.find_child("TradeMyOffer", true, false), "potion_hp_small")
	await click(button_named(p, "移回背包"))
	expect(requests.calls.back() == ["trade_take", "potion_hp_small", 1], "trade removes selected quantity from own offer")
	p = await show_only("loot")
	before = requests.calls.size()
	await click_grid(p.find_child("LootGrid", true, false), "potion_hp_small")
	expect(requests.calls.size() == before, "selecting loot cell never immediately picks up")
	await click(button_named(p, "拾取所选"))
	expect(requests.calls.back() == ["loot", "potion_hp_small", -1], "selected loot uses existing full-stack pickup")
	p = await show_only("auction")
	await click(button_named(p, "购买"))
	var listing = p.find_child("AuctionListing", true, false)
	expect(listing != null and listing.get_child(0).get_script().resource_path.ends_with("item_grid_cell.gd"), "auction retains rich rows with a leading item cell")
	await click(button_named(p, "购买这组"))
	expect(requests.calls.back() == ["auction_buy", "a1"], "auction row buys exact listing ID")
	p = await show_only("craft")
	var recipe: Dictionary = hud._craft_recipes[0]
	hud._server_inventory.clear()
	for ing in recipe.get("ingredients", []): hud._server_inventory.append({"id": ing.id, "qty": int(ing.qty) * 3})
	hud._craft_selected_id = str(recipe.id)
	hud._refresh_craft_panel()
	await settle()
	expect(hud._craft_qty_spin.max_value == 3, "craft maximum reflects all ingredients")
	hud._craft_qty_spin.value = 2
	await shot("craft_ready", p)
	await click(button_named(p, "制作"))
	expect(requests.calls.back() == ["craft", str(recipe.id), 2], "craft action uses selected recipe and count")
	p = await show_only("skills")
	hud._known_skills = {"power_strike": true}
	hud._fill_window("skills")
	await settle()
	var cells: Array = hud._iter_skill_cells(p)
	before = requests.calls.size()
	await click(cells[0])
	expect(requests.calls.size() == before and hud._selected_skill_id == "power_strike", "skill selection does not accidentally cast")
	await shot("skills_selected", p)
	await click(button_named(p, "使用"))
	expect(requests.calls.back() == ["skill", "power_strike"], "explicit skill use casts selected skill")
	p = await show_only("character")
	await click(button_named(p, "属性"))
	expect(button_named(p, "重置属性（30金）") != null, "character attribute actions are on the attribute page")
	hud._fill_window("character")
	await settle()
	expect(button_named(p, "重置属性（30金）").is_visible_in_tree(), "character refresh preserves attribute page during point allocation")
	await shot("character_attributes", p)
	p = await show_only("inventory")
	var search: Control = p.find_child("InvSearch", true, false)
	var position := search.global_position
	p.find_child("Scroll", true, false).scroll_vertical = 1000
	await settle()
	expect(search.global_position == position, "inventory search stays fixed while grid scrolls")
	p = await show_only("friends")
	await click(button_named(p, "来自北方的冒险者 · 在线"))
	expect(button_named(p, "私聊") != null, "friend actions belong to selected contact")
	await shot("friends_selected", p)
	p = await show_only("titles")
	await click(button_named(p, "已解锁"))
	await shot("titles_unlocked", p)
	p = await show_only("achievements")
	await click(button_named(p, "已解锁"))
	await shot("achievements_unlocked", p)
	p = await show_only("npc")
	await click(button_named(p, "接受任务"))
	expect(not p.visible and requests.calls.back() == ["choice", "", 0], "NPC full-row choice closes dialogue and sends the correct option")
	p = await show_only("emote")
	await click(button_named(p, "面部"))
	await shot("emote_face", p)
	p = await show_only("system")
	panels["titles"].show()
	panels["titles"].move_to_front()
	expect(hud._close_top_window() and not panels["titles"].visible and p.visible, "Escape closes the visually topmost auxiliary window")
	for item in panels.values(): item.hide()


func click_grid(grid: Control, key: String) -> void:
	var cell: Control
	for c in grid.cells.get_children():
		if c.get_meta("item_key", "") == key:
			cell = c
			break
	expect(cell != null, "%s contains item %s" % [grid.name, key])
	if cell == null: return
	grid.scroll.ensure_control_visible(cell)
	await settle()
	await click(cell)
	if is_instance_valid(grid): expect(grid.selected_key == key, "%s selects a cell with real pointer input" % grid.name)


func empty_shop_cells(grid: Control) -> int:
	var count := 0
	for cell in grid.cells.get_children():
		if cell.item_id.is_empty(): count += 1
	return count


func review_shop_slots(panel: Control) -> void:
	var stock: Array = hud._server_inventory.duplicate(true)
	var capacity: int = requests.inventory.max_slots
	requests.inventory.max_slots = 4
	hud._server_inventory = [{"id": "potion_hp_small", "qty": 8}]
	hud._shop_buy_cart.clear()
	hud._shop_panel_logic._on_shop_tab("buy")
	await settle()
	var catalog = panel.find_child("BuyCatalog", true, false)
	var cart = panel.find_child("BuyCart", true, false)
	expect(catalog.cells.get_child_count() == 1, "shop shows one catalog cell per listed product without padding")
	expect(cart.cells.get_child_count() == 3 and empty_shop_cells(cart) == 3, "empty shopping basket shows exactly three free bag slots")
	hud._shop_buy_cart = [{"item_id": "potion_hp_small", "qty": 3, "unit_price": 20}]
	hud._fill_shop_panel()
	expect(empty_shop_cells(cart) == 3 and cart.items[0].hint.contains("叠入"), "stacking into owned items does not consume an empty slot")
	hud._shop_buy_cart.append({"item_id": "potion_mp_small", "qty": 2, "unit_price": 30})
	hud._fill_shop_panel()
	expect(empty_shop_cells(cart) == 2 and cart.items[1].hint.contains("占用 1"), "new item in basket reserves one free slot")
	await click_grid(cart, "potion_mp_small")
	panel.find_child("BuyCartQuantity", true, false).value = 2
	await click(panel.find_child("BuyCartAction", true, false))
	expect(empty_shop_cells(cart) == 3, "removing basket item restores its reserved slot")
	expect(hud._server_inventory == [{"id": "potion_hp_small", "qty": 8}], "basket capacity forecast cannot mutate actual bag")
	hud._server_inventory = [{"id": "potion_hp_small", "qty": 8}, {"id": "wooden_sword", "qty": 1}, {"id": "leather_vest", "qty": 1}, {"id": "bait_worm", "qty": 2}]
	hud._fill_shop_panel()
	expect(empty_shop_cells(cart) == 0 and cart.items[0].hint.contains("叠入"), "full bag has no phantom empty cells but still permits existing stack preview")
	hud._shop_buy_cart.append({"item_id": "potion_mp_small", "qty": 2, "unit_price": 30})
	hud._fill_shop_panel()
	expect(empty_shop_cells(cart) == 0 and cart.items[1].hint.contains("空间不足"), "full bag reports unavailable space for a new item")
	hud._server_inventory.pop_back()
	hud._fill_shop_panel()
	expect(empty_shop_cells(cart) == 0 and cart.items[1].hint.contains("占用 1"), "live bag changes recalculate reserved capacity")
	hud._shop_listings = []
	hud._fill_shop_panel()
	expect(catalog.cells.get_child_count() == 0, "empty shop does not fabricate product slots")
	requests.inventory.max_slots = capacity
	hud._server_inventory = stock
	hud._shop_buy_cart.clear()
	hud.show_shop("grid_review", "杂货商", [{"item_id": "potion_hp_small", "name": "小型生命药水", "buy_price": 20}], 12840)


func review_grid_refresh() -> void:
	var stock: Array = [{"id": "potion_hp_small", "qty": 8}, {"id": "wooden_sword", "qty": 1, "locked": true}, {"id": "potion_mp_small", "qty": 2, "bound": true}]
	var p: Control = await show_only("mail")
	await click(button_named(p, "写信"))
	hud._inv_qty_known = false
	hud.apply_inventory_snapshot(stock, 1000)
	await settle()
	var picker = hud._mail_item_id_input
	expect(picker.items.size() == 1, "mail excludes locked and bound inventory cells")
	await click_grid(picker, "potion_hp_small")
	hud._mail_item_qty_spin.value = 7
	hud._mail_body_input.text = "保留正文"
	hud._mail_body_input.text_changed.emit()
	stock[0].qty = 2
	hud._inv_qty_known = false
	hud.apply_inventory_snapshot(stock, 1000)
	await settle()
	expect(picker.selected_key == "potion_hp_small" and hud._mail_item_qty_spin.value == 2, "live bag update preserves selection and clamps attachment quantity")
	expect(hud._mail_body_input.text == "保留正文", "live item refresh preserves mail draft")
	var cell = picker.cells.get_child(0)
	var badge: Label = cell.find_child("Qty", true, false)
	expect(badge.visible and badge.text == "2" and cell.get_global_rect().grow(1).encloses(badge.get_global_rect()), "quantity badge is readable and contained in item cell")
	picker.select_key("")
	cell.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	Input.parse_input_event(key)
	await settle()
	key.pressed = false
	Input.parse_input_event(key)
	expect(picker.selected_key == "potion_hp_small", "keyboard activation selects the focused item cell")
	var quantity_before_filter: float = hud._mail_item_qty_spin.value
	# Text input uses the real focused control; filtering never changes the action target.
	await click(picker.search)
	for character in "potion":
		var typed := InputEventKey.new()
		typed.unicode = character.unicode_at(0)
		typed.pressed = true
		Input.parse_input_event(typed)
	await settle()
	expect(picker.search.text == "potion" and picker._shown_count == 1, "typing into item search filters visible cells")
	picker.category.select(2)
	picker.category.item_selected.emit(2)
	expect(picker._shown_count == 0 and picker.detail.text.contains("没有匹配"), "category filter gives an explicit empty result")
	expect(picker.selected_key == "potion_hp_small" and hud._mail_item_qty_spin.value == quantity_before_filter, "filtering preserves selected attachment and quantity")
	picker.category.select(1)
	picker.category.item_selected.emit(1)
	expect(picker._shown_count == 1, "consumable filter restores matching stack")
	picker.set_items(picker.items.duplicate(true))
	expect(picker.search.text == "potion" and picker.category.selected == 1, "inventory refresh preserves text and category filters")
	# Click the native clear affordance.
	await pointer(picker.search.get_global_rect().end - Vector2(12, picker.search.size.y / 2), true)
	await pointer(picker.search.get_global_rect().end - Vector2(12, picker.search.size.y / 2), false)
	expect(picker.search.text.is_empty(), "search clear button responds to pointer")
	picker.category.select(0)
	picker.category.item_selected.emit(0)
	hud._inv_qty_known = false
	hud.apply_inventory_snapshot([], 1000)
	await settle()
	expect(picker.selected_item().is_empty() and not hud._mail_item_qty_spin.editable, "removed inventory item clears selection and disables quantity")
	# More than eight stacks: every grid scrolls to the final item and retains that place.
	stock.clear()
	for i in 60: stock.append({"id": "review_item_%d" % i, "qty": i + 1, "name": "测试物品 %d" % i})
	p = await show_only("warehouse")
	hud._inv_qty_known = false
	hud.apply_inventory_snapshot(stock, 1000)
	await settle()
	var grid = p.find_child("WarehouseBag", true, false)
	await click_grid(grid, "review_item_59")
	grid = p.find_child("WarehouseBag", true, false)
	expect(grid.items.size() == 60 and grid.selected_key == "review_item_59", "warehouse exposes all sixty stacks")
	expect(grid.scroll.scroll_vertical > 0, "warehouse selection rebuild keeps scroll position")
	await shot("warehouse_long_grid", p)
	p = await show_only("trade")
	hud._trade_state = {"active": true, "partner_name": "测试商人", "my_items": [], "their_items": [], "my_ready": false, "their_ready": false}
	hud._refresh_trade_panel()
	await settle()
	grid = p.find_child("TradeBag", true, false)
	await click_grid(grid, "review_item_59")
	grid = p.find_child("TradeBag", true, false)
	expect(grid.items.size() == 60 and grid.scroll.scroll_vertical > 0, "trade exposes later stacks without eight-item cutoff or scroll reset")
	await shot("trade_long_grid", p)
	hud._trade_state.my_ready = true
	hud._refresh_trade_panel()
	await settle()
	expect(p.find_child("TradeBag", true, false) == null and button_named(p, "放入报价") == null, "locked trade cannot change item offer")
	# Structured rewards use the same cells; legacy prose stays a description.
	hud._server_quests[0]["reward"] = {"exp": 10, "items": [{"id": "potion_hp_small", "qty": 3}]}
	hud._selected_quest_id = "q1"
	hud._ensure_quest_drawer()
	hud._refresh_quest_drawer_content()
	expect(hud._quest_drawer.find_child("RewardItems", true, false) != null, "quest item rewards use shared grid")
	for panel in panels.values(): panel.hide()
