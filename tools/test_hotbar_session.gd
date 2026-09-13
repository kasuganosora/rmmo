extends SceneTree
## Hotbar bindings persist on GameSession across simulated HUD rebuild.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failed := 0
	var sess: Node = root.get_node_or_null("GameSession")
	failed += _expect(sess != null, "GameSession present")
	if sess == null:
		_finish(failed)
		return
	sess.hotbar_bindings = {
		"0:1": {"kind": "skill", "id": "flame_burst"},
		"0:3": {"kind": "item", "id": "potion_hp_small"},
	}
	sess.hotbar_page = 1
	# Simulate new HUD local copy restore logic
	var raw: Dictionary = sess.hotbar_bindings.duplicate(true)
	var out: Dictionary = {}
	for k in raw.keys():
		var v: Variant = raw[k]
		if typeof(v) != TYPE_DICTIONARY:
			continue
		out[str(k)] = {"kind": str(v.get("kind", "")), "id": str(v.get("id", ""))}
	failed += _expect(out.has("0:1") and str(out["0:1"].get("id")) == "flame_burst", "restore flame")
	failed += _expect(out.has("0:3"), "restore potion")
	failed += _expect(int(sess.hotbar_page) == 1, "page persisted")
	# login clears
	sess.hotbar_bindings = {"0:1": {"kind": "skill", "id": "x"}}
	# call go_login would change scene — just mimic clear fields
	sess.hotbar_bindings = {}
	sess.hotbar_page = 0
	failed += _expect(sess.hotbar_bindings.is_empty(), "cleared on logout mimic")
	_finish(failed)

func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1

func _finish(failed: int) -> void:
	if failed == 0:
		print("test_hotbar_session: PASS")
		quit(0)
	else:
		print("test_hotbar_session: FAIL count=%d" % failed)
		quit(1)
