extends RefCounted
## UI panel: loot window and roll.

var ctrl
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const GameWindow = preload("res://scripts/ui/game_window.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

func show_loot(session_id: String, npc_id: String, items: Array) -> void:
	ctrl._loot_session_id = session_id.strip_edges()
	ctrl._loot_npc_id = npc_id.strip_edges()
	ctrl._loot_items = items.duplicate(true) if items != null else []
	_ensure_loot_panel()
	_fill_loot_panel()
	if ctrl._loot_panel != null:
		ctrl._loot_panel.visible = true
		ctrl._loot_panel.move_to_front()



func refresh_loot(session_id: String, items: Array) -> void:
	if session_id.strip_edges() != "" and ctrl._loot_session_id != "" and session_id != ctrl._loot_session_id:
		# Stale update from a previous session — ignore.
		return
	if session_id.strip_edges() != "":
		ctrl._loot_session_id = session_id.strip_edges()
	ctrl._loot_items = items.duplicate(true) if items != null else []
	if ctrl._loot_items.is_empty():
		hide_loot()
		return
	_ensure_loot_panel()
	_fill_loot_panel()
	if ctrl._loot_panel != null:
		ctrl._loot_panel.visible = true



func hide_loot() -> void:
	if ctrl._loot_panel != null:
		ctrl._loot_panel.visible = false
	ctrl._loot_session_id = ""
	ctrl._loot_npc_id = ""
	ctrl._loot_items.clear()



func _ensure_loot_panel() -> void:
	if ctrl._loot_panel != null and is_instance_valid(ctrl._loot_panel):
		if bool(ctrl._loot_panel.get_meta("loot_v2", false)):
			return
		ctrl._loot_panel.queue_free()
		ctrl._loot_panel = null
	var panel = PanelContainer.new()
	panel.set_script(GameWindow)
	panel.name = "LootWindow"
	panel.screen_margin = 4.0
	panel.min_size = Vector2(300, 240)
	panel.default_size = Vector2(340, 300)
	panel.initial_dock = "none"
	panel.drag_anywhere = true
	panel.visible = false
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(300, 240)
	panel.set_meta("fixed_size", true)
	panel.set_meta("base_size", Vector2(340, 300))
	panel.set_meta("loot_v2", true)
	ctrl.add_child(panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(marg)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marg.add_child(vbox)
	var head = HBoxContainer.new()
	vbox.add_child(head)
	var title_l = Label.new()
	title_l.name = "LootTitle"
	title_l.text = "战利品"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_l)
	var close_btn = Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_on_loot_close_pressed)
	head.add_child(close_btn)
	var hint = Label.new()
	hint.name = "LootHint"
	hint.text = "拾取战利品；关闭将放弃剩余物品。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", L2Style.COL_MUTED)
	vbox.add_child(hint)
	var grid = ItemGrid.create(ctrl, vbox, "LootGrid", 150)
	var selected_take := Button.new()
	selected_take.name = "TakeSelectedLoot"
	selected_take.text = "拾取所选"
	selected_take.disabled = true
	grid.item_selected.connect(func(item): selected_take.disabled = item.is_empty())
	selected_take.pressed.connect(func(): _on_loot_take_pressed(str(grid.selected_item().get("item_id", ""))))
	var bottom = HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)
	bottom.add_child(selected_take)
	var take_all = Button.new()
	take_all.name = "TakeAllLoot"
	take_all.text = "全部拾取"
	take_all.focus_mode = Control.FOCUS_NONE
	take_all.pressed.connect(_on_loot_take_all_pressed)
	L2Style.style_action_button(take_all)
	bottom.add_child(take_all)
	var close2 = Button.new()
	close2.text = "放弃剩余"
	close2.focus_mode = Control.FOCUS_NONE
	close2.pressed.connect(_on_loot_close_pressed)
	L2Style.style_action_button(close2)
	bottom.add_child(close2)
	ctrl._loot_panel = panel
	ctrl._apply_l2_chrome(panel)
	ctrl.call_deferred("_place_loot_panel")



func _place_loot_panel() -> void:
	if ctrl._loot_panel == null or not is_instance_valid(ctrl._loot_panel):
		return
	var vp = ctrl.get_viewport_rect().size
	var sz = Vector2(340, 300)
	ctrl._loot_panel.size = sz
	ctrl._window_manager_logic.place_at(ctrl._loot_panel, Vector2(maxf(8, (vp.x - sz.x) * 0.5), maxf(8, (vp.y - sz.y) * 0.35)))



func _fill_loot_panel() -> void:
	if ctrl._loot_panel == null or not is_instance_valid(ctrl._loot_panel):
		return
	var grid = ctrl._loot_panel.find_child("LootGrid", true, false)
	grid.set_items(ctrl._loot_items)
	ctrl._loot_panel.find_child("TakeAllLoot", true, false).disabled = ctrl._loot_items.is_empty()
	ctrl._loot_panel.find_child("TakeSelectedLoot", true, false).disabled = grid.selected_item().is_empty()



func _on_loot_take_pressed(item_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_loot_take"):
		ctrl._world_combat.request_loot_take(item_id, -1)
	else:
		ctrl.append_system("无法拾取。")



func _on_loot_take_all_pressed() -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_loot_take_all"):
		ctrl._world_combat.request_loot_take_all()
	else:
		ctrl.append_system("无法全部拾取。")



func _on_loot_close_pressed() -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_loot_close"):
		ctrl._world_combat.request_loot_close()
	else:
		hide_loot()



func show_loot_roll(action: Dictionary) -> void:
	hide_loot_roll({})
	ctrl._loot_roll_id = str(action.get("roll_id", action.get("id", ""))).strip_edges()
	var iname = str(action.get("name", action.get("item_id", "物品"))).strip_edges()
	var qty = int(action.get("qty", 1))
	ctrl._loot_roll_panel = PanelContainer.new()
	ctrl._loot_roll_panel.name = "LootRollDialog"
	ctrl._loot_roll_panel.custom_minimum_size = Vector2(280, 130)
	L2Style.apply_panel(ctrl._loot_roll_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 14)
	marg.add_theme_constant_override("margin_top", 12)
	marg.add_theme_constant_override("margin_right", 14)
	marg.add_theme_constant_override("margin_bottom", 12)
	ctrl._loot_roll_panel.add_child(marg)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	marg.add_child(col)
	ctrl._loot_roll_label = Label.new()
	var qty_s = (" ×%d" % qty) if qty > 1 else ""
	ctrl._loot_roll_label.text = "掷骰：%s%s\n需求 / 贪婪 / 放弃" % [iname, qty_s]
	ctrl._loot_roll_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctrl._loot_roll_label.add_theme_color_override("font_color", L2Style.COL_TEXT)
	col.add_child(ctrl._loot_roll_label)
	ItemGrid.display_cell(ctrl, col, action)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for pair in [["需求", "need"], ["贪婪", "greed"], ["放弃", "pass"]]:
		var btn = Button.new()
		btn.text = str(pair[0])
		btn.custom_minimum_size = Vector2(72, 28)
		btn.tooltip_text = {"need": "需要这件物品，参与需求掷骰", "greed": "有需要者优先，否则参与贪婪掷骰", "pass": "放弃这件物品"}.get(str(pair[1]), "")
		btn.focus_mode = Control.FOCUS_NONE
		var choice = str(pair[1])
		btn.pressed.connect(func():
			_submit_loot_roll(choice)
		)
		row.add_child(btn)
	ctrl.add_child(ctrl._loot_roll_panel)
	GameWindow.place_dialog.call_deferred(ctrl._loot_roll_panel, 0.2)
	ctrl._loot_roll_panel.move_to_front()



func apply_loot_roll_choice(action: Dictionary) -> void:
	# Optional: could grey out after self voted; keep panel until resolve.
	pass



func hide_loot_roll(_action: Dictionary = {}) -> void:
	if ctrl._loot_roll_panel != null and is_instance_valid(ctrl._loot_roll_panel):
		ctrl._loot_roll_panel.queue_free()
	ctrl._loot_roll_panel = null
	ctrl._loot_roll_id = ""
	ctrl._loot_roll_label = null



func _submit_loot_roll(choice: String) -> void:
	var rid = ctrl._loot_roll_id
	hide_loot_roll({})
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_loot_roll"):
		ctrl._world_combat.request_loot_roll(choice, rid)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_loot_roll"):
		var result: Dictionary = srv.try_loot_roll(choice, rid)
		if typeof(result.get("actions", null)) == TYPE_ARRAY and ctrl._world_combat != null and ctrl._world_combat.has_method("_apply_server_actions"):
			ctrl._world_combat._apply_server_actions(result["actions"])



func _on_party_set_loot_mode(mode: String) -> void:
	mode = str(mode).strip_edges().to_lower()
	if mode.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_set_loot_mode"):
		ctrl._world_combat.request_party_set_loot_mode(mode)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_set_loot_mode"):
		ctrl._apply_party_result_locally(srv.try_party_set_loot_mode(mode))


