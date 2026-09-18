extends SceneTree
## Headless: build quest tracker text from a sample journal snapshot.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var Util = load("res://scripts/ui/quest_tracker_util.gd")
	failed += _expect(Util != null, "util loaded")

	var snap: Array = [
		{
			"id": "starter_step",
			"title": "新手指引",
			"status": "in_progress",
			"objectives": [{"text": "假人", "cur": 1, "max": 3}],
		},
		{
			"id": "herb_gather",
			"title": "采集野草",
			"status": "in_progress",
			"objectives": [{"text": "野草", "cur": 2, "max": 5}],
		},
		{
			"id": "pond_fishing",
			"title": "池塘钓鱼",
			"status": "ready",
			"objectives": [{"text": "鲜鱼", "cur": 3, "max": 3}],
		},
		{
			"id": "welcome_gift",
			"title": "欢迎礼",
			"status": "completed",
			"objectives": [{"text": "领取", "cur": 1, "max": 1}],
		},
		{
			"id": "rat_cleanup",
			"title": "清理老鼠",
			"status": "in_progress",
			"objectives": [
				{"text": "老鼠", "cur": 0, "max": 5},
				{"text": "回报村长", "cur": 0, "max": 1},
			],
		},
		{
			"id": "extra_side",
			"title": "额外支线",
			"status": "in_progress",
			"objectives": [{"text": "探索", "cur": 0, "max": 1}],
		},
		{
			"id": "sixth_active",
			"title": "第六个不应出现",
			"status": "in_progress",
			"objectives": [{"text": "隐藏", "cur": 0, "max": 1}],
		},
	]

	var active: Array = Util.active_quests(snap, 5)
	failed += _expect(active.size() == 5, "cap 5 active (skip completed)")
	var ids: Array = []
	for q in active:
		ids.append(str(q.get("id", "")))
	failed += _expect(not ids.has("welcome_gift"), "completed excluded")
	failed += _expect(not ids.has("sixth_active"), "6th capped out")
	failed += _expect(ids.has("pond_fishing"), "ready included")

	var obj_line: String = Util.format_objective({"text": "野草", "cur": 2, "max": 5})
	failed += _expect(obj_line == "野草 2/5", "objective format 野草 2/5 got '%s'" % obj_line)

	var text: String = Util.build_tracker_text(snap, 5)
	failed += _expect(text.find("新手指引") >= 0, "title in text")
	failed += _expect(text.find("野草 2/5") >= 0, "herb progress in text")
	failed += _expect(text.find("假人 1/3") >= 0, "dummy progress in text")
	failed += _expect(text.find("可交付") >= 0, "ready marker")
	failed += _expect(text.find("欢迎礼") < 0, "completed title omitted")
	failed += _expect(text.find("第六个不应出现") < 0, "6th title omitted")
	failed += _expect(text.find("老鼠 0/5") >= 0, "multi-obj first line")
	failed += _expect(text.find("回报村长 0/1") >= 0, "multi-obj second line")

	# Live journal snapshot smoke (catalog + grant).
	var QuestJournal = load("res://scripts/net/combat/quest_journal.gd")
	var j = QuestJournal.new()
	j.load_catalog()
	j.clear()
	failed += _expect(j.accept_quest("herb_gather"), "accept herb_gather")
	j.note_item_gain("wild_herb", 2)
	var live: Array = j.snapshot()
	var live_text: String = Util.build_tracker_text(live, 5)
	failed += _expect(live_text.find("2/5") >= 0 or live_text.find("2 / 5") >= 0, "live journal progress in tracker text")
	failed += _expect(not live_text.strip_edges().is_empty(), "live text non-empty")

	# HUD wiring: apply_quest_snapshot refreshes tracker panel.
	var hud_scene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(hud_scene != null, "hud scene")
	if hud_scene != null:
		var hud = hud_scene.instantiate()
		root.add_child(hud)
		await process_frame
		await process_frame
		hud.apply_quest_snapshot(snap)
		await process_frame
		await process_frame
		failed += _expect(hud._quest_tracker != null, "tracker node")
		failed += _expect(hud._quest_tracker.visible, "tracker visible after snapshot")
		var body = hud._quest_tracker.find_child("TrackerBody", true, false)
		failed += _expect(body != null and body.get_child_count() >= 2, "tracker body has rows")
		# Toggle off via flag
		var gs = load("res://scripts/game/game_settings.gd").get_i()
		if gs != null:
			gs.persist_enabled = false
			gs.set_flag("show_quest_tracker", false)
			hud._refresh_quest_tracker()
			await process_frame
			failed += _expect(not hud._quest_tracker.visible, "tracker hidden when flag off")
			gs.set_flag("show_quest_tracker", true)
			hud._refresh_quest_tracker()
			await process_frame
			failed += _expect(hud._quest_tracker.visible, "tracker shown when flag on")
			failed += _expect(int(gs.key_for("quest_tracker")) == KEY_Y, "default Y bind")

	if failed == 0:
		print("PASS quest tracker")
		quit(0)
	else:
		push_error("FAIL quest tracker (%d)" % failed)
		quit(1)


func _expect(cond: bool, msg: String) -> int:
	if cond:
		print("  ok: ", msg)
		return 0
	push_error("FAIL: " + msg)
	print("  FAIL: ", msg)
	return 1
