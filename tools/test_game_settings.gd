extends SceneTree
## Headless: game settings persist, buses, HUD menu collapse, settings window.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var Settings = load("res://scripts/game/game_settings.gd")
	failed += _expect(Settings != null, "game_settings loads")
	if Settings == null:
		_finish(failed)
		return

	var gs: Node = Settings.new()
	gs.name = "GameSettingsTest"
	gs.persist_enabled = false
	gs.persist_path = "user://_test_game_settings.cfg"
	root.add_child(gs)
	gs.persist_enabled = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))
	gs.reset_defaults()
	failed += _expect(gs.window_mode == "windowed", "default windowed")
	failed += _expect(gs.master_volume == 80, "default master 80")
	failed += _expect(gs.show_npc_names == true, "default npc names")
	failed += _expect(gs.always_run == false, "default walk")
	failed += _expect(gs.volume_to_db(0) <= -79.0, "mute db")
	failed += _expect(gs.volume_to_db(100) >= -0.01, "full db")
	gs.ensure_buses()
	failed += _expect(AudioServer.get_bus_index("BGM") >= 0, "BGM bus")
	failed += _expect(AudioServer.get_bus_index("SFX") >= 0, "SFX bus")
	failed += _expect(AudioServer.get_bus_index("Ambient") >= 0, "Ambient bus")
	gs.set_master_volume(40)
	gs.set_flag("always_run", true)
	gs.set_flag("show_npc_names", false)
	gs.set_mute(true)
	failed += _expect(gs.master_volume == 40, "master set")
	failed += _expect(gs.always_run, "always_run set")
	failed += _expect(not gs.show_npc_names, "npc names off")
	var master_idx := AudioServer.get_bus_index("Master")
	failed += _expect(AudioServer.is_bus_mute(master_idx), "master muted")
	gs.save_to_disk()
	var gs2: Node = Settings.new()
	gs2.name = "GameSettingsTest2"
	gs2.persist_path = gs.persist_path
	gs2.persist_enabled = false
	root.add_child(gs2)
	gs2.load_from_disk()
	failed += _expect(gs2.master_volume == 40, "reload master")
	failed += _expect(gs2.always_run, "reload always_run")
	failed += _expect(not gs2.show_npc_names, "reload npc names")
	failed += _expect(gs2.mute, "reload mute")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))
	gs.persist_enabled = false
	gs.reset_defaults()

	var live: Node = Settings.get_i()
	failed += _expect(live != null, "autoload GameSettings")
	if live != null:
		live.persist_enabled = false
		var prev_run: bool = bool(live.always_run)
		var prev_names: bool = bool(live.show_npc_names)
		live.set_flag("always_run", true)
		failed += _expect(Settings.flag("always_run", false), "flag helper always_run")
		live.set_flag("show_npc_names", false)
		failed += _expect(not Settings.flag("show_npc_names", true), "flag helper npc names")
		live.set_flag("always_run", prev_run)
		live.set_flag("show_npc_names", prev_names)

	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "hud tscn")
	if packed == null:
		_finish(failed)
		return
	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	failed += _expect(hud.menu_row.get_child_count() == 1, "menu collapsed to 1 button")
	var launcher := hud.menu_row.get_child(0) as Button
	failed += _expect(launcher != null, "launcher button")
	if launcher != null:
		failed += _expect(launcher.text == "" or launcher.text == "菜单", "launcher uses icon (text empty or fallback)")
		failed += _expect(launcher.custom_minimum_size.x <= 48.0, "launcher compact")
	failed += _expect(hud._menu_popup != null, "menu popup built")
	hud._toggle_menu_popup()
	await process_frame
	failed += _expect(hud._menu_popup.visible, "popup opens")
	var items := hud._menu_popup.find_child("Items", true, false) as VBoxContainer
	failed += _expect(items != null and items.get_child_count() == 7, "popup has 7 items")
	hud._close_menu_popup()
	await process_frame
	failed += _expect(not hud._menu_popup.visible, "popup closes")

	hud._toggle_window("system")
	await process_frame
	var sys: PanelContainer = hud._windows.get("system")
	failed += _expect(sys != null and sys.visible, "system window open")
	failed += _expect(sys.find_child("TitleBar", true, false) != null, "system TitleBar")
	var tabs: HBoxContainer = sys.get_meta("system_tabs", null) if sys else null
	failed += _expect(tabs != null and tabs.get_child_count() == 5, "5 system tabs")
	var body: VBoxContainer = sys.get_meta("body")
	failed += _expect(body != null, "system body")
	var has_opt := false
	if body:
		for c in body.get_children():
			if c is HBoxContainer:
				for cc in c.get_children():
					if cc is OptionButton:
						has_opt = true
	failed += _expect(has_opt, "video tab has option")
	hud._on_system_tab("audio")
	await process_frame
	body = sys.get_meta("body")
	var sliders := 0
	if body:
		for c in body.get_children():
			if c is HBoxContainer:
				for cc in c.get_children():
					if cc is HSlider:
						sliders += 1
	failed += _expect(sliders >= 4, "audio tab 4 sliders got %d" % sliders)
	hud._on_system_tab("game")
	await process_frame
	body = sys.get_meta("body")
	var checks := 0
	if body:
		for c in body.get_children():
			if c is CheckBox:
				checks += 1
	failed += _expect(checks >= 6, "game tab checks got %d" % checks)
	hud._on_system_tab("system")
	await process_frame
	body = sys.get_meta("body")
	var nav_btns := 0
	if body:
		for c in body.get_children():
			if c is Button:
				nav_btns += 1
	failed += _expect(nav_btns >= 3, "system nav buttons got %d" % nav_btns)

	var Npc = load("res://scripts/game/npc_actor.gd")
	if live != null and Npc != null:
		live.persist_enabled = false
		live.set_flag("show_npc_names", false)
		var npc: Node2D = Npc.new()
		root.add_child(npc)
		npc.kind = "monster"
		npc.npc_name = "假人"
		npc.hp = 10
		npc.hp_max = 10
		npc._ensure_nameplate()
		npc._refresh_nameplate()
		failed += _expect(not npc.shows_nameplate(), "nameplate respects setting")
		live.set_flag("show_npc_names", true)
		failed += _expect(npc.shows_nameplate(), "nameplate back on")
		npc.queue_free()

	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("test_game_settings: ALL PASS")
		quit(0)
	else:
		print("test_game_settings: FAIL count=", failed)
		quit(1)
