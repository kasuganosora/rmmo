extends SceneTree
## Headless: NPC quest accept + journal abandon + MockServer dialogue options.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var QuestJournal = load("res://scripts/net/combat/quest_journal.gd")
	var j = QuestJournal.new()
	j.load_catalog()
	j.clear()
	failed += _expect(j.accept_quest("slime_hunt"), "accept slime_hunt")
	failed += _expect(j.is_accepted("slime_hunt"), "is_accepted")
	var n1: int = j.snapshot().size()
	var ab: Dictionary = j.try_abandon_quest("slime_hunt")
	failed += _expect(bool(ab.get("ok", false)), "abandon in_progress ok")
	failed += _expect(j.snapshot().size() == n1 - 1, "list shrunk after abandon")
	failed += _expect(not j.is_accepted("slime_hunt"), "not accepted after abandon")

	j.clear()
	j.accept_quest("welcome_gift")
	j.mark_completed("welcome_gift")
	var ab_c: Dictionary = j.try_abandon_quest("welcome_gift")
	failed += _expect(not bool(ab_c.get("ok", true)), "cannot abandon completed")
	failed += _expect(str(ab_c.get("reason", "")) == "completed", "reason completed")

	# Offers for giver when not accepted
	j.clear()
	var offers: Array = j.list_offers_for_npc("actor_rest")
	var offer_ids := {}
	for o in offers:
		offer_ids[str(o.get("id", ""))] = true
	failed += _expect(offer_ids.has("village_trial"), "actor_rest offers village_trial")
	failed += _expect(not offer_ids.has("slime_hunt"), "actor_rest does not offer slime_hunt")
	var voffers: Array = j.list_offers_for_npc("vendor_demo")
	var vids := {}
	for o2 in voffers:
		vids[str(o2.get("id", ""))] = true
	failed += _expect(vids.has("slime_hunt"), "vendor offers slime_hunt")
	failed += _expect(vids.has("herb_gather"), "vendor offers herb_gather")

	j.accept_quest("village_trial")
	var still := false
	for o3 in j.list_offers_for_npc("actor_rest"):
		if str(o3.get("id", "")) == "village_trial":
			still = true
	failed += _expect(not still, "village_trial no longer offered")

	# MockServer accept / interact options
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_quest_accept_abandon: FAIL no MockServer")
		quit(1)
		return
	if srv.quest_journal == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.quest_journal != null, "server quest_journal")
	srv.quest_journal.clear()
	srv.quest_journal.grant_starter()
	# Side quests not auto-granted
	failed += _expect(not srv.quest_journal.is_accepted("slime_hunt"), "slime_hunt not auto")
	failed += _expect(not srv.quest_journal.is_accepted("herb_gather"), "herb_gather not auto")
	failed += _expect(not srv.quest_journal.is_accepted("village_trial"), "village_trial not auto")
	failed += _expect(srv.quest_journal.is_accepted("starter_step"), "starter_step auto")

	# Register giver NPC (avoid pack tile load in headless CI).
	if srv.has_method("register_npc"):
		srv.register_npc("actor_rest", 15, 10, false, false, 2, 0, 0, {"name": "休息中的少女", "interact_text": "有委托可以交给你。"})
	if srv.has_method("set_player_cell"):
		srv.set_player_cell(15, 11)
	if srv.has_method("_build_quest_dialogue_options"):
		var built: Array = srv._build_quest_dialogue_options("actor_rest")
		var built_ok := false
		for b in built:
			if typeof(b) == TYPE_DICTIONARY and str(b.get("id", "")) == "quest_accept:village_trial":
				built_ok = true
		failed += _expect(built_ok, "list/build options contain accept for giver")

	var inter: Dictionary = srv.try_interact("actor_rest", 15, 11)
	failed += _expect(bool(inter.get("ok", false)), "interact actor_rest ok")
	var opts: Array = []
	for a in inter.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "show_npc_dialogue":
			var ov: Variant = a.get("options", [])
			if typeof(ov) == TYPE_ARRAY:
				opts = ov
	var has_accept := false
	for opt in opts:
		if typeof(opt) != TYPE_DICTIONARY:
			continue
		if str(opt.get("id", "")).begins_with("quest_accept:village_trial"):
			has_accept = true
	failed += _expect(has_accept, "interact options contain quest_accept:village_trial")

	var acc: Dictionary = srv.try_accept_quest("village_trial")
	failed += _expect(bool(acc.get("ok", false)), "try_accept_quest ok")
	failed += _expect(srv.quest_journal.is_accepted("village_trial"), "accepted after try_accept")
	var has_qu := false
	for a2 in acc.get("actions", []):
		if typeof(a2) == TYPE_DICTIONARY and str(a2.get("type", "")) == "quest_update":
			has_qu = true
	failed += _expect(has_qu, "accept emits quest_update")

	# dialogue choice path
	srv.quest_journal.try_abandon_quest("slime_hunt")
	if not srv.quest_journal.is_accepted("slime_hunt"):
		pass
	var dc: Dictionary = srv.try_dialogue_choice("quest_accept:slime_hunt")
	failed += _expect(bool(dc.get("ok", false)), "dialogue quest_accept ok")
	failed += _expect(srv.quest_journal.is_accepted("slime_hunt"), "slime accepted via dialogue")

	var n_before: int = srv.get_quest_list().size()
	var abd: Dictionary = srv.try_abandon_quest("slime_hunt")
	failed += _expect(bool(abd.get("ok", false)), "server abandon ok")
	failed += _expect(srv.get_quest_list().size() == n_before - 1, "server list shrunk")

	# completed refuse via server
	var abd2: Dictionary = srv.try_abandon_quest("welcome_gift")
	failed += _expect(not bool(abd2.get("ok", true)), "server cannot abandon completed")

	if failed == 0:
		print("test_quest_accept_abandon: PASS")
		quit(0)
	else:
		print("test_quest_accept_abandon: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
