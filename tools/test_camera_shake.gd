extends SceneTree
## Headless: CameraShake sets Camera2D.offset then settles; retrigger restarts (no stack).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var Shake = load("res://scripts/game/camera_shake.gd")
	failed += _expect(Shake != null, "load camera_shake.gd")

	var shake = Shake.new()
	shake.randomize_phase = false
	failed += _expect(not shake.is_active(), "idle inactive")
	failed += _expect(shake.offset == Vector2.ZERO, "idle offset zero")

	shake.trigger(0.2, 3.0, 0.0)
	failed += _expect(shake.is_active(), "active after trigger")
	failed += _expect(shake.remaining == 0.2, "remaining full")
	failed += _expect(shake.offset.length() > 0.01, "offset non-zero immediately")
	failed += _expect(shake.offset.length() <= 3.01, "offset <= amplitude")

	# Mid-shake sample
	shake.tick(0.05)
	failed += _expect(shake.is_active(), "still active mid")
	failed += _expect(absf(shake.remaining - 0.15) < 0.001, "remaining decayed")
	var mid_len: float = shake.offset.length()
	failed += _expect(mid_len <= 3.01, "mid amp capped")
	failed += _expect(mid_len < 3.0 * 0.8 + 0.05, "decayed below start amp*0.8")

	# Retrigger restarts — does not stack amplitude past max
	shake.trigger(0.2, 3.0, 0.0)
	failed += _expect(absf(shake.remaining - 0.2) < 0.001, "retrigger restarts remaining")
	failed += _expect(shake.amplitude <= 4.0, "amplitude capped")
	failed += _expect(shake.offset.length() <= 4.01, "no wild stack")

	# Settle
	var guard := 0
	while shake.is_active() and guard < 100:
		shake.tick(0.05)
		guard += 1
	failed += _expect(not shake.is_active(), "settled inactive")
	failed += _expect(shake.offset == Vector2.ZERO, "settled offset zero")

	# apply_to Camera2D
	var host := Node2D.new()
	root.add_child(host)
	var cam := Camera2D.new()
	host.add_child(cam)
	await process_frame

	shake.trigger(0.2, 3.0, 0.5)
	shake.apply_to(cam)
	failed += _expect(cam.offset.length() > 0.01, "cam.offset set")
	shake.clear()
	shake.apply_to(cam)
	failed += _expect(cam.offset == Vector2.ZERO, "cam.offset cleared")

	# Duration clamp
	shake.trigger(0.01, 3.0, 0.0)
	failed += _expect(shake.duration >= 0.15, "dur min clamp")
	shake.trigger(1.0, 3.0, 0.0)
	failed += _expect(shake.duration <= 0.25, "dur max clamp")

	# GameSettings flag (autoload) — set_flag allowlist + default ON
	var gs = root.get_node_or_null("GameSettings")
	failed += _expect(gs != null, "GameSettings autoload")
	if gs != null:
		var prev_persist = gs.persist_enabled
		gs.persist_enabled = false
		var prev = bool(gs.screen_shake)
		# Default property exists and set_flag accepts the key
		gs.screen_shake = true
		failed += _expect(bool(gs.screen_shake) == true, "screen_shake default ON")
		gs.set_flag("screen_shake", false)
		failed += _expect(bool(gs.screen_shake) == false, "screen_shake can disable")
		gs.set_flag("screen_shake", true)
		failed += _expect(bool(gs.screen_shake) == true, "screen_shake re-enable")
		gs.screen_shake = prev
		gs.persist_enabled = prev_persist

	host.queue_free()

	if failed == 0:
		print("test_camera_shake: OK")
		quit(0)
	else:
		print("test_camera_shake: FAIL %d" % failed)
		quit(1)


func _expect(cond: bool, msg: String) -> int:
	if cond:
		return 0
	print("  FAIL: ", msg)
	return 1
