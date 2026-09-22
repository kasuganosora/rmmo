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


func _fill_system(body: VBoxContainer) -> void:
	var gs := GameSettingsScript.get_i()
	match ctrl._system_tab:
		"audio":
			_fill_system_audio(body, gs)
		"game":
			_fill_system_game(body, gs)
		"keys":
			_fill_system_keys(body, gs)
		"system":
			ctrl._fill_system_nav(body)
		_:
			_fill_system_video(body, gs)


func _fill_system_video(body: VBoxContainer, gs: Node) -> void:
	ctrl._add_label(body, "画面设置", 14, L2Style.COL_TITLE)
	if gs == null:
		ctrl._add_label(body, "设置模块未加载。", 12, L2Style.COL_MUTED)
		return
	_add_setting_row(body, "显示模式", _make_mode_option(gs))
	var res_opt := _make_res_option(gs)
	_add_setting_row(body, "分辨率", res_opt)
	res_opt.disabled = str(gs.window_mode) != "windowed"
	_add_check(body, "垂直同步", bool(gs.vsync), func(on: bool): gs.set_vsync(on))
	_add_setting_row(body, "帧率上限", _make_fps_option(gs))
	_add_setting_row(body, "界面缩放", _make_scale_option(gs))
	_add_reset_row(body, gs)


func _fill_system_audio(body: VBoxContainer, gs: Node) -> void:
	ctrl._add_label(body, "声音设置", 14, L2Style.COL_TITLE)
	if gs == null:
		ctrl._add_label(body, "设置模块未加载。", 12, L2Style.COL_MUTED)
		return
	_add_volume_row(body, "主音量", int(gs.master_volume), func(v: int): gs.set_master_volume(v))
	_add_volume_row(body, "音乐", int(gs.bgm_volume), func(v: int): gs.set_bgm_volume(v))
	_add_volume_row(body, "音效", int(gs.sfx_volume), func(v: int): gs.set_sfx_volume(v))
	_add_volume_row(body, "环境", int(gs.ambient_volume), func(v: int): gs.set_ambient_volume(v))
	_add_check(body, "静音", bool(gs.mute), func(on: bool): gs.set_mute(on))
	_add_reset_row(body, gs)


func _fill_system_game(body: VBoxContainer, gs: Node) -> void:
	ctrl._add_label(body, "游戏设置", 14, L2Style.COL_TITLE)
	ctrl._gather_level_label = ctrl._add_label(
		body,
		"采集 Lv.%d" % maxi(ctrl._gather_level, 1),
		11,
		L2Style.COL_MUTED
	)
	if gs == null:
		ctrl._add_label(body, "设置模块未加载。", 12, L2Style.COL_MUTED)
		return
	_add_check(body, "显示 NPC 名称", bool(gs.show_npc_names), func(on: bool): gs.set_flag("show_npc_names", on))
	_add_check(body, "显示玩家名称", bool(gs.show_player_names), func(on: bool): gs.set_flag("show_player_names", on))
	_add_setting_row(body, "名牌距离", _make_nameplate_distance_spin(gs))
	_add_setting_row(body, "挂机提醒(分钟)", _make_afk_warn_minutes_spin(gs))
	_add_check(body, "显示血条", bool(gs.show_hp_bars), func(on: bool): gs.set_flag("show_hp_bars", on))
	_add_check(body, "显示伤害数字", bool(gs.show_damage_numbers), func(on: bool): gs.set_flag("show_damage_numbers", on))
	_add_check(body, "显示 DPS 计量", bool(gs.show_dps_meter), func(on: bool):
		gs.set_flag("show_dps_meter", on)
		ctrl._refresh_dps_meter_visibility()
	)
	_add_check(body, "聊天时间戳", bool(gs.show_chat_timestamps), func(on: bool):
		gs.set_flag("show_chat_timestamps", on)
		ctrl._rebuild_chat_log()
	)
	_add_check(body, "宠物助战", bool(gs.pet_assist) if "pet_assist" in gs else true, func(on: bool):
		gs.set_flag("pet_assist", on)
	)
	_add_check(body, "显示经验飘字", bool(gs.show_exp_floats), func(on: bool): gs.set_flag("show_exp_floats", on))
	_add_check(body, "显示金币飘字", bool(gs.show_gold_floats), func(on: bool): gs.set_flag("show_gold_floats", on))
	_add_check(body, "显示物品飘字", bool(gs.show_item_floats), func(on: bool): gs.set_flag("show_item_floats", on))
	_add_check(body, "暴击震屏", bool(gs.screen_shake), func(on: bool): gs.set_flag("screen_shake", on))
	_add_check(body, "战斗镜头偏移", bool(gs.combat_camera_frame), func(on: bool): gs.set_flag("combat_camera_frame", on))
	_add_check(body, "始终奔跑", bool(gs.always_run), func(on: bool): gs.set_flag("always_run", on))
	_add_check(body, "天气特效", bool(gs.weather_fx), func(on: bool): gs.set_flag("weather_fx", on))
	_add_check(body, "自动拾取", bool(gs.auto_pickup), func(on: bool): gs.set_flag("auto_pickup", on))
	_add_setting_row(body, "自动拾取过滤", _make_auto_pickup_filter_option(gs))
	_add_check(body, "低血自动喝药", bool(gs.auto_potion_hp), func(on: bool):
		if gs.has_method("set_auto_potion_hp"):
			gs.set_auto_potion_hp(on)
		else:
			gs.set_flag("auto_potion_hp", on)
	)
	_add_setting_row(body, "自动喝药 HP%", _make_auto_potion_pct_spin(gs, true))
	_add_check(body, "低蓝自动喝药", bool(gs.auto_potion_mp), func(on: bool):
		if gs.has_method("set_auto_potion_mp"):
			gs.set_auto_potion_mp(on)
		else:
			gs.set_flag("auto_potion_mp", on)
	)
	_add_setting_row(body, "自动喝药 MP%", _make_auto_potion_pct_spin(gs, false))
	_add_check(body, "锁定 HUD", bool(gs.hud_locked), func(on: bool): gs.set_flag("hud_locked", on))
	_add_check(body, "任务追踪", bool(gs.show_quest_tracker), func(on: bool):
		gs.set_flag("show_quest_tracker", on)
		ctrl._refresh_quest_tracker()
	)
	_add_setting_row(body, "镜头缩放", _make_zoom_option(gs))
	_add_setting_row(body, "小地图缩放", ctrl._make_radar_zoom_option(gs))
	var reset_lay := Button.new()
	reset_lay.text = "重置窗口位置"
	reset_lay.focus_mode = Control.FOCUS_NONE
	reset_lay.pressed.connect(func():
		gs.clear_window_layouts()
		ctrl.append_system("窗口位置已重置，下次打开按默认停靠。")
	)
	body.add_child(reset_lay)
	_add_reset_row(body, gs)


func _fill_system_keys(body: VBoxContainer, gs: Node) -> void:
	ctrl._add_label(body, "按键绑定", 14, L2Style.COL_TITLE)
	if gs == null:
		ctrl._add_label(body, "设置模块未加载。", 12, L2Style.COL_MUTED)
		return
	if not ctrl._waiting_bind.is_empty():
		ctrl._add_label(body, "请按下新按键…", 12, L2Style.COL_GOLD)
	for item in GameSettingsScript.KEYBIND_ACTIONS:
		var action := str(item[1])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lab := Label.new()
		lab.text = str(item[0])
		lab.custom_minimum_size = Vector2(96, 0)
		lab.add_theme_color_override("font_color", L2Style.COL_TEXT)
		row.add_child(lab)
		var btn := Button.new()
		btn.text = OS.get_keycode_string(int(gs.key_for(action)))
		if ctrl._waiting_bind == action:
			btn.text = "…"
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(100, 26)
		btn.pressed.connect(func():
			ctrl._waiting_bind = action
			ctrl._fill_window("system")
		)
		row.add_child(btn)
		body.add_child(row)
	_add_reset_row(body, gs)


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
	spin.suffix = "(0=关)"
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
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(96, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", L2Style.COL_TEXT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	body.add_child(row)


func _add_volume_row(body: VBoxContainer, label: String, value: int, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(72, 0)
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
	amt.text = str(value)
	amt.custom_minimum_size = Vector2(36, 0)
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt.add_theme_font_size_override("font_size", 13)
	amt.add_theme_color_override("font_color", L2Style.COL_GOLD)
	amt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.value_changed.connect(func(v: float):
		amt.text = str(int(v))
		cb.call(int(v))
	)
	row.add_child(sl)
	row.add_child(amt)
	body.add_child(row)


func _add_check(body: VBoxContainer, label: String, on: bool, cb: Callable) -> void:
	var box := CheckBox.new()
	box.text = label
	box.button_pressed = on
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	L2Style.style_check(box)
	box.toggled.connect(cb)
	body.add_child(box)


func _add_reset_row(body: VBoxContainer, gs: Node) -> void:
	body.add_child(L2Style.hairline())
	var b := Button.new()
	b.text = "恢复默认"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(96, 28)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func():
		if gs != null:
			gs.reset_defaults()
		ctrl._fill_window("system")
	)
	body.add_child(b)


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
