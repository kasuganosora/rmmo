extends SceneTree
## Headless: gold-gain float tip 「金币 +N」 + coalesce + TTL + inventory delta wiring.


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

	failed += _expect(hud.has_method("show_gold_gain_float"), "show_gold_gain_float API")
	failed += _expect(hud.has_method("hide_gold_gain_float"), "hide_gold_gain_float API")
	failed += _expect(hud.has_method("is_gold_gain_float_visible"), "is_gold_gain_float_visible API")
	failed += _expect(hud.has_method("get_gold_gain_float_text"), "get_gold_gain_float_text API")
	failed += _expect(hud.has_method("get_gold_gain_float_amount"), "get_gold_gain_float_amount API")

	hud.show_gold_gain_float(80)
	await process_frame
	failed += _expect(hud.is_gold_gain_float_visible(), "visible after show")
	var text0: String = hud.get_gold_gain_float_text()
	failed += _expect(text0.find("金币") >= 0, "Chinese 金币 in float")
	failed += _expect(text0.find("+80") >= 0, "+80 in float")
	failed += _expect(hud.get_gold_gain_float_amount() == 80, "amount 80")

	var tip: Control = hud.get_node_or_null("GoldGainFloat")
	failed += _expect(tip != null, "GoldGainFloat node exists")
	if tip != null:
		failed += _expect(tip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "mouse_filter IGNORE")
		failed += _expect(tip.visible, "Control visible")
		# Distinct gold/yellow color vs cyan exp float
		var fc: Color = tip.get_theme_color("font_color")
		failed += _expect(fc.r > 0.7 and fc.g > 0.5 and fc.b < 0.5, "gold/yellow font color")

	# Coalesce rapid gains
	hud.show_gold_gain_float(20)
	hud.show_gold_gain_float(50)
	await process_frame
	failed += _expect(hud.get_gold_gain_float_amount() == 150, "coalesce 80+20+50=150")
	failed += _expect(hud.get_gold_gain_float_text().find("+150") >= 0, "text shows +150")

	hud.hide_gold_gain_float()
	await process_frame
	failed += _expect(not hud.is_gold_gain_float_visible(), "hidden after hide")
	failed += _expect(hud.get_gold_gain_float_amount() == 0, "amount cleared")

	# Ignore non-positive
	hud.show_gold_gain_float(0)
	hud.show_gold_gain_float(-5)
	await process_frame
	failed += _expect(not hud.is_gold_gain_float_visible(), "no show for <=0")

	# Fresh show after hide
	hud.show_gold_gain_float(42)
	await process_frame
	failed += _expect(hud.get_gold_gain_float_text() == "金币 +42", "exact 金币 +42")

	# Auto-hide after ~1.2s
	if hud.has_method("_tick_gold_float"):
		hud._tick_gold_float(1.25)
	else:
		hud._process(1.25)
	await process_frame
	failed += _expect(not hud.is_gold_gain_float_visible(), "auto-hide after ~1.2s")

	# Distinct from exp float (both can show)
	hud.show_exp_gain_float(10)
	hud.show_gold_gain_float(25)
	await process_frame
	failed += _expect(hud.is_exp_gain_float_visible(), "exp float independent")
	failed += _expect(hud.is_gold_gain_float_visible(), "gold float alongside exp")
	failed += _expect(hud.get_exp_gain_float_text().find("经验") >= 0, "exp text unchanged")
	failed += _expect(hud.get_gold_gain_float_text().find("金币") >= 0, "gold float text")

	# inventory_update path: seed then gain via apply_inventory_snapshot
	hud.hide_gold_gain_float()
	hud.hide_exp_gain_float()
	hud.apply_inventory_snapshot([], 100)  # seed — no float
	await process_frame
	failed += _expect(not hud.is_gold_gain_float_visible(), "seed snapshot no float")
	hud.apply_inventory_snapshot([], 175)  # +75
	await process_frame
	failed += _expect(hud.is_gold_gain_float_visible(), "gain after seed shows float")
	failed += _expect(hud.get_gold_gain_float_amount() == 75, "delta 75 from inventory")
	failed += _expect(hud.get_gold_gain_float_text().find("+75") >= 0, "text +75")

	# Spending (decrease) ignored
	hud.hide_gold_gain_float()
	hud.apply_inventory_snapshot([], 50)
	await process_frame
	failed += _expect(not hud.is_gold_gain_float_visible(), "decrease ignored")

	# Settings flag present
	var gs_src := FileAccess.get_file_as_string("res://scripts/game/game_settings.gd")
	failed += _expect(gs_src.find("show_gold_floats") >= 0, "settings show_gold_floats")

	# World routes inventory_update → apply_inventory_snapshot
	var world_src := FileAccess.get_file_as_string("res://scripts/game/world.gd")
	failed += _expect(world_src.find("_apply_inventory_update") >= 0, "world _apply_inventory_update")
	failed += _expect(world_src.find("apply_inventory_snapshot") >= 0, "world calls apply_inventory_snapshot")

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
