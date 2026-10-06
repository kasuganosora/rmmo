extends SceneTree
## Capture each L2 window alone for visual QA; writes PNGs then quits.
var _input_failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Preview must not overwrite the player's saved window positions or settings.
	var settings := root.get_node("GameSettings")
	settings.persist_enabled = false
	settings.window_layouts = {}
	settings.ui_scale = 1.0
	root.content_scale_size = Vector2i.ZERO
	var viewport_size := Vector2i(1280, 800)
	for argument in OS.get_cmdline_user_args():
		if argument == "--compact": viewport_size = Vector2i(900, 700)
	DisplayServer.window_set_size(viewport_size)
	root.size = viewport_size
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.24, 0.14, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	var hud: Control = packed.instantiate()
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	hud.bind_character({"name": "艾琳", "class_id": "warrior", "level": 12})
	hud._server_gold = 12840
	hud._server_combat = {"level": 12, "atk": 30, "def": 22, "exp": 3400, "exp_to_next": 8000}
	hud._server_equip_bonuses = {"p_atk": 3, "p_def": 2}
	hud._server_inventory = [
		{"id": "wooden_sword", "qty": 1},
		{"id": "leather_vest", "qty": 1},
		{"id": "potion_hp_small", "qty": 8},
	]
	hud._server_quests = [
		{"id": "q1", "title": "新手的第一步", "status": "in_progress", "desc": "在训练场击败假人，向教官复命。", "objectives": [{"text": "训练假人", "cur": 1, "max": 3}], "rewards": "金币 100"},
	]
	hud._server_skills = [
		{"id": "power_strike", "name": "强力斩击", "category": "active"},
		{"id": "weapon_mastery", "name": "武器精通", "category": "passive"},
	]
	var label := "current"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=").get_file()
	var out_dir := preload("res://scripts/asset/art_paths.gd").review_path("l2_ui/" + label)
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Hide chrome that clutters isolated shots.
	for id in hud._windows.keys():
		(hud._windows[id] as Control).visible = false
	if hud._npc_chat:
		hud._npc_chat.visible = false
	if hud._shop_panel:
		hud._shop_panel.visible = false
	if hud._trade_panel:
		hud._trade_panel.visible = false
	if hud._party_panel:
		hud._party_panel.visible = false
	if hud._loot_panel:
		hud._loot_panel.visible = false

	await _shot_window(hud, "character", Vector2(40, 40), out_dir)
	await _shot_window(hud, "inventory", Vector2(40, 20), out_dir)
	await _shot_window(hud, "skills", Vector2(40, 40), out_dir)
	hud._toggle_window("quest")
	hud._on_quest_row_selected("q1")
	await process_frame
	var qp: PanelContainer = hud._windows["quest"]
	qp.global_position = Vector2(40, 40)
	if hud._quest_drawer:
		hud._place_quest_drawer()
	await _save(out_dir + "/quest.png")
	qp.global_position = Vector2(viewport_size.x - qp.size.x - 8, 40)
	hud._place_quest_drawer()
	await _save(out_dir + "/quest_right_edge.png")
	qp.visible = false
	if hud._quest_drawer:
		hud._quest_drawer.visible = false

	await _shot_window(hud, "map", Vector2(40, 20), out_dir)
	await _shot_window(hud, "system", Vector2(40, 20), out_dir)
	var sysp: PanelContainer = hud._windows["system"]
	sysp.visible = true
	hud._on_system_tab("audio")
	await process_frame
	sysp.global_position = Vector2(40, 20)
	await _save(out_dir + "/system_audio.png")
	hud._on_system_tab("game")
	await process_frame
	sysp.global_position = Vector2(40, 20)
	await _save(out_dir + "/system_game.png")
	hud._on_system_tab("system")
	await process_frame
	sysp.global_position = Vector2(40, 20)
	await _save(out_dir + "/system_nav.png")
	sysp.visible = false
	hud._on_system_tab("video")
	hud.show_death_dialog()
	await _save(out_dir + "/death.png")
	hud.hide_death_dialog()
	hud._show_inspect("p1", "测试玩家")
	if hud._inspect_panel:
		hud._inspect_panel.global_position = Vector2(40, 40)
	await _save(out_dir + "/inspect.png")
	if hud._inspect_panel:
		hud._inspect_panel.visible = false
	hud.apply_quest_snapshot([
		{"id": "q1", "title": "新手的第一步", "status": "in_progress", "objectives": [{"text": "训练假人", "cur": 1, "max": 3}]},
	])
	if hud._quest_tracker:
		hud._quest_tracker.global_position = Vector2(40, 40)
		hud._quest_tracker.visible = true
	await _save(out_dir + "/quest_tracker.png")
	hud._toggle_menu_popup()
	await process_frame
	await process_frame
	await _save(out_dir + "/menu_popup.png")
	hud._close_menu_popup()
	if hud._quest_tracker: hud._quest_tracker.visible = false

	hud.show_npc_dialogue("训练教官", "欢迎来到训练场。击败假人，再来向我复命。这里的文字不应压到金纹边框上。", ["接受任务", "打听村庄", "离开"])
	hud._npc_chat.global_position = Vector2(40, 40)
	await _save(out_dir + "/npc.png")
	hud._npc_chat.visible = false

	hud.show_shop("vendor", "杂货商", [
		{"item_id": "potion_hp_small", "name": "红药水", "buy_price": 20},
		{"item_id": "potion_mp_small", "name": "蓝药水", "buy_price": 25},
	], 12840)
	hud._shop_buy_cart = [{"item_id": "potion_hp_small", "qty": 2, "unit_price": 20, "name": "红药水"}]
	hud._fill_shop_panel()
	hud._shop_panel.global_position = Vector2(20, 20)
	await _save(out_dir + "/shop.png")
	hud._shop_panel.visible = false

	hud._trade_state = {
		"active": true, "partner_name": "测试商人",
		"my_items": [{"item_id": "potion_hp_small", "name": "红药水", "qty": 2}],
		"their_items": [{"item_id": "potion_mp_small", "name": "蓝药水", "qty": 1}],
		"my_gold": 10, "their_gold": 15, "my_ready": false, "their_ready": true,
	}
	hud._trade_panel.visible = true
	hud._refresh_trade_panel()
	hud._trade_panel.size = Vector2(520, 400)
	hud._trade_panel.global_position = Vector2(40, 40)
	await _save(out_dir + "/trade.png")
	hud._trade_panel.visible = false

	hud.show_loot("s1", "npc1", [{"item_id": "potion_hp_small", "name": "红药水", "qty": 3}])
	hud._loot_panel.global_position = Vector2(40, 40)
	await _save(out_dir + "/loot.png")
	hud._loot_panel.visible = false

	hud._toggle_party_panel()
	if hud._party_panel:
		hud._party_panel.global_position = Vector2(40, 40)
	await _save(out_dir + "/party.png")
	if hud._party_panel:
		hud._party_panel.visible = false

	hud._ensure_drop_qty_dialog()
	hud._drop_qty_label.text = "丢掉：红药水（最多 8）"
	hud._drop_qty_panel.visible = true
	hud._drop_qty_panel.position = Vector2(80, 80)
	await _save(out_dir + "/drop_qty.png")
	hud._drop_qty_panel.visible = false
	# A single overview shows the shared chrome at its actual in-game scale.
	hud._toggle_window("inventory")
	hud._toggle_window("system")
	await process_frame
	(hud._windows["inventory"] as Control).global_position = Vector2(230, 48)
	(hud._windows["system"] as Control).global_position = Vector2(mini(620, viewport_size.x - 448), 48)
	hud._on_system_tab("video")
	await _save(out_dir + "/overview.png")
	print("inspect dir ", out_dir)
	quit(0 if _input_failures == 0 else 1)


func _shot_window(hud, id: String, pos: Vector2, out_dir: String) -> void:
	for other in hud._windows.keys():
		(hud._windows[other] as Control).visible = false
	hud._toggle_window(id)
	await process_frame
	var p: PanelContainer = hud._windows[id]
	p.global_position = pos
	await process_frame
	await process_frame
	await _save("%s/%s.png" % [out_dir, id])
	if OS.get_cmdline_user_args().has("--interactions"):
		await _check_window_input(p, id)
	p.visible = false


func _save(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("saved ", path, " err=", err)


func _pointer(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	Input.parse_input_event(event)
	await process_frame


func _check_window_input(panel: PanelContainer, id: String) -> void:
	var title := panel.find_child("TitleBar", true, false) as PanelContainer
	if title == null: return
	var start := panel.global_position
	var point := title.get_global_rect().position + Vector2(40, 12)
	await _pointer(point, true)
	var motion := InputEventMouseMotion.new()
	motion.position = point + Vector2(32, 24)
	motion.global_position = motion.position
	motion.relative = Vector2(32, 24)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await process_frame
	await _pointer(motion.position, false)
	var dragged := panel.global_position.distance_to(start) > 10.0
	print("%s title drag: %s" % [id, "PASS" if dragged else "FAIL"])
	if not dragged: _input_failures += 1
	var head := title.get_child(0)
	var close := head.get_child(head.get_child_count() - 1) as Button
	await _pointer(close.get_global_rect().get_center(), true)
	await _pointer(close.get_global_rect().get_center(), false)
	print("%s close hit target: %s" % [id, "PASS" if not panel.visible else "FAIL"])
	if panel.visible: _input_failures += 1
