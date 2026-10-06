extends SceneTree
## Headless: action_apply robustness — unknown action opcodes are logged (deduped) and
## ignored, malformed/known items don't crash, null ctrl is guarded.


const ActionApply = preload("res://scripts/game/application/action_apply.gd")


func _init() -> void:
	call_deferred("_run")


func _make_stub() -> Node:
	var s := GDScript.new()
	s.source_code = "\n".join([
		"extends Node",
		"var hud = null",
		"var last_applied_action_types = []",
		"var _event_wait_left := 0.0",
		"var _deferred_event_actions = []",
		"var _deferred_event_npc = null",
	])
	s.reload()
	return s.new()


func _run() -> void:
	var failed := 0
	var ctrl := _make_stub()
	root.add_child(ctrl)

	ActionApply.reset_unknown_action_types()

	# Unknown opcode -> recorded + ignored (no crash).
	ActionApply.apply_server_actions(ctrl, [{"type": "zzz_unknown_op"}])
	failed += _expect("zzz_unknown_op" in ActionApply.unknown_action_types(), "unknown opcode recorded")

	# Dedup: seeing it again does not grow the set.
	ActionApply.apply_server_actions(ctrl, [{"type": "zzz_unknown_op"}])
	failed += _expect(ActionApply.unknown_action_types().size() == 1, "unknown opcode deduped")

	# Malformed items are skipped without crashing and empty type is not recorded.
	ActionApply.apply_server_actions(ctrl, [null, 123, "str", {"no_type": 1}, {"type": ""}])
	failed += _expect(ActionApply.unknown_action_types().size() == 1, "malformed/empty not recorded")

	# A known opcode is not flagged unknown (hud null is tolerated).
	ActionApply.apply_server_actions(ctrl, [{"type": "system_message", "text": "hi"}])
	failed += _expect(not ("system_message" in ActionApply.unknown_action_types()), "known opcode not flagged")

	# A second distinct unknown opcode is recorded.
	ActionApply.apply_server_actions(ctrl, [{"type": "another_unknown"}])
	failed += _expect("another_unknown" in ActionApply.unknown_action_types(), "second unknown recorded")
	failed += _expect(ActionApply.unknown_action_types().size() == 2, "two distinct unknowns tracked")

	# Null ctrl is guarded (no crash).
	ActionApply.apply_server_actions(null, [{"type": "whatever"}])
	failed += _expect(true, "null ctrl guarded (no crash)")

	ctrl.queue_free()
	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS test_action_robust")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
