extends SceneTree
## Headless: combat camera frame offset util + GameSettings.combat_camera_frame.


const CombatCamera = preload("res://scripts/game/combat_camera.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_compute_frame_offset()
	failed += _test_lerp_offset()
	failed += _test_settings()
	failed += await _test_shake_additive()

	if failed == 0:
		print("test_combat_camera: PASS")
		quit(0)
	else:
		print("test_combat_camera: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _test_compute_frame_offset() -> int:
	var failed := 0
	var player := Vector2(0, 0)
	var target := Vector2(100, 0)
	var off: Vector2 = CombatCamera.compute_frame_offset(player, target, 0.25, 64.0)
	failed += _expect(is_equal_approx(off.x, 25.0) and is_equal_approx(off.y, 0.0), "factor 0.25 → 25px")

	# Clamp to max_px
	target = Vector2(400, 0)
	off = CombatCamera.compute_frame_offset(player, target, 0.25, 64.0)
	failed += _expect(is_equal_approx(off.length(), 64.0), "clamped to max 64")
	failed += _expect(is_equal_approx(off.x, 64.0), "clamped along +x")

	# Diagonal clamp
	target = Vector2(200, 200)
	off = CombatCamera.compute_frame_offset(player, target, 0.25, 64.0)
	# raw = (50,50) length ~70.71 → clamp 64
	failed += _expect(absf(off.length() - 64.0) < 0.01, "diagonal clamp length 64")
	failed += _expect(is_equal_approx(off.x, off.y), "diagonal equal components")

	# Same position → zero
	off = CombatCamera.compute_frame_offset(Vector2(10, 10), Vector2(10, 10), 0.25, 64.0)
	failed += _expect(off == Vector2.ZERO, "same pos zero")

	# factor 0 → zero
	off = CombatCamera.compute_frame_offset(player, Vector2(100, 0), 0.0, 64.0)
	failed += _expect(off == Vector2.ZERO, "factor 0 zero")

	# Negative direction
	off = CombatCamera.compute_frame_offset(Vector2(50, 0), Vector2(0, 0), 0.25, 64.0)
	failed += _expect(is_equal_approx(off.x, -12.5), "toward left negative x")

	return failed


func _test_lerp_offset() -> int:
	var failed := 0
	var cur := Vector2.ZERO
	var desired := Vector2(40, 0)
	var next: Vector2 = CombatCamera.lerp_offset(cur, desired, 0.0)
	failed += _expect(next == Vector2.ZERO, "delta 0 no move")
	next = CombatCamera.lerp_offset(cur, desired, 0.05)
	failed += _expect(next.x > 0.0 and next.x < desired.x, "partial lerp moves toward")
	# With large delta fully arrives
	next = CombatCamera.lerp_offset(cur, desired, 10.0)
	failed += _expect(next == desired, "large delta snaps to desired")
	# Lerp back to zero
	next = CombatCamera.lerp_offset(desired, Vector2.ZERO, 10.0)
	failed += _expect(next == Vector2.ZERO, "lerp back to zero")
	return failed


func _test_settings() -> int:
	var failed := 0
	var Settings = load("res://scripts/game/game_settings.gd")
	failed += _expect(Settings != null, "game_settings loads")
	if Settings == null:
		return failed

	var gs: Node = Settings.new()
	gs.name = "GameSettingsCombatCamTest"
	gs.persist_enabled = false
	gs.persist_path = "user://_test_combat_camera.cfg"
	root.add_child(gs)
	gs.reset_defaults()
	failed += _expect(bool(gs.combat_camera_frame) == true, "default combat_camera_frame true")

	var snap: Dictionary = gs.snapshot()
	failed += _expect(snap.has("combat_camera_frame"), "snapshot has key")
	failed += _expect(bool(snap.get("combat_camera_frame", false)) == true, "snapshot default true")

	gs.set_flag("combat_camera_frame", false)
	failed += _expect(bool(gs.combat_camera_frame) == false, "toggle off via set_flag")
	gs.set_flag("combat_camera_frame", true)
	failed += _expect(bool(gs.combat_camera_frame) == true, "toggle on via set_flag")

	# Persist round-trip
	gs.persist_enabled = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))
	gs.set_flag("combat_camera_frame", false)
	gs.save_to_disk()
	var gs2: Node = Settings.new()
	gs2.name = "GameSettingsCombatCamTest2"
	gs2.persist_path = gs.persist_path
	gs2.persist_enabled = false
	root.add_child(gs2)
	gs2.load_from_disk()
	failed += _expect(bool(gs2.combat_camera_frame) == false, "reload combat_camera_frame false")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))

	# Autoload flag helper
	var live = Settings.get_i()
	if live != null:
		var prev_persist = live.persist_enabled
		live.persist_enabled = false
		var prev = bool(live.combat_camera_frame)
		live.set_flag("combat_camera_frame", false)
		failed += _expect(not Settings.flag("combat_camera_frame", true), "flag helper off")
		live.set_flag("combat_camera_frame", true)
		failed += _expect(Settings.flag("combat_camera_frame", false), "flag helper on")
		live.combat_camera_frame = prev
		live.persist_enabled = prev_persist
	else:
		failed += _expect(false, "GameSettings autoload present")

	gs.queue_free()
	gs2.queue_free()
	return failed


func _test_shake_additive() -> int:
	## shake.apply_to(cam, base) keeps combat frame under shake jitter.
	var failed := 0
	var Shake = load("res://scripts/game/camera_shake.gd")
	failed += _expect(Shake != null, "camera_shake loads")
	if Shake == null:
		return failed
	var host := Node2D.new()
	root.add_child(host)
	var cam := Camera2D.new()
	host.add_child(cam)
	await process_frame

	var shake = Shake.new()
	shake.randomize_phase = false
	var base := Vector2(20, 10)
	shake.clear()
	shake.apply_to(cam, base)
	failed += _expect(cam.offset == base, "idle shake keeps base offset")

	shake.trigger(0.2, 3.0, 0.0)
	shake.apply_to(cam, base)
	failed += _expect(cam.offset != base, "active shake moves off base")
	failed += _expect((cam.offset - base).length() > 0.01, "delta is shake component")
	failed += _expect((cam.offset - base).length() <= 3.01, "shake amp on top of base")

	shake.clear()
	shake.apply_to(cam, base)
	failed += _expect(cam.offset == base, "clear restores base")

	host.queue_free()
	return failed
