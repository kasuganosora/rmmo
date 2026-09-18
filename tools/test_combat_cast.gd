extends SceneTree
## Headless tests: cast_time / channel / interrupt / busy / instant.

const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")


func _init() -> void:
	var failed := 0
	failed += _expect(true, "boot")

	var stats = CombatStats.new()
	stats.reset_player(5)
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
	for _sid in ["heal_light", "arcane_bolt", "channel_beam", "power_strike", "battle_cry", "flame_burst"]:
		if not stats.skill_book.is_known(_sid):
			stats.skill_book.try_learn(_sid, skills, 99)

	failed += _expect(float(skills.get_skill("heal_light").get("cast_time", 0)) > 0.0, "heal_light has cast_time")
	failed += _expect(skills.has_skill("arcane_bolt"), "arcane_bolt loaded")
	failed += _expect(skills.has_skill("channel_beam"), "channel_beam loaded")
	failed += _expect(float(skills.get_skill("channel_beam").get("channel_time", 0)) > 0.0, "channel_beam channel_time")

	# --- cast begins, no instant heal ---
	stats.player["hp"] = 20
	stats.player["mp"] = 99
	stats.skill_ready_at.clear()
	var hp_before: int = int(stats.player.get("hp", 0))
	var mp_before: int = int(stats.player.get("mp", 0))
	var r0: Dictionary = engine.try_use_skill("heal_light", "", 0, 0)
	failed += _expect(bool(r0.get("ok", false)), "heal cast start ok")
	failed += _expect(_has_type(r0.get("actions", []), "cast_start"), "cast_start action")
	failed += _expect(not _has_type(r0.get("actions", []), "heal"), "no instant heal")
	failed += _expect(engine.is_casting(), "is casting")
	failed += _expect(int(stats.player.get("hp", 0)) == hp_before, "hp unchanged during cast")
	failed += _expect(int(stats.player.get("mp", 0)) < mp_before, "mp spent at start")

	# --- tick until finish applies effect ---
	var acts: Array = _drain_cast(engine, 2.0)
	failed += _expect(not engine.is_casting(), "cast finished")
	failed += _expect(_has_type(acts, "heal") or int(stats.player.get("hp", 0)) > hp_before, "heal applied after cast")
	failed += _expect(_has_type(acts, "cast_end"), "cast_end action")

	# --- move interrupt: no damage ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 99
	stats.ensure_npc("cast_tgt", true)
	stats.set_npc_cell("cast_tgt", 1, 0)
	stats.npcs["cast_tgt"]["hp"] = 100
	stats.npcs["cast_tgt"]["hp_max"] = 100
	stats.npcs["cast_tgt"]["def"] = 0
	var bolt: Dictionary = engine.try_use_skill("arcane_bolt", "cast_tgt", 0, 0)
	failed += _expect(bool(bolt.get("ok", false)), "arcane_bolt cast start")
	failed += _expect(engine.is_casting(), "casting arcane")
	var hp_npc: int = int(stats.npcs["cast_tgt"].get("hp", 0))
	var inter: Array = engine.interrupt_cast("move")
	failed += _expect(not engine.is_casting(), "interrupted clears cast")
	failed += _expect(_has_type(inter, "cast_end"), "interrupt cast_end")
	failed += _expect(int(stats.npcs["cast_tgt"].get("hp", 0)) == hp_npc, "no damage on interrupt")
	# Extra ticks should not apply
	var late: Array = engine.tick_cast(5.0)
	failed += _expect(not _has_type(late, "damage"), "no late damage after interrupt")

	# --- busy: second cast rejected ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 99
	var a: Dictionary = engine.try_use_skill("heal_light", "", 0, 0)
	failed += _expect(bool(a.get("ok", false)), "first heal cast ok")
	var b: Dictionary = engine.try_use_skill("flame_burst", "cast_tgt", 0, 0)
	failed += _expect(not bool(b.get("ok", true)), "second cast rejected while busy")
	engine.clear_cast()

	# --- instant skill still works ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 99
	stats.ensure_npc("inst", true)
	stats.set_npc_cell("inst", 1, 0)
	stats.npcs["inst"]["hp"] = 80
	stats.npcs["inst"]["def"] = 0
	var ps: Dictionary = engine.try_use_skill("power_strike", "inst", 0, 0)
	failed += _expect(bool(ps.get("ok", false)), "power_strike instant ok")
	failed += _expect(_has_type(ps.get("actions", []), "damage"), "instant damage")
	failed += _expect(not engine.is_casting(), "instant leaves idle")

	# --- channel completes once at end ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 99
	stats.ensure_npc("beam", true)
	stats.set_npc_cell("beam", 1, 0)
	stats.npcs["beam"]["hp"] = 200
	stats.npcs["beam"]["def"] = 0
	var ch: Dictionary = engine.try_use_skill("channel_beam", "beam", 0, 0)
	failed += _expect(bool(ch.get("ok", false)), "channel start ok")
	var mode := ""
	for act in ch.get("actions", []):
		if typeof(act) == TYPE_DICTIONARY and str(act.get("type", "")) == "cast_start":
			mode = str(act.get("mode", ""))
	failed += _expect(mode == "channel", "mode channel")
	failed += _expect(not _has_type(ch.get("actions", []), "damage"), "no damage at channel start")
	var ch_acts: Array = _drain_cast(engine, 3.0)
	failed += _expect(_has_type(ch_acts, "damage"), "channel end damage")
	failed += _expect(_has_type(ch_acts, "cast_end"), "channel cast_end")

	# --- battle_cry remains instant ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 99
	stats.statuses.clear_everything()
	var cry: Dictionary = engine.try_use_skill("battle_cry", "", 0, 0)
	failed += _expect(bool(cry.get("ok", false)), "battle_cry instant")
	failed += _expect(stats.statuses.has_status("player", "battle_cry"), "battle_cry applied instantly")

	if failed == 0:
		print("test_combat_cast: PASS")
		quit(0)
	else:
		print("test_combat_cast: FAIL count=", failed)
		quit(1)


func _drain_cast(engine, max_sec: float) -> Array:
	var out: Array = []
	var t := 0.0
	var step := 0.25
	while engine.is_casting() and t < max_sec:
		out.append_array(engine.tick_cast(step))
		t += step
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
