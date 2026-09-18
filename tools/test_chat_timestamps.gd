extends SceneTree
## Headless: chat [HH:MM:SS] prefixes — util shape, setting on/off, rebuild preserves ts.


const ChatTimestampUtil = preload("res://scripts/ui/chat_timestamp_util.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_util_format()
	failed += await _test_push_and_rebuild()

	if failed == 0:
		print("test_chat_timestamps: PASS")
		quit(0)
	else:
		print("test_chat_timestamps: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _test_util_format() -> int:
	var failed := 0
	var shaped := ChatTimestampUtil.format({"hour": 9, "minute": 5, "second": 7})
	failed += _expect(shaped == "[09:05:07]", "format zero-pads known dict")
	failed += _expect(ChatTimestampUtil.looks_like_ts(shaped), "looks_like_ts known")
	var now := ChatTimestampUtil.format_now()
	failed += _expect(ChatTimestampUtil.looks_like_ts(now), "format_now [HH:MM:SS] shape got %s" % now)
	var empty := ChatTimestampUtil.format({})
	failed += _expect(ChatTimestampUtil.looks_like_ts(empty), "format() uses system clock")
	failed += _expect(not ChatTimestampUtil.looks_like_ts("09:05:07"), "no brackets rejected")
	failed += _expect(not ChatTimestampUtil.looks_like_ts("[9:05:07]"), "short hour rejected")
	return failed


func _test_push_and_rebuild() -> int:
	var failed := 0
	var Settings = load("res://scripts/game/game_settings.gd")
	failed += _expect(Settings != null, "game_settings loads")
	var gs = Settings.get_i()
	failed += _expect(gs != null, "autoload GameSettings")
	if gs == null:
		return failed
	gs.persist_enabled = false
	failed += _expect(bool(gs.show_chat_timestamps), "show_chat_timestamps default ON")
	var snap: Dictionary = gs.snapshot() if gs.has_method("snapshot") else {}
	failed += _expect(snap.has("show_chat_timestamps"), "snapshot has show_chat_timestamps")

	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "game_hud.tscn loads")
	if packed == null:
		return failed
	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	failed += _expect(hud.has_method("_push_chat"), "_push_chat API")
	failed += _expect(hud.has_method("_rebuild_chat_log"), "_rebuild_chat_log API")
	failed += _expect(hud.has_method("_format_chat_bbcode"), "_format_chat_bbcode API")

	# Setting ON: pushed line contains brackets+digits
	gs.set_flag("show_chat_timestamps", true)
	hud._chat_history.clear()
	hud.chat_log.clear()
	hud._push_chat("nearby", "Alice", "hello nearby")
	hud._push_chat("whisper", "Bob", "psst")
	hud._push_chat("party", "Carol", "party up")
	hud._push_chat("system", "系统", "sys note")
	hud._push_chat("combat", "战斗", "hit 12")
	failed += _expect(hud._chat_history.size() == 5, "5 history rows")
	var row0: Dictionary = hud._chat_history[0]
	var stored_ts := str(row0.get("ts", ""))
	failed += _expect(ChatTimestampUtil.looks_like_ts(stored_ts), "history stores ts shape %s" % stored_ts)
	var plain_on: String = hud.chat_log.get_parsed_text()
	failed += _expect(plain_on.find("[") >= 0 and plain_on.find("]") >= 0, "ON: parsed text has brackets")
	# Digits between brackets in parsed or bbcode
	var bb_on: String = str(hud.chat_log.text) if "text" in hud.chat_log else ""
	# RichTextLabel.get_parsed_text() strips bbcode; timestamps should remain
	var has_digit_ts := false
	for row in hud._chat_history:
		var ts := str(row.get("ts", ""))
		if ChatTimestampUtil.looks_like_ts(ts) and plain_on.find(ts) >= 0:
			has_digit_ts = true
			break
	# System channel is hidden when not on "all" — ensure channel is all
	hud._chat_channel = "all"
	hud._rebuild_chat_log()
	plain_on = hud.chat_log.get_parsed_text()
	has_digit_ts = false
	for row in hud._chat_history:
		var ts2 := str(row.get("ts", ""))
		if ChatTimestampUtil.looks_like_ts(ts2) and plain_on.find(ts2) >= 0:
			has_digit_ts = true
			break
	failed += _expect(has_digit_ts, "ON: pushed/rebuild line contains [HH:MM:SS] digits")

	# Setting OFF: omit timestamps from display
	gs.set_flag("show_chat_timestamps", false)
	hud._rebuild_chat_log()
	var plain_off: String = hud.chat_log.get_parsed_text()
	var any_ts_in_off := false
	for row in hud._chat_history:
		var ts3 := str(row.get("ts", ""))
		if not ts3.is_empty() and plain_off.find(ts3) >= 0:
			any_ts_in_off = true
			break
	failed += _expect(not any_ts_in_off, "OFF: omits stored ts from display")
	# History still keeps ts
	failed += _expect(ChatTimestampUtil.looks_like_ts(str(hud._chat_history[0].get("ts", ""))), "OFF: history still has ts")

	# Rebuild preserves stored ts (same string after another rebuild with ON)
	var preserved := str(hud._chat_history[2].get("ts", ""))
	gs.set_flag("show_chat_timestamps", true)
	hud._rebuild_chat_log()
	failed += _expect(str(hud._chat_history[2].get("ts", "")) == preserved, "rebuild preserves stored ts")
	var plain_again: String = hud.chat_log.get_parsed_text()
	failed += _expect(plain_again.find(preserved) >= 0, "rebuild shows same preserved ts")

	# Direct format_chat_bbcode checks
	var with_ts: String = hud._format_chat_bbcode("#fff", "X", "m", "[12:34:56]")
	failed += _expect(with_ts.begins_with("[12:34:56] "), "bbcode prefixes when ON")
	gs.set_flag("show_chat_timestamps", false)
	var without: String = hud._format_chat_bbcode("#fff", "X", "m", "[12:34:56]")
	failed += _expect(not without.begins_with("[12:34:56]"), "bbcode omits when OFF")
	failed += _expect(without.find("X") >= 0, "bbcode still has speaker when OFF")

	# Settings UI checkbox label exists on game tab
	gs.set_flag("show_chat_timestamps", true)
	hud._toggle_window("system")
	await process_frame
	hud._on_system_tab("game")
	await process_frame
	var sys: PanelContainer = hud._windows.get("system")
	var body: VBoxContainer = sys.get_meta("body") if sys else null
	var found_chk := false
	if body:
		for c in body.get_children():
			if c is CheckBox and str(c.text).find("聊天时间戳") >= 0:
				found_chk = true
				failed += _expect(bool(c.button_pressed), "checkbox default checked")
				break
	failed += _expect(found_chk, "游戏设置 has 聊天时间戳 checkbox")

	hud.queue_free()
	await process_frame
	gs.persist_enabled = true
	return failed
