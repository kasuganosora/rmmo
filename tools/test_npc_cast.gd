extends SceneTree
## Headless: NPC cast_time → casting state; interrupt cancels; uninterrupted completes.

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
	stats.reset_player(5)
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
	engine.player_cell_hint = Vector2i(0, 0)

	stats.ensure_skill_book()
	if stats.skill_book.list_known().is_empty():
		stats.skill_book.grant_starters(skills)
	stats.skill_book.grant_skill_points(99)
	if not stats.skill_book.is_known("interrupt"):
		stats.skill_book.try_learn("interrupt", skills, 99)

	# Sample skill with cast_time (slime uses flame_burst in demo_map).
	failed += _expect(skills.has_skill("flame_burst"), "catalog has flame_burst")
	var fb: Dictionary = skills.get_skill("flame_burst")
	failed += _expect(float(fb.get("cast_time", 0.0)) > 0.0, "flame_burst cast_time > 0")

	# --- Setup hostile caster ---
	stats.ensure_npc("slime_a", true, true)
	stats.ensure_npc_ai("slime_a", 2, true, Vector2i(2, 0), 0)
	stats.set_npc_cell("slime_a", 2, 0)
	stats.npcs["slime_a"]["name"] = "史莱姆"
	stats.npcs["slime_a"]["hp"] = 200
	stats.npcs["slime_a"]["hp_max"] = 200
	stats.npcs["slime_a"]["def"] = 0
	stats.npcs["slime_a"]["mp"] = 80
	stats.npcs["slime_a"]["mp_max"] = 80
	stats.npcs["slime_a"]["atk"] = 10

	# --- Start cast (no instant damage) ---
	var hp_before: int = int(stats.player.get("hp", 0))
	var mp_before: int = int(stats.npcs["slime_a"].get("mp", 0))
	var start: Dictionary = engine.try_npc_skill("slime_a", "flame_burst", 2, 0, 0, 0)
	failed += _expect(bool(start.get("ok", false)), "npc cast start ok")
	failed += _expect(bool(start.get("casting", false)), "casting flag")
	failed += _expect(engine.is_npc_casting("slime_a"), "is_npc_casting")
	failed += _expect(_has_type(start.get("actions", []), "cast_start"), "cast_start action")
	failed += _expect(not _has_type(start.get("actions", []), "damage"), "no instant damage")
	failed += _expect(int(stats.player.get("hp", 0)) == hp_before, "player hp unchanged during cast")
	failed += _expect(int(stats.npcs["slime_a"].get("mp", 0)) < mp_before, "npc mp spent at start")
	var busy: Dictionary = engine.try_npc_skill("slime_a", "flame_burst", 2, 0, 0, 0)
	failed += _expect(not bool(busy.get("ok", true)), "second skill rejected while casting")
	failed += _expect(str(busy.get("reason", "")) == "busy", "reason busy")

	# --- Interrupt cancels cast ---
	stats.player["mp"] = 50
	stats.player["mp_max"] = 50
	stats.skill_ready_at.clear()
	var inter: Dictionary = engine.try_use_skill("interrupt", "slime_a", 0, 0)
	failed += _expect(bool(inter.get("ok", false)), "interrupt ok")
	failed += _expect(not engine.is_npc_casting("slime_a"), "cast cleared by interrupt")
	failed += _expect(_has_type(inter.get("actions", []), "cast_end"), "cast_end cancelled")
	failed += _expect(_has_msg(inter.get("actions", []), "打断了史莱姆的施法！"), "msg 打断了史莱姆的施法！")
	failed += _expect(stats.statuses.has_status("slime_a", "silence"), "silence still applied")
	failed += _expect(not _has_msg(inter.get("actions", []), "打断：沉默了史莱姆！"), "no double silence toast when cast interrupted")
	# Ticks must not resolve after cancel
	var late: Array = engine.tick_npc_casts(5.0)
	failed += _expect(not _has_type(late, "damage"), "no late damage after interrupt")
	failed += _expect(int(stats.player.get("hp", 0)) == hp_before, "no flame damage after cancel")

	# --- Uninterrupted cast completes ---
	stats.statuses.clear_status("slime_a", "silence")
	stats.npcs["slime_a"]["mp"] = 80
	stats.player["hp"] = int(stats.player.get("hp_max", 100))
	hp_before = int(stats.player.get("hp", 0))
	engine.player_cell_hint = Vector2i(0, 0)
	var start2: Dictionary = engine.try_npc_skill("slime_a", "flame_burst", 2, 0, 0, 0)
	failed += _expect(bool(start2.get("ok", false)), "second cast start ok")
	failed += _expect(engine.is_npc_casting("slime_a"), "casting again")
	var acts: Array = _drain_npc_cast(engine, 3.0)
	failed += _expect(not engine.is_npc_casting("slime_a"), "cast finished")
	failed += _expect(_has_type(acts, "cast_end"), "cast_end ok")
	failed += _expect(_has_type(acts, "damage") or int(stats.player.get("hp", 0)) < hp_before, "damage after cast completes")
	failed += _expect(_has_msg(acts, "使用了") or _has_msg(acts, "火焰爆发"), "resolve use msg")

	# --- Instant skill (cast_time 0) still immediate ---
	stats.npcs["slime_a"]["mp"] = 80
	stats.set_npc_cell("slime_a", 1, 0)  # adjacent for range-1 power_strike
	# power_strike has no cast_time in catalog → instant
	var ps_def: Dictionary = skills.get_skill("power_strike")
	failed += _expect(float(ps_def.get("cast_time", 0.0)) <= 0.0, "power_strike instant")
	stats.player["hp"] = int(stats.player.get("hp_max", 100))
	engine.player_cell_hint = Vector2i(0, 0)
	var inst: Dictionary = engine.try_npc_skill("slime_a", "power_strike", 1, 0, 0, 0)
	failed += _expect(bool(inst.get("ok", false)), "instant npc skill ok")
	failed += _expect(not bool(inst.get("casting", false)), "instant not casting")
	failed += _expect(not engine.is_npc_casting("slime_a"), "instant leaves idle")
	failed += _expect(_has_type(inst.get("actions", []), "damage") or int(stats.player.get("hp", 0)) < int(stats.player.get("hp_max", 100)), "instant damage")

	if failed == 0:
		print("test_npc_cast: PASS")
		quit(0)
	else:
		print("test_npc_cast: FAIL count=", failed)
		quit(1)


func _drain_npc_cast(engine, max_sec: float) -> Array:
	var out: Array = []
	var t := 0.0
	while t < max_sec and engine.is_npc_casting("slime_a"):
		out.append_array(engine.tick_npc_casts(0.1))
		t += 0.1
	if engine.is_npc_casting("slime_a"):
		out.append_array(engine.tick_npc_casts(max_sec))
	return out


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
