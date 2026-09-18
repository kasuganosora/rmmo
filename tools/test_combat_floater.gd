extends SceneTree
## Headless: CombatFloater spawn / colors / per-target cap.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var Floater = load("res://scripts/game/combat_floater.gd")
	failed += _expect(Floater != null, "load combat_floater.gd")
	Floater.clear_all()

	failed += _expect(Floater.text_for("miss") == "未命中", "miss text")
	failed += _expect(Floater.text_for("heal", 12) == "+12", "heal text")
	failed += _expect(Floater.text_for("damage", 9) == "9", "damage text")
	failed += _expect(Floater.text_for("damage", 9, true) == "9!", "crit text")
	failed += _expect(Floater.color_for("heal").g > Floater.color_for("heal").r, "heal green")
	failed += _expect(Floater.color_for("miss").r < 0.85, "miss grayish")
	failed += _expect(Floater.color_for("damage", true) == Floater.COLOR_CRIT, "crit color")

	var host := Node2D.new()
	root.add_child(host)
	await process_frame

	var lab: Label = Floater.spawn(host, Vector2(10, 20), "42", "damage", "npc:a", false)
	failed += _expect(lab != null and is_instance_valid(lab), "spawn creates Label")
	failed += _expect(lab.get_parent() == host, "label parented to host")
	failed += _expect(Floater.active_count("npc:a") == 1, "active_count 1")

	var miss_lab: Label = Floater.spawn(host, Vector2(10, 20), Floater.text_for("miss"), "miss", "npc:a", false)
	failed += _expect(miss_lab != null and miss_lab.text == "未命中", "miss label text")

	# Cap: flood beyond MAX_PER_TARGET
	for i in range(Floater.MAX_PER_TARGET + 4):
		Floater.spawn(host, Vector2(i, 0), str(i), "damage", "npc:cap", false)
	await process_frame
	failed += _expect(Floater.active_count("npc:cap") <= Floater.MAX_PER_TARGET, "cap <= %d (got %d)" % [Floater.MAX_PER_TARGET, Floater.active_count("npc:cap")])

	# Other target bucket independent
	failed += _expect(Floater.active_count("npc:a") >= 1, "other target untouched")

	Floater.clear_all()
	failed += _expect(Floater.active_count() == 0, "clear_all")

	if failed == 0:
		print("test_combat_floater: OK")
		quit(0)
	else:
		print("test_combat_floater: FAIL %d" % failed)
		quit(1)


func _expect(cond: bool, msg: String) -> int:
	if cond:
		return 0
	print("  FAIL: ", msg)
	return 1
