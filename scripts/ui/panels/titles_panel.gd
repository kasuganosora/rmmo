extends RefCounted
## UI panel: titles, daily board, achievements.

var ctrl
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const StatusPanel = preload("res://scripts/ui/panels/status_panel.gd")

func _build_titles_panel() -> void:
	ctrl._titles_panel = PanelContainer.new()
	ctrl._titles_panel.name = "TitlesPanel"
	ctrl._titles_panel.set_script(HudDrag)
	ctrl._titles_panel.screen_margin = 4.0
	ctrl._titles_panel.min_size = Vector2(300, 240)
	ctrl._titles_panel.default_size = Vector2(360, 440)
	ctrl._titles_panel.initial_dock = "none"
	ctrl._titles_panel.drag_anywhere = true
	ctrl.add_child(ctrl._titles_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._titles_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "TitlesTitle"
	title.text = "称号"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._titles_panel.visible = false)
	head.add_child(close_btn)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	outer.add_child(scroll)
	ctrl._titles_body = VBoxContainer.new()
	ctrl._titles_body.name = "TitlesBody"
	ctrl._titles_body.add_theme_constant_override("separation", 6)
	ctrl._titles_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ctrl._titles_body)
	ctrl._titles_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._titles_panel)
	_refresh_titles_panel()
	ctrl.call_deferred("_nudge_titles")



func _nudge_titles() -> void:
	if ctrl._titles_panel == null:
		return
	ctrl._titles_panel.size = Vector2(360, 440)
	var vp = ctrl.get_viewport_rect().size
	ctrl._titles_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 180)), 88)



func _toggle_titles_panel(force_open: bool = false) -> void:
	if ctrl._titles_panel == null:
		return
	if force_open:
		ctrl._titles_panel.visible = true
	else:
		ctrl._titles_panel.visible = not ctrl._titles_panel.visible
	if ctrl._titles_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_titles"):
			apply_title_update({"type": "title_update", "titles": srv.snapshot_titles()})
		_refresh_titles_panel()
		ctrl._titles_panel.move_to_front()
		ctrl.call_deferred("_nudge_titles")



func apply_title_update(action: Dictionary) -> void:
	var tv: Variant = action.get("titles", action)
	if typeof(tv) != TYPE_DICTIONARY:
		return
	var d: Dictionary = tv
	ctrl._titles_state = {
		"counters": d.get("counters", {}).duplicate(true) if typeof(d.get("counters", {})) == TYPE_DICTIONARY else {},
		"unlocked_titles": d.get("unlocked_titles", []).duplicate() if typeof(d.get("unlocked_titles", [])) == TYPE_ARRAY else [],
		"active_title": str(d.get("active_title", "")),
		"titles": d.get("titles", []).duplicate(true) if typeof(d.get("titles", [])) == TYPE_ARRAY else [],
		"kills": int(d.get("kills", 0)),
		"crafts": int(d.get("crafts", 0)),
		"deaths": int(d.get("deaths", 0)),
	}
	_refresh_name_with_title()
	if ctrl._titles_panel != null and ctrl._titles_panel.visible:
		_refresh_titles_panel()



func _build_daily_panel() -> void:
	ctrl._daily_panel = PanelContainer.new()
	ctrl._daily_panel.name = "DailyQuestPanel"
	ctrl._daily_panel.set_script(HudDrag)
	ctrl._daily_panel.screen_margin = 4.0
	ctrl._daily_panel.min_size = Vector2(280, 180)
	ctrl._daily_panel.default_size = Vector2(340, 280)
	ctrl._daily_panel.initial_dock = "none"
	ctrl._daily_panel.drag_anywhere = true
	ctrl.add_child(ctrl._daily_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._daily_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "DailyTitle"
	title.text = "日常任务"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._daily_panel.visible = false)
	head.add_child(close_btn)
	var date_lbl = Label.new()
	date_lbl.name = "DailyDateLabel"
	date_lbl.text = ""
	date_lbl.add_theme_color_override("font_color", L2Style.COL_MUTED)
	outer.add_child(date_lbl)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 180)
	outer.add_child(scroll)
	ctrl._daily_body = VBoxContainer.new()
	ctrl._daily_body.name = "DailyBody"
	ctrl._daily_body.add_theme_constant_override("separation", 6)
	ctrl._daily_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ctrl._daily_body)
	ctrl._daily_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._daily_panel)
	_refresh_daily_panel()
	ctrl.call_deferred("_nudge_daily")



func _nudge_daily() -> void:
	if ctrl._daily_panel == null:
		return
	ctrl._daily_panel.size = Vector2(340, 280)
	var vp = ctrl.get_viewport_rect().size
	ctrl._daily_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 170)), 100)



func _toggle_daily_panel(force_open: bool = false) -> void:
	if ctrl._daily_panel == null:
		return
	if force_open:
		ctrl._daily_panel.visible = true
	else:
		ctrl._daily_panel.visible = not ctrl._daily_panel.visible
	if ctrl._daily_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_daily"):
			apply_daily_board(srv.snapshot_daily())
		elif srv != null and srv.has_method("try_daily_board_list"):
			apply_daily_board({"daily": srv.try_daily_board_list(), "daily_date": ""})
		_refresh_daily_panel()
		ctrl._daily_panel.move_to_front()
		ctrl.call_deferred("_nudge_daily")



func apply_daily_board(action: Dictionary) -> void:
	var date = str(action.get("daily_date", "")).strip_edges()
	var list_v: Variant = action.get("daily", action.get("daily_quests", []))
	var list: Array = list_v if typeof(list_v) == TYPE_ARRAY else []
	if date != "" or not list.is_empty() or action.has("daily") or action.has("daily_date"):
		ctrl._daily_state = {
			"daily_date": date if date != "" else str(ctrl._daily_state.get("daily_date", "")),
			"daily": list.duplicate(true),
		}
	if ctrl._daily_panel != null and ctrl._daily_panel.visible:
		_refresh_daily_panel()



func _refresh_daily_panel() -> void:
	if ctrl._daily_body == null:
		return
	for c in ctrl._daily_body.get_children():
		c.queue_free()
	var date_lbl: Label = null
	if ctrl._daily_panel != null:
		date_lbl = ctrl._find_named_descendant(ctrl._daily_panel, "DailyDateLabel") as Label
	var ymd = str(ctrl._daily_state.get("daily_date", ""))
	if date_lbl != null:
		date_lbl.text = ("日期：%s" % ymd) if ymd != "" else "日常委托"
	var rows: Array = ctrl._daily_state.get("daily", [])
	if rows.is_empty():
		var empty = Label.new()
		empty.text = "今日暂无日常。"
		empty.add_theme_color_override("font_color", L2Style.COL_MUTED)
		ctrl._daily_body.add_child(empty)
		return
	for row_v in rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var qid = str(row.get("id", "")).strip_edges()
		var state = str(row.get("state", "available")).strip_edges()
		var box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		ctrl._daily_body.add_child(box)
		var line = HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		box.add_child(line)
		var name_lbl = Label.new()
		name_lbl.text = str(row.get("title", qid))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_lbl)
		var state_lbl = Label.new()
		var btn_text = "接取"
		match state:
			"accepted":
				state_lbl.text = "已接"
				state_lbl.add_theme_color_override("font_color", L2Style.COL_TITLE)
				btn_text = "已接"
			"done_today":
				state_lbl.text = "已完成"
				state_lbl.add_theme_color_override("font_color", L2Style.COL_MUTED)
				btn_text = "已完成"
			_:
				state_lbl.text = "可接"
				state_lbl.add_theme_color_override("font_color", L2Style.COL_TITLE)
				btn_text = "接取"
		line.add_child(state_lbl)
		var btn = Button.new()
		btn.text = btn_text
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = state != "available"
		btn.custom_minimum_size = Vector2(72, 26)
		var accept_id = qid
		btn.pressed.connect(func():
			if ctrl._world_combat != null and ctrl._world_combat.has_method("request_accept_quest"):
				ctrl._world_combat.request_accept_quest(accept_id)
			# Refresh from server after accept
			var srv = Net.server()
			if srv != null and srv.has_method("snapshot_daily"):
				apply_daily_board(srv.snapshot_daily())
			_refresh_daily_panel()
		)
		line.add_child(btn)
		var rewards = str(row.get("rewards", "")).strip_edges()
		if rewards != "":
			var rlab = Label.new()
			rlab.text = rewards
			rlab.add_theme_color_override("font_color", L2Style.COL_MUTED)
			box.add_child(rlab)



func _active_title_display_name() -> String:
	var aid = str(ctrl._titles_state.get("active_title", "")).strip_edges()
	if aid.is_empty():
		return ""
	for row in ctrl._titles_state.get("titles", []):
		if typeof(row) == TYPE_DICTIONARY and str(row.get("id", "")) == aid:
			return str(row.get("name", aid))
	var srv = Net.server()
	if srv != null and srv.get("title_catalog") != null and srv.title_catalog.has_method("title_name"):
		return str(srv.title_catalog.title_name(aid))
	return aid



func _ensure_title_under_name() -> void:
	## Thin Label under StatusPanel nameplate for equipped title (not glued into NameLabel).
	if ctrl._title_under_name != null and is_instance_valid(ctrl._title_under_name):
		return
	var panel = ctrl.get_node_or_null("%StatusPanel") as PanelContainer
	if panel == null:
		return
	var vbox = panel.find_child("StatusVBox", true, false) as VBoxContainer
	if vbox == null:
		return
	var existing = vbox.get_node_or_null("TitleUnderName") as Label
	if existing != null:
		ctrl._title_under_name = existing
	else:
		ctrl._title_under_name = Label.new()
		ctrl._title_under_name.name = "TitleUnderName"
		ctrl._title_under_name.add_theme_font_size_override("font_size", 10)
		ctrl._title_under_name.add_theme_color_override("font_color", L2Style.COL_GOLD)
		ctrl._title_under_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl._title_under_name.visible = false
		ctrl._title_under_name.text = ""
		var name_row = vbox.get_node_or_null("NameRow")
		if name_row != null:
			var idx = name_row.get_index()
			vbox.add_child(ctrl._title_under_name)
			vbox.move_child(ctrl._title_under_name, idx + 1)
		else:
			vbox.add_child(ctrl._title_under_name)
			vbox.move_child(ctrl._title_under_name, 0)
	# Slightly taller status so title line fits.
	if panel != null:
		panel.min_size = Vector2(160, 84)
		panel.default_size = Vector2(200, 100)
		panel.custom_minimum_size = Vector2(160, 84)



func _refresh_name_with_title() -> void:
	_ensure_title_under_name()
	if ctrl.name_label == null:
		return
	var base = ctrl._base_char_name.strip_edges()
	if base.is_empty():
		base = str(ctrl.name_label.text).strip_edges()
		# Strip previous suffix if re-applied without bind.
		var cut = base.find("「")
		if cut > 0:
			base = base.substr(0, cut)
		var cut2 = base.find("【")
		if cut2 > 0:
			base = base.substr(0, cut2)
		if base.is_empty():
			base = "???"
		ctrl._base_char_name = base
	var tname = _active_title_display_name()
	var gname = str(ctrl._guild_state.get("name", "")).strip_edges()
	var shown = base
	# Title lives on thin Label under nameplate; keep guild suffix on name if any.
	if not gname.is_empty():
		shown = "%s【%s】" % [shown, gname]
	ctrl.name_label.text = shown
	if ctrl._title_under_name != null:
		if tname.is_empty():
			ctrl._title_under_name.text = ""
			ctrl._title_under_name.visible = false
		else:
			ctrl._title_under_name.text = "「%s」" % tname
			ctrl._title_under_name.visible = true



func _title_unlock_hint(row: Dictionary) -> String:
	var desc = str(row.get("desc", "")).strip_edges()
	if not desc.is_empty():
		return desc
	var req_v: Variant = row.get("require", {})
	if typeof(req_v) != TYPE_DICTIONARY or (req_v as Dictionary).is_empty():
		return ""
	var parts: Array = []
	var labels = {"kills": "击杀", "crafts": "制作", "deaths": "死亡"}
	for k in (req_v as Dictionary).keys():
		var key = str(k)
		var need: int = int(req_v[k])
		var label = str(labels.get(key, key))
		parts.append("%s %d" % [label, need])
	if parts.is_empty():
		return ""
	return "解锁条件：" + " · ".join(PackedStringArray(parts))



func _refresh_titles_panel() -> void:
	if ctrl._titles_body == null:
		return
	for c in ctrl._titles_body.get_children():
		c.queue_free()
	var ctr: Dictionary = ctrl._titles_state.get("counters", {}) if typeof(ctrl._titles_state.get("counters", {})) == TYPE_DICTIONARY else {}
	var kills: int = int(ctr.get("kills", ctrl._titles_state.get("kills", 0)))
	var crafts: int = int(ctr.get("crafts", ctrl._titles_state.get("crafts", 0)))
	var deaths: int = int(ctr.get("deaths", ctrl._titles_state.get("deaths", 0)))
	ctrl._add_label(ctrl._titles_body, "进度  击杀 %d · 制作 %d · 死亡 %d" % [kills, crafts, deaths], 11, L2Style.COL_MUTED)
	var active = str(ctrl._titles_state.get("active_title", ""))
	if active.is_empty():
		ctrl._add_label(ctrl._titles_body, "当前：无（点击已解锁称号装备）", 12, L2Style.COL_TEXT)
	else:
		ctrl._add_label(ctrl._titles_body, "当前：%s（再点卸下）" % _active_title_display_name(), 12, L2Style.COL_GOLD)
	var unequip = Button.new()
	unequip.text = "卸下"
	unequip.focus_mode = Control.FOCUS_NONE
	unequip.disabled = active.is_empty()
	unequip.pressed.connect(func(): ctrl._on_title_equip(""))
	ctrl._titles_body.add_child(unequip)
	var rows: Array = ctrl._titles_state.get("titles", [])
	if rows.is_empty():
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_titles"):
			var snap: Dictionary = srv.snapshot_titles()
			rows = snap.get("titles", []) if typeof(snap.get("titles", [])) == TYPE_ARRAY else []
	if rows.is_empty():
		ctrl._add_label(ctrl._titles_body, "（暂无称号）", 12, L2Style.COL_MUTED)
		return
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var tid = str(row.get("id", "")).strip_edges()
		if tid.is_empty():
			continue
		var unlocked: bool = bool(row.get("unlocked", false))
		var is_active: bool = bool(row.get("active", false)) or tid == active
		var box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		ctrl._titles_body.add_child(box)
		var display = str(row.get("name", tid))
		if unlocked:
			var btn = Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if is_active:
				btn.text = "✓ %s  · 装备中" % display
				L2Style.style_row_button(btn, true)
				btn.pressed.connect(ctrl._on_title_equip.bind(""))
			else:
				btn.text = "○ %s" % display
				L2Style.style_row_button(btn, false)
				btn.pressed.connect(ctrl._on_title_equip.bind(tid))
			box.add_child(btn)
			var desc = str(row.get("desc", "")).strip_edges()
			if not desc.is_empty():
				ctrl._add_label(box, desc, 11, L2Style.COL_MUTED)
		else:
			var nm = Label.new()
			nm.text = "🔒 %s" % display
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.add_theme_font_size_override("font_size", 13)
			nm.add_theme_color_override("font_color", L2Style.COL_MUTED)
			nm.modulate = Color(0.72, 0.72, 0.72, 1.0)
			box.add_child(nm)
			var hint = _title_unlock_hint(row)
			if not hint.is_empty():
				ctrl._add_label(box, hint, 11, L2Style.COL_MUTED)



func _apply_title_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)
			"title_update":
				apply_title_update(action)



func _build_achievements_panel() -> void:
	ctrl._achievements_panel = PanelContainer.new()
	ctrl._achievements_panel.name = "AchievementsPanel"
	ctrl._achievements_panel.set_script(HudDrag)
	ctrl._achievements_panel.screen_margin = 4.0
	ctrl._achievements_panel.min_size = Vector2(300, 240)
	ctrl._achievements_panel.default_size = Vector2(360, 440)
	ctrl._achievements_panel.initial_dock = "none"
	ctrl._achievements_panel.drag_anywhere = true
	ctrl.add_child(ctrl._achievements_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._achievements_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "AchievementsTitle"
	title.text = "成就"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._achievements_panel.visible = false)
	head.add_child(close_btn)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	outer.add_child(scroll)
	ctrl._achievements_body = VBoxContainer.new()
	ctrl._achievements_body.name = "AchievementsBody"
	ctrl._achievements_body.add_theme_constant_override("separation", 6)
	ctrl._achievements_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ctrl._achievements_body)
	ctrl._achievements_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._achievements_panel)
	_refresh_achievements_panel()
	ctrl.call_deferred("_nudge_achievements")



func _nudge_achievements() -> void:
	if ctrl._achievements_panel == null:
		return
	ctrl._achievements_panel.size = Vector2(360, 440)
	var vp = ctrl.get_viewport_rect().size
	ctrl._achievements_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 180)), 100)



func _toggle_achievements_panel(force_open: bool = false) -> void:
	if ctrl._achievements_panel == null:
		return
	if force_open:
		ctrl._achievements_panel.visible = true
	else:
		ctrl._achievements_panel.visible = not ctrl._achievements_panel.visible
	if ctrl._achievements_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_achievements"):
			apply_achievement_update({"type": "achievement_update", "achievements": srv.snapshot_achievements()})
		_refresh_achievements_panel()
		ctrl._achievements_panel.move_to_front()
		ctrl.call_deferred("_nudge_achievements")



func apply_achievement_update(action: Dictionary) -> void:
	var av: Variant = action.get("achievements", action)
	if typeof(av) != TYPE_DICTIONARY:
		return
	var d: Dictionary = av
	ctrl._achievements_state = {
		"counters": d.get("counters", {}).duplicate(true) if typeof(d.get("counters", {})) == TYPE_DICTIONARY else {},
		"unlocked_achievements": d.get("unlocked_achievements", []).duplicate() if typeof(d.get("unlocked_achievements", [])) == TYPE_ARRAY else [],
		"achievements": d.get("achievements", []).duplicate(true) if typeof(d.get("achievements", [])) == TYPE_ARRAY else [],
		"kills": int(d.get("kills", 0)),
		"gathers": int(d.get("gathers", 0)),
		"level": int(d.get("level", 1)),
		"party": int(d.get("party", 0)),
	}
	if ctrl._achievements_panel != null and ctrl._achievements_panel.visible:
		_refresh_achievements_panel()



func _achievement_unlock_hint(row: Dictionary) -> String:
	var desc = str(row.get("desc", "")).strip_edges()
	if not desc.is_empty():
		return desc
	var req_v: Variant = row.get("require", {})
	if typeof(req_v) != TYPE_DICTIONARY:
		return ""
	var labels = {"kills": "击杀", "gathers": "采集", "level": "等级", "party": "组队"}
	var parts: PackedStringArray = PackedStringArray()
	for k in (req_v as Dictionary).keys():
		var key = str(k)
		var need: int = int(req_v[k])
		var label = str(labels.get(key, key))
		parts.append("%s %d" % [label, need])
	if parts.is_empty():
		return ""
	return "解锁条件：" + " · ".join(parts)



func _refresh_achievements_panel() -> void:
	if ctrl._achievements_body == null:
		return
	for c in ctrl._achievements_body.get_children():
		c.queue_free()
	var ctr: Dictionary = ctrl._achievements_state.get("counters", {}) if typeof(ctrl._achievements_state.get("counters", {})) == TYPE_DICTIONARY else {}
	var kills: int = int(ctr.get("kills", ctrl._achievements_state.get("kills", 0)))
	var gathers: int = int(ctr.get("gathers", ctrl._achievements_state.get("gathers", 0)))
	var level: int = int(ctr.get("level", ctrl._achievements_state.get("level", 1)))
	var party: int = int(ctr.get("party", ctrl._achievements_state.get("party", 0)))
	ctrl._add_label(ctrl._achievements_body, "进度  击杀 %d · 采集 %d · 等级 %d · 组队 %d" % [kills, gathers, level, party], 11, L2Style.COL_MUTED)
	var rows: Array = ctrl._achievements_state.get("achievements", [])
	if rows.is_empty():
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_achievements"):
			var snap: Dictionary = srv.snapshot_achievements()
			rows = snap.get("achievements", []) if typeof(snap.get("achievements", [])) == TYPE_ARRAY else []
	if rows.is_empty():
		ctrl._add_label(ctrl._achievements_body, "（暂无成就）", 12, L2Style.COL_MUTED)
		return
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var aid = str(row.get("id", "")).strip_edges()
		if aid.is_empty():
			continue
		var unlocked: bool = bool(row.get("unlocked", false))
		var box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		ctrl._achievements_body.add_child(box)
		var letter = str(row.get("letter", "")).strip_edges()
		var display = str(row.get("name", aid))
		if not letter.is_empty():
			display = "[%s] %s" % [letter, display]
		var nm = Label.new()
		if unlocked:
			nm.text = "✓ %s" % display
			nm.add_theme_color_override("font_color", L2Style.COL_GOLD)
		else:
			nm.text = "🔒 %s" % display
			nm.add_theme_color_override("font_color", L2Style.COL_MUTED)
			nm.modulate = Color(0.72, 0.72, 0.72, 1.0)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.add_theme_font_size_override("font_size", 13)
		box.add_child(nm)
		if unlocked:
			var desc = str(row.get("desc", "")).strip_edges()
			if not desc.is_empty():
				ctrl._add_label(box, desc, 11, L2Style.COL_MUTED)
			var rew_v: Variant = row.get("reward", {})
			if typeof(rew_v) == TYPE_DICTIONARY:
				var rg: int = int(rew_v.get("gold", 0))
				var re: int = int(rew_v.get("exp", 0))
				if rg > 0 or re > 0:
					var bits: PackedStringArray = PackedStringArray()
					if rg > 0:
						bits.append("金 %d" % rg)
					if re > 0:
						bits.append("经验 %d" % re)
					ctrl._add_label(box, "奖励：" + " · ".join(bits), 11, L2Style.COL_MUTED)
		else:
			var hint = _achievement_unlock_hint(row)
			if not hint.is_empty():
				ctrl._add_label(box, hint, 11, L2Style.COL_MUTED)


