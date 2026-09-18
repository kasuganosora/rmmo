extends SceneTree
## Headless: nameplate draw-distance helper + GameSettings clamp 4–32.


const NameplateUtil = preload("res://scripts/game/nameplate_util.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_helper()
	failed += _test_settings_clamp()

	if failed == 0:
		print("test_nameplate_distance: PASS")
		quit(0)
	else:
		print("test_nameplate_distance: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _test_helper() -> int:
	var failed := 0
	failed += _expect(NameplateUtil.should_show(0, 12, false), "dist 0 <= max show")
	failed += _expect(NameplateUtil.should_show(12, 12, false), "dist == max show")
	failed += _expect(not NameplateUtil.should_show(13, 12, false), "dist > max hide")
	failed += _expect(NameplateUtil.should_show(99, 12, true), "selected forces show")
	failed += _expect(NameplateUtil.chebyshev(Vector2i(0, 0), Vector2i(3, 5)) == 5, "chebyshev max(dx,dy)")
	failed += _expect(NameplateUtil.clamp_distance(3) == 4, "clamp low→4")
	failed += _expect(NameplateUtil.clamp_distance(40) == 32, "clamp high→32")
	failed += _expect(NameplateUtil.clamp_distance(12) == 12, "clamp mid unchanged")
	return failed


func _test_settings_clamp() -> int:
	var failed := 0
	var Settings = load("res://scripts/game/game_settings.gd")
	failed += _expect(Settings != null, "game_settings loads")
	if Settings == null:
		return failed

	var gs: Node = Settings.new()
	gs.name = "GameSettingsNameplateTest"
	gs.persist_enabled = false
	gs.persist_path = "user://_test_nameplate_distance.cfg"
	root.add_child(gs)
	gs.reset_defaults()
	failed += _expect(int(gs.nameplate_distance) == 12, "default nameplate_distance 12")

	var snap: Dictionary = gs.snapshot()
	failed += _expect(snap.has("nameplate_distance"), "snapshot has nameplate_distance")
	failed += _expect(int(snap.get("nameplate_distance", -1)) == 12, "snapshot default 12")

	gs.set_nameplate_distance(3)
	failed += _expect(int(gs.nameplate_distance) == 4, "set clamps low to 4")
	gs.set_nameplate_distance(99)
	failed += _expect(int(gs.nameplate_distance) == 32, "set clamps high to 32")
	gs.set_nameplate_distance(20)
	failed += _expect(int(gs.nameplate_distance) == 20, "set mid 20")

	var changed := [false]
	gs.changed.connect(func(): changed[0] = true)
	gs.set_nameplate_distance(21)
	failed += _expect(changed[0], "setter emits changed")

	gs.persist_enabled = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))
	gs.set_nameplate_distance(18)
	gs.save_to_disk()

	var gs2: Node = Settings.new()
	gs2.name = "GameSettingsNameplateTest2"
	gs2.persist_path = gs.persist_path
	gs2.persist_enabled = false
	root.add_child(gs2)
	gs2.load_from_disk()
	failed += _expect(int(gs2.nameplate_distance) == 18, "persist/load nameplate_distance")

	gs2.reset_defaults()
	failed += _expect(int(gs2.nameplate_distance) == 12, "reset restores 12")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))
	return failed
