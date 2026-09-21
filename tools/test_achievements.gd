extends SceneTree
## Headless: achievements catalog / force progress / unlock / reward crumbs.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_achievements: FAIL no MockServer")
		quit(1)
		return
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.get("achievement_catalog") == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("snapshot_achievements"), "has snapshot_achievements")
	failed += _expect(srv.has_method("force_achievement_progress"), "has force_achievement_progress")
	failed += _expect(srv.has_method("force_achievement_unlock"), "has force_achievement_unlock")
	failed += _expect(srv.get("achievement_catalog") != null, "achievement_catalog loaded")
	failed += _expect(srv.combat_stats != null, "combat_stats present")

	var cat_n := 0
	if srv.achievement_catalog != null and srv.achievement_catalog.has_method("list_all"):
		cat_n = srv.achievement_catalog.list_all().size()
	failed += _expect(cat_n >= 4, "catalog size>=4 (%d)" % cat_n)
	failed += _expect(srv.achievement_catalog.has_achievement("ach_first_kill"), "has ach_first_kill")
	failed += _expect(srv.achievement_catalog.has_achievement("ach_gather_10"), "has ach_gather_10")
	failed += _expect(srv.achievement_catalog.has_achievement("ach_level_5"), "has ach_level_5")
	failed += _expect(srv.achievement_catalog.has_achievement("ach_party"), "has ach_party")
	failed += _expect(
		srv.achievement_catalog.achievement_name("ach_first_kill") == "初战告捷",
		"name 初战告捷"
	)

	var am: Node = root.get_node_or_null("AssetManager")
	failed += _expect(am != null and bool(am.has("content://data/combat/achievements.json")), "external achievements.json")

	# Fresh
	srv.combat_stats.reset_achievements()
	var snap0: Dictionary = srv.snapshot_achievements()
	failed += _expect(int(snap0.get("kills", -1)) == 0, "kills 0")
	failed += _expect(int(snap0.get("gathers", -1)) == 0, "gathers 0")
	failed += _expect(int(snap0.get("party", -1)) == 0, "party 0")
	failed += _expect((snap0.get("unlocked_achievements", ["x"]) as Array).is_empty(), "no unlocks")

	# Force progress: first kill
	var gold0: int = 0
	if srv.inventory != null:
		gold0 = int(srv.inventory.get_gold())
	var r_kill: Dictionary = srv.force_achievement_progress("kills", 1)
	failed += _expect(bool(r_kill.get("ok", false)), "force kills=1 ok")
	failed += _expect(srv.combat_stats.is_achievement_unlocked("ach_first_kill"), "ach_first_kill unlocked")
	failed += _expect(_msg_has(r_kill, "成就解锁：初战告捷"), "unlock msg first kill")
	failed += _expect(_has(r_kill, "achievement_update"), "kill achievement_update")
	if srv.inventory != null:
		failed += _expect(int(srv.inventory.get_gold()) >= gold0 + 20, "gold crumb +20")
	failed += _expect(_msg_has(r_kill, "成就奖励") or _msg_has(r_kill, "金币"), "reward crumb msg")

	# Force gather progress (threshold 10)
	srv.combat_stats.reset_achievements()
	if srv.inventory != null:
		# re-baseline after reset (gold not reset by achievements)
		gold0 = int(srv.inventory.get_gold())
	var r_g9: Dictionary = srv.force_achievement_progress("gathers", 9)
	failed += _expect(not srv.combat_stats.is_achievement_unlocked("ach_gather_10"), "gather locked at 9")
	var r_g10: Dictionary = srv.force_achievement_progress("gathers", 10)
	failed += _expect(srv.combat_stats.is_achievement_unlocked("ach_gather_10"), "gather unlocked at 10")
	failed += _expect(_msg_has(r_g10, "勤劳采撷"), "gather unlock name")

	# Level path via force
	srv.combat_stats.reset_achievements()
	var r_lv: Dictionary = srv.force_achievement_progress("level", 5)
	failed += _expect(srv.combat_stats.is_achievement_unlocked("ach_level_5"), "level 5 unlocked")
	failed += _expect(_msg_has(r_lv, "初出茅庐"), "level unlock name")

	# Party via counter note helper
	srv.combat_stats.reset_achievements()
	var party_acts: Array = srv._note_achievement_counter("party", 1)
	failed += _expect(srv.combat_stats.is_achievement_unlocked("ach_party"), "party unlocked")
	failed += _expect(_msg_has_arr(party_acts, "结伴而行"), "party unlock name")

	# Force unlock path (direct)
	srv.combat_stats.reset_achievements()
	var r_force: Dictionary = srv.force_achievement_unlock("ach_first_kill")
	failed += _expect(bool(r_force.get("ok", false)), "force unlock ok")
	failed += _expect(srv.combat_stats.is_achievement_unlocked("ach_first_kill"), "force unlock set")
	failed += _expect(_msg_has(r_force, "成就解锁：初战告捷"), "force unlock msg")
	var r_again: Dictionary = srv.force_achievement_unlock("ach_first_kill")
	failed += _expect(not bool(r_again.get("ok", true)), "force unlock already fails")
	failed += _expect(str(r_again.get("reason", "")) == "already", "reason already")

	# Unknown force unlock
	var r_unk: Dictionary = srv.force_achievement_unlock("no_such_ach")
	failed += _expect(not bool(r_unk.get("ok", true)), "unknown force fails")
	failed += _expect(str(r_unk.get("reason", "")) == "unknown", "reason unknown")

	# Snapshot marks unlocked
	srv.combat_stats.reset_achievements()
	srv.force_achievement_progress("kills", 1)
	var snap1: Dictionary = srv.snapshot_achievements()
	var rows: Array = snap1.get("achievements", [])
	failed += _expect(rows.size() >= 4, "snap achievements list")
	var found_first := false
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and str(row.get("id", "")) == "ach_first_kill":
			found_first = bool(row.get("unlocked", false))
	failed += _expect(found_first, "snap marks ach_first_kill unlocked")

	# Hook helpers exist for live paths
	failed += _expect(srv.has_method("_note_achievement_counter"), "has _note_achievement_counter")
	failed += _expect(srv.has_method("_sync_achievement_level"), "has _sync_achievement_level")

	if failed == 0:
		print("test_achievements: PASS")
		quit(0)
		return
	print("test_achievements: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	return _has_arr(result.get("actions", []), typ)


func _has_arr(actions: Variant, typ: String) -> bool:
	if typeof(actions) != TYPE_ARRAY:
		return false
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _msg_has(result: Dictionary, needle: String) -> bool:
	return _msg_has_arr(result.get("actions", []), needle)


func _msg_has_arr(actions: Variant, needle: String) -> bool:
	if typeof(actions) != TYPE_ARRAY:
		return false
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if needle in str(a.get("text", "")):
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
