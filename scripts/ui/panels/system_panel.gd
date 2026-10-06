extends RefCounted
## UI module: system/settings window form — video, audio, game, keybinds and the
## reusable setting-row / option-control builders. The system-nav action list stays
## in game_hud (it toggles many sibling panels). State lives on the HUD (ctrl).

var ctrl
func _init(c):
	ctrl = c

const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const AfkWarnUtil = preload("res://scripts/game/afk_warn_util.gd")


var _game_section := "display"
var _game_tabs: HBoxContainer
var _footer_hint: Label
var _reset_button: Button


func setup_layout(panel: PanelContainer) -> void:
	var scroll: ScrollContainer = panel.find_child("Scroll", true, false)
	var host: VBoxContainer = scroll.get_parent()
	panel.visibility_changed.connect(func():
		if not panel.visible: ctrl._waiting_bind = ""
	)
	_game_tabs = HBoxContainer.new()
	_game_tabs.name = "GameSettingsTabs"
	_game_tabs.add_theme_constant_override("separation", 4)
	host.add_child(_game_tabs)
	host.move_child(_game_tabs, scroll.get_index())
	for entry in [["显示", "display"], ["操作", "assist"], ["界面", "hud"]]:
		var button := Button.new()
		button.text = entry[0]
		button.set_meta("section", entry[1])
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(80, 24)
		button.pressed.connect(_select_game_section.bind(entry[1]))
		_game_tabs.add_child(button)
	var inset := MarginContainer.new()
	inset.name = "SettingsContentInset"
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override("margin_left", 10)
	inset.add_theme_constant_override("margin_right", 12)
	inset.add_theme_constant_override("margin_top", 6)
	inset.add_theme_constant_override("margin_bottom", 10)
	var body: VBoxContainer = panel.get_meta("body")
	scroll.add_child(inset)
	body.reparent(inset)
	body.add_theme_constant_override("separation", 12)
	var footer := HBoxContainer.new()
	footer.name = "SettingsFooter"
	footer.add_theme_constant_override("separation", 12)
	footer.custom_minimum_size.y = 34
	host.add_child(L2Style.hairline())
	var footer_inset := MarginContainer.new()
	footer_inset.add_theme_constant_override("margin_left", 10)
	footer_inset.add_theme_constant_override("margin_right", 10)
	host.add_child(footer_inset)
	footer_inset.add_child(footer)
	_footer_hint = Label.new()
	_footer_hint.text = "更改自动保存"
	_footer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_hint.add_theme_font_size_override("font_size", 11)
	_footer_hint.add_theme_color_override("font_color", L2Style.COL_MUTED)
	footer.add_child(_footer_hint)
	_reset_button = Button.new()
	_reset_button.name = "ResetAllSettings"
	_reset_button.text = "恢复全部默认"
	_reset_button.tooltip_text = "恢复画面、声音、游戏选项与按键设置，并重置窗口位置。"
	_reset_button.custom_minimum_size = Vector2(116, 26)
	_reset_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reset_button.focus_mode = Control.FOCUS_NONE
	_reset_button.pressed.connect(func():
		preload("res://scripts/ui/game_window.gd").confirm_action(panel, "恢复画面、声音、游戏选项与按键，并重置窗口位置？", "确认恢复默认", func():
			var gs := GameSettingsScript.get_i()
			if gs != null: gs.reset_defaults()
			ctrl._waiting_bind = ""
			ctrl._fill_window("system")
		)
	)
	footer.add_child(_reset_button)
	_game_tabs.hide()
	ctrl._highlight_system_tabs(panel.get_meta("system_tabs"))


func style_settings_tab(button: Button, selected: bool) -> void:
	# Typography and a single underline establish hierarchy, without nested frames.
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.04 if selected else 0.0)
		if state == "hover": style.bg_color.a = 0.07
		elif state == "pressed": style.bg_color.a = 0.10
		style.border_color = L2Style.COL_GOLD if selected else Color.TRANSPARENT
		style.border_width_bottom = 2
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 4
		style.content_margin_bottom = 6
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", L2Style.COL_VALUE if selected else L2Style.COL_MUTED)
	button.add_theme_color_override("font_hover_color", L2Style.COL_VALUE)
	button.add_theme_color_override("font_pressed_color", L2Style.COL_TITLE)
	button.add_theme_font_size_override("font_size", 12)


func _select_game_section(section: String) -> void:
	if section == _game_section: return
	_game_section = section
	var panel: Control = ctrl._windows["system"]
	panel.find_child("Scroll", true, false).scroll_vertical = 0
	ctrl._fill_window("system")


func _fill_system(body: VBoxContainer) -> void:
	var gs := GameSettingsScript.get_i()
	if _game_tabs != null:
		_game_tabs.visible = ctrl._system_tab == "game"
		for button in _game_tabs.get_children():
			L2Style.style_tab_button(button, button.get_meta("section") == _game_section)
			button.add_theme_font_size_override("font_size", 11)
		_reset_button.visible = ctrl._system_tab != "system"
		_footer_hint.text = "快捷入口" if ctrl._system_tab == "system" else "更改自动保存"
	match ctrl._system_tab:
		"audio": _fill_system_audio(body, gs)
		"game": _fill_system_game(body, gs)
		"keys": _fill_system_keys(body, gs)
		"system":
			ctrl._fill_system_nav(body)
			_organize_system_actions(body)
		_: _fill_system_video(body, gs)


func _section(body: VBoxContainer, title: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	body.add_child(section)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	heading.custom_minimum_size.y = 22
	section.add_child(heading)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", L2Style.COL_GOLD)
	heading.add_child(label)
	var rule := L2Style.hairline()
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(rule)
	return section


func _check_grid(section: VBoxContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	section.add_child(grid)
	return grid


func _fill_system_video(body: VBoxContainer, gs: Node) -> void:
	if gs == null: return
	var display := _section(body, "显示")
	_add_setting_row(display, "显示模式", _make_mode_option(gs))
	var resolution := _make_res_option(gs)
	_add_setting_row(display, "分辨率", resolution)
	resolution.disabled = str(gs.window_mode) != "windowed"
	resolution.tooltip_text = "仅窗口模式可以调整分辨率。" if resolution.disabled else "游戏窗口的分辨率"
	var performance := _section(body, "性能")
	_add_setting_row(performance, "帧率上限", _make_fps_option(gs))
	var clouds := OptionButton.new()
	for label in ["低 · 简化体积云", "中 · 体积云", "高 · 精细体积云"]: clouds.add_item(label)
	clouds.select(maxi(0,["low","medium","high"].find(str(gs.cloud_quality))))
	clouds.item_selected.connect(func(index: int): gs.set_cloud_quality(["low","medium","high"][index]))
	_add_setting_row(performance, "云层画质", clouds)
	_add_check(performance, "垂直同步", bool(gs.vsync), func(on: bool): gs.set_vsync(on))
	var interface := _section(body, "界面")
	_add_setting_row(interface, "界面缩放", _make_scale_option(gs))


func _fill_system_audio(body: VBoxContainer, gs: Node) -> void:
	if gs == null: return
	var master := _section(body, "整体音量")
	_add_volume_row(master, "主音量", int(gs.master_volume), func(v: int): gs.set_master_volume(v))
	_add_check(master, "静音", bool(gs.mute), func(on: bool): gs.set_mute(on))
	var channels := _section(body, "分类音量")
	_add_volume_row(channels, "音乐", int(gs.bgm_volume), func(v: int): gs.set_bgm_volume(v))
	_add_volume_row(channels, "音效", int(gs.sfx_volume), func(v: int): gs.set_sfx_volume(v))
	_add_volume_row(channels, "环境", int(gs.ambient_volume), func(v: int): gs.set_ambient_volume(v))


func _fill_system_game(body: VBoxContainer, gs: Node) -> void:
	if gs == null: return
	match _game_section:
		"assist": _fill_game_assist(body, gs)
		"hud": _fill_game_hud(body, gs)
		_: _fill_game_display(body, gs)


func _fill_game_display(body: VBoxContainer, gs: Node) -> void:
	var names := _section(body, "名称与血条")
	var names_grid := _check_grid(names)
	_add_check(names_grid, "显示 NPC 名称", gs.show_npc_names, func(on: bool): gs.set_flag("show_npc_names", on))
	_add_check(names_grid, "显示玩家名称", gs.show_player_names, func(on: bool): gs.set_flag("show_player_names", on))
	_add_setting_row(names, "名牌距离", _make_nameplate_distance_spin(gs))
	var combat := _check_grid(_section(body, "战斗信息"))
	_add_check(combat, "显示血条", gs.show_hp_bars, func(on: bool): gs.set_flag("show_hp_bars", on))
	_add_check(combat, "显示伤害数字", gs.show_damage_numbers, func(on: bool): gs.set_flag("show_damage_numbers", on))
	_add_check(combat, "显示 DPS 计量", gs.show_dps_meter, func(on: bool):
		gs.set_flag("show_dps_meter", on)
		ctrl._refresh_dps_meter_visibility()
	)
	var gains := _check_grid(_section(body, "获得提示"))
	_add_check(gains, "经验飘字", gs.show_exp_floats, func(on: bool): gs.set_flag("show_exp_floats", on))
	_add_check(gains, "金币飘字", gs.show_gold_floats, func(on: bool): gs.set_flag("show_gold_floats", on))
	_add_check(gains, "物品飘字", gs.show_item_floats, func(on: bool): gs.set_flag("show_item_floats", on))


func _fill_game_assist(body: VBoxContainer, gs: Node) -> void:
	var movement := _section(body, "移动与提醒")
	var grid := _check_grid(movement)
	_add_check(grid, "键盘移动始终奔跑", gs.always_run, func(on: bool): gs.set_flag("always_run", on))
	_add_check(grid, "宠物助战", gs.pet_assist, func(on: bool): gs.set_flag("pet_assist", on))
	_add_setting_row(movement, "挂机提醒", _make_afk_warn_minutes_spin(gs))
	var pickup := _section(body, "拾取")
	var filter := _make_auto_pickup_filter_option(gs)
	filter.disabled = not gs.auto_pickup
	_add_check(pickup, "自动拾取", gs.auto_pickup, func(on: bool):
		gs.set_flag("auto_pickup", on)
		filter.disabled = not on
	)
	_add_setting_row(pickup, "拾取类型", filter)
	var potions := _section(body, "自动使用药水")
	_add_potion_row(potions, gs, true)
	_add_potion_row(potions, gs, false)


func _add_potion_row(body: VBoxContainer, gs: Node, hp: bool) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 30
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	var check := CheckBox.new()
	L2Style.style_check(check)
	check.text = "生命药水" if hp else "魔法药水"
	check.custom_minimum_size.x = 148
	check.set_pressed_no_signal(gs.auto_potion_hp if hp else gs.auto_potion_mp)
	row.add_child(check)
	var text := Label.new()
	text.text = "低于"
	text.add_theme_color_override("font_color", L2Style.COL_MUTED)
	row.add_child(text)
	var threshold := _make_auto_potion_pct_spin(gs, hp)
	threshold.suffix = "%"
	threshold.editable = check.button_pressed
	threshold.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	threshold.custom_minimum_size.x = 112
	row.add_child(threshold)
	check.toggled.connect(func(on: bool):
		if hp: gs.set_auto_potion_hp(on)
		else: gs.set_auto_potion_mp(on)
		threshold.editable = on
	)


func _fill_game_hud(body: VBoxContainer, gs: Node) -> void:
	var overlays := _check_grid(_section(body, "界面显示"))
	_add_check(overlays, "任务追踪", gs.show_quest_tracker, func(on: bool):
		gs.set_flag("show_quest_tracker", on)
		ctrl._refresh_quest_tracker()
	)
	_add_check(overlays, "聊天时间戳", gs.show_chat_timestamps, func(on: bool):
		gs.set_flag("show_chat_timestamps", on)
		ctrl._rebuild_chat_log()
	)
	_add_check(overlays, "锁定 HUD 位置", gs.hud_locked, func(on: bool): gs.set_flag("hud_locked", on))
	_add_check(overlays, "天气特效", gs.weather_fx, func(on: bool): gs.set_flag("weather_fx", on))
	var camera := _section(body, "镜头")
	_add_setting_row(camera, "镜头缩放", _make_zoom_option(gs))
	_add_setting_row(camera, "小地图缩放", ctrl._make_radar_zoom_option(gs))
	var effects := _check_grid(camera)
	_add_check(effects, "暴击震屏", gs.screen_shake, func(on: bool): gs.set_flag("screen_shake", on))
	_add_check(effects, "战斗镜头偏移", gs.combat_camera_frame, func(on: bool): gs.set_flag("combat_camera_frame", on))
	var layout := _section(body, "快捷栏与布局")
	var rows := OptionButton.new()
	L2Style.style_option(rows)
	for count in range(1, 4): rows.add_item("%d 排" % count)
	rows.select(gs.hotbar_rows - 1)
	rows.item_selected.connect(func(index: int): ctrl._skills_panel_logic._set_hotbar_rows(index + 1))
	_add_setting_row(layout, "快捷栏排数", rows)
	var layout_actions := HBoxContainer.new()
	layout_actions.add_theme_constant_override("separation", 12)
	layout.add_child(layout_actions)
	_add_check(layout_actions, "锁定快捷栏图标", gs.hotbar_locked, func(on: bool): ctrl._skills_panel_logic._set_hotbar_locked(on))
	var reset := Button.new()
	reset.text = "重置窗口位置"
	reset.custom_minimum_size = Vector2(130, 26)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func():
		gs.clear_window_layouts()
		ctrl.append_system("窗口位置已重置，下次打开按默认停靠。")
	)
	layout_actions.add_child(reset)


func _fill_system_keys(body: VBoxContainer, gs: Node) -> void:
	if gs == null: return
	var bindings := _section(body, "按键绑定")
	ctrl._add_label(bindings, "按下新按键，Esc 取消。" if not ctrl._waiting_bind.is_empty() else "点击右侧按键进行修改。", 12, L2Style.COL_MUTED)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	bindings.add_child(grid)
	for item in GameSettingsScript.KEYBIND_ACTIONS:
		var action := str(item[1])
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = str(item[0])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)
		var button := Button.new()
		button.text = "按键…" if ctrl._waiting_bind == action else OS.get_keycode_string(int(gs.key_for(action)))
		button.set_meta("binding_action", action)
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(76, 28)
		button.pressed.connect(func():
			ctrl._waiting_bind = action
			ctrl._fill_window("system")
		)
		row.add_child(button)
		grid.add_child(row)
	var hotbar := _section(body, "快捷栏固定按键")
	ctrl._add_label(hotbar, "第一排  1–0、-、= / F1–F12\n第二排  Ctrl+数字　　第三排  Alt+数字\n切换页  Shift+1–6 / Shift+PageUp、PageDown", 12, L2Style.COL_MUTED)


func _organize_system_actions(body: VBoxContainer) -> void:
	var groups := {"社交与玩法": [], "角色与会话": [], "工具": []}
	for child in body.get_children():
		body.remove_child(child)
		if child is Button:
			var title := "社交与玩法"
			if child.text in ["返回角色选择", "返回登录", "关闭所有窗口"]: title = "角色与会话"
			elif child.text in ["内容编辑器", "返回编辑器", "生成假玩家", "创建调试队伍"]: title = "工具"
			groups[title].append(child)
		else:
			child.queue_free()
	for title in groups:
		if groups[title].is_empty(): continue
		var section := _section(body, title)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		section.add_child(grid)
		for button in groups[title]:
			button.custom_minimum_size = Vector2(140, 28)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(button)


func _make_auto_pickup_filter_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var modes: Array = GameSettingsScript.AUTO_PICKUP_FILTERS
	var cur := str(gs.auto_pickup_filter)
	var sel := 0
	for i in range(modes.size()):
		opt.add_item(str(modes[i][0]), i)
		opt.set_item_metadata(i, str(modes[i][1]))
		if str(modes[i][1]) == cur:
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		gs.set_auto_pickup_filter(str(opt.get_item_metadata(idx)))
	)
	return opt


func _make_auto_potion_pct_spin(gs: Node, for_hp: bool) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 90
	spin.step = 1
	spin.rounded = true
	var cur: int = int(gs.auto_potion_hp_pct) if for_hp else int(gs.auto_potion_mp_pct)
	spin.value = clampi(cur, 1, 90)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float):
		if for_hp:
			if gs.has_method("set_auto_potion_hp_pct"):
				gs.set_auto_potion_hp_pct(int(v))
		else:
			if gs.has_method("set_auto_potion_mp_pct"):
				gs.set_auto_potion_mp_pct(int(v))
	)
	return spin


func _make_nameplate_distance_spin(gs: Node) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 4
	spin.max_value = 32
	spin.step = 1
	spin.rounded = true
	var cur: int = 12
	if gs != null and "nameplate_distance" in gs:
		cur = int(gs.nameplate_distance)
	spin.value = clampi(cur, 4, 32)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float):
		if gs != null and gs.has_method("set_nameplate_distance"):
			gs.set_nameplate_distance(int(v))
	)
	return spin


func _make_afk_warn_minutes_spin(gs: Node) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 60
	spin.step = 1
	spin.rounded = true
	spin.suffix = "分钟"
	spin.tooltip_text = "0 表示关闭提醒；开启后最少 5 分钟。"
	var cur: int = 10
	if gs != null and "afk_warn_minutes" in gs:
		cur = int(gs.afk_warn_minutes)
	spin.value = AfkWarnUtil.clamp_minutes(cur)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float):
		if gs != null and gs.has_method("set_afk_warn_minutes"):
			gs.set_afk_warn_minutes(int(v))
			# Reflect clamp (1–4 → 5) back into the spin.
			var clamped := int(gs.afk_warn_minutes)
			if int(spin.value) != clamped:
				spin.value = clamped
	)
	return spin


func _make_zoom_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var zooms: Array = GameSettingsScript.CAMERA_ZOOMS
	var cur := float(gs.camera_zoom)
	var sel := 1
	for i in range(zooms.size()):
		var z: float = float(zooms[i])
		opt.add_item("%d%%" % int(round(z * 100.0)), i)
		opt.set_item_metadata(i, z)
		if is_equal_approx(z, cur):
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		gs.set_camera_zoom(float(opt.get_item_metadata(idx)))
	)
	return opt


func _add_setting_row(body: VBoxContainer, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 32
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(148, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", L2Style.COL_TEXT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	if control is SpinBox:
		var field := HBoxContainer.new()
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.custom_minimum_size.x = 112
		control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		field.add_child(control)
		row.add_child(field)
	else:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(control)
	body.add_child(row)


func _add_volume_row(body: VBoxContainer, label: String, value: int, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 32
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(148, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", L2Style.COL_TEXT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 1
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	L2Style.style_slider(sl)
	var amt := Label.new()
	amt.text = "%d%%" % value
	amt.custom_minimum_size = Vector2(44, 0)
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt.add_theme_font_size_override("font_size", 13)
	amt.add_theme_color_override("font_color", L2Style.COL_GOLD)
	amt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.value_changed.connect(func(v: float):
		amt.text = "%d%%" % int(v)
		cb.call(int(v))
	)
	row.add_child(sl)
	row.add_child(amt)
	body.add_child(row)


func _add_check(body: Container, label: String, on: bool, cb: Callable) -> void:
	var box := CheckBox.new()
	box.text = label
	box.button_pressed = on
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.y = 28
	L2Style.style_check(box)
	box.add_theme_color_override("font_pressed_color", L2Style.COL_TEXT)
	box.toggled.connect(cb)
	body.add_child(box)


func _add_reset_row(_body: VBoxContainer, _gs: Node) -> void:
	# Kept for the HUD facade; reset now lives in the fixed footer.
	pass


func _make_mode_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var modes: Array = GameSettingsScript.WINDOW_MODES
	var cur := str(gs.window_mode)
	var sel := 0
	for i in range(modes.size()):
		opt.add_item(str(modes[i][0]), i)
		opt.set_item_metadata(i, str(modes[i][1]))
		if str(modes[i][1]) == cur:
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		gs.set_window_mode(str(opt.get_item_metadata(idx)))
		ctrl._fill_window("system")
	)
	return opt


func _make_res_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var cur: Vector2i = gs.resolution
	var sel := 0
	var res_list: Array = GameSettingsScript.RESOLUTIONS
	for i in range(res_list.size()):
		var r: Vector2i = res_list[i]
		opt.add_item("%d × %d" % [r.x, r.y], i)
		opt.set_item_metadata(i, r)
		if r == cur:
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		var r: Vector2i = opt.get_item_metadata(idx)
		gs.set_resolution(r)
	)
	return opt


func _make_fps_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var caps: Array = GameSettingsScript.FPS_CAPS
	var cur := int(gs.max_fps)
	var sel := 0
	for i in range(caps.size()):
		var cap: int = int(caps[i])
		opt.add_item("不限制" if cap == 0 else str(cap), i)
		opt.set_item_metadata(i, cap)
		if cap == cur:
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		gs.set_max_fps(int(opt.get_item_metadata(idx)))
	)
	return opt


func _make_scale_option(gs: Node) -> OptionButton:
	var opt := OptionButton.new()
	L2Style.style_option(opt)
	var scales: Array = GameSettingsScript.UI_SCALES
	var cur := float(gs.ui_scale)
	var sel := 1
	for i in range(scales.size()):
		var s: float = float(scales[i])
		opt.add_item("%d%%" % int(round(s * 100.0)), i)
		opt.set_item_metadata(i, s)
		if is_equal_approx(s, cur):
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		gs.set_ui_scale(float(opt.get_item_metadata(idx)))
	)
	return opt
