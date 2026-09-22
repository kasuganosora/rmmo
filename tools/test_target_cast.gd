extends SceneTree
## Headless: target (enemy) cast bar on the target frame — show/update/tick/clear + guards.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "game_hud.tscn loads")
	if packed == null:
		_finish(failed)
		return
	var hud = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	# Start an enemy cast.
	hud.apply_target_cast_start("mob1", {"duration": 2.0, "elapsed": 0.0, "name": "火球术"})
	failed += _expect(hud.is_target_casting(), "casting after start")
	failed += _expect(hud._target_cast_bar != null and hud._target_cast_bar.visible, "cast bar visible")
	failed += _expect(hud._target_cast_label != null and hud._target_cast_label.visible, "cast label visible")
	failed += _expect(hud._target_cast_label.text.find("火球术") >= 0, "label shows skill name")
	failed += _expect(hud._target_cast_bar.value <= 5.0, "bar ~0%% at start")

	# Update to half.
	hud.apply_target_cast_update("mob1", {"duration": 2.0, "elapsed": 1.0})
	failed += _expect(abs(hud._target_cast_bar.value - 50.0) < 2.0, "bar ~50%% after update (got %.1f)" % hud._target_cast_bar.value)

	# Mismatched caster must not end our cast.
	hud.apply_target_cast_end("someone_else")
	failed += _expect(hud.is_target_casting(), "mismatched caster does not end cast")

	# Tick to completion auto-clears.
	hud._tick_target_cast(1.5)
	failed += _expect(not hud.is_target_casting(), "cast auto-clears at completion")
	failed += _expect(not hud._target_cast_bar.visible, "bar hidden after completion")

	# Restart then explicit matching end clears.
	hud.apply_target_cast_start("mob2", {"duration": 3.0, "elapsed": 0.0, "name": "冰枪"})
	failed += _expect(hud.is_target_casting(), "casting after restart")
	hud.apply_target_cast_end("mob2")
	failed += _expect(not hud.is_target_casting(), "matching end clears cast")

	# clear_target() also drops the cast bar.
	hud.apply_target_cast_start("mob3", {"duration": 3.0, "elapsed": 0.0, "name": "闪电"})
	failed += _expect(hud.is_target_casting(), "casting before clear_target")
	hud.clear_target()
	failed += _expect(not hud.is_target_casting(), "clear_target() clears cast")

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
		print("ALL PASS test_target_cast")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
