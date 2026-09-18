extends SceneTree
## Headless: mana_shield skill — absorb damage via MP.

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
	var skills = SkillCatalog.new()
	skills.load_catalog()
	var items = ItemCatalog.new()
	items.load_catalog()
	var bag = Inventory.new()
	bag.grant_starter()
	var engine = CombatEngine.new()
	engine.setup(stats, skills, items, bag)
	engine.combat_randf = func() -> float: return 0.5  # hit, no crit

	stats.ensure_skill_book()
	if stats.skill_book.list_known().is_empty():
		stats.skill_book.grant_starters(skills)
	stats.skill_book.grant_skill_points(99)

	# --- Catalog ---
	failed += _expect(skills.has_skill("mana_shield"), "catalog has mana_shield")
	var def: Dictionary = skills.get_skill("mana_shield")
	failed += _expect(str(def.get("name", "")) == "法力护盾", "name 法力护盾")
	failed += _expect(str(def.get("category", "")) == "magic", "category magic")
	failed += _expect(str(def.get("effect", "")) == "apply_status", "effect apply_status")
	failed += _expect(int(def.get("mp_cost", 0)) > 0, "mp_cost > 0")
	failed += _expect(float(def.get("cooldown", 0.0)) > 0.0, "cooldown > 0")
	failed += _expect(not bool(def.get("requires_target", true)), "self buff no target")
	failed += _expect(not bool(def.get("starter", true)), "learnable not starter")
	failed += _expect(int(def.get("sp_cost", 0)) >= 1, "sp_cost learnable")
	var st_def: Dictionary = def.get("status", {}) if typeof(def.get("status", {})) == TYPE_DICTIONARY else {}
	failed += _expect(str(st_def.get("id", "")) == "mana_shield", "status id mana_shield")
	failed += _expect(str(st_def.get("kind", "")) == "buff", "status kind buff")
	failed += _expect(abs(float(st_def.get("duration", 0.0)) - 30.0) < 0.01, "duration 30s")
	failed += _expect(abs(float(st_def.get("absorb_ratio", 0.0)) - 0.5) < 0.001, "absorb_ratio 0.5")
	failed += _expect(int(st_def.get("hp_per_mp", 0)) == 2, "hp_per_mp 2")

	# --- Learn via SP ---
	failed += _expect(not stats.skill_book.is_known("mana_shield"), "not known before learn")
	var learn: Dictionary = stats.skill_book.try_learn("mana_shield", skills, 99)
	failed += _expect(bool(learn.get("ok", false)), "learn ok")
	failed += _expect(stats.skill_book.is_known("mana_shield"), "known after learn")

	# --- Cast applies status ---
	stats.player["mp"] = 80
	stats.player["mp_max"] = 80
	stats.player["hp"] = 100
	stats.player["hp_max"] = 100
	stats.player["def"] = 0
	stats.skill_ready_at.clear()
	var cast: Dictionary = engine.try_use_skill("mana_shield", "", 0, 0)
	failed += _expect(bool(cast.get("ok", false)), "cast mana_shield ok")
	failed += _expect(stats.statuses.has_status("player", "mana_shield"), "status applied")
	var snap: Array = stats.statuses.snapshot_statuses("player")
	var found := false
	for s in snap:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == "mana_shield":
			found = true
			failed += _expect(abs(float(s.get("remaining_sec", 0.0)) - 30.0) < 0.5, "remaining ~30")
			failed += _expect(abs(float(s.get("absorb_ratio", 0.0)) - 0.5) < 0.001, "snap absorb_ratio")
			failed += _expect(int(s.get("hp_per_mp", 0)) == 2, "snap hp_per_mp")
	failed += _expect(found, "mana_shield in snapshot")
	failed += _expect(_has_type(cast.get("actions", []), "status_update"), "status_update action")
	var mp_after_cast: int = int(stats.player.get("mp", 0))
	failed += _expect(mp_after_cast == 80 - int(def.get("mp_cost", 12)), "cast spent mp_cost")

	# --- Absorb 50% of hit, 1 MP per 2 HP ---
	# Incoming atk 40, def 0 → dealt 40; want absorb 20; mp_drain 10.
	var mp_before: int = int(stats.player.get("mp", 0))
	var hp_before: int = int(stats.player.get("hp", 0))
	var acts: Array = []
	var landed: bool = engine._damage_player(40, acts, "test_npc", false)
	failed += _expect(landed, "hit landed")
	var dmg_act := _find_damage(acts)
	failed += _expect(not dmg_act.is_empty(), "damage action")
	failed += _expect(int(dmg_act.get("absorbed", 0)) == 20, "absorbed 20 (50%% of 40)")
	failed += _expect(int(dmg_act.get("mp_drain", 0)) == 10, "mp_drain 10")
	failed += _expect(int(dmg_act.get("amount", -1)) == 20, "hp damage 20")
	failed += _expect(int(stats.player.get("hp", 0)) == hp_before - 20, "hp -= 20")
	failed += _expect(int(stats.player.get("mp", 0)) == mp_before - 10, "mp -= 10")

	# --- MP empty caps absorb ---
	stats.player["mp"] = 3
	stats.player["hp"] = 100
	acts = []
	engine._damage_player(40, acts, "test_npc", false)
	dmg_act = _find_damage(acts)
	# want 20, but only 3 MP → absorb 6, drain 3, hp loss 34
	failed += _expect(int(dmg_act.get("absorbed", 0)) == 6, "low-mp absorbed 6")
	failed += _expect(int(dmg_act.get("mp_drain", 0)) == 3, "low-mp drain 3")
	failed += _expect(int(dmg_act.get("amount", -1)) == 34, "low-mp hp dmg 34")
	failed += _expect(int(stats.player.get("mp", 0)) == 0, "mp emptied")

	# --- No absorb without status ---
	stats.statuses.clear_status("player", "mana_shield")
	stats.player["mp"] = 50
	stats.player["hp"] = 100
	acts = []
	engine._damage_player(40, acts, "test_npc", false)
	dmg_act = _find_damage(acts)
	failed += _expect(int(dmg_act.get("absorbed", 0)) == 0, "no shield no absorb")
	failed += _expect(int(dmg_act.get("amount", -1)) == 40, "full damage without shield")

	# --- absorb_max flat cap ---
	stats.statuses.apply_status("player", {
		"id": "mana_shield",
		"name": "法力护盾",
		"kind": "buff",
		"duration": 30.0,
		"absorb_ratio": 1.0,
		"absorb_max": 8,
		"hp_per_mp": 2,
	}, 30.0, "player")
	stats.player["mp"] = 50
	stats.player["hp"] = 100
	acts = []
	engine._damage_player(40, acts, "test_npc", false)
	dmg_act = _find_damage(acts)
	failed += _expect(int(dmg_act.get("absorbed", 0)) == 8, "absorb_max caps at 8")
	failed += _expect(int(dmg_act.get("mp_drain", 0)) == 4, "absorb_max mp_drain 4")
	failed += _expect(int(dmg_act.get("amount", -1)) == 32, "absorb_max leftover 32")

	if failed == 0:
		print("test_mana_shield: PASS")
		quit(0)
	else:
		print("test_mana_shield: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _find_damage(actions: Array) -> Dictionary:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "damage" and str(a.get("target", "")) == "player":
			return a
	return {}
