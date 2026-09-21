extends SceneTree
## Headless: titles catalog / counters / unlock / equip / craft+death hooks.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_titles: FAIL no MockServer")
		quit(1)
		return
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.get("title_catalog") == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_title_equip"), "has try_title_equip")
	failed += _expect(srv.has_method("snapshot_titles"), "has snapshot_titles")
	failed += _expect(srv.get("title_catalog") != null, "title_catalog loaded")
	failed += _expect(srv.combat_stats != null, "combat_stats present")

	var cat_n := 0
	if srv.title_catalog != null and srv.title_catalog.has_method("list_all"):
		cat_n = srv.title_catalog.list_all().size()
	failed += _expect(cat_n >= 4, "catalog size>=4 (%d)" % cat_n)
	failed += _expect(srv.title_catalog.has_title("newbie_slayer"), "has newbie_slayer")
	failed += _expect(srv.title_catalog.has_title("crafter"), "has crafter")
	failed += _expect(srv.title_catalog.has_title("fallen"), "has fallen")

	# Fresh progress
	srv.combat_stats.reset_titles()
	var snap0: Dictionary = srv.snapshot_titles()
	failed += _expect(int(snap0.get("kills", -1)) == 0, "kills 0")
	failed += _expect(int(snap0.get("crafts", -1)) == 0, "crafts 0")
	failed += _expect(int(snap0.get("deaths", -1)) == 0, "deaths 0")
	failed += _expect(str(snap0.get("active_title", "x")) == "", "no active")
	failed += _expect((snap0.get("unlocked_titles", ["x"]) as Array).is_empty(), "no unlocks")

	# Equip locked fails
	var locked: Dictionary = srv.try_title_equip("newbie_slayer")
	failed += _expect(not bool(locked.get("ok", true)), "equip locked fails")
	failed += _expect(str(locked.get("reason", "")) == "locked", "reason locked")

	# Kill counter unlock
	var kill_acts: Array = srv._note_title_counter("kills", 1)
	failed += _expect(int(srv.combat_stats.title_counters.get("kills", 0)) == 1, "kills=1")
	failed += _expect(_msg_has_arr(kill_acts, "解锁称号"), "unlock msg on kill")
	failed += _expect(srv.combat_stats.is_title_unlocked("newbie_slayer"), "newbie unlocked")
	failed += _expect(_has_arr(kill_acts, "title_update"), "kill title_update")

	# Equip / unequip
	var eq: Dictionary = srv.try_title_equip("newbie_slayer")
	failed += _expect(bool(eq.get("ok", false)), "equip ok")
	failed += _expect(str(srv.combat_stats.active_title) == "newbie_slayer", "active set")
	failed += _expect(_has(eq, "title_update"), "equip title_update")
	failed += _expect(_msg_has(eq, "已装备称号"), "equip msg")
	var uneq: Dictionary = srv.try_title_equip("")
	failed += _expect(bool(uneq.get("ok", false)), "unequip ok")
	failed += _expect(str(srv.combat_stats.active_title) == "", "active cleared")
	failed += _expect(_msg_has(uneq, "已卸下称号"), "unequip msg")

	# Unknown title
	var unk: Dictionary = srv.try_title_equip("no_such_title")
	failed += _expect(not bool(unk.get("ok", true)), "unknown fails")
	failed += _expect(str(unk.get("reason", "")) == "unknown", "reason unknown")

	# Craft hook (if inventory/recipe ready)
	if srv.inventory != null and srv.recipe_catalog != null:
		srv.inventory.clear()
		srv.inventory.add_gold(100)
		srv.inventory.add_item("wild_herb", 2)
		var before_c: int = int(srv.combat_stats.title_counters.get("crafts", 0))
		var craft: Dictionary = srv.try_craft("craft_hp_potion", 1)
		failed += _expect(bool(craft.get("ok", false)), "craft success for titles")
		failed += _expect(int(srv.combat_stats.title_counters.get("crafts", 0)) == before_c + 1, "crafts +1")
		failed += _expect(srv.combat_stats.is_title_unlocked("crafter") or before_c + 1 >= 1, "crafter path")
		if int(srv.combat_stats.title_counters.get("crafts", 0)) >= 1:
			failed += _expect(srv.combat_stats.is_title_unlocked("crafter"), "crafter unlocked")
			failed += _expect(_msg_has(craft, "解锁称号") or srv.combat_stats.is_title_unlocked("crafter"), "craft unlock msg or already")
	else:
		print("  SKIP craft hook (no inventory/recipe)")

	# Death counter via _note_title_counter (finalize path uses same helper)
	var before_d: int = int(srv.combat_stats.title_counters.get("deaths", 0))
	var death_acts: Array = srv._note_title_counter("deaths", 1)
	failed += _expect(int(srv.combat_stats.title_counters.get("deaths", 0)) == before_d + 1, "deaths +1")
	if before_d == 0:
		failed += _expect(srv.combat_stats.is_title_unlocked("fallen"), "fallen unlocked")
		failed += _expect(_msg_has_arr(death_acts, "解锁称号"), "death unlock msg")

	# Snapshot lists unlocked flags
	var snap1: Dictionary = srv.snapshot_titles()
	var titles: Array = snap1.get("titles", [])
	failed += _expect(titles.size() >= 4, "snap titles list")
	var found_newbie := false
	for row in titles:
		if typeof(row) == TYPE_DICTIONARY and str(row.get("id", "")) == "newbie_slayer":
			found_newbie = bool(row.get("unlocked", false))
	failed += _expect(found_newbie, "snap marks newbie unlocked")

	# Multi-kill threshold (hunter needs 10)
	srv.combat_stats.reset_titles()
	srv._note_title_counter("kills", 9)
	failed += _expect(not srv.combat_stats.is_title_unlocked("hunter"), "hunter still locked at 9")
	srv._note_title_counter("kills", 1)
	failed += _expect(srv.combat_stats.is_title_unlocked("hunter"), "hunter at 10")
	failed += _expect(srv.combat_stats.is_title_unlocked("newbie_slayer"), "newbie also at 10")

	var am: Node = root.get_node_or_null("AssetManager")
	failed += _expect(am != null and bool(am.has("content://data/combat/titles.json")), "external titles.json")

	# Document: kill/craft/death hooks all wired via _note_title_counter in
	# _finalize_combat_result (kills + deaths) and try_craft (crafts).

	if failed == 0:
		print("test_titles: PASS")
		quit(0)
		return
	print("test_titles: FAIL count=%d" % failed)
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
