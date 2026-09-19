extends RefCounted
## UI panel: chat log, NPC chat, DPS meter, combat log.

var ctrl
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const CombatLogScript = preload("res://scripts/game/combat_log.gd")
const ChatTimestampUtil = preload("res://scripts/ui/chat_timestamp_util.gd")
const CHAT_HISTORY_MAX := 200
const CHAT_CHANNELS := [
	["全部", "all"],
	["附近", "nearby"],
	["私聊", "whisper"],
	["队伍", "party"],
	["血盟", "clan"],
	["交易", "trade"],
	["同盟", "alliance"],
	["战斗", "combat"],
]

func append_chat(speaker: String, msg: String) -> void:
	_push_chat(ctrl._chat_channel if ctrl._chat_channel != "all" else "all", speaker, msg)


func append_system(msg: String) -> void:
	_push_chat("system", "系统", msg)



func _ensure_npc_chat() -> void:
	if ctrl._npc_chat != null and is_instance_valid(ctrl._npc_chat):
		return
	var panel = PanelContainer.new()
	panel.set_script(HudDrag)
	panel.name = "NpcChat"
	panel.screen_margin = 4.0
	panel.min_size = Vector2(280, 220)
	panel.default_size = Vector2(380, 400)
	panel.initial_dock = "none"
	panel.drag_anywhere = true
	panel.visible = false
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(280, 220)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl.add_child(panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(marg)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marg.add_child(vbox)
	var head = HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)
	var title_l = Label.new()
	title_l.text = "对话"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title_l)
	var close_btn = Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(ctrl.hide_npc_dialogue)
	head.add_child(close_btn)
	vbox.add_child(L2Style.hairline())
	var name_l = Label.new()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", L2Style.COL_TITLE)
	name_l.add_theme_constant_override("outline_size", 3)
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_l)
	var face_tex = TextureRect.new()
	face_tex.name = "Face"
	face_tex.visible = false
	face_tex.custom_minimum_size = Vector2(96, 96)
	face_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(face_tex)
	vbox.add_child(L2Style.hairline())
	# Body scroll
	var scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(scroll)
	var body_rtl = RichTextLabel.new()
	body_rtl.name = "Body"
	body_rtl.bbcode_enabled = true
	body_rtl.fit_content = true
	body_rtl.scroll_active = false
	body_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	L2Style.style_body_rtl(body_rtl)
	scroll.add_child(body_rtl)
	var opts = VBoxContainer.new()
	opts.name = "Options"
	opts.add_theme_constant_override("separation", 4)
	opts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opts.size_flags_vertical = Control.SIZE_SHRINK_END
	opts.custom_minimum_size = Vector2(0, 88)
	vbox.add_child(opts)
	var foot = Control.new()
	foot.name = "FiligreePad"
	foot.custom_minimum_size = Vector2(0, 12)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(foot)
	panel.set_meta("base_size", Vector2(380, 400))
	ctrl._npc_chat = panel
	ctrl._npc_chat_name = name_l
	ctrl._npc_chat_body = body_rtl
	ctrl._npc_chat_options = opts
	ctrl._npc_chat_face = face_tex
	ctrl._apply_l2_chrome(panel)



func _place_npc_chat() -> void:
	if ctrl._npc_chat == null or not ctrl._npc_chat.visible:
		return
	var vp = ctrl.get_viewport().get_visible_rect().size
	var base: Vector2 = ctrl._npc_chat.get_meta("base_size", Vector2(380, 400))
	if ctrl._npc_chat.size.x < 64.0 or ctrl._npc_chat.size.y < 64.0:
		ctrl._npc_chat.size = base
	# Fixed left-ish like classic L2 Chat
	ctrl._npc_chat.global_position = Vector2(24, clampf((vp.y - ctrl._npc_chat.size.y) * 0.35, 48, vp.y - ctrl._npc_chat.size.y - 24))



func _push_chat(channel: String, speaker: String, msg: String) -> void:
	var color = "#c9a66b"
	match channel:
		"system":
			color = "#a8a890"
		"nearby":
			color = "#9ec9ff"
		"whisper":
			color = "#e0a0ff"
		"party":
			color = "#6bc98a"
		"clan":
			color = "#6ba0c9"
		"trade":
			color = "#c9c26b"
		"alliance":
			color = "#c96bb0"
		"combat":
			color = "#e08060"
		_:
			color = "#c9a66b"
	var ts = ChatTimestampUtil.format_now()
	ctrl._chat_history.append({
		"channel": channel,
		"speaker": speaker,
		"msg": msg,
		"color": color,
		"ts": ts,
	})
	if ctrl._chat_history.size() > CHAT_HISTORY_MAX:
		ctrl._chat_history = ctrl._chat_history.slice(ctrl._chat_history.size() - CHAT_HISTORY_MAX)
	if _chat_visible(channel):
		ctrl.chat_log.append_text(_format_chat_bbcode(color, speaker, msg, ts))


func _format_chat_bbcode(color: String, speaker: String, msg: String, ts: String = "") -> String:
	var line = "[color=%s]%s[/color]: %s\n" % [color, speaker, msg]
	if GameSettingsScript.flag("show_chat_timestamps", true) and not str(ts).is_empty():
		return "%s %s" % [ts, line]
	return line


func _chat_visible(channel: String) -> bool:
	if ctrl._chat_channel == "all":
		return true
	# System chatter stays on 全部 only, so other tabs filter cleanly.
	if channel == "system":
		return false
	return channel == ctrl._chat_channel


func _rebuild_chat_log() -> void:
	ctrl.chat_log.clear()
	for row in ctrl._chat_history:
		var ch = str(row.get("channel", "all"))
		if not _chat_visible(ch):
			continue
		ctrl.chat_log.append_text(_format_chat_bbcode(
			str(row.get("color", "#c9a66b")),
			str(row.get("speaker", "")),
			str(row.get("msg", "")),
			str(row.get("ts", "")),
		))


func _on_chat_submitted(text: String) -> void:
	var t = text.strip_edges()
	if t.is_empty():
		return
	var channel = ctrl._chat_channel
	var body = t
	var whisper_to = ""
	# Prefixes override current tab.
	if t.begins_with("/w ") or t.begins_with("/W "):
		channel = "whisper"
		var rest = t.substr(3).strip_edges()
		var sp = rest.find(" ")
		if sp <= 0:
			append_system("私聊格式：/w 名字 内容")
			ctrl.chat_input.clear()
			return
		whisper_to = rest.substr(0, sp).strip_edges()
		body = rest.substr(sp + 1).strip_edges()
	elif t.begins_with(char(34)) and t.length() > 1:
		# "Name message
		channel = "whisper"
		var rest2 = t.substr(1).strip_edges()
		var sp2 = rest2.find(" ")
		if sp2 <= 0:
			append_system("私聊格式：/w 名字 内容")
			ctrl.chat_input.clear()
			return
		whisper_to = rest2.substr(0, sp2).strip_edges()
		body = rest2.substr(sp2 + 1).strip_edges()
	elif t.begins_with("~"):
		channel = "nearby"
		body = t.substr(1).strip_edges()
	elif t.begins_with("!"):
		channel = "all"
		body = t.substr(1).strip_edges()
		if not body.is_empty():
			body = "（喊）" + body
	elif t.begins_with("#"):
		channel = "party"
		body = t.substr(1).strip_edges()
	elif t.begins_with("@"):
		channel = "clan"
		body = t.substr(1).strip_edges()
	elif t.begins_with("+"):
		channel = "trade"
		body = t.substr(1).strip_edges()
	elif t.begins_with("$"):
		channel = "alliance"
		body = t.substr(1).strip_edges()
	elif ctrl._chat_channel == "whisper":
		# On whisper tab without /w: need a prior target — prompt.
		append_system("私聊请用：/w 名字 内容")
		ctrl.chat_input.clear()
		return
	elif ctrl._chat_channel == "all":
		# Default typing on 全部 = shout
		channel = "all"
	elif ctrl._chat_channel == "nearby":
		channel = "nearby"
	if body.is_empty():
		ctrl.chat_input.clear()
		return
	ctrl._chat_channel = channel if channel != "whisper" else "whisper"
	_highlight_chat_tab(ctrl._chat_channel)
	# Prefer server-authoritative chat (nearby range, whisper stub echo).
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_chat"):
		ctrl._world_combat.request_chat(channel, body, whisper_to)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_chat"):
			_apply_chat_result_locally(srv.try_chat(channel, body, whisper_to))
		else:
			var who: String = str(Net.session().active_character().get("name", ""))
			if who.is_empty():
				who = "你"
			_push_chat(channel, who, body)
	if not _chat_visible(channel):
		_rebuild_chat_log()
	ctrl.chat_input.clear()



func apply_chat_message(action: Dictionary) -> void:
	var channel = str(action.get("channel", "all"))
	var speaker = str(action.get("speaker", ""))
	var msg = str(action.get("text", "")).strip_edges()
	if msg.is_empty():
		return
	if channel == "whisper":
		var target = str(action.get("target", "")).strip_edges()
		var is_self = bool(action.get("self", false))
		if is_self and not target.is_empty():
			speaker = "%s → %s" % [speaker, target]
		elif not is_self and not target.is_empty():
			speaker = "%s → %s" % [speaker, target]
	_push_chat(channel, speaker if not speaker.is_empty() else "?", msg)
	if channel != ctrl._chat_channel and ctrl._chat_channel != "all":
		# Nudge: whisper/nearby always visible on 全部; optional flash ignored.
		pass



func _apply_chat_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"chat_message":
				apply_chat_message(action)
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					append_system(msg)
			"remote_spawn":
				if ctrl._world_combat != null and ctrl._world_combat.has_method("_upsert_remote_marker"):
					var rp: Variant = action.get("player", {})
					if typeof(rp) == TYPE_DICTIONARY:
						ctrl._world_combat._upsert_remote_marker(rp)
			"remote_despawn":
				if ctrl._world_combat != null and ctrl._world_combat.has_method("_remove_remote_marker"):
					ctrl._world_combat._remove_remote_marker(str(action.get("player_id", "")))



func _build_chat_tabs() -> void:
	for c in ctrl.chat_tabs.get_children():
		c.queue_free()
	for item in CHAT_CHANNELS:
		var btn = Button.new()
		btn.text = str(item[0])
		btn.toggle_mode = false
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(52, 24)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var channel = str(item[1])
		btn.pressed.connect(_on_chat_tab.bind(channel))
		ctrl.chat_tabs.add_child(btn)
	_highlight_chat_tab("all")


func _on_chat_tab(channel: String) -> void:
	ctrl._chat_channel = channel
	_highlight_chat_tab(channel)
	_rebuild_chat_log()


func _highlight_chat_tab(channel: String) -> void:
	for i in range(ctrl.chat_tabs.get_child_count()):
		var btn = ctrl.chat_tabs.get_child(i) as Button
		if btn == null:
			continue
		var id = str(CHAT_CHANNELS[i][1])
		var on = id == channel
		btn.modulate = Color(1.15, 1.05, 0.75) if on else Color(0.85, 0.85, 0.9)
		btn.disabled = false


func _refresh_dps_meter_visibility() -> void:
	_ensure_dps_meter()
	if ctrl._dps_meter_panel == null:
		return
	var gs = null
	var Settings = load("res://scripts/game/game_settings.gd")
	if Settings != null and Settings.has_method("get_i"):
		gs = Settings.get_i()
	var setting_on = true
	if gs != null and "show_dps_meter" in gs:
		setting_on = bool(gs.show_dps_meter)
	var DpsUtil = preload("res://scripts/ui/dps_meter_util.gd")
	# Hide when idle; show when active (or setting forces idle zero — we hide).
	ctrl._dps_meter_panel.visible = DpsUtil.should_show(setting_on, ctrl._dps_meter_active, false)



func _ensure_dps_meter() -> void:
	if ctrl._dps_meter_panel != null and is_instance_valid(ctrl._dps_meter_panel):
		return
	_build_dps_meter()



func _build_dps_meter() -> void:
	if ctrl._dps_meter_panel != null and is_instance_valid(ctrl._dps_meter_panel):
		return
	ctrl._dps_meter_panel = PanelContainer.new()
	ctrl._dps_meter_panel.name = "DpsMeterPanel"
	ctrl._dps_meter_panel.set_script(HudDrag)
	ctrl._dps_meter_panel.screen_margin = 4.0
	ctrl._dps_meter_panel.min_size = Vector2(88, 28)
	ctrl._dps_meter_panel.default_size = Vector2(110, 32)
	ctrl._dps_meter_panel.initial_dock = "none"
	ctrl._dps_meter_panel.drag_anywhere = true
	ctrl._dps_meter_panel.resizable = false
	ctrl.add_child(ctrl._dps_meter_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 8)
	marg.add_theme_constant_override("margin_top", 4)
	marg.add_theme_constant_override("margin_right", 8)
	marg.add_theme_constant_override("margin_bottom", 4)
	ctrl._dps_meter_panel.add_child(marg)
	ctrl._dps_meter_label = Label.new()
	ctrl._dps_meter_label.name = "DpsMeterLabel"
	ctrl._dps_meter_label.text = "DPS 0"
	ctrl._dps_meter_label.add_theme_font_size_override("font_size", 13)
	ctrl._dps_meter_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
	ctrl._dps_meter_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.9))
	ctrl._dps_meter_label.add_theme_constant_override("outline_size", 2)
	ctrl._dps_meter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marg.add_child(ctrl._dps_meter_label)
	if ctrl.has_method("_apply_l2_chrome"):
		ctrl._apply_l2_chrome(ctrl._dps_meter_panel)
	ctrl._dps_meter_panel.visible = false
	ctrl.call_deferred("_nudge_dps_meter")



func _nudge_dps_meter() -> void:
	if ctrl._dps_meter_panel == null:
		return
	ctrl._dps_meter_panel.size = Vector2(110, 32)
	var vp = ctrl.get_viewport_rect().size
	# Near combat log / bottom-left.
	ctrl._dps_meter_panel.global_position = Vector2(12, maxf(8.0, vp.y - 120.0))



func _ensure_combat_log() -> void:
	if ctrl._combat_log == null:
		ctrl._combat_log = CombatLogScript.new()



func _build_combat_log_panel() -> void:
	_ensure_combat_log()
	ctrl._combat_log_panel = PanelContainer.new()
	ctrl._combat_log_panel.name = "CombatLogPanel"
	ctrl._combat_log_panel.set_script(HudDrag)
	ctrl._combat_log_panel.screen_margin = 4.0
	ctrl._combat_log_panel.min_size = Vector2(280, 200)
	ctrl._combat_log_panel.default_size = Vector2(320, 290)
	ctrl._combat_log_panel.initial_dock = "none"
	ctrl._combat_log_panel.drag_anywhere = true
	ctrl.add_child(ctrl._combat_log_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 8)
	ctrl._combat_log_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "CombatLogTitle"
	title.text = "战斗日志"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var clear_btn = Button.new()
	clear_btn.text = "清除"
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(_on_combat_log_clear)
	head.add_child(clear_btn)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._combat_log_panel.visible = false)
	head.add_child(close_btn)
	ctrl._combat_log_filter_row = HBoxContainer.new()
	ctrl._combat_log_filter_row.name = "CombatLogFilters"
	ctrl._combat_log_filter_row.add_theme_constant_override("separation", 8)
	outer.add_child(ctrl._combat_log_filter_row)
	_build_combat_log_filters()
	ctrl._combat_log_scroll = ScrollContainer.new()
	ctrl._combat_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ctrl._combat_log_scroll.custom_minimum_size = Vector2(0, 180)
	ctrl._combat_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(ctrl._combat_log_scroll)
	ctrl._combat_log_body = VBoxContainer.new()
	ctrl._combat_log_body.name = "CombatLogBody"
	ctrl._combat_log_body.add_theme_constant_override("separation", 2)
	ctrl._combat_log_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl._combat_log_scroll.add_child(ctrl._combat_log_body)
	ctrl._combat_log_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._combat_log_panel)
	_refresh_combat_log_panel()
	ctrl.call_deferred("_nudge_combat_log")



func _nudge_combat_log() -> void:
	if ctrl._combat_log_panel == null:
		return
	ctrl._combat_log_panel.size = Vector2(320, 290)
	var vp = ctrl.get_viewport_rect().size
	ctrl._combat_log_panel.global_position = Vector2(12, maxi(8, int(vp.y * 0.35)))



func _toggle_combat_log_panel(force_open: bool = false) -> void:
	if ctrl._combat_log_panel == null:
		_build_combat_log_panel()
	if force_open:
		ctrl._combat_log_panel.visible = true
	else:
		ctrl._combat_log_panel.visible = not ctrl._combat_log_panel.visible
	if ctrl._combat_log_panel.visible:
		_refresh_combat_log_panel()
		ctrl._combat_log_panel.move_to_front()
		ctrl.call_deferred("_nudge_combat_log")



func _on_combat_log_clear() -> void:
	_ensure_combat_log()
	ctrl._combat_log.clear()
	_refresh_combat_log_panel()



func _refresh_combat_log_panel() -> void:
	if ctrl._combat_log_body == null:
		return
	_ensure_combat_log()
	for c in ctrl._combat_log_body.get_children():
		c.queue_free()
	var flags = _combat_log_filter_flags()
	var rows: PackedStringArray = ctrl._combat_log.filtered_lines(flags)
	if rows.is_empty():
		var empty = Label.new()
		empty.text = "（暂无战斗记录）" if ctrl._combat_log.size() == 0 else "（当前筛选无记录）"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ctrl._combat_log_body.add_child(empty)
	else:
		for line in rows:
			var lab = Label.new()
			lab.text = str(line)
			lab.add_theme_font_size_override("font_size", 12)
			lab.add_theme_color_override("font_color", Color(0.88, 0.55, 0.42))
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ctrl._combat_log_body.add_child(lab)
	# Scroll to bottom after layout.
	if ctrl._combat_log_scroll != null:
		ctrl.call_deferred("_combat_log_scroll_to_end")



func _combat_log_filter_flags() -> Dictionary:
	var gs = GameSettingsScript.get_i()
	if gs == null:
		return {
			"show_damage": true,
			"show_heal": true,
			"show_miss": true,
			"show_kill": true,
		}
	return {
		"show_damage": bool(gs.get("combat_log_show_damage")),
		"show_heal": bool(gs.get("combat_log_show_heal")),
		"show_miss": bool(gs.get("combat_log_show_miss")),
		"show_kill": bool(gs.get("combat_log_show_kill")),
	}



func _build_combat_log_filters() -> void:
	if ctrl._combat_log_filter_row == null:
		return
	for c in ctrl._combat_log_filter_row.get_children():
		c.queue_free()
	var specs = [
		["伤害", "combat_log_show_damage"],
		["治疗", "combat_log_show_heal"],
		["未命中", "combat_log_show_miss"],
		["击杀", "combat_log_show_kill"],
	]
	var gs = GameSettingsScript.get_i()
	for spec in specs:
		var label: String = spec[0]
		var key: String = spec[1]
		var box = CheckBox.new()
		box.text = label
		box.focus_mode = Control.FOCUS_NONE
		box.button_pressed = true if gs == null else bool(gs.get(key))
		var captured_key = key
		box.toggled.connect(func(on: bool):
			var g = GameSettingsScript.get_i()
			if g != null:
				g.set_flag(captured_key, on)
			_refresh_combat_log_panel()
		)
		ctrl._combat_log_filter_row.add_child(box)



func _combat_log_scroll_to_end() -> void:
	if ctrl._combat_log_scroll == null:
		return
	await ctrl.get_tree().process_frame
	if ctrl._combat_log_scroll == null or not is_instance_valid(ctrl._combat_log_scroll):
		return
	var bar = ctrl._combat_log_scroll.get_v_scroll_bar()
	if bar != null:
		ctrl._combat_log_scroll.scroll_vertical = int(bar.max_value)


