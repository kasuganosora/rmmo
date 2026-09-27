extends SceneTree
## Bridge deck and the ground under it stay different surfaces.

const Surface = preload("res://scripts/world3d/world_surface.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var stacked := [{"id": "ground", "y": 0.0}, {"id": "bridge_deck", "y": 3.0}]
	failed += _expect(Surface.pick_surface(0.1, stacked) == "ground", "feet under the bridge stay on the ground")
	failed += _expect(Surface.pick_surface(3.0, stacked) == "bridge_deck", "feet on the deck stay on the deck")
	failed += _expect(Surface.pick_surface(1.2, stacked) == "ground", "a body between decks does not snap up")
	failed += _expect(not Surface.allows("ground", "bridge_deck"), "ground does not jump to the deck")
	failed += _expect(Surface.allows("ground", "ramp") and Surface.allows("ramp", "bridge_deck"), "the ramp joins the two decks")
	print("test_world3d_surface: %s" % ("FAIL %d" % failed if failed else "PASS"))
	quit(1 if failed else 0)


func _expect(ok: bool, label: String) -> int:
	if not ok:
		print("test_world3d_surface: FAIL %s" % label)
		return 1
	return 0
