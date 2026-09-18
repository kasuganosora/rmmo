extends SceneTree
## Headless: mark skill — hostile debuff def_mul 0.85 / 12s; CD 10; MP 8; range 5.

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
	failed += _expect(skills.has_skill("mark"), "catalog has mark")
	var def: Dictionary = skills.get_skill("mark")
	failed += _expect(str(def.get("name", "")) == "标记", "name 标记")
	failed += _expect(str(def.get("category", "")) == "magic", "category magic")
	failed += _expect(str(def.get("effect", "")) == "mark", "effect mark")
	failed += _expect(int(def.get("mp_cost", 0)) == 8, "mp_cost 8")
	failed += _expect(abs(float(def.get("cooldown", 0.0)) - 10.0) < 0.01, "cooldown 10s")
	failed += _expect(int(def.get("range", 0)) == 5, "range 5")
	failed += _expect(float(def.get("cast_time", 0.0)) <= 0.0, "instant no cast_time")
	failed += _expect(bool(def.get("requires_target", false)), "requires_target")
	failed += _expect(not bool(def.get("starter", true)), "learnable not starter")
	failed += _expect(int(def.get("sp_cost", 0)) >= 1, "sp_cost learnable")
	var st_def: Dictionary = def.get("status", {}) if typeof(def.get("status", {})) == TYPE_DICTIONARY else {}
	failed += _expect(str(st_def.get("id", "")) == "mark", "status id mark")
	failed += _expect(str(st_def.get("name", "")) == "标记", "status name 标记")
	failed += _expect(str(st_def.get("kind", "")) == "debuff", "status kind debuff")
	failed += _expect(abs(float(st_def.get("duration", 0.0)) - 12.0) < 0.01, "duration 12s")
	failed += _expect(abs(float(st_def.get("def_mul", 1.0)) - 0.85) < 0.001, "def_mul 0.85")

	# --- Builtin fallback ---
	var fb = SkillCatalog.new()
	fb._load_builtin_fallback()
	failed += _expect(fb.has_skill("mark"), "fallback has mark")
	failed += _expect(str(fb.get_skill("mark").get("name", "")) == "标记", "fallback name")
	var fb_st: Dictionary = fb.get_skill("mark").get("status", {}) if typeof(fb.get_skill("mark").get("status", {})) == TYPE_DICTIONARY else {}
	failed += _expect(abs(float(fb_st.get("def_mul", 1.0)) - 0.85) < 0.001, "fallback def_mul")

	# --- Learn via SP ---
	failed += _expect(not stats.skill_book.is_known("mark"), "not known before learn")
	var learn: Dictionary = stats.skill_book.try_learn("mark", skills, 99)
	failed += _expect(bool(learn.get("ok", false)), "learn ok")
	failed += _expect(stats.skill_book.is_known("mark"), "known after learn")

	# --- Setup hostile with high def so def_mul matters ---
	stats.ensure_npc("slime_a", true, true)
	stats.ensure_npc_ai("slime_a", 2, true, Vector2i(2, 0), 0)
	stats.set_npc_cell("slime_a", 2, 0)
	stats.npcs["slime_a"]["name"] = "史莱姆"
	stats.npcs["slime_a"]["hp"] = 500
	stats.npcs["slime_a"]["hp_max"] = 500
	stats.npcs["slime_a"]["def"] = 20
	stats.npcs["slime_a"]["mp"] = 50
	stats.npcs["slime_a"]["mp_max"] = 50

	# Baseline damage without mark (atk 40 vs def 20 → 20)
	stats.player["atk"] = 40
	stats.player["mp"] = 50
	stats.player["mp_max"] = 50
	var actions_base: Array = []
	var hp0: int = int(stats.npcs["slime_a"].get("hp", 0))
	engine._damage_npc("slime_a", 40, actions_base, false)
	var dmg_base: int = hp0 - int(stats.npcs["slime_a"].get("hp", 0))
	failed += _expect(dmg_base == 20, "baseline dmg 20 (40-20)")

	# --- Cast mark ---
	stats.npcs["slime_a"]["hp"] = 500
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var mp_before: int = int(stats.player.get("mp", 0))
	var cast: Dictionary = engine.try_use_skill("mark", "slime_a", 0, 0)
	failed += _expect(bool(cast.get("ok", false)), "cast mark ok")
	failed += _expect(int(stats.player.get("mp", 0)) == mp_before - 8, "spent mp 8")
	failed += _expect(stats.statuses.has_status("slime_a", "mark"), "mark applied")
	var mk: Dictionary = stats.statuses.get_status("slime_a", "mark")
	failed += _expect(abs(float(mk.get("remaining_sec", 0.0)) - 12.0) < 0.05, "mark remaining ~12s")
	failed += _expect(abs(float(mk.get("def_mul", 1.0)) - 0.85) < 0.001, "inst def_mul 0.85")
	failed += _expect(_has_msg(cast.get("actions", []), "标记了史莱姆！"), "log 标记了史莱姆！")
	failed += _expect(_has_type(cast.get("actions", []), "status_update"), "status_update action")
	failed += _expect(not stats.is_skill_ready("mark"), "on cooldown")

	# Effective def should be round(20 * 0.85) = 17
	var eff_def: int = engine._effective_def_npc("slime_a")
	failed += _expect(eff_def == 17, "effective def 17 (20*0.85)")

	# Damage with mark: 40 - 17 = 23 > baseline 20
	var actions_mk: Array = []
	var hp1: int = int(stats.npcs["slime_a"].get("hp", 0))
	engine._damage_npc("slime_a", 40, actions_mk, false)
	var dmg_mk: int = hp1 - int(stats.npcs["slime_a"].get("hp", 0))
	failed += _expect(dmg_mk == 23, "marked dmg 23 (40-17)")
	failed += _expect(dmg_mk > dmg_base, "marked dmg > baseline")

	# --- Reject: no target ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var no_tgt: Dictionary = engine.try_use_skill("mark", "", 0, 0)
	failed += _expect(not bool(no_tgt.get("ok", true)), "no target rejected")
	failed += _expect(_has_msg(no_tgt.get("actions", []), "需要目标"), "need target msg")

	# --- Reject: out of range ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.set_npc_cell("slime_a", 20, 20)
	var far: Dictionary = engine.try_use_skill("mark", "slime_a", 0, 0)
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
	var soft: Dictionary = engine.try_use_skill("mark", "vendor_x", 0, 0)
	failed += _expect(not bool(soft.get("ok", true)), "non-hostile rejected")
	failed += _expect(_has_msg(soft.get("actions", []), "只能标记敌对目标"), "hostile-only msg")

	# --- Reject: unlearned ---
	var stats2 = CombatStats.new()
	stats2.reset_player(3)
	stats2.ensure_skill_book()
	stats2.skill_book.grant_starters(skills)
	var eng2 = CombatEngine.new()
	eng2.setup(stats2, skills, items, bag)
	stats2.ensure_npc("m2", true, true)
	stats2.set_npc_cell("m2", 1, 0)
	var unl: Dictionary = eng2.try_use_skill("mark", "m2", 0, 0)
	failed += _expect(not bool(unl.get("ok", true)), "unlearned rejected")
	failed += _expect(_has_msg(unl.get("actions", []), "尚未学会"), "unlearned msg")

	if failed == 0:
		print("test_mark: PASS")
		quit(0)
	else:
		print("test_mark: FAIL count=", failed)
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
