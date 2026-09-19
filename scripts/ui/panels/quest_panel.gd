extends RefCounted
## UI panel: quests, tracker, drawer, quest toasts.

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const QuestTrackerUtil = preload("res://scripts/ui/quest_tracker_util.gd")
const MinimapPanel = preload("res://scripts/ui/panels/minimap_panel.gd")
const QUEST_TOAST_DURATION := 2.0
const QUEST_DRAWER_WIDTH := 320.0
const QUEST_TABS := [
	["正在进行", "active"],
	["已完成", "completed"],
]

static func _on_status_cancel_requested(ctrl, status_id: String) -> void:
	status_id = str(status_id).strip_edges()
	if status_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_cancel_status"):
		ctrl._world_combat.request_cancel_status(status_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_cancel_status"):
		ctrl._apply_party_result_locally(srv.try_cancel_status(status_id))
	else:
		ctrl.append_system("无法取消状态。")



static func apply_quest_snapshot(ctrl, quests: Array) -> void:
	ctrl._detect_quest_status_toasts(quests)
	ctrl._server_quests = quests.duplicate(true)
	# Drop selection if quest no longer in journal.
	if not ctrl._selected_quest_id.is_empty():
		var still = false
		for q in ctrl._server_quests:
			if typeof(q) == TYPE_DICTIONARY and str(q.get("id", "")) == ctrl._selected_quest_id:
				still = true
				break
		if not still:
			ctrl._selected_quest_id = ""
			ctrl._close_quest_drawer(false)
	if ctrl._windows.has("quest") and ctrl._windows["quest"].visible:
		ctrl._refresh_window_contents()
		ctrl._refresh_quest_drawer_content()
	ctrl._refresh_quest_tracker()





static func _build_quest_tracker(ctrl) -> void:
	if ctrl._quest_tracker != null and is_instance_valid(ctrl._quest_tracker):
		return
	ctrl._quest_tracker = PanelContainer.new()
	ctrl._quest_tracker.name = "QuestTracker"
	ctrl._quest_tracker.set_script(HudDrag)
	ctrl._quest_tracker.screen_margin = 4.0
	ctrl._quest_tracker.min_size = Vector2(180, 48)
	ctrl._quest_tracker.default_size = Vector2(220, 120)
	ctrl._quest_tracker.initial_dock = "none"
	ctrl._quest_tracker.resizable = false
	ctrl._quest_tracker.visible = false
	L2Style.apply_panel(ctrl._quest_tracker)
	ctrl.add_child(ctrl._quest_tracker)
	if ctrl._quest_tracker.has_signal("layout_changed"):
		ctrl._quest_tracker.layout_changed.connect(func():
			var gs = GameSettingsScript.get_i()
			if gs != null:
				gs.save_window_layout("quest_tracker", ctrl._quest_tracker.global_position, ctrl._quest_tracker.visible)
		)
	ctrl.call_deferred("_place_quest_tracker")



static func _default_quest_tracker_pos(ctrl) -> Vector2:
	## Prefer just under the minimap (top-right); fall back to viewport top-right.
	var tracker_w = 220.0
	var mini = ctrl.get_node_or_null("MinimapPanel") as Control
	if mini != null and is_instance_valid(mini):
		var mx: float = mini.global_position.x + mini.size.x - tracker_w
		var my: float = mini.global_position.y + mini.size.y + 4.0
		return Vector2(maxf(mx, 4.0), maxf(my, 4.0))
	var vp = ctrl.get_viewport_rect().size
	return Vector2(maxf(vp.x - tracker_w - 4.0, 4.0), 176.0)



static func _place_quest_tracker(ctrl) -> void:
	if ctrl._quest_tracker == null or not is_instance_valid(ctrl._quest_tracker):
		return
	var gs = GameSettingsScript.get_i()
	var placed = false
	if gs != null:
		var lay: Dictionary = gs.window_layout("quest_tracker")
		if not lay.is_empty():
			ctrl._quest_tracker.global_position = Vector2(float(lay.get("x", 8)), float(lay.get("y", 176)))
			placed = true
	if not placed:
		ctrl._quest_tracker.global_position = ctrl._default_quest_tracker_pos()
	if ctrl._quest_tracker.find_child("TrackerBody", true, false) == null:
		var marg = MarginContainer.new()
		marg.add_theme_constant_override("margin_left", 8)
		marg.add_theme_constant_override("margin_top", 6)
		marg.add_theme_constant_override("margin_right", 8)
		marg.add_theme_constant_override("margin_bottom", 6)
		ctrl._quest_tracker.add_child(marg)
		var col = VBoxContainer.new()
		col.name = "TrackerBody"
		col.add_theme_constant_override("separation", 4)
		marg.add_child(col)
	ctrl._refresh_quest_tracker()



static func _refresh_quest_tracker(ctrl) -> void:
	if ctrl._quest_tracker == null or not is_instance_valid(ctrl._quest_tracker):
		return
	var col = ctrl._quest_tracker.find_child("TrackerBody", true, false) as VBoxContainer
	if col == null:
		return
	for c in col.get_children():
		c.queue_free()
	var active: Array = QuestTrackerUtil.active_quests(ctrl._server_quests, QuestTrackerUtil.MAX_TRACKED)
	if active.is_empty():
		ctrl._quest_tracker.visible = false
		return
	if not GameSettingsScript.flag("show_quest_tracker", true):
		ctrl._quest_tracker.visible = false
		return
	ctrl._quest_tracker.visible = true
	# Header row with close (hides via settings flag).
	var head = HBoxContainer.new()
	col.add_child(head)
	var head_lab = Label.new()
	head_lab.text = "任务追踪"
	head_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_lab.add_theme_font_size_override("font_size", 11)
	head_lab.add_theme_color_override("font_color", L2Style.COL_MUTED)
	head.add_child(head_lab)
	var close_b = Button.new()
	close_b.text = "×"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.custom_minimum_size = Vector2(22, 22)
	close_b.pressed.connect(func():
		var gs = GameSettingsScript.get_i()
		if gs != null:
			gs.set_flag("show_quest_tracker", false)
		ctrl._quest_tracker.visible = false
	)
	head.add_child(close_b)
	for q in active:
		var qid = str(q.get("id", "")).strip_edges()
		var title = str(q.get("title", "")).strip_edges()
		if title.is_empty():
			title = qid if not qid.is_empty() else "任务"
		var st = ctrl._normalize_quest_status(str(q.get("status", "")))
		var title_row = HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 4)
		col.add_child(title_row)
		var title_btn = Button.new()
		if st == "ready":
			title_btn.text = "%s [可交付]" % title
		else:
			title_btn.text = title
		title_btn.focus_mode = Control.FOCUS_NONE
		title_btn.flat = true
		title_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_btn.add_theme_font_size_override("font_size", 12)
		title_btn.add_theme_color_override("font_color", L2Style.COL_TITLE)
		title_btn.add_theme_color_override("font_hover_color", L2Style.COL_GOLD)
		title_btn.tooltip_text = "左键前往 / 右键详情"
		if not qid.is_empty():
			title_btn.gui_input.connect(ctrl._on_tracked_quest_gui_input.bind(qid, -1))
			# Flat button still emits pressed on LMB; route through path-or-journal.
			title_btn.pressed.connect(ctrl._on_tracked_quest_activate.bind(qid, -1))
		title_row.add_child(title_btn)
		var nav_preview: Dictionary = ctrl._resolve_tracked_quest_nav(qid, -1)
		if bool(nav_preview.get("ok", false)):
			var go_btn = Button.new()
			go_btn.text = "去"
			go_btn.focus_mode = Control.FOCUS_NONE
			go_btn.flat = true
			go_btn.custom_minimum_size = Vector2(22, 18)
			go_btn.add_theme_font_size_override("font_size", 11)
			go_btn.add_theme_color_override("font_color", L2Style.COL_GOLD)
			go_btn.tooltip_text = "前往：%s" % str(nav_preview.get("label", ""))
			go_btn.pressed.connect(ctrl._path_to_tracked_quest.bind(qid, -1))
			title_row.add_child(go_btn)
		var objs: Variant = q.get("objectives", [])
		if typeof(objs) != TYPE_ARRAY:
			continue
		var oi = 0
		for o in objs:
			if typeof(o) != TYPE_DICTIONARY:
				continue
			var obj_row = HBoxContainer.new()
			obj_row.add_theme_constant_override("separation", 4)
			col.add_child(obj_row)
			var line = Button.new()
			line.text = "  %s" % QuestTrackerUtil.format_objective(o)
			line.focus_mode = Control.FOCUS_NONE
			line.flat = true
			line.alignment = HORIZONTAL_ALIGNMENT_LEFT
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_theme_font_size_override("font_size", 11)
			line.add_theme_color_override("font_color", L2Style.COL_TEXT)
			line.add_theme_color_override("font_hover_color", L2Style.COL_GOLD)
			line.tooltip_text = "左键前往 / 右键详情"
			if not qid.is_empty():
				line.gui_input.connect(ctrl._on_tracked_quest_gui_input.bind(qid, oi))
				line.pressed.connect(ctrl._on_tracked_quest_activate.bind(qid, oi))
			obj_row.add_child(line)
			oi += 1
	ctrl.call_deferred("_fit_quest_tracker")



static func _fit_quest_tracker(ctrl) -> void:
	if ctrl._quest_tracker == null or not is_instance_valid(ctrl._quest_tracker):
		return
	if not ctrl._quest_tracker.visible:
		return
	var ms = ctrl._quest_tracker.get_combined_minimum_size()
	ctrl._quest_tracker.size = Vector2(maxf(ms.x, 180.0), maxf(ms.y, 48.0))



static func _open_tracked_quest(ctrl, quest_id: String) -> void:
	## Open journal detail drawer for a tracked quest.
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty():
		return
	ctrl._quest_tab = "active"
	ctrl._selected_quest_id = quest_id
	if not (ctrl._windows.has("quest") and ctrl._windows["quest"] != null and ctrl._windows["quest"].visible):
		ctrl._toggle_window("quest")
	else:
		ctrl._fill_window("quest")
	ctrl._open_quest_drawer(quest_id, true)



static func _quest_nav_world_ctx(ctrl) -> Dictionary:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("get_quest_nav_context"):
		var ctx_v: Variant = ctrl._world_combat.get_quest_nav_context()
		if typeof(ctx_v) == TYPE_DICTIONARY:
			return ctx_v
	# Headless / unbound fallback: empty context (resolver returns ok=false → journal).
	return {"npcs": [], "gather": [], "fish": [], "warps": []}



static func _find_tracked_quest_row(ctrl, quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	for q in ctrl._server_quests:
		if typeof(q) != TYPE_DICTIONARY:
			continue
		if str(q.get("id", "")).strip_edges() == quest_id:
			return q
	return {}



static func _resolve_tracked_quest_nav(ctrl, quest_id: String, objective_index: int = -1) -> Dictionary:
	var row: Dictionary = ctrl._find_tracked_quest_row(quest_id)
	if row.is_empty():
		return {"ok": false, "cell": Vector2i.ZERO, "label": "", "reason": ""}
	return QuestTrackerUtil.resolve_quest_nav(row, ctrl._quest_nav_world_ctx(), objective_index)



static func _path_to_tracked_quest(ctrl, quest_id: String, objective_index: int = -1) -> void:
	var nav: Dictionary = ctrl._resolve_tracked_quest_nav(quest_id, objective_index)
	if not bool(nav.get("ok", false)):
		return
	var cell: Vector2i = nav.get("cell", Vector2i.ZERO)
	if typeof(cell) != TYPE_VECTOR2I:
		cell = Vector2i(int(nav.get("x", 0)), int(nav.get("y", 0)))
	var label = str(nav.get("label", "")).strip_edges()
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_map_move"):
		ctrl._world_combat.request_map_move(cell, label)
	else:
		ctrl.append_system("前往：%s" % (label if label != "" else "(%d, %d)" % [cell.x, cell.y]))



static func _on_tracked_quest_activate(ctrl, quest_id: String, objective_index: int = -1) -> void:
	var nav: Dictionary = ctrl._resolve_tracked_quest_nav(quest_id, objective_index)
	if bool(nav.get("ok", false)):
		ctrl._path_to_tracked_quest(quest_id, objective_index)
		return
	ctrl._open_tracked_quest(quest_id)



static func _lock_quest_window(ctrl, panel: PanelContainer) -> void:
	## Fixed-size quest list window; tabs above Scroll; drawer is a separate HUD sibling.
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(380, 430))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	ctrl._apply_l2_chrome(panel)
	var scroll = panel.find_child("Scroll", true, false) as ScrollContainer
	if scroll == null:
		return
	var vbox = scroll.get_parent() as VBoxContainer
	if vbox == null:
		return
	# Restore list Scroll (previous pass hid it for internal HBox split).
	scroll.visible = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Remove legacy internal QuestHost split if present.
	var legacy = vbox.get_node_or_null("QuestHost")
	if legacy != null:
		vbox.remove_child(legacy)
		legacy.free()
	if panel.has_meta("quest_host"):
		panel.remove_meta("quest_host")
	var tabs = vbox.get_node_or_null("QuestTabs") as HBoxContainer
	if tabs == null:
		tabs = HBoxContainer.new()
		tabs.name = "QuestTabs"
		tabs.add_theme_constant_override("separation", 4)
		tabs.mouse_filter = Control.MOUSE_FILTER_STOP
		vbox.add_child(tabs)
		vbox.move_child(tabs, scroll.get_index())
	panel.set_meta("quest_tabs", tabs)
	ctrl._rebuild_quest_tab_bar(panel)
	if not panel.visibility_changed.is_connected(ctrl._on_quest_window_visibility):
		panel.visibility_changed.connect(ctrl._on_quest_window_visibility)
	ctrl._ensure_quest_drawer()



static func _rebuild_quest_tab_bar(ctrl, panel: PanelContainer) -> void:
	var tabs: HBoxContainer = panel.get_meta("quest_tabs", null) if panel else null
	if tabs == null or not is_instance_valid(tabs):
		return
	while tabs.get_child_count() > 0:
		var c: Node = tabs.get_child(0)
		tabs.remove_child(c)
		c.queue_free()
	for item in QUEST_TABS:
		var btn = Button.new()
		btn.text = str(item[0])
		btn.toggle_mode = false
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(140, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var tid = str(item[1])
		btn.pressed.connect(ctrl._on_quest_tab.bind(tid))
		tabs.add_child(btn)
	ctrl._highlight_quest_tabs(tabs)



static func _on_quest_tab(ctrl, tab_id: String) -> void:
	tab_id = tab_id.strip_edges()
	if tab_id.is_empty():
		return
	ctrl._quest_tab = tab_id
	# Drop selection if it no longer matches the active tab filter.
	if not ctrl._selected_quest_id.is_empty():
		var keep = false
		for q in ctrl._server_quests:
			if typeof(q) != TYPE_DICTIONARY:
				continue
			if str(q.get("id", "")) != ctrl._selected_quest_id:
				continue
			if ctrl._quest_status_matches_tab(str(q.get("status", ""))):
				keep = true
			break
		if not keep:
			ctrl._selected_quest_id = ""
			ctrl._close_quest_drawer(false)
	if ctrl._windows.has("quest"):
		var panel: PanelContainer = ctrl._windows["quest"]
		ctrl._highlight_quest_tabs(panel.get_meta("quest_tabs", null) as HBoxContainer)
		if panel.visible:
			ctrl._fill_window("quest")



static func _highlight_quest_tabs(ctrl, tabs: HBoxContainer) -> void:
	if tabs == null:
		return
	for i in range(tabs.get_child_count()):
		var btn = tabs.get_child(i) as Button
		if btn == null or i >= QUEST_TABS.size():
			continue
		var id = str(QUEST_TABS[i][1])
		L2Style.style_tab_button(btn, id == ctrl._quest_tab)



static func _on_quest_window_visibility(ctrl) -> void:
	var panel: PanelContainer = ctrl._windows.get("quest") as PanelContainer
	if panel == null or not panel.visible:
		ctrl._selected_quest_id = ""
		ctrl._close_quest_drawer(false)



static func _fill_quest(ctrl, body: VBoxContainer, _ch: Dictionary) -> void:
	## List-only quest window (tabs filter); detail lives in external side drawer.
	var panel: PanelContainer = ctrl._windows.get("quest") as PanelContainer
	if panel != null:
		if not panel.has_meta("quest_tabs"):
			ctrl._lock_quest_window(panel)
		else:
			ctrl._rebuild_quest_tab_bar(panel)
	body.custom_minimum_size = Vector2.ZERO
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var quests: Array = ctrl._server_quests
	if quests.is_empty():
		var srv = Net.server()
		if srv != null and srv.has_method("get_quest_list"):
			quests = srv.get_quest_list()
			ctrl._server_quests = quests.duplicate(true)
	var filtered: Array = []
	for q in quests:
		if typeof(q) != TYPE_DICTIONARY:
			continue
		if ctrl._quest_status_matches_tab(str(q.get("status", ""))):
			filtered.append(q)
	# Validate selection against filtered list.
	if not ctrl._selected_quest_id.is_empty():
		var still = false
		for q in filtered:
			if str(q.get("id", "")) == ctrl._selected_quest_id:
				still = true
				break
		if not still:
			ctrl._selected_quest_id = ""
			ctrl._close_quest_drawer(false)
	if filtered.is_empty():
		var empty_msg = "（暂无已完成任务）" if ctrl._quest_tab == "completed" else "（暂无进行中任务）"
		ctrl._add_label(body, empty_msg, 12, L2Style.COL_MUTED)
	else:
		for q in filtered:
			body.add_child(ctrl._make_quest_row(q, str(q.get("id", "")) == ctrl._selected_quest_id))
	if panel != null and bool(panel.get_meta("fixed_size", false)):
		ctrl.call_deferred("_lock_window_size", panel)
	# Soft drawer sync: refresh content if open; do not cancel in-flight slide tweens.
	ctrl._soft_sync_quest_drawer()



static func _soft_sync_quest_drawer(ctrl) -> void:
	if ctrl._selected_quest_id.is_empty():
		return
	if ctrl._quest_drawer != null and is_instance_valid(ctrl._quest_drawer) and ctrl._quest_drawer.visible:
		ctrl._refresh_quest_drawer_content()
		ctrl._place_quest_drawer()



static func _quest_status_matches_tab(ctrl, status: String) -> bool:
	var st = ctrl._normalize_quest_status(status)
	if ctrl._quest_tab == "completed":
		return st == "completed"
	# 正在进行: in_progress / ready (and legacy active aliases)
	return st in ["in_progress", "ready"]



static func _normalize_quest_status(ctrl, status: String) -> String:
	match status.strip_edges():
		"completed", "complete":
			return "completed"
		"ready", "deliverable":
			return "ready"
		"active", "in_progress", "progress":
			return "in_progress"
		_:
			return "in_progress"



static func _make_quest_row(ctrl, q: Dictionary, selected: bool) -> Button:
	var qid = str(q.get("id", "")).strip_edges()
	var title = str(q.get("title", qid if not qid.is_empty() else "?"))
	var st = ctrl._quest_status_label(str(q.get("status", "in_progress")))
	var btn = Button.new()
	btn.text = "%s    [%s]" % [title, st]
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 34)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	L2Style.style_row_button(btn, selected)
	if not qid.is_empty():
		btn.pressed.connect(ctrl._on_quest_row_selected.bind(qid))
	return btn



static func _quest_status_label(ctrl, status: String) -> String:
	match ctrl._normalize_quest_status(status):
		"ready":
			return "可交付"
		"completed":
			return "已完成"
		_:
			return "进行中"



static func _on_quest_row_selected(ctrl, quest_id: String) -> void:
	ctrl._abandon_confirm_id = ""
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty():
		return
	if ctrl._selected_quest_id == quest_id:
		# Toggle off → slide drawer away; list stays.
		ctrl._selected_quest_id = ""
		if ctrl._windows.has("quest") and ctrl._windows["quest"].visible:
			ctrl._fill_window("quest")
		ctrl._close_quest_drawer(true)
		return
	ctrl._selected_quest_id = quest_id
	if ctrl._windows.has("quest") and ctrl._windows["quest"].visible:
		ctrl._fill_window("quest")
	ctrl._open_quest_drawer(quest_id, true)



static func _on_quest_drawer_close(ctrl) -> void:
	ctrl._selected_quest_id = ""
	ctrl._close_quest_drawer(true)
	if ctrl._windows.has("quest") and ctrl._windows["quest"].visible:
		ctrl._fill_window("quest")



static func _ensure_quest_drawer(ctrl) -> void:
	if ctrl._quest_drawer != null and is_instance_valid(ctrl._quest_drawer):
		return
	var drawer = PanelContainer.new()
	drawer.name = "QuestDrawer"
	drawer.visible = false
	drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer.clip_contents = true
	drawer.custom_minimum_size = Vector2(0, 0)
	L2Style.apply_panel(drawer)
	ctrl.add_child(drawer)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.add_child(marg)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marg.add_child(vbox)
	var title_bar = PanelContainer.new()
	title_bar.name = "TitleBar"
	title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.custom_minimum_size = Vector2(0, 30)
	title_bar.add_theme_stylebox_override("panel", L2Style.title_box())
	vbox.add_child(title_bar)
	var head = HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(head)
	var title_l = Label.new()
	title_l.name = "DrawerTitle"
	title_l.text = "详情"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	L2Style.style_title(title_l)
	head.add_child(title_l)
	var close_btn = Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(ctrl._on_quest_drawer_close)
	L2Style.style_close(close_btn)
	head.add_child(close_btn)
	var scroll = ScrollContainer.new()
	scroll.name = "DrawerScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(scroll)
	var dbody = VBoxContainer.new()
	dbody.name = "DrawerBody"
	dbody.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dbody.add_theme_constant_override("separation", 6)
	dbody.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(dbody)
	ctrl._quest_drawer = drawer
	ctrl._quest_drawer_body = dbody



static func _quest_by_id(ctrl, quest_id: String) -> Dictionary:
	for q in ctrl._server_quests:
		if typeof(q) != TYPE_DICTIONARY:
			continue
		if str(q.get("id", "")) == quest_id:
			return q
	return {}



static func _place_quest_drawer(ctrl) -> void:
	if ctrl._quest_drawer == null or not is_instance_valid(ctrl._quest_drawer):
		return
	var panel: PanelContainer = ctrl._windows.get("quest") as PanelContainer
	if panel == null or not panel.visible:
		return
	# Sibling of quest window: attach to its right edge, same top.
	ctrl._quest_drawer.global_position = Vector2(
		panel.global_position.x + panel.size.x,
		panel.global_position.y
	)
	var h: float = panel.size.y
	if ctrl._quest_drawer.size.y != h:
		ctrl._quest_drawer.size.y = h
	ctrl._quest_drawer.move_to_front()



static func _sync_quest_drawer_follow(ctrl) -> void:
	if ctrl._quest_drawer == null or not is_instance_valid(ctrl._quest_drawer):
		return
	if not ctrl._quest_drawer.visible:
		return
	var panel: PanelContainer = ctrl._windows.get("quest") as PanelContainer
	if panel == null or not panel.visible:
		ctrl._close_quest_drawer(false)
		return
	ctrl._place_quest_drawer()



static func _open_quest_drawer(ctrl, quest_id: String, animate: bool) -> void:
	ctrl._ensure_quest_drawer()
	var selected: Dictionary = ctrl._quest_by_id(quest_id)
	if selected.is_empty():
		ctrl._close_quest_drawer(false)
		return
	ctrl._refresh_quest_drawer_content()
	var panel: PanelContainer = ctrl._windows.get("quest") as PanelContainer
	var h: float = panel.size.y if panel != null else 400.0
	var was_open = ctrl._quest_drawer.visible and ctrl._quest_drawer.size.x > 1.0
	ctrl._quest_drawer.visible = true
	ctrl._place_quest_drawer()
	if ctrl._quest_drawer_tween != null and is_instance_valid(ctrl._quest_drawer_tween):
		ctrl._quest_drawer_tween.kill()
		ctrl._quest_drawer_tween = null
	# Animate only when sliding out from collapsed; switching rows keeps width.
	if animate and not was_open:
		ctrl._quest_drawer.size = Vector2(0, h)
		ctrl._quest_drawer.modulate = Color(1, 1, 1, 0.35)
		ctrl._quest_drawer_tween = ctrl.create_tween()
		ctrl._quest_drawer_tween.set_parallel(true)
		ctrl._quest_drawer_tween.tween_property(ctrl._quest_drawer, "size:x", QUEST_DRAWER_WIDTH, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ctrl._quest_drawer_tween.tween_property(ctrl._quest_drawer, "modulate:a", 1.0, 0.14)
	else:
		ctrl._quest_drawer.size = Vector2(QUEST_DRAWER_WIDTH, h)
		ctrl._quest_drawer.modulate = Color(1, 1, 1, 1)



static func _close_quest_drawer(ctrl, animate: bool) -> void:
	if ctrl._quest_drawer == null or not is_instance_valid(ctrl._quest_drawer):
		return
	if not ctrl._quest_drawer.visible and (ctrl._quest_drawer_tween == null or not is_instance_valid(ctrl._quest_drawer_tween)):
		return
	if ctrl._quest_drawer_tween != null and is_instance_valid(ctrl._quest_drawer_tween):
		ctrl._quest_drawer_tween.kill()
		ctrl._quest_drawer_tween = null
	if animate and ctrl._quest_drawer.visible and ctrl._quest_drawer.size.x > 1.0:
		var tw = ctrl.create_tween()
		ctrl._quest_drawer_tween = tw
		tw.set_parallel(true)
		tw.tween_property(ctrl._quest_drawer, "size:x", 0.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(ctrl._quest_drawer, "modulate:a", 0.0, 0.12)
		tw.chain().tween_callback(ctrl._finish_quest_drawer_close)
	else:
		ctrl._finish_quest_drawer_close()



static func _finish_quest_drawer_close(ctrl) -> void:
	if ctrl._quest_drawer != null and is_instance_valid(ctrl._quest_drawer):
		ctrl._quest_drawer.visible = false
		ctrl._quest_drawer.size.x = 0
		ctrl._quest_drawer.modulate = Color(1, 1, 1, 1)
	ctrl._quest_drawer_tween = null



static func _refresh_quest_drawer_content(ctrl) -> void:
	ctrl._ensure_quest_drawer()
	if ctrl._quest_drawer_body == null or not is_instance_valid(ctrl._quest_drawer_body):
		return
	while ctrl._quest_drawer_body.get_child_count() > 0:
		var c: Node = ctrl._quest_drawer_body.get_child(0)
		ctrl._quest_drawer_body.remove_child(c)
		c.free()
	if ctrl._selected_quest_id.is_empty():
		return
	var selected: Dictionary = ctrl._quest_by_id(ctrl._selected_quest_id)
	if selected.is_empty():
		return
	var title_l = ctrl._quest_drawer.find_child("DrawerTitle", true, false) as Label
	if title_l != null:
		title_l.text = str(selected.get("title", "?"))
	ctrl._add_label(ctrl._quest_drawer_body, ctrl._quest_status_label(str(selected.get("status", "in_progress"))), 12, L2Style.COL_GOLD)
	var desc = str(selected.get("desc", "")).strip_edges()
	if not desc.is_empty():
		ctrl._add_label(ctrl._quest_drawer_body, desc, 12, L2Style.COL_TEXT)
	ctrl._add_label(ctrl._quest_drawer_body, "目标", 12, L2Style.COL_MUTED)
	var objs_v: Variant = selected.get("objectives", [])
	if typeof(objs_v) == TYPE_ARRAY and not (objs_v as Array).is_empty():
		for o in objs_v:
			if typeof(o) != TYPE_DICTIONARY:
				continue
			var ot = str(o.get("text", ""))
			var cur: int = int(o.get("cur", 0))
			var mx: int = maxi(int(o.get("max", 1)), 1)
			var done = cur >= mx
			var col = Color(0.55, 0.85, 0.55) if done else L2Style.COL_TEXT
			ctrl._add_label(ctrl._quest_drawer_body, "· %s（%d / %d）" % [ot, cur, mx], 12, col)
	else:
		ctrl._add_label(ctrl._quest_drawer_body, "· （无）", 12, L2Style.COL_MUTED)
	var rewards = str(selected.get("rewards", "")).strip_edges()
	ctrl._add_label(ctrl._quest_drawer_body, "奖励", 12, L2Style.COL_MUTED)
	ctrl._add_label(ctrl._quest_drawer_body, rewards if not rewards.is_empty() else "（无）", 12, L2Style.COL_GOLD)
	var qstatus = ctrl._normalize_quest_status(str(selected.get("status", "")))
	if qstatus == "ready":
		var turn_btn = Button.new()
		turn_btn.text = "交付任务"
		turn_btn.focus_mode = Control.FOCUS_NONE
		turn_btn.pressed.connect(ctrl._on_quest_turn_in.bind(ctrl._selected_quest_id))
		L2Style.style_action_button(turn_btn)
		ctrl._quest_drawer_body.add_child(turn_btn)
	elif qstatus == "completed":
		ctrl._add_label(ctrl._quest_drawer_body, "（已完成）", 12, Color(0.55, 0.75, 0.55))
	if qstatus == "in_progress" or qstatus == "ready":
		var ab_btn = Button.new()
		ab_btn.text = "确认放弃" if ctrl._abandon_confirm_id == ctrl._selected_quest_id else "放弃任务"
		ab_btn.focus_mode = Control.FOCUS_NONE
		ab_btn.pressed.connect(ctrl._on_quest_abandon.bind(ctrl._selected_quest_id))
		L2Style.style_action_button(ab_btn)
		ctrl._quest_drawer_body.add_child(ab_btn)



static func _on_quest_turn_in(ctrl, quest_id: String) -> void:
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_turn_in_quest"):
		ctrl._world_combat.request_turn_in_quest(quest_id)



static func _on_quest_abandon(ctrl, quest_id: String) -> void:
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty():
		return
	if ctrl._abandon_confirm_id != quest_id:
		ctrl._abandon_confirm_id = quest_id
		ctrl.append_system("再点一次以确认放弃任务。")
		ctrl._refresh_quest_drawer_content()
		return
	ctrl._abandon_confirm_id = ""
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_abandon_quest"):
		ctrl._world_combat.request_abandon_quest(quest_id)



static func _detect_quest_status_toasts(ctrl, quests: Array) -> void:
	var next_seen: Dictionary = {}
	var ready_titles: Array = []
	var done_titles: Array = []
	for q_v in quests:
		if typeof(q_v) != TYPE_DICTIONARY:
			continue
		var q: Dictionary = q_v
		var qid = str(q.get("id", "")).strip_edges()
		if qid.is_empty():
			continue
		var st = ctrl._normalize_quest_status(str(q.get("status", "")))
		next_seen[qid] = st
		var title = str(q.get("title", qid)).strip_edges()
		if title.is_empty():
			title = qid
		if not ctrl._quest_status_seeded:
			continue
		var prev = str(ctrl._quest_status_seen.get(qid, ""))
		if st == "ready" and prev != "ready":
			ready_titles.append(title)
		elif st == "completed" and prev != "completed":
			done_titles.append(title)
	ctrl._quest_status_seen = next_seen
	ctrl._quest_status_seeded = true
	# Prefer complete over ready if both somehow fire; show one banner (last wins).
	for t in ready_titles:
		ctrl.show_quest_ready_toast(str(t))
	for t in done_titles:
		ctrl.show_quest_complete_toast(str(t))



static func _build_quest_toast(ctrl) -> void:
	if ctrl._quest_toast != null and is_instance_valid(ctrl._quest_toast):
		return
	ctrl._quest_toast = PanelContainer.new()
	ctrl._quest_toast.name = "QuestToast"
	ctrl._quest_toast.visible = false
	ctrl._quest_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._quest_toast.z_index = 80
	ctrl.add_child(ctrl._quest_toast)
	var marg = MarginContainer.new()
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marg.add_theme_constant_override("margin_left", 18)
	marg.add_theme_constant_override("margin_top", 10)
	marg.add_theme_constant_override("margin_right", 18)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._quest_toast.add_child(marg)
	ctrl._quest_toast_label = Label.new()
	ctrl._quest_toast_label.name = "QuestToastLabel"
	ctrl._quest_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._quest_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctrl._quest_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ctrl._quest_toast_label.add_theme_font_size_override("font_size", 20)
	ctrl._quest_toast_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.55, 1.0))
	ctrl._quest_toast_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 0.95))
	ctrl._quest_toast_label.add_theme_constant_override("outline_size", 4)
	ctrl._quest_toast_label.text = "任务"
	marg.add_child(ctrl._quest_toast_label)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.12, 0.88)
	sb.border_color = Color(0.55, 0.82, 0.40, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	ctrl._quest_toast.add_theme_stylebox_override("panel", sb)



static func show_quest_complete_toast(ctrl, title: String) -> void:
	ctrl._show_quest_toast("任务完成：%s" % title.strip_edges(), Color(1.0, 0.92, 0.45, 1.0), Color(0.85, 0.72, 0.28, 0.95))



static func _show_quest_toast(ctrl, line: String, font_col: Color, border_col: Color) -> void:
	ctrl._build_quest_toast()
	if ctrl._quest_toast == null or ctrl._quest_toast_label == null:
		return
	ctrl._quest_toast_label.text = line
	ctrl._quest_toast_label.add_theme_color_override("font_color", font_col)
	var sb: StyleBox = ctrl._quest_toast.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var flat: StyleBoxFlat = (sb as StyleBoxFlat).duplicate()
		flat.border_color = border_col
		ctrl._quest_toast.add_theme_stylebox_override("panel", flat)
	ctrl._quest_toast_ttl = QUEST_TOAST_DURATION
	ctrl._quest_toast.visible = true
	ctrl._layout_quest_toast()
	ctrl._quest_toast.move_to_front()



static func hide_quest_toast(ctrl) -> void:
	ctrl._quest_toast_ttl = 0.0
	if ctrl._quest_toast != null:
		ctrl._quest_toast.visible = false



static func is_quest_toast_visible(ctrl) -> bool:
	return ctrl._quest_toast != null and ctrl._quest_toast.visible and ctrl._quest_toast_ttl > 0.0



static func get_quest_toast_text(ctrl) -> String:
	if ctrl._quest_toast_label == null:
		return ""
	return str(ctrl._quest_toast_label.text)



static func _layout_quest_toast(ctrl) -> void:
	if ctrl._quest_toast == null:
		return
	ctrl._quest_toast.reset_size()
	var vp = ctrl.get_viewport_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1280, 720)
	var sz: Vector2 = ctrl._quest_toast.get_combined_minimum_size()
	if sz.x < 1.0:
		sz = ctrl._quest_toast.size
	# Sit just under level-up toast band when that is visible; else same top slot.
	var y = 56.0
	if ctrl.is_level_up_toast_visible():
		y = 100.0
	ctrl._quest_toast.position = Vector2((vp.x - sz.x) * 0.5, y)



static func _tick_quest_toast(ctrl, delta: float) -> void:
	if ctrl._quest_toast_ttl <= 0.0:
		return
	ctrl._quest_toast_ttl -= delta
	if ctrl._quest_toast_ttl <= 0.0:
		ctrl.hide_quest_toast()


