extends RefCounted
## UI module: generic floating-window shell — build/make/place/toggle/close, layout
## save+restore, L2 chrome, grid metrics, the content dispatcher (_fill_window) and the
## system-window tab bar. Window state (_windows, _system_tab) lives on the HUD (ctrl);
## per-window content lives in the individual panel modules.

var ctrl
func _init(c):
	ctrl = c

const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const Net = preload("res://scripts/net/net.gd")


func _connect_window_layout_signals() -> void:
	for id in ctrl._windows.keys():
		var p: Control = ctrl._windows[id]
		if p != null and p.has_signal("layout_changed"):
			if not p.layout_changed.is_connected(_on_window_layout.bind(str(id))):
				p.layout_changed.connect(_on_window_layout.bind(str(id)))
		if p != null and not p.visibility_changed.is_connected(_on_window_layout.bind(str(id))):
			p.visibility_changed.connect(_on_window_layout.bind(str(id)))


func _on_window_layout(id: String) -> void:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	var p: Control = ctrl._windows.get(id)
	if p == null:
		return
	gs.save_window_layout(id, p.global_position, p.visible)


func _restore_window_layouts() -> void:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	for id in ctrl._windows.keys():
		var lay: Dictionary = gs.window_layout(str(id))
		if lay.is_empty():
			continue
		var p: Control = ctrl._windows[id]
		if p == null:
			continue
		p.global_position = Vector2(float(lay.get("x", p.global_position.x)), float(lay.get("y", p.global_position.y)))


func _build_windows() -> void:
	ctrl._windows["character"] = _make_window("角色状态", Vector2(560, 420), "top_left", Vector2(200, 90))
	_lock_character_window(ctrl._windows["character"] as PanelContainer)
	ctrl._windows["inventory"] = _make_window("背包", Vector2(420, 500), "top_right", Vector2(200, 40))
	ctrl._lock_inventory_window(ctrl._windows["inventory"] as PanelContainer)
	ctrl._windows["skills"] = _make_window("技能与魔法", Vector2(400, 420), "top_center", Vector2(0, 100))
	ctrl._lock_skills_window(ctrl._windows["skills"] as PanelContainer)
	ctrl._windows["quest"] = _make_window("任务", Vector2(380, 430), "bottom_right", Vector2(40, 80))
	ctrl._lock_quest_window(ctrl._windows["quest"] as PanelContainer)
	ctrl._windows["map"] = _make_window("地图", Vector2(460, 580), "top_center", Vector2(0, 36))
	_apply_l2_chrome(ctrl._windows["map"] as PanelContainer)
	ctrl._windows["system"] = _make_window("系统设置", Vector2(500, 520), "bottom_center", Vector2(0, 80))
	_lock_system_window(ctrl._windows["system"] as PanelContainer)
	var map_panel: PanelContainer = ctrl._windows.get("map")
	if map_panel:
		map_panel.min_size = Vector2(300, 280)
		map_panel.custom_minimum_size = Vector2(300, 280)
	for id in ctrl._windows.keys():
		(ctrl._windows[id] as Control).visible = false


func _make_window(title: String, size: Vector2, dock: String, offset: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_script(HudDrag)
	panel.screen_margin = 4.0
	panel.min_size = Vector2(240, 180)
	panel.default_size = size
	panel.initial_dock = "none"
	panel.drag_anywhere = true
	panel.visible = false
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(240, 180)
	ctrl.add_child(panel)
	var marg := MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 8)
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(marg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marg.add_child(vbox)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)
	var title_l := Label.new()
	title_l.text = title
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.add_theme_font_size_override("font_size", 14)
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title_l)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(func(): panel.visible = false)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(body)
	panel.set_meta("body", body)
	panel.set_meta("title", title)
	panel.set_meta("dock_hint", dock)
	panel.set_meta("pos_offset", offset)
	panel.set_meta("base_size", size)
	return panel


func _lock_character_window(panel: PanelContainer) -> void:
	## Fixed-size character / paperdoll window (L2 chrome).
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(560, 420))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	_apply_l2_chrome(panel)


func _lock_system_window(panel: PanelContainer) -> void:
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(500, 520))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	_apply_l2_chrome(panel)
	var scroll := panel.find_child("Scroll", true, false) as ScrollContainer
	if scroll == null:
		return
	var vbox := scroll.get_parent() as VBoxContainer
	if vbox == null:
		return
	var tabs := vbox.get_node_or_null("SystemTabs") as HBoxContainer
	if tabs == null:
		tabs = HBoxContainer.new()
		tabs.name = "SystemTabs"
		tabs.add_theme_constant_override("separation", 4)
		tabs.mouse_filter = Control.MOUSE_FILTER_STOP
		vbox.add_child(tabs)
		vbox.move_child(tabs, scroll.get_index())
	panel.set_meta("system_tabs", tabs)
	_rebuild_system_tab_bar(panel)


func _rebuild_system_tab_bar(panel: PanelContainer) -> void:
	var tabs: HBoxContainer = panel.get_meta("system_tabs", null) if panel else null
	if tabs == null or not is_instance_valid(tabs):
		return
	while tabs.get_child_count() > 0:
		var c: Node = tabs.get_child(0)
		tabs.remove_child(c)
		c.queue_free()
	for item in ctrl.SYSTEM_TABS:
		var btn := Button.new()
		btn.text = str(item[0])
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(90, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_on_system_tab.bind(str(item[1])))
		tabs.add_child(btn)
	_highlight_system_tabs(tabs)


func _on_system_tab(tab_id: String) -> void:
	tab_id = tab_id.strip_edges()
	if tab_id.is_empty() or tab_id == ctrl._system_tab:
		return
	ctrl._system_tab = tab_id
	var panel: PanelContainer = ctrl._windows.get("system")
	if panel != null:
		_highlight_system_tabs(panel.get_meta("system_tabs", null) as HBoxContainer)
	if panel != null and panel.visible:
		_fill_window("system")


func _highlight_system_tabs(tabs: HBoxContainer) -> void:
	if tabs == null:
		return
	for i in range(tabs.get_child_count()):
		var btn := tabs.get_child(i) as Button
		if btn == null or i >= ctrl.SYSTEM_TABS.size():
			continue
		L2Style.style_tab_button(btn, str(ctrl.SYSTEM_TABS[i][1]) == ctrl._system_tab)


func _apply_l2_chrome(panel: PanelContainer) -> void:
	## Ornate panel + title strip + close icon. Idempotent. Works without a named Scroll.
	if panel == null:
		return
	L2Style.apply_panel(panel)
	var marg := panel.get_child(0) as MarginContainer
	if marg != null:
		marg.add_theme_constant_override("margin_left", 8)
		marg.add_theme_constant_override("margin_top", 6)
		marg.add_theme_constant_override("margin_right", 8)
		marg.add_theme_constant_override("margin_bottom", 14)
	var vbox: VBoxContainer = null
	if marg != null and marg.get_child_count() > 0:
		vbox = marg.get_child(0) as VBoxContainer
	if vbox == null:
		return
	vbox.add_theme_constant_override("separation", 4)
	var title_bar := vbox.get_node_or_null("TitleBar") as PanelContainer
	var head: HBoxContainer = null
	if title_bar != null:
		head = title_bar.get_child(0) as HBoxContainer if title_bar.get_child_count() > 0 else null
	else:
		for c in vbox.get_children():
			if c is HBoxContainer:
				head = c
				break
		if head != null:
			title_bar = PanelContainer.new()
			title_bar.name = "TitleBar"
			title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			title_bar.custom_minimum_size = Vector2(0, 30)
			title_bar.add_theme_stylebox_override("panel", L2Style.title_box())
			var idx := head.get_index()
			vbox.remove_child(head)
			title_bar.add_child(head)
			vbox.add_child(title_bar)
			vbox.move_child(title_bar, idx)
	if head != null:
		head.add_theme_constant_override("separation", 4)
		if head.get_child_count() > 0:
			L2Style.style_title(head.get_child(0) as Label)
		if head.get_child_count() > 1:
			L2Style.style_close(head.get_child(head.get_child_count() - 1) as Button)
		for c in head.get_children():
			if c is Label and str(c.name).find("Gold") >= 0:
				L2Style.style_gold_amount(c)


func _grid_cell_size() -> Vector2:
	## Same pixel size as hotbar slots.
	return Vector2(ctrl.GRID_CELL, ctrl.GRID_CELL)


func _grid_cols_for(panel: PanelContainer) -> int:
	## How many GRID_CELL columns fit the fixed window width (scroll for extra rows).
	var base: Vector2 = panel.get_meta("base_size", Vector2(420, 500)) if panel else Vector2(420, 460)
	var win_w: float = panel.size.x if panel and panel.size.x >= 64.0 else base.x
	const MARGIN_X := 20.0
	var inner: float = maxf(float(ctrl.GRID_CELL), win_w - MARGIN_X)
	var cols := int(floor((inner + float(ctrl.GRID_SEP)) / (float(ctrl.GRID_CELL) + float(ctrl.GRID_SEP))))
	return maxi(1, cols)


func _place_window(panel: PanelContainer) -> void:
	var vp: Vector2 = ctrl.get_viewport().get_visible_rect().size
	var dock := str(panel.get_meta("dock_hint", "top_left"))
	var off: Vector2 = panel.get_meta("pos_offset", Vector2.ZERO)
	var base: Vector2 = panel.get_meta("base_size", panel.default_size)
	if panel.size.x < 64.0 or panel.size.y < 64.0 or panel.size.y > vp.y - 8.0:
		panel.size = base
	var s := panel.size
	var pos := Vector2(8, 8)
	match dock:
		"top_right":
			pos = Vector2(vp.x - s.x - 8, 8) + Vector2(-off.x, off.y)
		"top_center":
			pos = Vector2((vp.x - s.x) * 0.5, 8) + off
		"bottom_right":
			pos = Vector2(vp.x - s.x - 8, vp.y - s.y - 8) - off
		"bottom_center":
			pos = Vector2((vp.x - s.x) * 0.5, vp.y - s.y - 90) - Vector2(0, off.y)
		_:
			pos = Vector2(8, 150) + off
	panel.global_position = pos


func _toggle_window(id: String) -> void:
	if not ctrl._windows.has(id):
		return
	var panel: PanelContainer = ctrl._windows[id]
	panel.visible = not panel.visible
	if panel.visible:
		var base: Vector2 = panel.get_meta("base_size", panel.default_size)
		panel.size = base
		_fill_window(id)
		call_deferred("_lock_window_size", panel)
		call_deferred("_place_window", panel)
		panel.move_to_front()


func _lock_window_size(panel: PanelContainer) -> void:
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", panel.default_size)
	if bool(panel.get_meta("fixed_size", false)):
		panel.size = base
		panel.custom_minimum_size = base
		if "min_size" in panel:
			panel.min_size = base
		return
	var vp: Vector2 = ctrl.get_viewport().get_visible_rect().size
	if panel.size.y > base.y + 8.0 or panel.size.y > vp.y * 0.85:
		panel.size = base


func _close_top_window() -> bool:
	# NPC Chat first, then shop, then highest visible floating window
	if ctrl._inspect_panel != null and ctrl._inspect_panel.visible:
		ctrl._inspect_panel.visible = false
		return true
	if ctrl._invite_panel != null and ctrl._invite_panel.visible:
		ctrl._hide_invite_dialog()
		return true
	if ctrl._npc_chat != null and ctrl._npc_chat.visible:
		ctrl._npc_chat.visible = false
		return true
	if ctrl._shop_panel != null and ctrl._shop_panel.visible:
		ctrl.hide_shop()
		return true
	if ctrl._party_panel != null and ctrl._party_panel.visible:
		ctrl._party_panel.visible = false
		return true
	if ctrl._friends_panel != null and ctrl._friends_panel.visible:
		ctrl._friends_panel.visible = false
		return true
	if ctrl._guild_panel != null and ctrl._guild_panel.visible:
		ctrl._guild_panel.visible = false
		return true
	if ctrl._auction_panel != null and ctrl._auction_panel.visible:
		ctrl._auction_panel.visible = false
		return true
	if ctrl._daily_panel != null and ctrl._daily_panel.visible:
		ctrl._daily_panel.visible = false
		return true
	if ctrl._mail_panel != null and ctrl._mail_panel.visible:
		ctrl._mail_panel.visible = false
		return true
	if ctrl._emote_panel != null and ctrl._emote_panel.visible:
		ctrl._emote_panel.visible = false
		return true
	if ctrl._combat_log_panel != null and ctrl._combat_log_panel.visible:
		ctrl._combat_log_panel.visible = false
		return true
	if ctrl._craft_panel != null and ctrl._craft_panel.visible:
		ctrl._craft_panel.visible = false
		return true
	if ctrl._warehouse_panel != null and ctrl._warehouse_panel.visible:
		ctrl._warehouse_panel.visible = false
		return true
	var order := ["system", "map", "quest", "skills", "inventory", "character"]
	for id in order:
		var p: PanelContainer = ctrl._windows.get(id)
		if p and p.visible:
			p.visible = false
			return true
	return false


func _refresh_window_contents() -> void:
	for id in ctrl._windows.keys():
		var p: PanelContainer = ctrl._windows[id]
		if p.visible:
			_fill_window(str(id))


func _fill_window(id: String) -> void:
	var panel: PanelContainer = ctrl._windows[id]
	var body: VBoxContainer = panel.get_meta("body")
	for c in body.get_children():
		c.queue_free()
	var ch: Dictionary = ctrl._character
	if ch.is_empty():
		ch = Net.session().active_character()
	match id:
		"character":
			ctrl._fill_character(body, ch)
		"inventory":
			ctrl._fill_inventory(body, ch)
		"skills":
			ctrl._fill_skills(body, ch)
		"quest":
			ctrl._fill_quest(body, ch)
		"map":
			ctrl._fill_map(body, ch)
		"system":
			ctrl._fill_system(body)
