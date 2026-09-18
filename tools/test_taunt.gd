extends SceneTree
## Headless: taunt skill — force victim / top hate onto player.

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

	# --- Catalog (JSON + has_skill) ---
	failed += _expect(skills.has_skill("taunt"), "catalog has taunt")
	var def: Dictionary = skills.get_skill("taunt")
	failed += _expect(str(def.get("name", "")) == "嘲讽", "name 嘲讽")
	failed += _expect(str(def.get("category", "")) == "physical", "category physical")
	failed += _expect(str(def.get("effect", "")) == "taunt", "effect taunt")
	failed += _expect(int(def.get("mp_cost", 0)) > 0, "mp_cost > 0")
	failed += _expect(int(def.get("mp_cost", 99)) <= 12, "mp_cost small")
	failed += _expect(float(def.get("cooldown", 0.0)) > 0.0, "cooldown > 0")
	failed += _expect(float(def.get("cooldown", 99.0)) <= 15.0, "cooldown short")
	failed += _expect(float(def.get("cast_time", 0.0)) <= 0.0, "instant no cast_time")
	failed += _expect(bool(def.get("requires_target", false)), "requires_target")
	failed += _expect(int(def.get("range", 0)) >= 1, "range >= 1")
	failed += _expect(not bool(def.get("starter", true)), "learnable not starter")
	failed += _expect(int(def.get("sp_cost", 0)) >= 1, "sp_cost learnable")
	failed += _expect(float(def.get("hate_amount", 0.0)) >= 100.0, "hate_amount spike")

	# --- Builtin fallback still has taunt ---
	var fb = SkillCatalog.new()
	fb._load_builtin_fallback()
	failed += _expect(fb.has_skill("taunt"), "fallback has taunt")
	failed += _expect(str(fb.get_skill("taunt").get("name", "")) == "嘲讽", "fallback name")

	# --- Learn via SP ---
	failed += _expect(not stats.skill_book.is_known("taunt"), "not known before learn")
	var learn: Dictionary = stats.skill_book.try_learn("taunt", skills, 99)
	failed += _expect(bool(learn.get("ok", false)), "learn ok")
	failed += _expect(stats.skill_book.is_known("taunt"), "known after learn")

	# --- Setup mob with rival top hate ---
	stats.ensure_npc("slime_a", true, true)
	stats.ensure_npc_ai("slime_a", 2, true, Vector2i(2, 0), 0)
	stats.set_npc_cell("slime_a", 2, 0)
	stats.npcs["slime_a"]["name"] = "史莱姆"
	stats.npcs["slime_a"]["hp"] = 200
	stats.npcs["slime_a"]["hp_max"] = 200
	stats.npcs["slime_a"]["def"] = 0
	# Rival holds victim with high hate.
	stats.add_hate("slime_a", "dps_ally", 500.0, 1.0)
	failed += _expect(str(stats.npc_ai["slime_a"].get("victim_id", "")) == "dps_ally", "victim was ally")
	failed += _expect(stats.get_threat("slime_a", "player") < 1.0, "player hate near 0")

	# --- Cast taunt ---
	stats.player["mp"] = 50
	stats.player["mp_max"] = 50
	stats.skill_ready_at.clear()
	var mp_before: int = int(stats.player.get("mp", 0))
	var cast: Dictionary = engine.try_use_skill("taunt", "slime_a", 0, 0)
	failed += _expect(bool(cast.get("ok", false)), "cast taunt ok")
	failed += _expect(int(stats.player.get("mp", 0)) == mp_before - int(def.get("mp_cost", 6)), "spent mp")
	failed += _expect(str(stats.npc_ai["slime_a"].get("victim_id", "")) == "player", "victim_id player")
	failed += _expect(str(stats.npc_ai["slime_a"].get("chase_target", "")) == "player", "chase_target player")
	failed += _expect(stats.get_threat("slime_a", "player") > stats.get_threat("slime_a", "dps_ally"), "player top hate")
	failed += _expect(_has_msg(cast.get("actions", []), "嘲讽了史莱姆"), "log 嘲讽了史莱姆")
	failed += _expect(_has_type(cast.get("actions", []), "threat_update"), "threat_update action")
	failed += _expect(not stats.is_skill_ready("taunt"), "on cooldown")

	# --- Reject: no target ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var no_tgt: Dictionary = engine.try_use_skill("taunt", "", 0, 0)
	failed += _expect(not bool(no_tgt.get("ok", true)), "no target rejected")
	failed += _expect(_has_msg(no_tgt.get("actions", []), "需要目标"), "need target msg")

	# --- Reject: out of range ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.set_npc_cell("slime_a", 20, 20)
	var far: Dictionary = engine.try_use_skill("taunt", "slime_a", 0, 0)
	failed += _expect(not bool(far.get("ok", true)), "oor rejected")
	failed += _expect(_has_msg(far.get("actions", []), "目标太远"), "oor msg")
	stats.set_npc_cell("slime_a", 2, 0)

	# --- Reject: non-hostile ---
	stats.ensure_npc("vendor_x", false, false)
	stats.set_npc_cell("vendor_x", 1, 0)
	stats.npcs["vendor_x"]["hostile"] = false
	stats.npcs["vendor_x"]["hp"] = 50
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var soft: Dictionary = engine.try_use_skill("taunt", "vendor_x", 0, 0)
	failed += _expect(not bool(soft.get("ok", true)), "non-hostile rejected")
	failed += _expect(_has_msg(soft.get("actions", []), "只能嘲讽敌对目标"), "hostile-only msg")

	# --- Reject: unlearned ---
	var stats2 = CombatStats.new()
	stats2.reset_player(3)
	stats2.ensure_skill_book()
	stats2.skill_book.grant_starters(skills)
	var eng2 = CombatEngine.new()
	eng2.setup(stats2, skills, items, bag)
	stats2.ensure_npc("m2", true, true)
	stats2.set_npc_cell("m2", 1, 0)
	var unl: Dictionary = eng2.try_use_skill("taunt", "m2", 0, 0)
	failed += _expect(not bool(unl.get("ok", true)), "unlearned rejected")
	failed += _expect(_has_msg(unl.get("actions", []), "尚未学会"), "unlearned msg")

	if failed == 0:
		print("test_taunt: PASS")
		quit(0)
	else:
		print("test_taunt: FAIL count=", failed)
		quit(1)


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
