extends SceneTree
## Headless: EXP-gain float tip 「经验 +N」 + coalesce + TTL + world wiring.


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

	failed += _expect(hud.has_method("show_exp_gain_float"), "show_exp_gain_float API")
	failed += _expect(hud.has_method("hide_exp_gain_float"), "hide_exp_gain_float API")
	failed += _expect(hud.has_method("is_exp_gain_float_visible"), "is_exp_gain_float_visible API")
	failed += _expect(hud.has_method("get_exp_gain_float_text"), "get_exp_gain_float_text API")
	failed += _expect(hud.has_method("get_exp_gain_float_amount"), "get_exp_gain_float_amount API")

	hud.show_exp_gain_float(120)
	await process_frame
	failed += _expect(hud.is_exp_gain_float_visible(), "visible after show")
	var text0: String = hud.get_exp_gain_float_text()
	failed += _expect(text0.find("经验") >= 0, "Chinese 经验 in float")
	failed += _expect(text0.find("+120") >= 0, "+120 in float")
	failed += _expect(hud.get_exp_gain_float_amount() == 120, "amount 120")

	var tip: Control = hud.get_node_or_null("ExpGainFloat")
	failed += _expect(tip != null, "ExpGainFloat node exists")
	if tip != null:
		failed += _expect(tip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "mouse_filter IGNORE")
		failed += _expect(tip.visible, "Control visible")

	# Coalesce rapid gains (same-frame / while still showing)
	hud.show_exp_gain_float(30)
	hud.show_exp_gain_float(50)
	await process_frame
	failed += _expect(hud.get_exp_gain_float_amount() == 200, "coalesce 120+30+50=200")
	failed += _expect(hud.get_exp_gain_float_text().find("+200") >= 0, "text shows +200")

	hud.hide_exp_gain_float()
	await process_frame
	failed += _expect(not hud.is_exp_gain_float_visible(), "hidden after hide")
	failed += _expect(hud.get_exp_gain_float_amount() == 0, "amount cleared")

	# Ignore non-positive
	hud.show_exp_gain_float(0)
	hud.show_exp_gain_float(-5)
	await process_frame
	failed += _expect(not hud.is_exp_gain_float_visible(), "no show for <=0")

	# Fresh show after hide
	hud.show_exp_gain_float(42)
	await process_frame
	failed += _expect(hud.get_exp_gain_float_text() == "经验 +42", "exact 经验 +42")

	# Auto-hide after ~1.2s
	if hud.has_method("_tick_exp_float"):
		hud._tick_exp_float(1.25)
	else:
		hud._process(1.25)
	await process_frame
	failed += _expect(not hud.is_exp_gain_float_visible(), "auto-hide after ~1.2s")

	# Distinct from level-up toast
	hud.show_level_up_toast(5, 0)
	hud.show_exp_gain_float(10)
	await process_frame
	failed += _expect(hud.is_level_up_toast_visible(), "level toast still independent")
	failed += _expect(hud.is_exp_gain_float_visible(), "exp float alongside level toast")
	failed += _expect(hud.get_level_up_toast_text().find("升级") >= 0, "level toast text unchanged")
	failed += _expect(hud.get_exp_gain_float_text().find("经验") >= 0, "exp float text")

	# World routes exp_gain → show_exp_gain_float
	var world_src := FileAccess.get_file_as_string("res://scripts/game/world.gd")
	failed += _expect(world_src.find('"exp_gain"') >= 0, "world handles exp_gain")
	failed += _expect(world_src.find("_apply_exp_gain") >= 0, "world _apply_exp_gain")
	failed += _expect(world_src.find("show_exp_gain_float") >= 0, "world calls show_exp_gain_float")

	# Settings flag present
	var gs_src := FileAccess.get_file_as_string("res://scripts/game/game_settings.gd")
	failed += _expect(gs_src.find("show_exp_floats") >= 0, "settings show_exp_floats")

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
