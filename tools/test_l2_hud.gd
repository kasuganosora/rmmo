extends SceneTree
## Headless: L2 chrome kit loads; character paperdoll + quest tabs restyle.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var L2Style = load("res://scripts/ui/l2_style.gd")
	failed += _expect(L2Style != null, "l2_style loads")
	if L2Style == null:
		_finish(failed)
		return
	var names := [
		"panel.png", "title_bar.png", "close.png", "close_hover.png",
		"slot_empty.png", "slot_filled.png", "tab_idle.png", "tab_on.png",
		"row_idle.png", "row_on.png", "paperdoll.png",
		"icon_menu.png", "icon_character.png", "icon_inventory.png",
		"icon_skills.png", "icon_quest.png", "icon_party.png",
		"icon_map.png", "icon_system.png",
	]
	var am: Node = root.get_node_or_null("AssetManager")
	failed += _expect(am != null, "AssetManager autoload")
	for n in names:
		var ref := "content://ui/l2/%s" % n
		failed += _expect(am != null and bool(am.has(ref)), "pack has %s" % n)
		failed += _expect(L2Style.tex(n) != null, "tex %s" % n)
	failed += _expect(L2Style.has_kit(), "has_kit")
	failed += _expect(L2Style.panel_box() != null, "panel_box")
	failed += _expect(L2Style.slot_box(false) is StyleBoxTexture, "slot empty texture")
	failed += _expect(L2Style.slot_box(true) is StyleBoxTexture, "slot filled texture")
	failed += _expect(L2Style.tab_box(true) is StyleBoxTexture, "tab on texture")
	failed += _expect(L2Style.row_box(false) is StyleBoxTexture, "row idle texture")

	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "game_hud.tscn loads")
	if packed == null:
		_finish(failed)
		return
	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	failed += _expect(hud.has_method("_fill_character"), "hud has _fill_character")
	failed += _expect(hud._windows.has("character"), "character window")
	failed += _expect(hud._windows.has("quest"), "quest window")
	var char_p: PanelContainer = hud._windows["character"]
	var quest_p: PanelContainer = hud._windows["quest"]
	failed += _expect(char_p.get_meta("base_size", Vector2.ZERO).x >= 520.0, "character window wider")
	failed += _expect(quest_p.get_node_or_null("MarginContainer") != null or char_p.get_child_count() > 0, "window has children")
	var title_bar := char_p.find_child("TitleBar", true, false)
	failed += _expect(title_bar != null, "character TitleBar")
	hud._character = {"name": "测试", "class_id": "warrior", "level": 5}
	hud._server_quests = [
		{"id": "q1", "title": "新手的第一步", "status": "in_progress", "desc": "打假人", "objectives": [{"text": "训练假人", "cur": 1, "max": 3}], "rewards": "Adena 100"},
		{"id": "q2", "title": "旧日委托", "status": "completed", "desc": "完成", "objectives": [], "rewards": ""},
	]
	hud._fill_window("character")
	await process_frame
	var canvas := char_p.find_child("DollCanvas", true, false) as Control
	failed += _expect(canvas != null, "DollCanvas")
	if canvas != null:
		var slots := 0
		var sil := canvas.get_node_or_null("Silhouette")
		failed += _expect(sil != null, "paperdoll silhouette")
		for c in canvas.get_children():
			if c is PanelContainer:
				slots += 1
		failed += _expect(slots == 12, "12 paperdoll slots got %d" % slots)
	hud._fill_window("quest")
	await process_frame
	var tabs: HBoxContainer = quest_p.get_meta("quest_tabs", null) if quest_p.has_meta("quest_tabs") else null
	failed += _expect(tabs != null and tabs.get_child_count() == 2, "quest tabs")
	if tabs != null and tabs.get_child_count() > 0:
		var t0 := tabs.get_child(0) as Button
		failed += _expect(t0 != null and t0.get_theme_stylebox("normal") is StyleBoxTexture, "tab uses texture style")
	var body: VBoxContainer = quest_p.get_meta("body")
	failed += _expect(body != null and body.get_child_count() >= 1, "quest rows")
	if body != null and body.get_child_count() > 0:
		var row := body.get_child(0) as Button
		failed += _expect(row != null and row.get_theme_stylebox("normal") is StyleBoxTexture, "quest row texture")
	hud._selected_quest_id = "q1"
	hud._ensure_quest_drawer()
	hud._refresh_quest_drawer_content()
	failed += _expect(hud._quest_drawer != null, "quest drawer")
	if hud._quest_drawer != null:
		failed += _expect(hud._quest_drawer.find_child("TitleBar", true, false) != null, "drawer TitleBar")

	hud._toggle_window("inventory")
	await process_frame
	var inv_p: PanelContainer = hud._windows["inventory"]
	failed += _expect(inv_p.find_child("TitleBar", true, false) != null, "inventory TitleBar")
	var inv_grid := inv_p.find_child("InvGrid", true, false)
	failed += _expect(inv_grid != null, "inventory grid")

	hud.show_npc_dialogue("训练教官", "欢迎来到训练场。", ["接受任务", "离开"])
	await process_frame
	failed += _expect(hud._npc_chat != null and hud._npc_chat.visible, "npc chat visible")
	failed += _expect(hud._npc_chat.find_child("TitleBar", true, false) != null, "npc TitleBar")
	failed += _expect(hud._npc_chat_options.get_child_count() == 2, "npc two options")

	hud.show_shop("vendor", "杂货商", [
		{"item_id": "potion_hp_small", "name": "红药水", "buy_price": 20},
		{"item_id": "potion_mp_small", "name": "蓝药水", "buy_price": 25},
	], 12840)
	await process_frame
	failed += _expect(hud._shop_panel != null and hud._shop_panel.visible, "shop visible")
	failed += _expect(hud._shop_panel.find_child("TitleBar", true, false) != null, "shop TitleBar")
	failed += _expect(hud._shop_panel.find_child("BuyPage", true, false) != null, "shop BuyPage")
	failed += _expect(hud._shop_panel.find_child("SellPage", true, false) != null, "shop SellPage")
	var shop_tabs: HBoxContainer = hud._shop_panel.get_meta("shop_tabs", null)
	failed += _expect(shop_tabs != null and shop_tabs.get_child_count() == 3, "shop L2 tabs")
	var buy_cat := hud._shop_panel.find_child("BuyCatalog", true, false) as VBoxContainer
	failed += _expect(buy_cat != null and buy_cat.get_child_count() >= 1, "shop catalog rows")

	hud._trade_state = {
		"active": true,
		"partner_name": "测试商人",
		"my_items": [{"item_id": "potion_hp_small", "name": "红药水", "qty": 2}],
		"their_items": [{"item_id": "potion_mp_small", "name": "蓝药水", "qty": 1}],
		"my_gold": 10,
		"their_gold": 15,
		"my_ready": false,
		"their_ready": false,
	}
	hud._trade_panel.visible = true
	hud._refresh_trade_panel()
	await process_frame
	failed += _expect(hud._trade_panel.find_child("TitleBar", true, false) != null, "trade TitleBar")
	failed += _expect(hud._trade_body.get_child_count() >= 2, "trade body columns")
	hud._toggle_window("skills")
	await process_frame
	var sk: PanelContainer = hud._windows["skills"]
	failed += _expect(sk.find_child("TitleBar", true, false) != null, "skills TitleBar")
	hud._toggle_window("system")
	await process_frame
	var sys: PanelContainer = hud._windows["system"]
	failed += _expect(sys.find_child("TitleBar", true, false) != null, "system TitleBar")
	failed += _expect(hud.menu_row.get_child_count() == 1, "menu collapsed")
	var sys_tabs: HBoxContainer = sys.get_meta("system_tabs", null)
	failed += _expect(sys_tabs != null and sys_tabs.get_child_count() == 5, "system 5 tabs")
	hud._toggle_window("map")
	await process_frame
	var mp: PanelContainer = hud._windows["map"]
	failed += _expect(mp.find_child("TitleBar", true, false) != null, "map TitleBar")
	hud.show_loot("s1", "n1", [{"item_id": "potion_hp_small", "name": "红药水", "qty": 1}])
	failed += _expect(hud._loot_panel.find_child("TitleBar", true, false) != null, "loot TitleBar")
	failed += _expect(hud._party_panel.find_child("TitleBar", true, false) != null, "party TitleBar")
	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("test_l2_hud: ALL PASS")
		quit(0)
	else:
		print("test_l2_hud: FAIL count=", failed)
		quit(1)
