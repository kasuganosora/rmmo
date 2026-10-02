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
const GameWindow = preload("res://scripts/ui/game_window.gd")
const Net = preload("res://scripts/net/net.gd")


func _connect_window_layout_signals() -> void:
	for id in ctrl._windows.keys():
		var p: Control = ctrl._windows[id]
		if p != null and p.has_signal("layout_changed"):
			if not p.layout_changed.is_connected(_on_window_layout.bind(str(id))):
				p.layout_changed.connect(_on_window_layout.bind(str(id)))


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
	ctrl._windows["character"] = _make_window("角色状态", Vector2(540, 400), "top_left", Vector2(200, 90))
	_lock_character_window(ctrl._windows["character"] as PanelContainer)
	ctrl._windows["inventory"] = _make_window("背包", Vector2(376, 438), "top_right", Vector2(200, 40))
	ctrl._lock_inventory_window(ctrl._windows["inventory"] as PanelContainer)
	ctrl._windows["skills"] = _make_window("技能与魔法", Vector2(360, 380), "top_center", Vector2(0, 100))
	ctrl._lock_skills_window(ctrl._windows["skills"] as PanelContainer)
	ctrl._windows["quest"] = _make_window("任务", Vector2(330, 380), "bottom_right", Vector2(40, 80))
	ctrl._lock_quest_window(ctrl._windows["quest"] as PanelContainer)
	ctrl._windows["map"] = _make_window("地图", Vector2(420, 480), "top_center", Vector2(0, 36))
	_apply_l2_chrome(ctrl._windows["map"] as PanelContainer)
	ctrl._windows["system"] = _make_window("系统设置", Vector2(560, 480), "bottom_center", Vector2(0, 80))
	_lock_system_window(ctrl._windows["system"] as PanelContainer)
	var map_panel: PanelContainer = ctrl._windows.get("map")
	if map_panel:
		map_panel.min_size = Vector2(300, 280)
		map_panel.custom_minimum_size = Vector2(300, 280)
	for id in ctrl._windows.keys():
		(ctrl._windows[id] as Control).visible = false


func _make_window(title: String, size: Vector2, dock: String, offset: Vector2) -> PanelContainer:
	var panel := GameWindow.new()
	panel.screen_margin = 4.0
	panel.min_size = Vector2(240, 180)
	panel.default_size = size
	panel.initial_dock = "none"
	panel.drag_anywhere = false
	panel.drag_strip_height = 36
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
	ctrl._system_panel_logic.setup_layout(panel)


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
		btn.custom_minimum_size = Vector2(64, L2Style.TAB_HEIGHT)
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
	ctrl._waiting_bind = ""
	var panel: PanelContainer = ctrl._windows.get("system")
	if panel != null:
		_highlight_system_tabs(panel.get_meta("system_tabs", null) as HBoxContainer)
		panel.find_child("Scroll", true, false).scroll_vertical = 0
	if panel != null and panel.visible:
		_fill_window("system")


func _highlight_system_tabs(tabs: HBoxContainer) -> void:
	if tabs == null:
		return
	for i in range(tabs.get_child_count()):
		var btn := tabs.get_child(i) as Button
		if btn == null or i >= ctrl.SYSTEM_TABS.size():
			continue
		ctrl._system_panel_logic.style_settings_tab(btn, str(ctrl.SYSTEM_TABS[i][1]) == ctrl._system_tab)


func _apply_l2_chrome(panel: PanelContainer) -> void:
	## Thin metal frame + compact title strip. Idempotent, including auxiliary windows.
	if panel == null:
		return
	GameWindow.apply_chrome(panel)
	if panel.has_signal("layout_changed") and not panel.layout_changed.is_connected(_remember_position.bind(panel)):
		panel.layout_changed.connect(_remember_position.bind(panel))


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
	var s := panel.size * panel.get_global_transform().get_scale()
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
	place_at(panel, pos)


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
	if ctrl._invite_panel != null and ctrl._invite_panel.visible:
		ctrl._hide_invite_dialog()
		return true
	# Match visual stacking, including titles/achievements and auxiliary windows.
	# Reuse each close callback so shop/trade cleanup follows the same path as X.
	var children: Array = ctrl.get_children()
	children.reverse()
	for child in children:
		if not child is PanelContainer or not child.visible: continue
		if child.has_meta("confirmation") and is_instance_valid(child.get_meta("confirmation")):
			GameWindow.cancel_confirmation(child)
			return true
		var title := child.find_child("TitleBar", true, false) as PanelContainer
		if title == null or title.get_child_count() == 0: continue
		var head := title.get_child(0)
		var close := head.get_child(head.get_child_count() - 1) as Button
		if close != null:
			close.pressed.emit()
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
		body.remove_child(c)
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


func _layout_key(panel: Control) -> String:
	for id in ctrl._windows:
		if ctrl._windows[id] == panel: return str(id)
	return "aux:" + str(panel.get_meta("title", panel.name))


func _remember_position(panel: Control) -> void:
	var gs := GameSettingsScript.get_i()
	if gs != null: gs.save_window_layout(_layout_key(panel), panel.global_position, panel.visible)


func place_at(panel: Control, fallback: Vector2) -> void:
	var gs := GameSettingsScript.get_i()
	var saved: Dictionary = gs.window_layout(_layout_key(panel)) if gs != null else {}
	panel.global_position = Vector2(float(saved.get("x", fallback.x)), float(saved.get("y", fallback.y)))
	if panel.has_method("_clamp_on_screen"): panel._clamp_on_screen()


func clamp_visible_windows() -> void:
	for child in ctrl.get_children():
		if child is Control and child.visible and child.has_method("_clamp_on_screen"):
			child._clamp_on_screen()
