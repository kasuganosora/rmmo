extends SceneTree
## Headless smoke test for mob vision, enrage, return-home, idle wander helpers.

const MobAI = preload("res://scripts/net/combat/mob_ai.gd")
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

	# Facing down (2): player south within range → in vision.
	failed += _expect(
		MobAI.player_in_vision(Vector2i(10, 10), 2, Vector2i(10, 14)),
		"down cone in range"
	)
	# Behind NPC → out of vision.
	failed += _expect(
		not MobAI.player_in_vision(Vector2i(10, 10), 2, Vector2i(10, 6)),
		"behind not in cone"
	)
	# Too far (Euclidean > 6).
	failed += _expect(
		not MobAI.player_in_vision(Vector2i(10, 10), 2, Vector2i(10, 17)),
		"beyond 6 cells"
	)
	# Diagonal within 60° of down.
	failed += _expect(
		MobAI.player_in_vision(Vector2i(10, 10), 2, Vector2i(12, 15)),
		"diagonal in cone"
	)
	# Wide side (~90°): right of down-facing NPC.
	failed += _expect(
		not MobAI.player_in_vision(Vector2i(10, 10), 2, Vector2i(14, 10)),
		"90deg side out of 120 cone"
	)

	var stats = CombatStats.new()
	stats.reset_player(3)
	stats.ensure_npc("pas", true, false)
	stats.ensure_npc_ai("pas", 2, false, Vector2i(5, 5), 0)
	stats.set_npc_cell("pas", 5, 5)
	failed += _expect(not MobAI.wants_chase(stats.npc_ai["pas"]), "passive not chase")
	failed += _expect(str(stats.npc_ai["pas"].get("ai_state", "")) == MobAI.AI_IDLE, "pas starts idle")
	failed += _expect(MobAI.get_home_cell(stats.npc_ai["pas"]) == Vector2i(5, 5), "pas home_cell")
	failed += _expect(int(stats.npc_ai["pas"].get("wander_radius", -1)) == 0, "pas wander 0")
	stats.enrage_npc("pas")
	failed += _expect(MobAI.wants_chase(stats.npc_ai["pas"]), "enraged wants chase")
	failed += _expect(bool(stats.npc_ai["pas"].get("enraged", false)), "enraged flag")

	stats.ensure_npc("agg", true, true)
	stats.ensure_npc_ai("agg", 6, true, Vector2i(8, 8), 3)
	stats.set_npc_cell("agg", 10, 9)
	failed += _expect(MobAI.wants_chase(stats.npc_ai["agg"]), "aggressive wants chase")
	failed += _expect(int(stats.npc_ai["agg"].get("wander_radius", -1)) == 3, "agg wander 3")

	# clear_chase away from home → return_home; passive loses enrage.
	stats.npc_ai["pas"]["chase_target"] = "player"
	stats.npc_ai["pas"]["ai_state"] = MobAI.AI_CHASE
	stats.set_npc_cell("pas", 7, 5)  # away from home (5,5)
	stats.npc_ai["agg"]["chase_target"] = "player"
	stats.npc_ai["agg"]["ai_state"] = MobAI.AI_CHASE
	stats.clear_chase("pas")
	stats.clear_chase("agg")
	failed += _expect(str(stats.npc_ai["pas"].get("chase_target", "")) == "", "pas chase cleared")
	failed += _expect(not bool(stats.npc_ai["pas"].get("enraged", true)), "pas enrage cleared")
	failed += _expect(str(stats.npc_ai["pas"].get("ai_state", "")) == MobAI.AI_RETURN_HOME, "pas return_home")
	failed += _expect(str(stats.npc_ai["agg"].get("ai_state", "")) == MobAI.AI_RETURN_HOME, "agg return_home")
	failed += _expect(bool(stats.npc_ai["agg"].get("aggressive", false)), "agg still aggressive")
	failed += _expect(MobAI.wants_chase(stats.npc_ai["agg"]), "agg still wants chase")
	failed += _expect(not MobAI.wants_chase(stats.npc_ai["pas"]), "pas no longer chase")

	# clear_chase already at home → idle
	stats.set_npc_cell("pas", 5, 5)
	stats.npc_ai["pas"]["chase_target"] = "player"
	stats.npc_ai["pas"]["ai_state"] = MobAI.AI_CHASE
	stats.clear_chase("pas")
	failed += _expect(str(stats.npc_ai["pas"].get("ai_state", "")) == MobAI.AI_IDLE, "at home → idle")

	# within_wander_radius / idle dir with null collision
	failed += _expect(MobAI.within_wander_radius(Vector2i(5, 5), Vector2i(5, 5), 0), "r0 at home")
	failed += _expect(not MobAI.within_wander_radius(Vector2i(6, 5), Vector2i(5, 5), 0), "r0 off home")
	failed += _expect(MobAI.within_wander_radius(Vector2i(7, 6), Vector2i(5, 5), 2), "r2 inside")
	failed += _expect(not MobAI.within_wander_radius(Vector2i(8, 5), Vector2i(5, 5), 2), "r2 outside")
	failed += _expect(MobAI.next_idle_wander_dir(null, Vector2i(5, 5), Vector2i(5, 5), 0) == 0, "wander0 no dir")
	failed += _expect(MobAI.next_idle_wander_dir(null, Vector2i(5, 5), Vector2i(5, 5), 3) == 0, "null coll no dir")
	failed += _expect(MobAI.next_home_dir(null, Vector2i(5, 5), Vector2i(5, 5)) == 0, "already home dir0")

	# Damage path sets enrage via combat_engine.
	var skills = SkillCatalog.new()
	skills.load_catalog()
	var items = ItemCatalog.new()
	items.load_catalog()
	var bag = Inventory.new()
	bag.grant_starter()
	var engine = CombatEngine.new()
	engine.setup(stats, skills, items, bag)
	stats.ensure_npc("hitme", true, false)
	stats.ensure_npc_ai("hitme", 2, false, Vector2i(1, 0), 2)
	stats.set_npc_cell("hitme", 1, 0)
	stats.attack_ready_at = 0.0
	var atk: Dictionary = engine.try_attack("hitme", 0, 0)
	failed += _expect(bool(atk.get("ok", false)), "attack ok")
	failed += _expect(bool(stats.npc_ai["hitme"].get("enraged", false)), "damage enrages passive")
	failed += _expect(str(stats.npc_ai["hitme"].get("chase_target", "")) == "player", "chase started on hit")
	failed += _expect(str(stats.npc_ai["hitme"].get("ai_state", "")) == MobAI.AI_CHASE, "ai_state chase on hit")

	# Pack assist: same group_id within hit wander_radius of hit cell.
	stats.ensure_npc("pack_a", true, false)
	stats.ensure_npc_ai("pack_a", 2, false, Vector2i(0, 0), 3, 7)
	stats.set_npc_cell("pack_a", 0, 0)
	stats.ensure_npc("pack_b", true, false)
	stats.ensure_npc_ai("pack_b", 2, false, Vector2i(2, 0), 3, 7)
	stats.set_npc_cell("pack_b", 2, 0)  # chebyshev 2 ≤ 3
	stats.ensure_npc("pack_far", true, false)
	stats.ensure_npc_ai("pack_far", 2, false, Vector2i(10, 0), 3, 7)
	stats.set_npc_cell("pack_far", 10, 0)  # chebyshev 10 > 3
	stats.ensure_npc("solo", true, false)
	stats.ensure_npc_ai("solo", 2, false, Vector2i(1, 0), 3, 0)
	stats.set_npc_cell("solo", 1, 0)
	stats.begin_chase("pack_a")
	stats.activate_group_allies("pack_a")
	failed += _expect(str(stats.npc_ai["pack_b"].get("chase_target", "")) == "player", "pack ally chases")
	failed += _expect(bool(stats.npc_ai["pack_b"].get("enraged", false)), "pack ally enraged")
	failed += _expect(str(stats.npc_ai["pack_far"].get("chase_target", "")) == "", "far pack not activated")
	failed += _expect(str(stats.npc_ai["solo"].get("chase_target", "")) == "", "solo not activated")
	stats.clear_chase("pack_b")
	failed += _expect(not bool(stats.npc_ai["pack_b"].get("enraged", true)), "pack ally enrage cleared")
	var pack_b_state: String = str(stats.npc_ai["pack_b"].get("ai_state", ""))
	failed += _expect(
		pack_b_state == MobAI.AI_RETURN_HOME or pack_b_state == MobAI.AI_IDLE,
		"pack ally return/idle"
	)

	# Killing blow still wakes pack (activate before remove_npc).
	stats.ensure_npc("kill_a", true, false)
	stats.ensure_npc_ai("kill_a", 2, false, Vector2i(0, 0), 3, 9)
	stats.set_npc_cell("kill_a", 0, 0)
	stats.npcs["kill_a"]["hp"] = 1
	stats.npcs["kill_a"]["def"] = 0
	stats.ensure_npc("kill_b", true, false)
	stats.ensure_npc_ai("kill_b", 2, false, Vector2i(1, 0), 3, 9)
	stats.set_npc_cell("kill_b", 1, 0)
	stats.attack_ready_at = 0.0
	var kill_atk: Dictionary = engine.try_attack("kill_a", 0, 1)
	failed += _expect(bool(kill_atk.get("ok", false)), "kill attack ok")
	failed += _expect(not stats.npcs.has("kill_a"), "kill_a removed")
	failed += _expect(str(stats.npc_ai["kill_b"].get("chase_target", "")) == "player", "kill blow wakes ally")
	failed += _expect(str(stats.npc_ai["kill_b"].get("ai_state", "")) == MobAI.AI_CHASE, "kill ally chase")

	failed += _expect(is_equal_approx(MobAI.VISION_RANGE_CELLS, 6.0), "vision range 6")
	failed += _expect(is_equal_approx(MobAI.LOSE_SIGHT_SEC, 5.0), "lose sight 5s")
	failed += _expect(MobAI.IDLE_WANDER_INTERVAL_SEC > 1.0, "idle wander not jittery")
	failed += _expect(MobAI.DEFAULT_LEASH_RADIUS == 12, "default leash 12")
	failed += _expect(is_equal_approx(MobAI.DEFAULT_RESPAWN_SEC, 30.0), "default respawn 30")
	failed += _expect(not MobAI.beyond_leash(Vector2i(5, 5), Vector2i(5, 5), 12), "leash at home")
	failed += _expect(not MobAI.beyond_leash(Vector2i(10, 5), Vector2i(5, 5), 12), "leash inside 12")
	failed += _expect(MobAI.beyond_leash(Vector2i(18, 5), Vector2i(5, 5), 12), "leash beyond 12")
	failed += _expect(not MobAI.beyond_leash(Vector2i(18, 5), Vector2i(5, 5), -1), "leash disabled")

	# ensure_npc_ai seeds leash/respawn defaults
	stats.ensure_npc("leash_m", true, true)
	stats.ensure_npc_ai("leash_m", 2, true, Vector2i(0, 0), 2, 0, 8, 15.0)
	failed += _expect(int(stats.npc_ai["leash_m"].get("leash_radius", -1)) == 8, "ai leash 8")
	failed += _expect(is_equal_approx(float(stats.npc_ai["leash_m"].get("respawn_sec", -1)), 15.0), "ai respawn 15")

	# Integration: MockServer return_home emits npc_move toward home.
	failed += _run_return_home_tick()
	failed += _run_leash_and_respawn_tick()

	if failed == 0:
		print("test_mob_ai: PASS")
		quit(0)
	else:
		print("test_mob_ai: FAIL count=", failed)
		quit(1)


func _run_return_home_tick() -> int:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		# Autoload may not be ready in bare SceneTree — skip soft.
		print("  SKIP return_home tick (no MockServer)")
		return 0
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var pack = TilemapPack.load_pack("res://demo_map")
	if pack == null or pack.collision == null:
		print("  SKIP return_home tick (no demo pack)")
		return 0
	srv.map_collision = pack.collision
	srv.map_tile_size = pack.tile_size
	srv.map_collision.clear_extra_blocked()
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	srv.combat_stats.clear_npcs()
	srv.set_player_cell(20, 20)
	# Place hostile away from home; register home at (15,12), current at (17,12).
	srv.register_npc("ret_test", 15, 12, true, true, 2, 2)
	srv.map_collision.set_extra_blocked(15, 12, false)
	srv.map_collision.set_extra_blocked(17, 12, true)
	srv.combat_stats.set_npc_cell("ret_test", 17, 12)
	var ai: Dictionary = srv.combat_stats.npc_ai["ret_test"]
	ai["chase_target"] = "player"
	ai["ai_state"] = MobAI.AI_CHASE
	srv.combat_stats.npc_ai["ret_test"] = ai
	srv.combat_stats.clear_chase("ret_test")
	failed += _expect(
		str(srv.combat_stats.npc_ai["ret_test"].get("ai_state", "")) == MobAI.AI_RETURN_HOME,
		"tick setup return_home"
	)
	var acts: Array = srv._tick_mob_ai(0.5)
	var moved := false
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "npc_move" and str(a.get("npc_id", "")) == "ret_test":
			moved = true
			var nx: int = int(a.get("x", 17))
			var ny: int = int(a.get("y", 12))
			failed += _expect(nx != 17 or ny != 12 or int(a.get("facing", 0)) != 0, "return step or face")
			# Prefer actual step closer to home (15,12).
			if nx != 17 or ny != 12:
				var before: int = absi(17 - 15) + absi(12 - 12)
				var after: int = absi(nx - 15) + absi(ny - 12)
				failed += _expect(after < before, "return closer to home")
			break
	failed += _expect(moved, "return_home emitted npc_move")

	# Idle wander_radius 0: no move.
	srv.combat_stats.clear_npcs()
	srv.map_collision.clear_extra_blocked()
	srv.set_player_cell(20, 20)
	srv.register_npc("still", 15, 12, true, false, 2, 0)
	srv.map_collision.set_extra_blocked(15, 12, true)
	var idle_acts: Array = srv._tick_mob_ai(5.0)
	var idle_move := false
	for a2 in idle_acts:
		if typeof(a2) == TYPE_DICTIONARY and str(a2.get("npc_id", "")) == "still" and str(a2.get("type", "")) == "npc_move":
			if int(a2.get("x", 15)) != 15 or int(a2.get("y", 12)) != 12:
				idle_move = true
	failed += _expect(not idle_move, "wander0 idle no step")
	return failed



func _run_leash_and_respawn_tick() -> int:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("  SKIP leash/respawn tick (no MockServer)")
		return 0
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var pack = TilemapPack.load_pack("res://demo_map")
	if pack == null or pack.collision == null:
		print("  SKIP leash/respawn tick (no demo pack)")
		return 0
	srv.map_collision = pack.collision
	srv.map_tile_size = pack.tile_size
	srv.map_collision.clear_extra_blocked()
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	srv.combat_stats.clear_npcs()
	srv.npc_spawn_templates.clear()
	srv._npc_respawn_at.clear()
	srv.set_player_cell(30, 12)

	# Leash: chase far from home with leash_radius 3 → clear_chase / return_home.
	var leash_data := {
		"id": "leash_test",
		"name": "Leash Mob",
		"charset": "Monster",
		"index": 0,
		"cell": {"x": 15, "y": 12},
		"direction": 6,
		"hostile": true,
		"aggressive": true,
		"wander_radius": 1,
		"group_id": 0,
		"leash_radius": 3,
		"respawn_sec": 30.0,
	}
	srv.register_npc("leash_test", 15, 12, true, true, 6, 1, 0, leash_data)
	srv.map_collision.set_extra_blocked(15, 12, false)
	srv.map_collision.set_extra_blocked(20, 12, true)
	srv.combat_stats.set_npc_cell("leash_test", 20, 12)  # Chebyshev 5 > 3
	var lai: Dictionary = srv.combat_stats.npc_ai["leash_test"]
	lai["chase_target"] = "player"
	lai["ai_state"] = MobAI.AI_CHASE
	lai["seen_target"] = true
	srv.combat_stats.npc_ai["leash_test"] = lai
	var leash_acts: Array = srv._tick_mob_ai(0.5)
	var after: Dictionary = srv.combat_stats.npc_ai["leash_test"]
	failed += _expect(
		str(after.get("ai_state", "")) == MobAI.AI_RETURN_HOME
		or str(after.get("chase_target", "x")) == "",
		"leash break clears chase"
	)
	failed += _expect(str(after.get("ai_state", "")) == MobAI.AI_RETURN_HOME, "leash → return_home")

	# Respawn: kill hostile with respawn_sec 0 → due immediately on tick.
	srv.combat_stats.clear_npcs()
	srv.npc_spawn_templates.clear()
	srv._npc_respawn_at.clear()
	srv.map_collision.clear_extra_blocked()
	srv.set_player_cell(30, 12)
	var rs_data := {
		"id": "respawn_test",
		"name": "Respawn Mob",
		"charset": "Monster",
		"index": 0,
		"cell": {"x": 16, "y": 12},
		"direction": 2,
		"hostile": true,
		"aggressive": true,
		"wander_radius": 0,
		"group_id": 0,
		"leash_radius": 12,
		"respawn_sec": 0.0,
	}
	srv.register_npc("respawn_test", 16, 12, true, true, 2, 0, 0, rs_data)
	srv.map_collision.set_extra_blocked(16, 12, true)
	failed += _expect(srv.npc_spawn_templates.has("respawn_test"), "template stored")
	# Simulate kill path: remove + schedule via finalize.
	var kill_result := {
		"ok": true,
		"actions": [{"type": "kill_npc", "npc_id": "respawn_test"}],
	}
	srv.combat_stats.remove_npc("respawn_test")
	srv.map_collision.set_extra_blocked(16, 12, false)
	kill_result = srv._finalize_combat_result(kill_result)
	failed += _expect(srv._npc_respawn_at.has("respawn_test"), "respawn scheduled")
	failed += _expect(not srv.combat_stats.npcs.has("respawn_test"), "dead until timer")
	# Force due (respawn_sec 0 → ready_at ≈ now).
	srv._npc_respawn_at["respawn_test"] = 0.0
	var ra: Array = srv._tick_npc_respawns()
	var got_spawn := false
	for a in ra:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "spawn_npc":
			got_spawn = true
			var npc_v: Variant = a.get("npc", {})
			failed += _expect(typeof(npc_v) == TYPE_DICTIONARY, "spawn_npc has npc")
			if typeof(npc_v) == TYPE_DICTIONARY:
				failed += _expect(str(npc_v.get("id", "")) == "respawn_test", "spawn id")
				failed += _expect(str(npc_v.get("charset", "")) == "Monster", "spawn charset")
	failed += _expect(got_spawn, "spawn_npc emitted")
	failed += _expect(srv.combat_stats.npcs.has("respawn_test"), "npc re-registered")
	failed += _expect(srv.combat_stats.npc_ai.has("respawn_test"), "ai re-seeded")
	var cell: Vector2i = srv.combat_stats.get_npc_cell("respawn_test")
	failed += _expect(cell.x > -9990, "respawn cell set")
	return failed


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
