extends SceneTree
## Headless smoke: quest_journal catalog + MockServer get_quest_list snapshot.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var QuestJournal = load("res://scripts/net/combat/quest_journal.gd")
	var j = QuestJournal.new()
	j.load_catalog()
	failed += _expect(not j._catalog.is_empty(), "catalog loaded")
	j.grant_starter()
	var snap: Array = j.snapshot()
	failed += _expect(snap.size() >= 3, "starter quests >= 3 (starter + completed samples)")
	var statuses := {}
	for q in snap:
		failed += _expect(typeof(q) == TYPE_DICTIONARY, "entry dict")
		failed += _expect(str(q.get("id", "")) != "", "has id")
		failed += _expect(str(q.get("title", "")) != "", "has title")
		failed += _expect(typeof(q.get("objectives", null)) == TYPE_ARRAY, "has objectives")
		var st := str(q.get("status", ""))
		statuses[st] = true
		failed += _expect(st in ["in_progress", "ready", "completed"], "status in_progress|ready|completed")
	failed += _expect(statuses.has("in_progress"), "has in-progress")
	# Live starters begin at 0 progress (ready only after objectives complete).
	failed += _expect(statuses.has("completed"), "has completed")
	# Progress API smoke: force a quest ready via note_kill spam.
	var progressed := false
	for _i in range(5):
		if j.note_kill("slime"):
			progressed = true
	failed += _expect(progressed, "note_kill progresses")
	var any_ready := false
	for q in j.snapshot():
		if str(q.get("status", "")) == "ready":
			any_ready = true
			break
	failed += _expect(any_ready, "has deliverable after kills")

	# Reach / gather objective wiring
	var j2 = QuestJournal.new()
	j2.load_catalog()
	j2.clear()
	failed += _expect(j2.accept_quest("village_trial"), "accept village_trial")
	failed += _expect(j2.accept_quest("herb_gather"), "accept herb_gather")
	# talk first objective optional; reach should complete 2nd obj
	var reach_ok: bool = bool(j2.note_reach("street_map"))
	failed += _expect(reach_ok, "note_reach street_map progresses")
	var vt: Dictionary = j2.get_quest("village_trial")
	var vt_objs: Array = vt.get("objectives", [])
	var reach_done: bool = false
	for o in vt_objs:
		if typeof(o) != TYPE_DICTIONARY:
			continue
		var od: Dictionary = o
		if str(od.get("reach", od.get("map_id", ""))) != "":
			reach_done = int(od.get("cur", 0)) >= int(od.get("max", 1))
	failed += _expect(reach_done, "village_trial reach objective done")
	# alias: street_central matches street_map reach
	var j3 = QuestJournal.new()
	j3.load_catalog()
	j3.clear()
	j3.accept_quest("village_trial")
	failed += _expect(j3.note_reach("street_central", "street_central", "res://street_map"), "alias street_central match")
	var vt3: Dictionary = j3.get_quest("village_trial")
	var reach_alias: bool = false
	for o in vt3.get("objectives", []):
		if typeof(o) != TYPE_DICTIONARY:
			continue
		if str(o.get("reach", "")) == "street_map":
			reach_alias = int(o.get("cur", 0)) >= 1
	failed += _expect(reach_alias, "street_central aliases street_map")
	# herb via item gain ×5
	var j4 = QuestJournal.new()
	j4.load_catalog()
	j4.clear()
	j4.accept_quest("herb_gather")
	failed += _expect(j4.note_item_gain("wild_herb", 5), "herb ×5 item gain")
	var hg: Dictionary = j4.get_quest("herb_gather")
	failed += _expect(str(hg.get("status", "")) == "ready", "herb_gather ready after 5")
	var j5 = QuestJournal.new()
	j5.load_catalog()
	j5.clear()
	j5.accept_quest("herb_gather")
	var stepped: bool = true
	for _k in range(5):
		if not j5.note_item_gain("wild_herb", 1):
			# last calls may still return true until capped; allow final false only after full
			pass
	var hg5: Dictionary = j5.get_quest("herb_gather")
	failed += _expect(str(hg5.get("status", "")) == "ready", "herb_gather ready after five ×1")
	# gather helper
	var j6 = QuestJournal.new()
	j6.load_catalog()
	j6.clear()
	j6.accept_quest("herb_gather")
	failed += _expect(j6.note_gather("wild_herb", 5), "note_gather wild_herb")
	failed += _expect(str(j6.get_quest("herb_gather").get("status", "")) == "ready", "note_gather ready")

	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_quest_journal: FAIL no MockServer")
		quit(1)
		return
	if srv.quest_journal == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.quest_journal != null, "server quest_journal")
	failed += _expect(srv.has_method("get_quest_list"), "get_quest_list")
	var list: Array = srv.get_quest_list()
	failed += _expect(list.size() >= 3, "server list >= 3")

	# abandon in-progress only
	var abandon_id := ""
	for q in list:
		if str(q.get("status", "")) == "in_progress":
			abandon_id = str(q.get("id", ""))
			break
	failed += _expect(abandon_id != "", "has in_progress to abandon")
	var ab: Dictionary = srv.quest_journal.try_abandon_quest(abandon_id)
	failed += _expect(bool(ab.get("ok", false)), "abandon ok")
	failed += _expect(srv.get_quest_list().size() == list.size() - 1, "list shrunk")
	# cannot abandon completed
	var completed_id := ""
	for q2 in srv.get_quest_list():
		if str(q2.get("status", "")) == "completed":
			completed_id = str(q2.get("id", ""))
			break
	if completed_id != "":
		var ab2: Dictionary = srv.quest_journal.try_abandon_quest(completed_id)
		failed += _expect(not bool(ab2.get("ok", true)), "cannot abandon completed")

	if failed == 0:
		print("test_quest_journal: PASS")
		quit(0)
	else:
		print("test_quest_journal: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL", label)
	return 1
