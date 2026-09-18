extends SceneTree
## Headless: daily quest board accept-once-per-day + date rollover.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var QuestJournal = load("res://scripts/net/combat/quest_journal.gd")
	var j = QuestJournal.new()
	j.load_catalog()
	failed += _expect(j._catalog.has("daily_slime"), "catalog daily_slime")
	failed += _expect(j._catalog.has("daily_herb"), "catalog daily_herb")
	failed += _expect(str(j.get_catalog_entry("daily_slime").get("category", "")) == "daily", "slime category daily")
	failed += _expect(j.has_method("try_daily_board_list"), "has try_daily_board_list")
	failed += _expect(j.has_method("force_daily_date"), "has force_daily_date")
	failed += _expect(j.has_method("snapshot_daily"), "has snapshot_daily")

	j.clear()
	j.clear_daily_log()
	j.force_daily_date("2026-09-18")

	var board0: Array = j.try_daily_board_list()
	failed += _expect(board0.size() >= 2, "board has >=2 dailies")
	failed += _expect(_board_state(board0, "daily_slime") == "available", "slime available")
	failed += _expect(_board_state(board0, "daily_herb") == "available", "herb available")

	var acc1: Dictionary = j.try_accept_quest("daily_slime")
	failed += _expect(bool(acc1.get("ok", false)), "accept daily_slime OK")
	failed += _expect(j.is_accepted("daily_slime"), "slime accepted in journal")
	failed += _expect(_board_state(j.try_daily_board_list(), "daily_slime") == "accepted", "board accepted")

	var acc_again: Dictionary = j.try_accept_quest("daily_slime")
	failed += _expect(not bool(acc_again.get("ok", false)), "second accept while active fails")
	failed += _expect(str(acc_again.get("reason", "")) == "daily_claimed", "reason daily_claimed")
	failed += _expect(str(acc_again.get("message", "")).find("今日已领取") >= 0, "msg 今日已领取")

	# Complete + turn in
	for _i in range(5):
		j.note_kill("slime_a")
	failed += _expect(j.get_status("daily_slime") == "ready", "slime ready after kills")
	var ti: Dictionary = j.try_turn_in("daily_slime")
	failed += _expect(bool(ti.get("ok", false)), "turn_in ok")
	failed += _expect(bool(ti.get("daily", false)), "turn_in marks daily")
	failed += _expect(not j.is_accepted("daily_slime"), "removed from active after daily turn-in")
	failed += _expect(_board_state(j.try_daily_board_list(), "daily_slime") == "done_today", "done_today")

	var acc_after: Dictionary = j.try_accept_quest("daily_slime")
	failed += _expect(not bool(acc_after.get("ok", false)), "second accept same day after complete fails")
	failed += _expect(str(acc_after.get("message", "")).find("今日已领取") >= 0, "msg after complete")

	var snap: Dictionary = j.snapshot_daily()
	failed += _expect(str(snap.get("daily_date", "")) == "2026-09-18", "snapshot daily_date")
	failed += _expect(typeof(snap.get("daily", null)) == TYPE_ARRAY, "snapshot daily list")

	# Date change → can accept again
	j.force_daily_date("2026-09-19")
	failed += _expect(_board_state(j.try_daily_board_list(), "daily_slime") == "available", "next day available")
	var acc_next: Dictionary = j.try_accept_quest("daily_slime")
	failed += _expect(bool(acc_next.get("ok", false)), "accept again next day")
	failed += _expect(j.is_accepted("daily_slime"), "accepted next day")

	# MockServer path
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		failed += _expect(false, "MockServer present")
	else:
		if srv.quest_journal == null and srv.has_method("_init_combat_layers"):
			srv._init_combat_layers()
		failed += _expect(srv.quest_journal != null, "srv quest_journal")
		failed += _expect(srv.has_method("try_daily_board_list"), "srv try_daily_board_list")
		failed += _expect(srv.has_method("snapshot_daily"), "srv snapshot_daily")
		srv.quest_journal.clear()
		srv.quest_journal.clear_daily_log()
		srv.quest_journal.force_daily_date("2026-03-01")
		var r1: Dictionary = srv.try_accept_quest("daily_herb")
		failed += _expect(bool(r1.get("ok", false)), "srv accept daily_herb")
		failed += _expect(_msg_has(r1.get("actions", []), "已接取"), "srv accept msg")
		# Force ready + turn in
		for _k in range(3):
			srv.quest_journal.note_gather("wild_herb", 1)
		var r2: Dictionary = srv.try_turn_in_quest("daily_herb")
		failed += _expect(bool(r2.get("ok", false)), "srv turn_in daily_herb")
		var r3: Dictionary = srv.try_accept_quest("daily_herb")
		failed += _expect(not bool(r3.get("ok", false)), "srv same-day reaccept fails")
		failed += _expect(_msg_has(r3.get("actions", []), "今日已领取该日常"), "srv daily claimed msg")
		var st: Array = srv.try_daily_board_list()
		failed += _expect(_board_state(st, "daily_herb") == "done_today", "srv board done_today")
		srv.quest_journal.force_daily_date("2026-03-02")
		var r4: Dictionary = srv.try_accept_quest("daily_herb")
		failed += _expect(bool(r4.get("ok", false)), "srv accept after date change")
		# Cleanup
		srv.quest_journal.clear()
		srv.quest_journal.clear_daily_log()
		srv.quest_journal.force_daily_date("")

	if failed == 0:
		print("test_daily_quests: PASS")
		quit(0)
		return
	print("test_daily_quests: FAIL count=%d" % failed)
	quit(1)


func _board_state(board: Array, qid: String) -> String:
	for row in board:
		if typeof(row) == TYPE_DICTIONARY and str(row.get("id", "")) == qid:
			return str(row.get("state", ""))
	return ""


func _msg_has(actions: Variant, frag: String) -> bool:
	if typeof(actions) != TYPE_ARRAY:
		return false
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			if str(a.get("text", "")).find(frag) >= 0:
				return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
