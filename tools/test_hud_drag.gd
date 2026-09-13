extends SceneTree
## Headless: HUD window drag helper snaps to pixels and clamp stays on-canvas.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var HudDrag = load("res://scripts/ui/hud_draggable.gd")
	failed += _expect(HudDrag != null, "hud_draggable loads")
	if HudDrag == null:
		_finish(failed)
		return

	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var panel := PanelContainer.new()
	panel.set_script(HudDrag)
	host.add_child(panel)
	await process_frame
	panel.size = Vector2(200, 100)
	panel.global_position = Vector2(10.6, 20.4)
	if panel.has_method("_snap_px"):
		var snapped: Vector2 = panel._snap_px(Vector2(10.6, 20.4))
		failed += _expect(snapped == Vector2(11, 20), "_snap_px rounds 10.6,20.4")
	if panel.has_method("_clamp_on_screen"):
		panel._clamp_on_screen()
		failed += _expect(panel.global_position == panel.global_position.round(), "clamp snaps to pixels")
		failed += _expect(panel.global_position.x >= 0.0 and panel.global_position.y >= 0.0, "clamp stays on-canvas")
	failed += _expect(panel.is_processing_input() == false, "input off until drag starts")
	if panel.has_method("_begin_pointer_capture"):
		panel._dragging = true
		panel._begin_pointer_capture()
		failed += _expect(panel.is_processing_input() == true, "input on while dragging")
		panel._end_pointer_capture()
		failed += _expect(panel.is_processing_input() == false, "input off after drag end")
		failed += _expect(panel._dragging == false, "drag flag cleared")
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
