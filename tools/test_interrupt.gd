extends SceneTree
## Headless: interrupt skill — silence hostile 3s + tiny damage; blocks try_npc_skill.

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
	failed += _expect(skills.has_skill("interrupt"), "catalog has interrupt")
	var def: Dictionary = skills.get_skill("interrupt")
	failed += _expect(str(def.get("name", "")) == "打断", "name 打断")
	failed += _expect(str(def.get("category", "")) == "magic", "category magic")
	failed += _expect(str(def.get("effect", "")) == "interrupt", "effect interrupt")
	failed += _expect(int(def.get("mp_cost", 0)) > 0, "mp_cost > 0")
	failed += _expect(int(def.get("mp_cost", 99)) <= 12, "mp_cost small")
	failed += _expect(float(def.get("cooldown", 0.0)) > 0.0, "cooldown > 0")
	failed += _expect(float(def.get("cooldown", 99.0)) <= 15.0, "cooldown short")
	failed += _expect(float(def.get("cast_time", 0.0)) <= 0.0, "instant no cast_time")
	failed += _expect(bool(def.get("requires_target", false)), "requires_target")
	failed += _expect(int(def.get("range", 0)) >= 1, "range >= 1")
	failed += _expect(not bool(def.get("starter", true)), "learnable not starter")
	failed += _expect(int(def.get("sp_cost", 0)) >= 1, "sp_cost learnable")
	failed += _expect(float(def.get("power", 0.0)) > 0.0 and float(def.get("power", 9.0)) < 1.0, "tiny power")
	var st_def: Dictionary = def.get("status", {}) if typeof(def.get("status", {})) == TYPE_DICTIONARY else {}
	failed += _expect(str(st_def.get("id", "")) == "silence", "status id silence")
	failed += _expect(str(st_def.get("name", "")) == "沉默", "status name 沉默")
	failed += _expect(str(st_def.get("kind", "")) == "debuff", "status kind debuff")
	failed += _expect(abs(float(st_def.get("duration", 0.0)) - 3.0) < 0.01, "silence duration 3s")

	# --- Builtin fallback ---
	var fb = SkillCatalog.new()
	fb._load_builtin_fallback()
	failed += _expect(fb.has_skill("interrupt"), "fallback has interrupt")
	failed += _expect(str(fb.get_skill("interrupt").get("name", "")) == "打断", "fallback name")

	# --- Learn via SP ---
	failed += _expect(not stats.skill_book.is_known("interrupt"), "not known before learn")
	var learn: Dictionary = stats.skill_book.try_learn("interrupt", skills, 99)
	failed += _expect(bool(learn.get("ok", false)), "learn ok")
	failed += _expect(stats.skill_book.is_known("interrupt"), "known after learn")

	# --- Setup hostile ---
	stats.ensure_npc("slime_a", true, true)
	stats.ensure_npc_ai("slime_a", 2, true, Vector2i(2, 0), 0)
	stats.set_npc_cell("slime_a", 2, 0)
	stats.npcs["slime_a"]["name"] = "史莱姆"
	stats.npcs["slime_a"]["hp"] = 200
	stats.npcs["slime_a"]["hp_max"] = 200
	stats.npcs["slime_a"]["def"] = 0
	stats.npcs["slime_a"]["mp"] = 50
	stats.npcs["slime_a"]["mp_max"] = 50

	# --- Cast interrupt ---
	stats.player["mp"] = 50
	stats.player["mp_max"] = 50
	stats.skill_ready_at.clear()
	var mp_before: int = int(stats.player.get("mp", 0))
	var hp_before: int = int(stats.npcs["slime_a"].get("hp", 0))
	var cast: Dictionary = engine.try_use_skill("interrupt", "slime_a", 0, 0)
	failed += _expect(bool(cast.get("ok", false)), "cast interrupt ok")
	failed += _expect(int(stats.player.get("mp", 0)) == mp_before - int(def.get("mp_cost", 8)), "spent mp")
	failed += _expect(int(stats.npcs["slime_a"].get("hp", 0)) < hp_before, "dealt tiny damage")
	failed += _expect(int(stats.npcs["slime_a"].get("hp", 0)) > hp_before - 40, "damage stays tiny")
	failed += _expect(stats.statuses.has_status("slime_a", "silence"), "silence applied")
	var sil: Dictionary = stats.statuses.get_status("slime_a", "silence")
	failed += _expect(abs(float(sil.get("remaining_sec", 0.0)) - 3.0) < 0.05, "silence remaining ~3s")
	failed += _expect(_has_msg(cast.get("actions", []), "打断：沉默了史莱姆！"), "log 打断：沉默了史莱姆！")
	failed += _expect(_has_type(cast.get("actions", []), "status_update"), "status_update action")
	failed += _expect(not stats.is_skill_ready("interrupt"), "on cooldown")

	# --- Silenced NPC cannot use skills ---
	engine.player_cell_hint = Vector2i(0, 0)
	var blocked: Dictionary = engine.try_npc_skill("slime_a", "power_strike", 2, 0, 2, 0)
	failed += _expect(not bool(blocked.get("ok", true)), "npc skill blocked while silenced")
	failed += _expect(str(blocked.get("reason", "")) == "silence", "reason silence")

	# --- After silence expires, NPC skill works ---
	stats.statuses.clear_status("slime_a", "silence")
	failed += _expect(not stats.statuses.has_status("slime_a", "silence"), "silence cleared")
	var ok_skill: Dictionary = engine.try_npc_skill("slime_a", "power_strike", 2, 0, 2, 0)
	failed += _expect(bool(ok_skill.get("ok", false)), "npc skill ok after silence")

	# --- Reject: no target ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var no_tgt: Dictionary = engine.try_use_skill("interrupt", "", 0, 0)
	failed += _expect(not bool(no_tgt.get("ok", true)), "no target rejected")
	failed += _expect(_has_msg(no_tgt.get("actions", []), "需要目标"), "need target msg")

	# --- Reject: out of range ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.set_npc_cell("slime_a", 20, 20)
	var far: Dictionary = engine.try_use_skill("interrupt", "slime_a", 0, 0)
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
	var soft: Dictionary = engine.try_use_skill("interrupt", "vendor_x", 0, 0)
	failed += _expect(not bool(soft.get("ok", true)), "non-hostile rejected")
	failed += _expect(_has_msg(soft.get("actions", []), "只能打断敌对目标"), "hostile-only msg")

	# --- Reject: unlearned ---
	var stats2 = CombatStats.new()
	stats2.reset_player(3)
	stats2.ensure_skill_book()
	stats2.skill_book.grant_starters(skills)
	var eng2 = CombatEngine.new()
	eng2.setup(stats2, skills, items, bag)
	stats2.ensure_npc("m2", true, true)
	stats2.set_npc_cell("m2", 1, 0)
	var unl: Dictionary = eng2.try_use_skill("interrupt", "m2", 0, 0)
	failed += _expect(not bool(unl.get("ok", true)), "unlearned rejected")
	failed += _expect(_has_msg(unl.get("actions", []), "尚未学会"), "unlearned msg")

	if failed == 0:
		print("test_interrupt: PASS")
		quit(0)
	else:
		print("test_interrupt: FAIL count=", failed)
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
