extends SceneTree
## Isolated settings UI input/layout review; --capture requires private-desktop GPU runner.
var hud
var panel: Control
var body: VBoxContainer
var gs
var failures := 0
var checks := 0
var capture := false
var out_dir: String

func _init() -> void:
	call_deferred("_run")

func _expect(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	gs = root.get_node("GameSettings")
	gs.persist_enabled = false
	gs.window_layouts = {}
	gs.ui_scale = 1.0
	gs.window_mode = "windowed"
	gs.auto_pickup = false
	gs.auto_potion_hp = false
	gs.auto_potion_mp = false
	gs.hud_locked = false
	root.content_scale_size = Vector2i.ZERO
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)
	if capture: DisplayServer.window_set_size(root.size)
	out_dir = preload("res://scripts/asset/art_paths.gd").review_path("settings")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var bg := ColorRect.new()
	bg.color = Color("202c30")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	hud = load("res://scenes/ui/game_hud.tscn").instantiate()
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _settle()
	hud._toggle_window("system")
	await _settle()
	panel = hud._windows["system"]
	body = panel.get_meta("body")
	panel.global_position = Vector2(240, 120)
	var footer: Control = panel.find_child("SettingsFooter", true, false)
	var footer_position := footer.global_position
	for tab in ["video", "audio", "game", "keys", "system"]:
		await _tab(tab)
		_expect(_content_fits(), "%s controls fit the content width" % tab)
		_expect(footer.global_position == footer_position, "%s footer stays fixed" % tab)
		await _shot(tab)
	await _tab("game")
	var before: bool = gs.show_npc_names
	await _click(_check("显示 NPC 名称"))
	_expect(gs.show_npc_names != before, "visibility checkbox updates its setting")
	for section in ["display", "assist", "hud"]:
		await _game_section(section)
		_expect(_content_fits(), "%s game group has no horizontal overflow" % section)
		await _shot("game_" + section)
	await _game_section("assist")
	var filters := body.find_children("*", "OptionButton", true, false)
	_expect(filters.size() == 1 and filters[0].disabled, "pickup filter disabled when automatic pickup is off")
	await _click(_check("自动拾取"))
	_expect(gs.auto_pickup and not filters[0].disabled, "pickup toggle immediately enables its filter")
	var potions := body.find_children("*", "SpinBox", true, false)
	var hp_spin: SpinBox = potions[1]
	_expect(not hp_spin.editable, "HP threshold disabled while auto potion is off")
	await _click(_check("生命药水"))
	_expect(gs.auto_potion_hp and hp_spin.editable, "HP toggle enables its threshold")
	hp_spin.value = 55
	_expect(gs.auto_potion_hp_pct == 55, "HP threshold writes through existing setting API")
	await _tab("audio")
	var sliders := body.find_children("*", "HSlider", true, false)
	var slider: HSlider = sliders[0]
	var point := slider.get_global_rect().position + Vector2(slider.size.x * 0.3, slider.size.y * 0.5)
	await _pointer(point, true)
	await _pointer(point, false)
	_expect(gs.master_volume >= 20 and gs.master_volume <= 40, "master volume responds to pointer")
	_expect(slider.get_parent().get_child(2).text == "%d%%" % gs.master_volume, "volume value stays in sync")
	await _tab("keys")
	var button: Button = _binding("inventory")
	await _click(button)
	_expect(hud._waiting_bind == "inventory", "key button enters capture mode")
	await _key(KEY_Q)
	_expect(gs.key_for("inventory") == KEY_Q and hud._waiting_bind.is_empty(), "key capture saves selected action")
	await _click(_binding("inventory"))
	await _key(KEY_ESCAPE)
	_expect(gs.key_for("inventory") == KEY_Q and hud._waiting_bind.is_empty(), "Escape cancels key capture")
	await _click(_binding("inventory"))
	await _tab("audio")
	_expect(hud._waiting_bind.is_empty(), "tab switch cancels key capture")
	await _tab("keys")
	await _click(_binding("inventory"))
	panel.hide()
	_expect(hud._waiting_bind.is_empty(), "closing settings cancels key capture")
	panel.show()
	var scroll: ScrollContainer = panel.find_child("Scroll", true, false)
	scroll.scroll_vertical = 1000
	await _settle()
	_expect(footer.global_position == footer_position, "scrolling never moves the footer")
	await _tab("video")
	_expect(scroll.scroll_vertical == 0, "switching tabs starts at the top")
	await _tab("system")
	var action_names: Array = []
	for action in body.find_children("*", "Button", true, false): action_names.append(action.text)
	var expected_actions := ["内容编辑器", "返回角色选择", "返回登录", "生成假玩家", "创建调试队伍", "仓库", "好友", "邮件", "制作", "表情", "战斗日志", "称号", "成就", "公会", "拍卖", "日常任务", "进入试炼洞窟", "清除标记", "召唤宠物", "收回宠物", "关闭所有窗口"]
	_expect(expected_actions.all(func(label): return action_names.has(label)), "grouped system page keeps all existing actions")
	_expect(not panel.find_child("ResetAllSettings", true, false).visible, "system actions do not show unrelated settings reset")
	# Opening at 130% must fit a small display without clipped controls.
	root.size = Vector2i(900, 700)
	if capture: DisplayServer.window_set_size(root.size)
	gs.set_ui_scale(1.3)
	await _settle()
	for tab in ["video", "audio", "game", "keys", "system"]:
		await _tab(tab)
		_expect(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(panel.get_global_rect()), "%s window fits 900x700 at 130%%" % tab)
		_expect(_content_fits(), "%s content fits at 130%%" % tab)
		await _shot("compact_" + tab)
	var title: Control = panel.find_child("TitleBar", true, false)
	var start := panel.global_position
	var grip_point := title.get_global_rect().get_center()
	var hover := InputEventMouseMotion.new()
	hover.position = grip_point
	hover.global_position = grip_point
	Input.parse_input_event(hover)
	await process_frame
	await _pointer(grip_point, true)
	var motion := InputEventMouseMotion.new()
	motion.position = grip_point + Vector2(-40, -20)
	motion.global_position = motion.position
	motion.relative = Vector2(-40, -20)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await process_frame
	await _pointer(motion.position, false)
	_expect(panel.global_position.distance_to(start) > 15.0, "frameless title remains draggable at 130%")
	var head: HBoxContainer = title.get_child(0)
	await _click(head.get_child(head.get_child_count() - 1))
	_expect(not panel.visible, "unframed close button responds to pointer")
	hud.queue_free()
	await _settle()
	print("test_settings_layout: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _tab(id: String) -> void:
	var tabs: HBoxContainer = panel.get_meta("system_tabs")
	for i in hud.SYSTEM_TABS.size():
		if hud.SYSTEM_TABS[i][1] == id:
			await _click(tabs.get_child(i))
			break
	await _settle()

func _game_section(id: String) -> void:
	for button in panel.find_child("GameSettingsTabs", true, false).get_children():
		if button.get_meta("section") == id:
			await _click(button)
			break
	await _settle()

func _check(label: String) -> Control:
	for button in body.find_children("*", "CheckBox", true, false):
		if button.text == label: return button
	return null

func _binding(action: String) -> Button:
	for button in body.find_children("*", "Button", true, false):
		if button.get_meta("binding_action", "") == action: return button
	return null

func _content_fits() -> bool:
	var scroll: Control = panel.find_child("Scroll", true, false)
	var bounds := scroll.get_global_rect()
	for child in body.find_children("*", "Control", true, false):
		# OptionButton popup internals are separate Window coordinates, not content.
		if child.get_viewport() != body.get_viewport() or not child.is_visible_in_tree(): continue
		if child is BaseButton or child is Range:
			var rect: Rect2 = child.get_global_rect()
			if rect.position.x < bounds.position.x - 1 or rect.end.x > bounds.end.x + 1:
				print("OVERFLOW ", child.name, " ", rect, " outside ", bounds)
				return false
	return true

func _click(control: Control) -> void:
	if control == null:
		_expect(false, "click target exists")
		return
	var point := control.get_global_rect().get_center()
	await _pointer(point, true)
	await _pointer(point, false)

func _pointer(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	await process_frame

func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _shot(label: String) -> void:
	if not capture: return
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(out_dir.path_join(label + ".png"))
	image.get_region(Rect2i(panel.get_global_rect().grow(4))).save_png(out_dir.path_join(label + "_detail.png"))
