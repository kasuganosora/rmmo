extends SceneTree
## Headless: party quest share — ally kill/gather/fish via note_party_* advances local journal.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_party_quest_share: FAIL no MockServer")
		quit(1)
		return

	if srv.quest_journal == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.quest_journal != null, "quest_journal ready")
	failed += _expect(srv.has_method("note_party_kill"), "has note_party_kill")
	failed += _expect(srv.has_method("note_party_gather"), "has note_party_gather")
	failed += _expect(srv.has_method("note_party_fish"), "has note_party_fish")
	failed += _expect(srv.has_method("_party_quest_share_eligible"), "has share eligible helper")

	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._party_poll_pending = false
	srv._stub_ally_seq = 1
	srv._session_character_id = "1"
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.combat_stats != null:
		srv.combat_stats.reset_player(3)
		if srv.combat_stats.has_method("set_player_actor_id"):
			srv.combat_stats.set_player_actor_id("1")

	# Fresh journal with kill / gather / fish quests
	srv.quest_journal.clear()
	srv.quest_journal.load_catalog()
	failed += _expect(srv.quest_journal.accept_quest("slime_hunt"), "accept slime_hunt")
	failed += _expect(srv.quest_journal.accept_quest("herb_gather"), "accept herb_gather")
	failed += _expect(srv.quest_journal.accept_quest("pond_fishing"), "accept pond_fishing")
	failed += _expect(_kill_cur(srv, "slime_hunt") == 0, "kill cur 0 start")
	failed += _expect(_gather_cur(srv, "herb_gather") == 0, "gather cur 0 start")
	failed += _expect(_fish_cur(srv, "pond_fishing") == 0, "fish cur 0 start")

	# --- Solo: note_party_* must be no-ops ---
	failed += _expect(not srv.in_party(), "solo not in party")
	failed += _expect(not bool(srv._party_quest_share_eligible()), "solo not share-eligible")
	var solo_k: Array = srv.note_party_kill("street_slime")
	failed += _expect(solo_k.is_empty(), "solo note_party_kill empty")
	failed += _expect(_kill_cur(srv, "slime_hunt") == 0, "solo ally kill no progress")
	var solo_g: Array = srv.note_party_gather("wild_herb", 1)
	failed += _expect(solo_g.is_empty(), "solo note_party_gather empty")
	failed += _expect(_gather_cur(srv, "herb_gather") == 0, "solo ally gather no progress")
	var solo_f: Array = srv.note_party_fish("fish_small", 1)
	failed += _expect(solo_f.is_empty(), "solo note_party_fish empty")
	failed += _expect(_fish_cur(srv, "pond_fishing") == 0, "solo ally fish no progress")

	# Own kill still works solo (normal path)
	failed += _expect(bool(srv.quest_journal.note_kill("street_slime")), "own note_kill works solo")
	failed += _expect(_kill_cur(srv, "slime_hunt") == 1, "own kill → cur 1")

	# --- Party with stub (N=2 same-map) ---
	var cr: Dictionary = srv.try_party_create()
	failed += _expect(bool(cr.get("ok", false)), "party create ok")
	var stub: Dictionary = srv._party_make_stub("stub_ally_qshare")
	srv._party_members.append(stub)
	failed += _expect(srv.in_party(), "in party")
	failed += _expect(int(srv._party_online_same_map_count()) == 2, "online same-map N=2")
	failed += _expect(bool(srv._party_quest_share_eligible()), "share eligible N=2")

	# Ally kill credit
	var ally_k: Array = srv.note_party_kill("slime")
	failed += _expect(not ally_k.is_empty(), "note_party_kill returns actions")
	failed += _expect(_has_action(ally_k, "quest_update"), "ally kill quest_update")
	failed += _expect(_has_msg(ally_k, "队伍协作：任务进度 +1"), "ally kill collab msg")
	failed += _expect(_kill_cur(srv, "slime_hunt") == 2, "ally kill → cur 2")

	# Own kill while in party: normal path, no party-collab message from note_kill
	failed += _expect(bool(srv.quest_journal.note_kill("street_slime")), "own kill in party")
	failed += _expect(_kill_cur(srv, "slime_hunt") == 3, "own kill → cur 3 (capped max)")
	# At cap: further ally credit no-ops
	var capped: Array = srv.note_party_kill("slime")
	failed += _expect(capped.is_empty(), "at-cap ally kill empty")

	# Ally gather
	var ally_g: Array = srv.note_party_gather("wild_herb", 2)
	failed += _expect(_has_msg(ally_g, "队伍协作：任务进度 +1"), "ally gather collab msg")
	failed += _expect(_gather_cur(srv, "herb_gather") == 2, "ally gather → cur 2")

	# Ally fish
	var ally_f: Array = srv.note_party_fish("fish_small", 1)
	failed += _expect(_has_msg(ally_f, "队伍协作：任务进度 +1"), "ally fish collab msg")
	failed += _expect(_fish_cur(srv, "pond_fishing") == 1, "ally fish → cur 1")

	# Offline stub → not eligible
	srv._party_members[1]["online"] = false
	failed += _expect(not bool(srv._party_quest_share_eligible()), "offline stub not eligible")
	var off_g: Array = srv.note_party_gather("wild_herb", 1)
	failed += _expect(off_g.is_empty(), "offline ally gather empty")
	failed += _expect(_gather_cur(srv, "herb_gather") == 2, "offline no gather advance")

	# Far map stub → not eligible
	srv._party_members[1]["online"] = true
	srv._party_members[1]["map_id"] = "other_map_xyz"
	failed += _expect(not bool(srv._party_quest_share_eligible()), "far map not eligible")
	var far_f: Array = srv.note_party_fish("fish_small", 1)
	failed += _expect(far_f.is_empty(), "far map ally fish empty")
	failed += _expect(_fish_cur(srv, "pond_fishing") == 1, "far map no fish advance")

	# Restore same-map and confirm still works
	srv._party_members[1]["map_id"] = ""
	failed += _expect(bool(srv._party_quest_share_eligible()), "restored eligible")
	var again: Array = srv.note_party_fish("fish_any", 1)
	failed += _expect(_has_msg(again, "队伍协作：任务进度 +1"), "restored ally fish msg")
	failed += _expect(_fish_cur(srv, "pond_fishing") == 2, "restored ally fish → cur 2")

	# Empty kind / empty gather
	failed += _expect(srv.note_party_kill("").is_empty(), "empty npc_kind empty")
	failed += _expect(srv.note_party_gather("").is_empty(), "empty gather_id empty")

	# Cleanup
	if srv.has_method("_party_clear"):
		srv._party_clear()

	if failed == 0:
		print("test_party_quest_share: PASS")
		quit(0)
	else:
		print("test_party_quest_share: FAIL count=%d" % failed)
		quit(1)


func _kill_cur(srv, qid: String) -> int:
	var q: Dictionary = srv.quest_journal.get_quest(qid)
	for o in q.get("objectives", []):
		if typeof(o) != TYPE_DICTIONARY:
			continue
		if str(o.get("kill", o.get("kill_contains", ""))).strip_edges() != "":
			return int(o.get("cur", 0))
	return -1


func _gather_cur(srv, qid: String) -> int:
	var q: Dictionary = srv.quest_journal.get_quest(qid)
	for o in q.get("objectives", []):
		if typeof(o) != TYPE_DICTIONARY:
			continue
		if str(o.get("gather", o.get("item", ""))).strip_edges() != "":
			return int(o.get("cur", 0))
	return -1


func _fish_cur(srv, qid: String) -> int:
	var q: Dictionary = srv.quest_journal.get_quest(qid)
	for o in q.get("objectives", []):
		if typeof(o) != TYPE_DICTIONARY:
			continue
		if str(o.get("fish_catch", o.get("fish", ""))).strip_edges() != "" or o.has("fish_catch") or o.has("fish"):
			return int(o.get("cur", 0))
	return -1


func _has_action(actions: Array, typ: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _has_msg(actions: Array, text: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			if str(a.get("text", "")) == text:
				return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
