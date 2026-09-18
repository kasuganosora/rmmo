extends SceneTree
## Headless: level-up toast API + fake level_up / skill_book_update SP note.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "game_hud.tscn loads")
	if packed == null:
		_finish(failed)
		return

	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	failed += _expect(hud.has_method("show_level_up_toast"), "show_level_up_toast API")
	failed += _expect(hud.has_method("hide_level_up_toast"), "hide_level_up_toast API")
	failed += _expect(hud.has_method("is_level_up_toast_visible"), "is_level_up_toast_visible API")
	failed += _expect(hud.has_method("get_level_up_toast_text"), "get_level_up_toast_text API")
	failed += _expect(hud.has_method("apply_level_up"), "apply_level_up API")

	# Direct toast API
	hud.show_level_up_toast(7, 0)
	await process_frame
	failed += _expect(hud.is_level_up_toast_visible(), "toast visible after show")
	var text0: String = hud.get_level_up_toast_text()
	failed += _expect(text0.find("升级！") >= 0, "Chinese 升级！ in toast")
	failed += _expect(text0.find("Lv.7") >= 0, "Lv.7 in toast")
	failed += _expect(text0.find("获得技能点") < 0, "no SP note when sp_gained=0")

	# mouse_filter ignore — must not block input
	var toast: Control = hud.get_node_or_null("LevelUpToast")
	failed += _expect(toast != null, "LevelUpToast node exists")
	if toast != null:
		failed += _expect(toast.mouse_filter == Control.MOUSE_FILTER_IGNORE, "toast mouse_filter IGNORE")
		failed += _expect(toast.visible, "toast Control visible")

	hud.hide_level_up_toast()
	await process_frame
	failed += _expect(not hud.is_level_up_toast_visible(), "hidden after hide")

	# Fake level_up action path (apply_level_up)
	hud.apply_skill_book({"known": [], "skill_points": 0})
	hud.apply_level_up(3, {"level": 3, "hp": 100, "hp_max": 100}, 0)
	await process_frame
	failed += _expect(hud.is_level_up_toast_visible(), "visible after apply_level_up")
	failed += _expect(hud.get_level_up_toast_text().find("Lv.3") >= 0, "Lv.3 after apply_level_up")

	# skill_book_update / apply_skill_book while armed → 「获得技能点」
	hud.apply_skill_book({"known": [], "skill_points": 2})
	await process_frame
	var text_sp: String = hud.get_level_up_toast_text()
	failed += _expect(text_sp.find("获得技能点") >= 0, "SP note after skill_book increase")
	failed += _expect(hud.is_level_up_toast_visible(), "still visible after SP note")

	# Direct API with sp_gained
	hud.show_level_up_toast(12, 1)
	await process_frame
	var text12: String = hud.get_level_up_toast_text()
	failed += _expect(text12.find("Lv.12") >= 0, "Lv.12")
	failed += _expect(text12.find("获得技能点") >= 0, "SP note from sp_gained arg")

	# Auto-hide after ~2s (drive _process)
	hud.show_level_up_toast(4, 0)
	await process_frame
	failed += _expect(hud.is_level_up_toast_visible(), "visible before TTL")
	# Simulate time passage via _tick_level_toast / _process
	if hud.has_method("_tick_level_toast"):
		hud._tick_level_toast(2.1)
	else:
		hud._process(2.1)
	await process_frame
	failed += _expect(not hud.is_level_up_toast_visible(), "auto-hide after ~2s")

	# World action dispatcher: fake level_up dict through apply_level_up again
	hud.apply_level_up(9, {}, 1)
	await process_frame
	failed += _expect(hud.get_level_up_toast_text().find("Lv.9") >= 0, "Lv.9 with SP")
	failed += _expect(hud.get_level_up_toast_text().find("获得技能点") >= 0, "SP on apply_level_up(..., 1)")

	# Source wiring: world routes level_up → apply_level_up
	var world_src := FileAccess.get_file_as_string("res://scripts/game/world.gd")
	failed += _expect(world_src.find('"level_up"') >= 0, "world handles level_up")
	failed += _expect(world_src.find("_apply_level_up") >= 0, "world _apply_level_up")
	failed += _expect(world_src.find("apply_level_up(lv, combat, sp_gained)") >= 0, "world passes sp_gained")

	hud.queue_free()
	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
