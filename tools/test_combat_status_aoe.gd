extends SceneTree
## Headless tests: status DoT/HoT/buff + AoE skills.

const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")


func _init() -> void:
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
	engine.combat_randf = func() -> float: return 0.5  # force hit, no crit

	# Skill-book gate: learn non-starters used by this suite.
	stats.ensure_skill_book()
	if stats.skill_book.list_known().is_empty():
		stats.skill_book.grant_starters(skills)
	stats.skill_book.grant_skill_points(99)
	for _sid in ["flame_burst", "poison_dart", "battle_cry", "regen_mist", "power_strike"]:
		if not stats.skill_book.is_known(_sid):
			stats.skill_book.try_learn(_sid, skills, 99)

	failed += _expect(skills.has_skill("flame_burst"), "flame_burst loaded")
	failed += _expect(skills.has_skill("poison_dart"), "poison_dart loaded")
	failed += _expect(skills.has_skill("battle_cry"), "battle_cry loaded")
	failed += _expect(skills.has_skill("regen_mist"), "regen_mist loaded")
	failed += _expect(str(skills.get_skill("flame_burst").get("effect", "")) == "aoe_damage", "flame effect")
	failed += _expect(str(skills.get_skill("poison_dart").get("effect", "")) == "damage_and_status", "poison effect")

	# --- DoT tick reduces HP over time ---
	stats.ensure_npc("dot_slime", true)
	stats.set_npc_cell("dot_slime", 1, 0)
	stats.npcs["dot_slime"]["hp"] = 40
	stats.npcs["dot_slime"]["hp_max"] = 40
	stats.npcs["dot_slime"]["def"] = 0
	stats.statuses.apply_status("dot_slime", {
		"id": "poison",
		"name": "中毒",
		"kind": "dot",
		"duration": 5.0,
		"tick_interval": 1.0,
		"tick_hp": -5,
	}, 5.0, "player")
	var hp0: int = int(stats.npcs["dot_slime"].get("hp", 0))
	var tick_acts: Array = stats.statuses.tick_statuses(1.0, stats)
	var hp1: int = int(stats.npcs["dot_slime"].get("hp", 0)) if stats.npcs.has("dot_slime") else 0
	failed += _expect(hp1 == hp0 - 5, "DoT tick -5 hp (%d -> %d)" % [hp0, hp1])
	failed += _expect(_has_type(tick_acts, "damage"), "DoT emits damage")
	stats.statuses.tick_statuses(1.0, stats)
	var hp2: int = int(stats.npcs["dot_slime"].get("hp", 0)) if stats.npcs.has("dot_slime") else 0
	failed += _expect(hp2 == hp1 - 5, "DoT second tick")

	# --- Buff modifies atk used in damage ---
	stats.reset_player(3)
	stats.statuses.clear_everything()
	stats.player["atk"] = 20
	stats.player["mp"] = 99
	stats.player["mp_max"] = 99
	var base_eff: int = stats.statuses.effective_atk(20, "player")
	failed += _expect(base_eff == 20, "base effective atk")
	stats.skill_ready_at.clear()
	var cry: Dictionary = engine.try_use_skill("battle_cry", "", 0, 0)
	failed += _expect(bool(cry.get("ok", false)), "battle_cry ok")
	failed += _expect(stats.statuses.has_status("player", "battle_cry"), "battle_cry on player")
	var snap: Array = stats.statuses.snapshot_statuses("player")
	failed += _expect(not snap.is_empty(), "battle_cry in snapshot")
	var found_cry := false
	for s in snap:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == "battle_cry":
			found_cry = true
			failed += _expect(abs(float(s.get("atk_mul", 1.0)) - 1.35) < 0.001, "atk_mul 1.35")
	failed += _expect(found_cry, "battle_cry status id in snapshot")
	var buffed: int = stats.statuses.effective_atk(20, "player")
	failed += _expect(buffed == int(round(20.0 * 1.35)), "buffed atk %d" % buffed)
	failed += _expect(_has_type(cry.get("actions", []), "status_update"), "battle_cry status_update")

	# Place NPC and hit with buffed atk via power path
	stats.ensure_npc("buff_target", true)
	stats.set_npc_cell("buff_target", 1, 0)
	stats.npcs["buff_target"]["hp"] = 200
	stats.npcs["buff_target"]["hp_max"] = 200
	stats.npcs["buff_target"]["def"] = 0
	stats.skill_ready_at.clear()
	stats.attack_ready_at = 0.0
	var atk_r: Dictionary = engine.try_attack("buff_target", 0, 0)
	failed += _expect(bool(atk_r.get("ok", false)), "buffed attack ok")
	var dealt := 0
	for a in atk_r.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "damage" and str(a.get("target", "")) == "npc":
			dealt = int(a.get("amount", 0))
			break
	failed += _expect(dealt == engine._effective_atk_player(), "damage uses buffed+passive atk (%d)" % dealt)

	# --- AoE hits >= 2 adjacent NPCs ---
	stats.statuses.clear_everything()
	stats.clear_npcs()
	stats.player["mp"] = 99
	stats.skill_ready_at.clear()
	stats.ensure_npc("aoe_a", true)
	stats.ensure_npc("aoe_b", true)
	stats.ensure_npc("aoe_c", true)
	stats.set_npc_cell("aoe_a", 2, 0)
	stats.set_npc_cell("aoe_b", 3, 0)  # chebyshev dist 1 from aoe_a at (2,0) when center is aoe_a
	stats.set_npc_cell("aoe_c", 2, 1)
	for nid in ["aoe_a", "aoe_b", "aoe_c"]:
		stats.npcs[nid]["hp"] = 80
		stats.npcs[nid]["hp_max"] = 80
		stats.npcs[nid]["def"] = 0
		stats.npcs[nid]["hostile"] = true
	# Player at (0,0); target aoe_a at (2,0) within range 3
	var aoe: Dictionary = engine.try_use_skill("flame_burst", "aoe_a", 0, 0)
	failed += _expect(bool(aoe.get("ok", false)), "flame_burst ok")
	var aoe_acts: Array = aoe.get("actions", [])
	aoe_acts.append_array(_finish_cast(engine))
	var hit_ids: Dictionary = {}
	for a in aoe_acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "damage" and str(a.get("target", "")) == "npc":
			hit_ids[str(a.get("id", ""))] = true
	failed += _expect(hit_ids.size() >= 2, "aoe hits >=2 (got %d: %s)" % [hit_ids.size(), str(hit_ids.keys())])
	failed += _expect(hit_ids.has("aoe_a"), "aoe includes primary")

	# --- poison_dart applies status id ---
	stats.statuses.clear_everything()
	stats.player["mp"] = 99
	stats.skill_ready_at.clear()
	stats.ensure_npc("poison_tgt", true)
	stats.set_npc_cell("poison_tgt", 1, 0)
	stats.npcs["poison_tgt"]["hp"] = 100
	stats.npcs["poison_tgt"]["hp_max"] = 100
	stats.npcs["poison_tgt"]["def"] = 0
	var pd: Dictionary = engine.try_use_skill("poison_dart", "poison_tgt", 0, 0)
	failed += _expect(bool(pd.get("ok", false)), "poison_dart ok")
	var pd_acts: Array = pd.get("actions", [])
	pd_acts.append_array(_finish_cast(engine))
	failed += _expect(stats.statuses.has_status("poison_tgt", "poison"), "poison status applied")
	failed += _expect(_has_type(pd_acts, "status_update"), "poison status_update action")

	# --- regen_mist HoT ---
	stats.statuses.clear_everything()
	stats.clear_npcs()
	stats.player["mp"] = 99
	stats.player["hp"] = 20
	stats.skill_ready_at.clear()
	var mist: Dictionary = engine.try_use_skill("regen_mist", "", 0, 0)
	failed += _expect(bool(mist.get("ok", false)), "regen_mist ok")
	_finish_cast(engine)
	failed += _expect(stats.statuses.has_status("player", "regen"), "regen on player")
	var before_h: int = int(stats.player.get("hp", 0))
	engine.tick(0, 0, 1.0)
	var after_h: int = int(stats.player.get("hp", 0))
	failed += _expect(after_h > before_h, "HoT healed via tick (%d -> %d)" % [before_h, after_h])

	# Existing skills still work
	stats.statuses.clear_everything()
	stats.player["mp"] = 99
	stats.skill_ready_at.clear()
	stats.ensure_npc("old", true)
	stats.set_npc_cell("old", 1, 0)
	stats.npcs["old"]["hp"] = 50
	var ps: Dictionary = engine.try_use_skill("power_strike", "old", 0, 0)
	failed += _expect(bool(ps.get("ok", false)), "power_strike still ok")

	if failed == 0:
		print("test_combat_status_aoe: PASS")
		quit(0)
	else:
		print("test_combat_status_aoe: FAIL count=", failed)
		quit(1)


func _finish_cast(engine, max_sec: float = 4.0) -> Array:
	var out: Array = []
	var t := 0.0
	while engine.is_casting() and t < max_sec:
		out.append_array(engine.tick_cast(0.25))
		t += 0.25
	return out


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
