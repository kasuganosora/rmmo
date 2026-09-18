extends SceneTree
## Headless: AFK idle warn helper + GameSettings afk_warn_minutes (0 off / 5–60).


const AfkWarnUtil = preload("res://scripts/game/afk_warn_util.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_helper()
	failed += _test_settings()
	failed += await _test_hud_toast_api()

	if failed == 0:
		print("test_afk_warn: PASS")
		quit(0)
	else:
		print("test_afk_warn: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _test_helper() -> int:
	var failed := 0
	print("-- should_warn helper --")
	failed += _expect(not AfkWarnUtil.should_warn(100.0, 0.0, false), "threshold 0 disables")
	failed += _expect(not AfkWarnUtil.should_warn(100.0, -1.0, false), "negative threshold disables")
	failed += _expect(not AfkWarnUtil.should_warn(30.0, 60.0, false), "idle below threshold")
	failed += _expect(AfkWarnUtil.should_warn(60.0, 60.0, false), "idle == threshold warns")
	failed += _expect(AfkWarnUtil.should_warn(90.0, 60.0, false), "idle above threshold warns")
	failed += _expect(not AfkWarnUtil.should_warn(90.0, 60.0, true), "already_warned blocks")
	failed += _expect(AfkWarnUtil.clamp_minutes(0) == 0, "clamp 0 stays 0")
	failed += _expect(AfkWarnUtil.clamp_minutes(-3) == 0, "clamp negative → 0")
	failed += _expect(AfkWarnUtil.clamp_minutes(3) == 5, "clamp 3 → 5")
	failed += _expect(AfkWarnUtil.clamp_minutes(10) == 10, "clamp 10 unchanged")
	failed += _expect(AfkWarnUtil.clamp_minutes(99) == 60, "clamp 99 → 60")
	failed += _expect(AfkWarnUtil.threshold_sec_from_minutes(0) == 0.0, "threshold 0 min → 0s")
	failed += _expect(is_equal_approx(AfkWarnUtil.threshold_sec_from_minutes(10), 600.0), "10 min → 600s")
	return failed


func _test_settings() -> int:
	var failed := 0
	print("-- GameSettings afk_warn_minutes --")
	var Settings = load("res://scripts/game/game_settings.gd")
	failed += _expect(Settings != null, "game_settings loads")
	if Settings == null:
		return failed

	var gs: Node = Settings.new()
	gs.name = "GameSettingsAfkTest"
	gs.persist_enabled = false
	gs.persist_path = "user://_test_afk_warn.cfg"
	root.add_child(gs)
	gs.reset_defaults()
	failed += _expect(int(gs.afk_warn_minutes) == 10, "default afk_warn_minutes 10")

	var snap: Dictionary = gs.snapshot()
	failed += _expect(snap.has("afk_warn_minutes"), "snapshot has afk_warn_minutes")
	failed += _expect(int(snap.get("afk_warn_minutes", -1)) == 10, "snapshot default 10")

	gs.set_afk_warn_minutes(0)
	failed += _expect(int(gs.afk_warn_minutes) == 0, "set 0 disables")
	gs.set_afk_warn_minutes(3)
	failed += _expect(int(gs.afk_warn_minutes) == 5, "set 3 clamps to 5")
	gs.set_afk_warn_minutes(99)
	failed += _expect(int(gs.afk_warn_minutes) == 60, "set 99 clamps to 60")
	gs.set_afk_warn_minutes(15)
	failed += _expect(int(gs.afk_warn_minutes) == 15, "set mid 15")

	var changed := [false]
	gs.changed.connect(func(): changed[0] = true)
	gs.set_afk_warn_minutes(20)
	failed += _expect(changed[0], "setter emits changed")

	gs.persist_enabled = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))
	gs.set_afk_warn_minutes(25)
	gs.save_to_disk()

	var gs2: Node = Settings.new()
	gs2.name = "GameSettingsAfkTest2"
	gs2.persist_path = gs.persist_path
	gs2.persist_enabled = false
	root.add_child(gs2)
	gs2.load_from_disk()
	failed += _expect(int(gs2.afk_warn_minutes) == 25, "persist/load afk_warn_minutes")

	gs2.reset_defaults()
	failed += _expect(int(gs2.afk_warn_minutes) == 10, "reset restores 10")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))
	return failed


func _test_hud_toast_api() -> int:
	var failed := 0
	print("-- HUD AFK toast API --")
	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "game_hud.tscn loads")
	if packed == null:
		return failed
	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	failed += _expect(hud.has_method("show_afk_warn_toast"), "show_afk_warn_toast API")
	failed += _expect(hud.has_method("hide_afk_warn_toast"), "hide_afk_warn_toast API")
	failed += _expect(hud.has_method("is_afk_warn_toast_visible"), "is_afk_warn_toast_visible API")
	failed += _expect(hud.has_method("get_afk_warn_toast_text"), "get_afk_warn_toast_text API")
	failed += _expect(hud.has_method("_note_player_input"), "_note_player_input API")

	hud.show_afk_warn_toast(true)
	await process_frame
	failed += _expect(hud.is_afk_warn_toast_visible(), "toast visible after show")
	var text0: String = hud.get_afk_warn_toast_text()
	failed += _expect(text0.find("你已离开一段时间") >= 0, "Chinese AFK text in toast")
	failed += _expect(text0.find("坐下") >= 0, "soft sit suggestion in toast")

	var toast: Control = hud.get_node_or_null("AfkWarnToast")
	failed += _expect(toast != null, "AfkWarnToast node exists")
	if toast != null:
		failed += _expect(toast.mouse_filter == Control.MOUSE_FILTER_IGNORE, "toast mouse_filter IGNORE")

	hud.hide_afk_warn_toast()
	await process_frame
	failed += _expect(not hud.is_afk_warn_toast_visible(), "hidden after hide")

	var gs = load("res://scripts/game/game_settings.gd").get_i()
	failed += _expect(gs != null, "autoload GameSettings")
	if gs != null:
		gs.persist_enabled = false
		gs.set_afk_warn_minutes(5)

	# Force idle past threshold → one warn
	hud._last_input_sec = Time.get_ticks_msec() / 1000.0 - 400.0
	hud._afk_warned = false
	hud._tick_afk_warn(0.016)
	await process_frame
	failed += _expect(hud.is_afk_warn_toast_visible(), "tick warns after idle")
	failed += _expect(bool(hud._afk_warned), "warned flag set")

	hud.hide_afk_warn_toast()
	await process_frame
	hud._tick_afk_warn(0.016)
	failed += _expect(not hud.is_afk_warn_toast_visible(), "no re-warn same streak")

	hud._note_player_input()
	failed += _expect(not bool(hud._afk_warned), "input resets warn flag")

	# Settings 0 disables
	if gs != null:
		gs.set_afk_warn_minutes(0)
	hud._last_input_sec = Time.get_ticks_msec() / 1000.0 - 9999.0
	hud._afk_warned = false
	hud._tick_afk_warn(0.016)
	await process_frame
	failed += _expect(not hud.is_afk_warn_toast_visible(), "minutes 0 never warns")

	# System → 游戏设置 SpinBox row
	var found_row := false
	if hud.has_method("_fill_system_game") and gs != null:
		var body := VBoxContainer.new()
		hud.add_child(body)
		hud._fill_system_game(body, gs)
		await process_frame
		for c in body.get_children():
			if c is HBoxContainer:
				for cc in c.get_children():
					if cc is Label and str(cc.text).find("挂机提醒") >= 0:
						found_row = true
			elif c is Label and str(c.text).find("挂机提醒") >= 0:
				found_row = true
	failed += _expect(found_row, "游戏设置 has 挂机提醒(分钟) row")

	# Source wiring smoke
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	failed += _expect(hud_src.find("_tick_afk_warn") >= 0, "hud ticks afk warn")
	failed += _expect(hud_src.find("_note_player_input") >= 0, "hud notes input")
	failed += _expect(hud_src.find("挂机提醒(分钟)") >= 0, "settings label in source")

	hud.queue_free()
	return failed
