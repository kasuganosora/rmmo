extends SceneTree
## Headless: radar_view_radius clamp/snap + RadarView.set_view_radius.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_settings_clamp()
	failed += await _test_radar_set_view_radius()

	if failed == 0:
		print("test_radar_zoom: PASS")
		quit(0)
	else:
		print("test_radar_zoom: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _test_settings_clamp() -> int:
	var failed := 0
	var Settings = load("res://scripts/game/game_settings.gd")
	failed += _expect(Settings != null, "game_settings loads")
	if Settings == null:
		return failed

	var gs: Node = Settings.new()
	gs.name = "GameSettingsRadarZoomTest"
	gs.persist_enabled = false
	gs.persist_path = "user://_test_radar_zoom.cfg"
	root.add_child(gs)
	gs.reset_defaults()
	failed += _expect(int(gs.radar_view_radius) == 11, "default radar_view_radius 11")

	var snap: Dictionary = gs.snapshot()
	failed += _expect(snap.has("radar_view_radius"), "snapshot has radar_view_radius")
	failed += _expect(int(snap.get("radar_view_radius", -1)) == 11, "snapshot default 11")

	# Snap to nearest allowed: 8, 11, 16, 22
	gs.set_radar_view_radius(1)
	failed += _expect(int(gs.radar_view_radius) == 8, "set 1 snaps to 8")
	gs.set_radar_view_radius(9)
	failed += _expect(int(gs.radar_view_radius) == 8, "set 9 snaps to 8")
	gs.set_radar_view_radius(10)
	failed += _expect(int(gs.radar_view_radius) == 11, "set 10 snaps to 11")
	gs.set_radar_view_radius(14)
	failed += _expect(int(gs.radar_view_radius) == 16 or int(gs.radar_view_radius) == 11, "set 14 snaps nearest")
	# 14 is equidistant? |14-11|=3, |14-16|=2 → 16
	gs.set_radar_view_radius(14)
	failed += _expect(int(gs.radar_view_radius) == 16, "set 14 snaps to 16")
	gs.set_radar_view_radius(20)
	failed += _expect(int(gs.radar_view_radius) == 22, "set 20 snaps to 22")
	gs.set_radar_view_radius(99)
	failed += _expect(int(gs.radar_view_radius) == 22, "set 99 snaps to 22")
	gs.set_radar_view_radius(16)
	failed += _expect(int(gs.radar_view_radius) == 16, "set exact 16")

	var changed := [false]
	gs.changed.connect(func(): changed[0] = true)
	gs.set_radar_view_radius(8)
	failed += _expect(changed[0], "setter emits changed")
	failed += _expect(int(gs.radar_view_radius) == 8, "set 8")

	# Cycle: at 8, zoom-in stays 8; zoom-out → 11
	gs.set_radar_view_radius(8)
	gs.cycle_radar_view_radius(-1)
	failed += _expect(int(gs.radar_view_radius) == 8, "cycle zoom-in at min stays 8")
	gs.cycle_radar_view_radius(1)
	failed += _expect(int(gs.radar_view_radius) == 11, "cycle zoom-out 8→11")
	gs.cycle_radar_view_radius(1)
	failed += _expect(int(gs.radar_view_radius) == 16, "cycle 11→16")
	gs.cycle_radar_view_radius(1)
	failed += _expect(int(gs.radar_view_radius) == 22, "cycle 16→22")
	gs.cycle_radar_view_radius(1)
	failed += _expect(int(gs.radar_view_radius) == 22, "cycle at max stays 22")
	gs.cycle_radar_view_radius(-1)
	failed += _expect(int(gs.radar_view_radius) == 16, "cycle zoom-in 22→16")

	gs.persist_enabled = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))
	gs.set_radar_view_radius(22)
	gs.save_to_disk()

	var gs2: Node = Settings.new()
	gs2.name = "GameSettingsRadarZoomTest2"
	gs2.persist_path = gs.persist_path
	gs2.persist_enabled = false
	root.add_child(gs2)
	gs2.load_from_disk()
	failed += _expect(int(gs2.radar_view_radius) == 22, "persist/load radar_view_radius")

	gs2.reset_defaults()
	failed += _expect(int(gs2.radar_view_radius) == 11, "reset restores 11")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))
	return failed


func _test_radar_set_view_radius() -> int:
	var failed := 0
	var Radar = load("res://scripts/ui/radar_view.gd")
	failed += _expect(Radar != null, "radar_view loads")
	if Radar == null:
		return failed

	var rv: Control = Control.new()
	rv.set_script(Radar)
	rv.name = "RadarZoomView"
	# Avoid GameSettings autoload overriding in _ready before we set.
	root.add_child(rv)
	await process_frame

	failed += _expect(rv.has_method("set_view_radius"), "has set_view_radius")
	rv.set_view_radius(8.0)
	failed += _expect(is_equal_approx(float(rv.view_radius_tiles), 8.0), "set_view_radius → 8")
	rv.set_view_radius(22.0)
	failed += _expect(is_equal_approx(float(rv.view_radius_tiles), 22.0), "set_view_radius → 22")
	rv.set_view_radius(11.0)
	failed += _expect(is_equal_approx(float(rv.view_radius_tiles), 11.0), "set_view_radius → 11")

	rv.queue_free()
	return failed
