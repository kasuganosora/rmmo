extends SceneTree
## Headless: note_reach / herb gather / MockServer transfer quest_update.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var QuestJournal = load("res://scripts/net/combat/quest_journal.gd")
	var j = QuestJournal.new()
	j.load_catalog()
	j.clear()
	j.accept_quest("village_trial")
	j.accept_quest("herb_gather")
	failed += _expect(bool(j.note_reach("street_map")), "reach street_map")
	var objs: Array = j.get_quest("village_trial").get("objectives", [])
	var ok_reach: bool = false
	for o in objs:
		if str(o.get("reach", "")) == "street_map" and int(o.get("cur", 0)) >= 1:
			ok_reach = true
	failed += _expect(ok_reach, "reach cur>=1")
	j.clear()
	j.accept_quest("village_trial")
	failed += _expect(bool(j.note_reach("", "street_central", "res://street_map")), "reach via content/pack")
	failed += _expect(int(j.get_quest("village_trial")["objectives"][1].get("cur", 0)) >= 1, "obj1 progressed")
	j.clear()
	j.accept_quest("herb_gather")
	failed += _expect(bool(j.note_item_gain("wild_herb", 5)), "herb 5")
	failed += _expect(str(j.get_quest("herb_gather").get("status", "")) == "ready", "herb ready")

	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_quest_reach_gather: FAIL no MockServer")
		quit(1)
		return
	if srv.quest_journal == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	# Simulate enter + transfer to street
	if srv.has_method("_load_pack"):
		srv._load_pack("res://demo_map")
	if srv.quest_journal != null:
		srv.quest_journal.clear()
		srv.quest_journal.grant_starter()
		# Side/main offers are NPC-accepted; accept village_trial for reach smoke.
		srv.quest_journal.accept_quest("village_trial")
	# Place on demo warp to street (15,9) if present
	var tr: Dictionary = {}
	if srv.has_method("set_player_cell"):
		srv.set_player_cell(15, 9)
	if srv.has_method("try_transfer"):
		tr = srv.try_transfer(15, 9)
	failed += _expect(bool(tr.get("ok", false)), "try_transfer to street ok")
	if bool(tr.get("ok", false)):
		failed += _expect(str(tr.get("map_id", "")).find("street") >= 0 or str(tr.get("pack_path", "")).find("street") >= 0, "landed street")
		var snap: Array = tr.get("quests", [])
		if typeof(snap) != TYPE_ARRAY or snap.is_empty():
			snap = srv.get_quest_list()
		var found_reach: bool = false
		for q in snap:
			if str(q.get("id", "")) != "village_trial":
				continue
			for o in q.get("objectives", []):
				if str(o.get("reach", o.get("map_id", ""))) != "" and int(o.get("cur", 0)) >= 1:
					found_reach = true
		failed += _expect(found_reach, "transfer notes village_trial reach")

	if failed == 0:
		print("test_quest_reach_gather: PASS")
		quit(0)
	else:
		print("test_quest_reach_gather: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
