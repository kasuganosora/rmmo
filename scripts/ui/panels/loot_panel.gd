extends RefCounted
## UI panel: loot window and roll.

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

static func show_loot(ctrl, session_id: String, npc_id: String, items: Array) -> void:
	ctrl._loot_session_id = session_id.strip_edges()
	ctrl._loot_npc_id = npc_id.strip_edges()
	ctrl._loot_items = items.duplicate(true) if items != null else []
	ctrl._ensure_loot_panel()
	ctrl._fill_loot_panel()
	if ctrl._loot_panel != null:
		ctrl._loot_panel.visible = true
		ctrl._loot_panel.move_to_front()

static func refresh_loot(ctrl, session_id: String, items: Array) -> void:
	if session_id.strip_edges() != "" and ctrl._loot_session_id != "" and session_id != ctrl._loot_session_id:
		# Stale update from a previous session — ignore.
		return
	if session_id.strip_edges() != "":
		ctrl._loot_session_id = session_id.strip_edges()
	ctrl._loot_items = items.duplicate(true) if items != null else []
	if ctrl._loot_items.is_empty():
		ctrl.hide_loot()
		return
	ctrl._ensure_loot_panel()
	ctrl._fill_loot_panel()
	if ctrl._loot_panel != null:
		ctrl._loot_panel.visible = true

static func hide_loot(ctrl) -> void:
	if ctrl._loot_panel != null:
		ctrl._loot_panel.visible = false
	ctrl._loot_session_id = ""
	ctrl._loot_npc_id = ""
	ctrl._loot_items.clear()

static func _ensure_loot_panel(ctrl) -> void:
	if ctrl._loot_panel != null and is_instance_valid(ctrl._loot_panel):
		if bool(ctrl._loot_panel.get_meta("loot_v2", false)):
			return
		ctrl._loot_panel.queue_free()
		ctrl._loot_panel = null
	var panel = PanelContainer.new()
	panel.set_script(HudDrag)
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
	title_l.text = "掉落确认"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_l)
	var close_btn = Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(ctrl._on_loot_close_pressed)
	head.add_child(close_btn)
	var hint = Label.new()
	hint.name = "LootHint"
	hint.text = "选择拾取或关闭（关闭将丢弃剩余）"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", L2Style.COL_MUTED)
	vbox.add_child(hint)
	var scroll = ScrollContainer.new()
	scroll.name = "LootScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	vbox.add_child(scroll)
	var list = VBoxContainer.new()
	list.name = "LootList"
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var bottom = HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)
	var take_all = Button.new()
	take_all.text = "全部拾取"
	take_all.focus_mode = Control.FOCUS_NONE
	take_all.pressed.connect(ctrl._on_loot_take_all_pressed)
	L2Style.style_action_button(take_all)
	bottom.add_child(take_all)
	var close2 = Button.new()
	close2.text = "关闭"
	close2.focus_mode = Control.FOCUS_NONE
	close2.pressed.connect(ctrl._on_loot_close_pressed)
	L2Style.style_action_button(close2)
	bottom.add_child(close2)
	ctrl._loot_panel = panel
	ctrl._apply_l2_chrome(panel)
	ctrl.call_deferred("_place_loot_panel")

static func _place_loot_panel(ctrl) -> void:
	if ctrl._loot_panel == null or not is_instance_valid(ctrl._loot_panel):
		return
	var vp = ctrl.get_viewport_rect().size
	var sz = Vector2(340, 300)
	ctrl._loot_panel.size = sz
	ctrl._loot_panel.global_position = Vector2(
		maxi(8, int((vp.x - sz.x) * 0.5)),
		maxi(8, int((vp.y - sz.y) * 0.35))
	)

static func _fill_loot_panel(ctrl) -> void:
	if ctrl._loot_panel == null or not is_instance_valid(ctrl._loot_panel):
		return
	var list = ctrl._loot_panel.find_child("LootList", true, false) as VBoxContainer
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	if ctrl._loot_items.is_empty():
		var empty = Label.new()
		empty.text = "（无掉落）"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", L2Style.COL_MUTED)
		list.add_child(empty)
		return
	for it_v in ctrl._loot_items:
		if typeof(it_v) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_v
		var iid = str(it.get("item_id", it.get("id", ""))).strip_edges()
		var qty: int = int(it.get("qty", 0))
		if iid.is_empty() or qty <= 0:
			continue
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		var dname = str(it.get("name", "")).strip_edges()
		if dname.is_empty():
			dname = ctrl._item_label(iid) if ctrl.has_method("_item_label") else iid
		var iix = int(it.get("icon_index", ctrl._item_icon_index(iid)))
		var iref = str(it.get("icon_ref", "")).strip_edges()
		if iref.is_empty():
			var ic = str(it.get("icon", "")).strip_edges()
			if not ic.is_empty():
				iref = ic if ic.begins_with("content:") else ("content://icon/%s" % ic)
			else:
				iref = ctrl._item_icon_ref(iid)
		var icon_tex: Texture2D = null
		var am: Node = ctrl.get_node_or_null("/root/AssetManager")
		if am != null and am.has_method("resolve_slot_icon_texture"):
			icon_tex = am.resolve_slot_icon_texture(iix, iref)
		if icon_tex != null:
			var tr = TextureRect.new()
			tr.texture = icon_tex
			tr.custom_minimum_size = Vector2(22, 22)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tr)
		else:
			var letter = Label.new()
			letter.text = dname.substr(0, 1) if dname.length() > 0 else "?"
			letter.custom_minimum_size = Vector2(22, 22)
			letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			letter.add_theme_font_size_override("font_size", 13)
			letter.add_theme_color_override("font_color", Color(0.95, 0.9, 0.55))
			row.add_child(letter)
		var lab = Label.new()
		lab.text = "%s ×%d" % [dname, qty]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.add_theme_font_size_override("font_size", 13)
		lab.add_theme_color_override("font_color", L2Style.COL_TEXT)
		var loot_tip = ctrl._equip_compare_tip(iid, "%s ×%d" % [ctrl._item_rarity_name_line(iid, dname), qty])
		lab.tooltip_text = loot_tip
		row.tooltip_text = loot_tip
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(lab)
		var take_btn = Button.new()
		take_btn.text = "拾取"
		take_btn.focus_mode = Control.FOCUS_NONE
		take_btn.custom_minimum_size = Vector2(56, 26)
		var captured = iid
		take_btn.pressed.connect(func(): ctrl._on_loot_take_pressed(captured))
		L2Style.style_compact_button(take_btn)
		row.add_child(take_btn)

static func _on_loot_take_pressed(ctrl, item_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_loot_take"):
		ctrl._world_combat.request_loot_take(item_id, -1)
	else:
		ctrl.append_system("无法拾取。")

static func _on_loot_take_all_pressed(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_loot_take_all"):
		ctrl._world_combat.request_loot_take_all()
	else:
		ctrl.append_system("无法全部拾取。")

static func _on_loot_close_pressed(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_loot_close"):
		ctrl._world_combat.request_loot_close()
	else:
		ctrl.hide_loot()

static func show_loot_roll(ctrl, action: Dictionary) -> void:
	ctrl.hide_loot_roll({})
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
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for pair in [["需求", "need"], ["贪婪", "greed"], ["放弃", "pass"]]:
		var btn = Button.new()
		btn.text = str(pair[0])
		btn.focus_mode = Control.FOCUS_NONE
		var choice = str(pair[1])
		btn.pressed.connect(func():
			ctrl._submit_loot_roll(choice)
		)
		row.add_child(btn)
	ctrl.add_child(ctrl._loot_roll_panel)
	ctrl._loot_roll_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	ctrl._loot_roll_panel.position = Vector2(-140, 72)
	ctrl._loot_roll_panel.move_to_front()

static func apply_loot_roll_choice(ctrl, action: Dictionary) -> void:
	# Optional: could grey out after self voted; keep panel until resolve.
	pass

static func hide_loot_roll(ctrl, _action: Dictionary = {}) -> void:
	if ctrl._loot_roll_panel != null and is_instance_valid(ctrl._loot_roll_panel):
		ctrl._loot_roll_panel.queue_free()
	ctrl._loot_roll_panel = null
	ctrl._loot_roll_id = ""
	ctrl._loot_roll_label = null

static func _submit_loot_roll(ctrl, choice: String) -> void:
	var rid = ctrl._loot_roll_id
	ctrl.hide_loot_roll({})
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_loot_roll"):
		ctrl._world_combat.request_loot_roll(choice, rid)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_loot_roll"):
		var result: Dictionary = srv.try_loot_roll(choice, rid)
		if typeof(result.get("actions", null)) == TYPE_ARRAY and ctrl._world_combat != null and ctrl._world_combat.has_method("_apply_server_actions"):
			ctrl._world_combat._apply_server_actions(result["actions"])

static func _on_party_set_loot_mode(ctrl, mode: String) -> void:
	mode = str(mode).strip_edges().to_lower()
	if mode.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_set_loot_mode"):
		ctrl._world_combat.request_party_set_loot_mode(mode)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_set_loot_mode"):
		ctrl._apply_party_result_locally(srv.try_party_set_loot_mode(mode))

