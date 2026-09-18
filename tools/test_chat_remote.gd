extends SceneTree
## Headless: nearby/whisper chat + remote player spawn.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_chat_remote: FAIL no MockServer")
		quit(1)
		return
	if srv.has_method("try_remote_despawn"):
		srv.try_remote_despawn("")
	srv.set_player_cell(10, 10)

	failed += _expect(srv.has_method("try_chat"), "has try_chat")
	failed += _expect(srv.has_method("try_remote_debug_spawn"), "has remote spawn")

	var sp: Dictionary = srv.try_remote_debug_spawn("旅人甲")
	failed += _expect(bool(sp.get("ok", false)), "spawn ok")
	failed += _expect(_has(sp, "remote_spawn"), "remote_spawn action")
	failed += _expect(srv.snapshot_remote_players().size() == 1, "one remote")
	var cell: Dictionary = srv.snapshot_remote_players()[0].get("cell", {})
	failed += _expect(srv._chebyshev(10, 10, int(cell.get("x", 0)), int(cell.get("y", 0))) <= srv.NEARBY_CHAT_RANGE, "spawn in nearby range")

	var near: Dictionary = srv.try_chat("nearby", "你好附近")
	failed += _expect(bool(near.get("ok", false)), "nearby ok")
	failed += _expect(_count(near, "chat_message") >= 2, "nearby self+echo")
	var first := _first(near, "chat_message")
	failed += _expect(str(first.get("channel", "")) == "nearby", "nearby channel")

	var wh: Dictionary = srv.try_chat("whisper", "密信测试", "旅人甲")
	failed += _expect(bool(wh.get("ok", false)), "whisper ok")
	failed += _expect(_count(wh, "chat_message") == 1, "whisper self only (no stub reply)")

	var miss: Dictionary = srv.try_chat("whisper", "x", "不存在的人")
	failed += _expect(not bool(miss.get("ok", true)), "whisper miss fails")

	var shout: Dictionary = srv.try_chat("all", "大喊一声")
	failed += _expect(bool(shout.get("ok", false)), "shout ok")

	# Move remote far and nearby should say nobody heard
	var rid := str(srv.snapshot_remote_players()[0].get("id", ""))
	srv._remote_players[rid]["cell"] = {"x": 10 + srv.NEARBY_CHAT_RANGE + 5, "y": 10}
	var far: Dictionary = srv.try_chat("nearby", "远处喊")
	failed += _expect(bool(far.get("ok", false)), "far nearby still ok")
	failed += _expect(_has(far, "system_message"), "far: system nobody heard")
	failed += _expect(_count(far, "chat_message") == 1, "far: only self message")

	if failed == 0:
		print("test_chat_remote: PASS")
		quit(0)
		return
	print("test_chat_remote: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _count(result: Dictionary, typ: String) -> int:
	var n := 0
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			n += 1
	return n


func _first(result: Dictionary, typ: String) -> Dictionary:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return a
	return {}


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
