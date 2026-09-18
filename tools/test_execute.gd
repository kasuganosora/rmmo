extends SceneTree
## Headless: execute「斩杀」— hostile only when HP ≤ 30% max; ~2.0× atk; MP15 CD15 range2.

const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _expect(true, "boot")

	var stats = CombatStats.new()
	stats.reset_player(3)
	if stats.has_method("set_player_actor_id"):
		stats.set_player_actor_id("player")
	var skills = SkillCatalog.new()
	skills.load_catalog()
	var items = ItemCatalog.new()
	items.load_catalog()
	var bag = Inventory.new()
	bag.grant_starter()
	var engine = CombatEngine.new()
	engine.setup(stats, skills, items, bag)
	engine.combat_randf = func() -> float: return 0.5

	stats.ensure_skill_book()
	if stats.skill_book.list_known().is_empty():
		stats.skill_book.grant_starters(skills)
	stats.skill_book.grant_skill_points(99)

	# --- Catalog ---
	failed += _expect(skills.has_skill("execute"), "catalog has execute")
	var def: Dictionary = skills.get_skill("execute")
	failed += _expect(str(def.get("name", "")) == "斩杀", "name 斩杀")
	failed += _expect(str(def.get("category", "")) == "physical", "category physical")
	failed += _expect(str(def.get("effect", "")) == "execute", "effect execute")
	failed += _expect(int(def.get("mp_cost", 0)) == 15, "mp_cost 15")
	failed += _expect(abs(float(def.get("cooldown", 0.0)) - 15.0) < 0.01, "cooldown 15s")
	failed += _expect(int(def.get("range", 0)) == 2, "range 2")
	failed += _expect(abs(float(def.get("power", 0.0)) - 2.0) < 0.01, "power 2.0")
	failed += _expect(abs(float(def.get("hp_threshold", 0.0)) - 0.3) < 0.001, "hp_threshold 0.3")
	failed += _expect(float(def.get("cast_time", 0.0)) <= 0.0, "instant no cast_time")
	failed += _expect(bool(def.get("requires_target", false)), "requires_target")
	failed += _expect(not bool(def.get("starter", true)), "learnable not starter")
	failed += _expect(int(def.get("sp_cost", 0)) >= 1, "sp_cost learnable")

	# --- Builtin fallback ---
	var fb = SkillCatalog.new()
	fb._load_builtin_fallback()
	failed += _expect(fb.has_skill("execute"), "fallback has execute")
	failed += _expect(str(fb.get_skill("execute").get("name", "")) == "斩杀", "fallback name")
	failed += _expect(abs(float(fb.get_skill("execute").get("power", 0.0)) - 2.0) < 0.01, "fallback power")
	failed += _expect(int(fb.get_skill("execute").get("mp_cost", 0)) == 15, "fallback mp 15")

	# --- Learn via SP ---
	failed += _expect(not stats.skill_book.is_known("execute"), "not known before learn")
	var learn: Dictionary = stats.skill_book.try_learn("execute", skills, 99)
	failed += _expect(bool(learn.get("ok", false)), "learn ok")
	failed += _expect(stats.skill_book.is_known("execute"), "known after learn")

	# --- Setup hostile adjacent; HP at 30% (eligible). Keep HP > damage so NPC stays in table. ---
	# atk 40 * 2.0 = 80; use hp_max 400 / hp 120 (30%).
	stats.ensure_npc("slime_a", true, true)
	stats.ensure_npc_ai("slime_a", 2, true, Vector2i(1, 0), 0)
	stats.set_npc_cell("slime_a", 1, 0)
	stats.npcs["slime_a"]["name"] = "史莱姆"
	stats.npcs["slime_a"]["hp"] = 120
	stats.npcs["slime_a"]["hp_max"] = 400
	stats.npcs["slime_a"]["def"] = 0
	stats.npcs["slime_a"]["hostile"] = true
	stats.player["atk"] = 40
	stats.player["mp"] = 50
	stats.player["mp_max"] = 50
	stats.skill_ready_at.clear()

	var mp_before: int = int(stats.player.get("mp", 0))
	var hp_before: int = int(stats.npcs["slime_a"].get("hp", 0))
	var cast: Dictionary = engine.try_use_skill("execute", "slime_a", 0, 0)
	failed += _expect(bool(cast.get("ok", false)), "cast execute ok at 30%")
	failed += _expect(int(stats.player.get("mp", 0)) == mp_before - 15, "spent mp 15")
	failed += _expect(stats.npcs.has("slime_a"), "npc still present after non-lethal")
	var expected_dmg: int = int(round(40.0 * 2.0))  # 80 with def 0
	var dmg: int = hp_before - int(stats.npcs["slime_a"].get("hp", 0))
	failed += _expect(dmg == expected_dmg, "dmg ~2.0×atk (%d got %d)" % [expected_dmg, dmg])
	failed += _expect(_has_msg(cast.get("actions", []), "斩杀了史莱姆！"), "log 斩杀了史莱姆！")
	failed += _expect(_has_type(cast.get("actions", []), "damage"), "damage action / float")
	failed += _expect(not _has_msg(cast.get("actions", []), "使用了【斩杀】"), "no generic use msg")
	failed += _expect(not stats.is_skill_ready("execute"), "on cooldown")

	# --- CD gate ---
	stats.npcs["slime_a"]["hp"] = 100
	var r_cd: Dictionary = engine.try_use_skill("execute", "slime_a", 0, 0)
	failed += _expect(not bool(r_cd.get("ok", false)), "on cooldown")

	# --- HP too high (>30%) ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.npcs["slime_a"]["hp"] = 121
	stats.npcs["slime_a"]["hp_max"] = 400
	var r_high: Dictionary = engine.try_use_skill("execute", "slime_a", 0, 0)
	failed += _expect(not bool(r_high.get("ok", false)), "hp>30% rejected")
	failed += _expect(_has_msg(r_high.get("actions", []), "目标生命过高"), "hp high msg")
	failed += _expect(int(stats.player.get("mp", 0)) == 50, "hp high no mp spend")

	# --- Exactly at 30% ok; also 29% ok ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.npcs["slime_a"]["hp"] = 120
	stats.npcs["slime_a"]["hp_max"] = 400
	stats.npcs["slime_a"]["def"] = 0
	var r_edge: Dictionary = engine.try_use_skill("execute", "slime_a", 0, 0)
	failed += _expect(bool(r_edge.get("ok", false)), "exactly 30% cast ok")

	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.npcs["slime_a"]["hp"] = 116
	stats.npcs["slime_a"]["hp_max"] = 400
	var r_ok: Dictionary = engine.try_use_skill("execute", "slime_a", 0, 0)
	failed += _expect(bool(r_ok.get("ok", false)), "29% cast ok")

	# --- Range 2 ok, range 3 fail ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.set_npc_cell("slime_a", 2, 0)
	stats.npcs["slime_a"]["hp"] = 100
	var r_r2: Dictionary = engine.try_use_skill("execute", "slime_a", 0, 0)
	failed += _expect(bool(r_r2.get("ok", false)), "range 2 cast ok")

	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.set_npc_cell("slime_a", 3, 0)
	stats.npcs["slime_a"]["hp"] = 100
	var r_oor: Dictionary = engine.try_use_skill("execute", "slime_a", 0, 0)
	failed += _expect(not bool(r_oor.get("ok", false)), "oor rejected")
	failed += _expect(_has_msg(r_oor.get("actions", []), "目标太远"), "oor msg")
	stats.set_npc_cell("slime_a", 1, 0)

	# --- No target ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var r_nt: Dictionary = engine.try_use_skill("execute", "", 0, 0)
	failed += _expect(not bool(r_nt.get("ok", false)), "no target rejected")
	failed += _expect(_has_msg(r_nt.get("actions", []), "需要目标"), "need target msg")

	# --- Non-hostile ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.ensure_npc("ally_b", false, false)
	stats.set_npc_cell("ally_b", 1, 0)
	stats.npcs["ally_b"]["name"] = "路人"
	stats.npcs["ally_b"]["hostile"] = false
	stats.npcs["ally_b"]["ally"] = true
	stats.npcs["ally_b"]["hp"] = 10
	stats.npcs["ally_b"]["hp_max"] = 100
	var r_nh: Dictionary = engine.try_use_skill("execute", "ally_b", 0, 0)
	failed += _expect(not bool(r_nh.get("ok", false)), "non-hostile rejected")
	failed += _expect(_has_msg(r_nh.get("actions", []), "只能斩杀敌对"), "hostile-only msg")

	# --- Unlearned ---
	var stats2 = CombatStats.new()
	stats2.reset_player(3)
	stats2.ensure_skill_book()
	stats2.skill_book.grant_starters(skills)
	var eng2 = CombatEngine.new()
	eng2.setup(stats2, skills, items, bag)
	eng2.combat_randf = func() -> float: return 0.5
	stats2.ensure_npc("m2", true, true)
	stats2.set_npc_cell("m2", 1, 0)
	stats2.npcs["m2"]["hp"] = 10
	stats2.npcs["m2"]["hp_max"] = 100
	var unl: Dictionary = eng2.try_use_skill("execute", "m2", 0, 0)
	failed += _expect(not bool(unl.get("ok", true)), "unlearned rejected")
	failed += _expect(_has_msg(unl.get("actions", []), "尚未学会"), "unlearned msg")

	# --- MockServer path (autoload if present) ---
	failed += _mock_server_execute()

	if failed == 0:
		print("test_execute: PASS")
		quit(0)
	else:
		print("test_execute: FAIL count=", failed)
		quit(1)


func _mock_server_execute() -> int:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("  SKIP mock_server (no autoload)")
		return 0
	if srv.combat_engine == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.skill_catalog == null or srv.combat_engine == null or srv.combat_stats == null:
		print("  SKIP mock_server layers missing")
		return 0
	failed += _expect(srv.has_method("try_use_skill"), "srv has try_use_skill")
	var skills = srv.skill_catalog
	var stats = srv.combat_stats
	var engine = srv.combat_engine
	engine.combat_randf = func() -> float: return 0.5
	if "awaiting_respawn" in srv:
		srv.awaiting_respawn = false
	if "sitting" in srv:
		srv.sitting = false
	stats.ensure_skill_book()
	if stats.skill_book.list_known().is_empty():
		stats.skill_book.grant_starters(skills)
	stats.skill_book.grant_skill_points(99)
	if not stats.skill_book.is_known("execute"):
		var lr: Dictionary = stats.skill_book.try_learn("execute", skills, 99)
		failed += _expect(bool(lr.get("ok", false)), "srv learn ok")
	stats.ensure_npc("exec_mob", true, true)
	stats.set_npc_cell("exec_mob", 1, 0)
	stats.npcs["exec_mob"]["name"] = "史莱姆乙"
	stats.npcs["exec_mob"]["hostile"] = true
	stats.npcs["exec_mob"]["hp"] = 120
	stats.npcs["exec_mob"]["hp_max"] = 400
	stats.npcs["exec_mob"]["def"] = 0
	stats.player["atk"] = 40
	stats.player["mp"] = 50
	stats.player["mp_max"] = 50
	stats.skill_ready_at.clear()
	if srv.has_method("set_player_cell"):
		srv.set_player_cell(0, 0)
	var r: Dictionary = srv.try_use_skill("execute", "exec_mob", 0, 0)
	failed += _expect(bool(r.get("ok", false)), "srv cast ok")
	failed += _expect(_has_msg(r.get("actions", []), "斩杀了史莱姆乙！"), "srv log 斩杀")
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.npcs["exec_mob"]["hp"] = 300
	var rh: Dictionary = srv.try_use_skill("execute", "exec_mob", 0, 0)
	failed += _expect(not bool(rh.get("ok", false)), "srv hp high rejected")
	failed += _expect(_has_msg(rh.get("actions", []), "目标生命过高"), "srv hp high msg")
	return failed


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _has_msg(actions: Array, sub: String) -> bool:
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(sub) >= 0:
			return true
	return false
