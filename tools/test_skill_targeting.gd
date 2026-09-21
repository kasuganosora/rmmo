extends SceneTree
## Headless: ground-target skills, AoE shapes, NPC skill hits player.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_ground_and_shapes()
	failed += await _test_npc_skill()
	failed += _test_demo_art()
	if failed == 0:
		print("test_skill_targeting: PASS")
		quit(0)
	else:
		print("test_skill_targeting: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _engine():
	var CombatStats = load("res://scripts/net/combat/combat_stats.gd")
	var CombatEngine = load("res://scripts/net/combat/combat_engine.gd")
	var SkillCatalog = load("res://scripts/net/combat/skill_catalog.gd")
	var ItemCatalog = load("res://scripts/net/combat/item_catalog.gd")
	var Inventory = load("res://scripts/net/combat/inventory.gd")
	var stats = CombatStats.new()
	stats.reset_player(3)
	stats.player["mp"] = 99
	stats.player["mp_max"] = 99
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
	for _sid in ["flame_burst", "poison_dart"]:
		if not stats.skill_book.is_known(_sid):
			stats.skill_book.try_learn(_sid, skills, 99)
	return {"stats": stats, "skills": skills, "engine": engine}


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


func _test_ground_and_shapes() -> int:
	var failed := 0
	var ctx = _engine()
	var stats = ctx.stats
	var engine = ctx.engine
	var skills = ctx.skills
	failed += _expect(str(skills.get_skill("flame_burst").get("target_mode", "")) == "ground", "flame ground mode")
	failed += _expect(engine.skill_target_mode(skills.get_skill("flame_burst")) == "ground", "engine mode ground")
	# No target, no cell → need ground
	var miss: Dictionary = engine.try_use_skill("flame_burst", "", 0, 0)
	failed += _expect(not bool(miss.get("ok", true)), "ground skill needs cell")
	failed += _expect(str(miss.get("reason", "")) == "need_ground", "reason need_ground")
	# Selected target becomes landing cell
	stats.ensure_npc("g_a", true)
	stats.ensure_npc("g_b", true)
	stats.ensure_npc("g_far", true)
	stats.set_npc_cell("g_a", 2, 0)
	stats.set_npc_cell("g_b", 3, 0)
	stats.set_npc_cell("g_far", 8, 8)
	for nid in ["g_a", "g_b", "g_far"]:
		stats.npcs[nid]["hp"] = 80
		stats.npcs[nid]["hp_max"] = 80
		stats.npcs[nid]["def"] = 0
		stats.npcs[nid]["hostile"] = true
	stats.skill_ready_at.clear()
	var via_tgt: Dictionary = engine.try_use_skill("flame_burst", "g_a", 0, 0)
	failed += _expect(bool(via_tgt.get("ok", false)), "ground via target ok")
	var acts: Array = via_tgt.get("actions", [])
	acts.append_array(_finish_cast(engine))
	var hits := {}
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "damage" and str(a.get("target", "")) == "npc":
			hits[str(a.get("id", ""))] = true
	failed += _expect(hits.has("g_a"), "via target hits a")
	failed += _expect(hits.has("g_b"), "via target hits neighbor")
	failed += _expect(not hits.has("g_far"), "far not hit")
	failed += _expect(_has_type(acts, "skill_fx"), "skill_fx emitted")
	failed += _expect(_has_type(acts, "skill_anim"), "skill_anim emitted")
	# Explicit ground cell, no unit
	stats.skill_ready_at.clear()
	stats.player["mp"] = 99
	stats.npcs["g_a"]["hp"] = 80
	stats.npcs["g_b"]["hp"] = 80
	var via_cell: Dictionary = engine.try_use_skill("flame_burst", "", 0, 0, 2, 0)
	failed += _expect(bool(via_cell.get("ok", false)), "ground via cell ok")
	var acts2: Array = via_cell.get("actions", [])
	acts2.append_array(_finish_cast(engine))
	var hits2 := {}
	for a2 in acts2:
		if typeof(a2) != TYPE_DICTIONARY:
			continue
		if str(a2.get("type", "")) == "damage" and str(a2.get("target", "")) == "npc":
			hits2[str(a2.get("id", ""))] = true
	failed += _expect(hits2.has("g_a") and hits2.has("g_b"), "explicit cell aoe")
	# Out of range cell
	stats.skill_ready_at.clear()
	stats.player["mp"] = 99
	var far: Dictionary = engine.try_use_skill("flame_burst", "", 0, 0, 9, 9)
	failed += _expect(not bool(far.get("ok", true)), "ground out of range")
	# Shapes
	failed += _expect(engine.cell_in_aoe(Vector2i(0, 0), Vector2i(2, 0), 2, "circle"), "circle includes")
	failed += _expect(not engine.cell_in_aoe(Vector2i(0, 0), Vector2i(2, 2), 2, "cross"), "cross excludes diagonal")
	failed += _expect(engine.cell_in_aoe(Vector2i(0, 0), Vector2i(0, 2), 2, "cross"), "cross includes axis")
	failed += _expect(engine.cell_in_aoe(Vector2i(0, 0), Vector2i(0, 2), 2, "line", 2), "line south")
	failed += _expect(not engine.cell_in_aoe(Vector2i(0, 0), Vector2i(1, 0), 2, "line", 2), "line not side")
	failed += _expect(engine.aoe_cells(Vector2i(0, 0), 1, "cross").size() == 5, "cross size 5")
	# Register shape skill
	skills.register_skill({
		"id": "_cap_cross",
		"name": "cross cap",
		"effect": "aoe_damage",
		"target_mode": "ground",
		"requires_target": false,
		"aoe_radius": 2,
		"aoe_shape": "cross",
		"power": 1.0,
		"range": 5,
		"mp_cost": 0,
		"cooldown": 0,
	})

	stats.ensure_skill_book()
	stats.skill_book.known["_cap_cross"] = true
	stats.skill_ready_at.clear()
	stats.ensure_npc("diag", true)
	stats.set_npc_cell("diag", 1, 1)
	stats.npcs["diag"]["hp"] = 50
	stats.npcs["diag"]["def"] = 0
	stats.npcs["diag"]["hostile"] = true
	stats.npcs["g_a"]["hp"] = 50
	var cr: Dictionary = engine.try_use_skill("_cap_cross", "", 0, 0, 0, 0)
	failed += _expect(bool(cr.get("ok", false)), "cross skill ok")
	var chits := {}
	for a3 in cr.get("actions", []):
		if typeof(a3) == TYPE_DICTIONARY and str(a3.get("type", "")) == "damage":
			chits[str(a3.get("id", ""))] = true
	failed += _expect(not chits.has("diag"), "cross skips diagonal npc")
	return failed


func _test_npc_skill() -> int:
	var failed := 0
	var MockServer = load("res://scripts/net/mock_server.gd")
	var srv = MockServer.new()
	root.add_child(srv)
	await process_frame
	if srv.combat_stats == null:
		srv._init_combat_layers()
	srv.map_collision = null
	srv.set_player_cell(5, 5)
	srv.combat_engine.player_cell_hint = Vector2i(5, 5)
	srv.combat_stats.reset_player(3)
	srv.combat_stats.player["hp"] = 80
	srv.register_npc("mob_sk", 5, 7, true, true, 8, 0, 0, {
		"name": "技能怪",
		"hostile": true,
		"skills": ["flame_burst"],
	})
	failed += _expect(srv.combat_stats.npc_ai.has("mob_sk"), "npc ai")
	var ai: Dictionary = srv.combat_stats.npc_ai["mob_sk"]
	failed += _expect(ai.get("skills", []).has("flame_burst"), "npc has flame")
	var st0: Dictionary = srv.combat_stats.npcs["mob_sk"]
	failed += _expect(int(st0.get("mp_max", 0)) > 0, "npc has mp_max")
	st0["mp"] = 99
	st0["mp_max"] = 99
	srv.combat_stats.npcs["mob_sk"] = st0
	var hp0: int = int(srv.combat_stats.player.get("hp", 0))
	var r: Dictionary = srv.try_npc_skill("mob_sk", "flame_burst", 5, 5)
	failed += _expect(bool(r.get("ok", false)), "npc skill ok")
	var hp1: int = int(srv.combat_stats.player.get("hp", 0))
	failed += _expect(hp1 < hp0, "npc aoe damaged player %d -> %d" % [hp0, hp1])
	failed += _expect(_has_type(r.get("actions", []), "skill_fx"), "npc skill_fx")
	failed += _expect(_has_type(r.get("actions", []), "damage"), "npc damage action")
	# AI chase path also fires when in range
	ai = srv.combat_stats.npc_ai["mob_sk"]
	ai["skill_ready_at"] = {}
	srv.combat_stats.npc_ai["mob_sk"] = ai
	srv.combat_stats.player["hp"] = 80
	var chase: Array = srv._try_npc_skill_tick("mob_sk", srv.combat_stats.npc_ai["mob_sk"], Vector2i(5, 7), 5, 5)
	failed += _expect(_has_type(chase, "skill_fx") or _has_type(chase, "damage"), "chase tick casts")
	# MP gate: empty mana cannot cast
	var st1: Dictionary = srv.combat_stats.npcs["mob_sk"]
	st1["mp"] = 0
	st1["mp_max"] = 40
	srv.combat_stats.npcs["mob_sk"] = st1
	ai = srv.combat_stats.npc_ai["mob_sk"]
	ai["skill_ready_at"] = {}
	srv.combat_stats.npc_ai["mob_sk"] = ai
	var dry: Dictionary = srv.try_npc_skill("mob_sk", "flame_burst", 5, 5)
	failed += _expect(not bool(dry.get("ok", true)), "npc skill blocked without mp")
	failed += _expect(str(dry.get("reason", "")) == "mp", "reason mp")
	st1["mp"] = 18
	srv.combat_stats.npcs["mob_sk"] = st1
	var wet: Dictionary = srv.try_npc_skill("mob_sk", "flame_burst", 5, 5)
	failed += _expect(bool(wet.get("ok", false)), "npc skill spends last mp")
	failed += _expect(int(srv.combat_stats.npcs["mob_sk"].get("mp", 99)) == 0, "mp drained to 0")
	srv.queue_free()
	return failed


func _test_demo_art() -> int:
	var failed := 0
	var am: Node = root.get_node_or_null("AssetManager")
	failed += _expect(am != null, "AssetManager")
	if am != null:
		failed += _expect(bool(am.has("content://fx/fx_slash.png")), "slash fx")
		failed += _expect(bool(am.has("content://fx/fx_cast.png")), "cast fx")
		failed += _expect(bool(am.has("content://fx/fx_dash.png")), "dash fx")
		failed += _expect(bool(am.has("content://fx/fx_spin.png")), "spin fx")
		failed += _expect(bool(am.has("content://icon/wooden_sword")), "sword icon")
		failed += _expect(bool(am.has("content://icon/leather_vest")), "vest icon")
		failed += _expect(bool(am.has("content://fx/equip_wooden_sword.png")), "sword world")
	var ctx = _engine()
	var engine = ctx.engine
	var skills = ctx.skills
	failed += _expect(engine.skill_anim_kind(skills.get_skill("power_strike"), "power_strike") == "strike", "strike anim")
	failed += _expect(engine.skill_anim_kind(skills.get_skill("heal_light"), "heal_light") == "cast", "cast anim")
	failed += _expect(engine.skill_anim_kind(skills.get_skill("poison_dart"), "poison_dart") == "dash", "dash anim")
	failed += _expect(engine.skill_anim_kind(skills.get_skill("battle_cry"), "battle_cry") == "spin", "spin anim")
	return failed
