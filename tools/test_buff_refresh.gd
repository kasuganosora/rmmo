extends SceneTree
## Headless: same-id status re-apply refreshes duration; stack_max>1 increments (cap).


const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_buff_refresh: FAIL no MockServer")
		quit(1)
		return
	if srv.combat_engine == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	var stats = srv.combat_stats
	var engine = srv.combat_engine
	failed += _expect(stats != null and stats.statuses != null and engine != null, "combat layers")
	if stats == null or engine == null:
		print("test_buff_refresh: FAIL count=%d" % failed)
		quit(1)
		return

	# --- Core: refresh duration, default stack_max 1 ---
	stats.statuses.clear_everything()
	var def_a := {
		"id": "debug_refresh",
		"name": "调试刷新",
		"kind": "buff",
		"duration": 10.0,
		"atk_add": 1,
	}
	engine._apply_status_to("player", def_a, "player", [])
	failed += _expect(stats.statuses.has_status("player", "debug_refresh"), "debug applied")
	failed += _expect(_count(stats, "debug_refresh") == 1, "one instance")
	failed += _expect(_stacks(stats, "debug_refresh") == 1, "stacks 1 default")
	failed += _expect(abs(_remaining(stats, "debug_refresh") - 10.0) < 0.05, "remaining ~10")

	# Tick down then re-apply → duration refreshed, still 1 stack / 1 instance
	stats.statuses.tick_statuses(4.0, stats)
	var mid := _remaining(stats, "debug_refresh")
	failed += _expect(mid < 7.0 and mid > 5.0, "ticked to ~6 (got %.2f)" % mid)
	engine._apply_status_to("player", def_a, "player", [])
	failed += _expect(_count(stats, "debug_refresh") == 1, "re-apply still one instance")
	failed += _expect(_stacks(stats, "debug_refresh") == 1, "re-apply stacks stay 1")
	failed += _expect(abs(_remaining(stats, "debug_refresh") - 10.0) < 0.05, "re-apply refreshed to ~10")

	# --- stack_max 3 (debug-only): increment + cap ---
	stats.statuses.clear_everything()
	var def_stack := {
		"id": "debug_stack",
		"name": "调试叠加",
		"kind": "buff",
		"duration": 8.0,
		"stack_max": 3,
		"atk_add": 1,
	}
	engine._apply_status_to("player", def_stack, "player", [])
	failed += _expect(_stacks(stats, "debug_stack") == 1, "stack start 1")
	engine._apply_status_to("player", def_stack, "player", [])
	failed += _expect(_stacks(stats, "debug_stack") == 2, "stack 2")
	failed += _expect(_count(stats, "debug_stack") == 1, "still one instance at 2")
	failed += _expect(abs(_remaining(stats, "debug_stack") - 8.0) < 0.05, "stack refresh dur")
	engine._apply_status_to("player", def_stack, "player", [])
	failed += _expect(_stacks(stats, "debug_stack") == 3, "stack 3")
	engine._apply_status_to("player", def_stack, "player", [])
	failed += _expect(_stacks(stats, "debug_stack") == 3, "stack capped at 3")
	failed += _expect(_count(stats, "debug_stack") == 1, "capped still one instance")

	# --- Food well_fed: re-eat refreshes, stack_max 1 ---
	stats.statuses.clear_everything()
	stats.item_ready_at.clear()
	stats.player["hp"] = 10
	stats.player["hp_max"] = 200
	srv.inventory.clear()
	srv.inventory.add_item("food_grilled_fish", 2)
	var r1: Dictionary = srv.try_use_item("food_grilled_fish")
	failed += _expect(bool(r1.get("ok", false)), "eat grilled ok")
	failed += _expect(stats.statuses.has_status("player", "well_fed"), "well_fed on")
	failed += _expect(_stacks(stats, "well_fed") == 1, "well_fed stacks 1")
	var wf_max := _remaining(stats, "well_fed")
	failed += _expect(wf_max > 50.0, "well_fed ~60s")
	stats.statuses.tick_statuses(20.0, stats)
	var wf_mid := _remaining(stats, "well_fed")
	failed += _expect(wf_mid < wf_max - 10.0, "well_fed ticked down")
	stats.item_ready_at.clear()
	stats.player["hp"] = 10
	var r1b: Dictionary = srv.try_use_item("food_grilled_fish")
	failed += _expect(bool(r1b.get("ok", false)), "re-eat ok")
	failed += _expect(_count(stats, "well_fed") == 1, "well_fed one instance")
	failed += _expect(_stacks(stats, "well_fed") == 1, "well_fed still stack 1")
	failed += _expect(_remaining(stats, "well_fed") > wf_mid + 10.0, "well_fed refreshed")

	# --- battle_shout re-cast refreshes ---
	var skills = srv.skill_catalog
	failed += _expect(skills != null and skills.has_skill("battle_shout"), "has battle_shout")
	stats.ensure_skill_book()
	if stats.skill_book.list_known().is_empty():
		stats.skill_book.grant_starters(skills)
	stats.skill_book.grant_skill_points(99)
	if not stats.skill_book.is_known("battle_shout"):
		var learn_bs: Dictionary = stats.skill_book.try_learn("battle_shout", skills, 99)
		failed += _expect(bool(learn_bs.get("ok", false)), "learn battle_shout")
	if srv.has_method("_party_clear"):
		srv._party_clear()
	stats.statuses.clear_everything()
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.player["mp_max"] = 50
	var rs1: Dictionary = srv.try_use_skill("battle_shout", "", 0, 0)
	failed += _expect(bool(rs1.get("ok", false)), "shout cast 1")
	failed += _expect(stats.statuses.has_status("player", "battle_shout"), "shout applied")
	failed += _expect(_stacks(stats, "battle_shout") == 1, "shout stacks 1")
	stats.statuses.tick_statuses(5.0, stats)
	var sh_mid := _remaining(stats, "battle_shout")
	failed += _expect(sh_mid < 12.0, "shout ticked (%.2f)" % sh_mid)
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var rs2: Dictionary = srv.try_use_skill("battle_shout", "", 0, 0)
	failed += _expect(bool(rs2.get("ok", false)), "shout cast 2")
	failed += _expect(_count(stats, "battle_shout") == 1, "shout one instance")
	failed += _expect(_stacks(stats, "battle_shout") == 1, "shout still stack 1")
	failed += _expect(_remaining(stats, "battle_shout") > 14.0, "shout refreshed ~15")

	# --- mark re-apply refreshes debuff ---
	if not stats.skill_book.is_known("mark"):
		var learn_mk: Dictionary = stats.skill_book.try_learn("mark", skills, 99)
		failed += _expect(bool(learn_mk.get("ok", false)), "learn mark")
	stats.ensure_npc("slime_rf", true, true)
	stats.ensure_npc_ai("slime_rf", 2, true, Vector2i(2, 0), 0)
	stats.set_npc_cell("slime_rf", 2, 0)
	stats.npcs["slime_rf"]["hp"] = 200
	stats.npcs["slime_rf"]["hp_max"] = 200
	stats.npcs["slime_rf"]["name"] = "史莱姆"
	stats.statuses.clear_status("slime_rf", "mark")
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var rm1: Dictionary = engine.try_use_skill("mark", "slime_rf", 0, 0)
	failed += _expect(bool(rm1.get("ok", false)), "mark cast 1")
	failed += _expect(stats.statuses.has_status("slime_rf", "mark"), "mark on npc")
	failed += _expect(_stacks_on(stats, "slime_rf", "mark") == 1, "mark stacks 1")
	stats.statuses.tick_statuses(4.0, stats)
	var mk_mid := _remaining_on(stats, "slime_rf", "mark")
	failed += _expect(mk_mid < 10.0, "mark ticked (%.2f)" % mk_mid)
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var rm2: Dictionary = engine.try_use_skill("mark", "slime_rf", 0, 0)
	failed += _expect(bool(rm2.get("ok", false)), "mark cast 2")
	failed += _expect(_count_on(stats, "slime_rf", "mark") == 1, "mark one instance")
	failed += _expect(_stacks_on(stats, "slime_rf", "mark") == 1, "mark still stack 1")
	failed += _expect(_remaining_on(stats, "slime_rf", "mark") > 11.0, "mark refreshed ~12")

	# Catalog stack_max hints
	var gf: Dictionary = srv.item_catalog.get_item("food_grilled_fish")
	var wf_st: Dictionary = gf.get("status", {}) if typeof(gf.get("status", {})) == TYPE_DICTIONARY else {}
	failed += _expect(int(wf_st.get("stack_max", 0)) == 1, "catalog well_fed stack_max 1")
	var bs_st: Dictionary = skills.get_skill("battle_shout").get("status", {})
	if typeof(bs_st) != TYPE_DICTIONARY:
		bs_st = {}
	failed += _expect(int(bs_st.get("stack_max", 0)) == 1, "catalog battle_shout stack_max 1")
	var mk_st: Dictionary = skills.get_skill("mark").get("status", {})
	if typeof(mk_st) != TYPE_DICTIONARY:
		mk_st = {}
	failed += _expect(int(mk_st.get("stack_max", 0)) == 1, "catalog mark stack_max 1")

	if failed == 0:
		print("test_buff_refresh: PASS")
		quit(0)
	else:
		print("test_buff_refresh: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _remaining(stats, status_id: String) -> float:
	return _remaining_on(stats, "player", status_id)


func _remaining_on(stats, target: String, status_id: String) -> float:
	for s in stats.statuses.snapshot_statuses(target):
		if str(s.get("id", "")) == status_id:
			return float(s.get("remaining_sec", 0.0))
	return -1.0


func _stacks(stats, status_id: String) -> int:
	return _stacks_on(stats, "player", status_id)


func _stacks_on(stats, target: String, status_id: String) -> int:
	for s in stats.statuses.snapshot_statuses(target):
		if str(s.get("id", "")) == status_id:
			return int(s.get("stacks", 1))
	return 0


func _count(stats, status_id: String) -> int:
	return _count_on(stats, "player", status_id)


func _count_on(stats, target: String, status_id: String) -> int:
	var n := 0
	for s in stats.statuses.snapshot_statuses(target):
		if str(s.get("id", "")) == status_id:
			n += 1
	return n
