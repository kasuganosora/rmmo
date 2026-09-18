extends SceneTree
## Headless: mob leash / return-to-spawn — home_cell, radius, hate clear, HP reset, no attack while returning.

const MobAI = preload("res://scripts/net/combat/mob_ai.gd")
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _expect(MobAI.DEFAULT_LEASH_RADIUS == 12, "default leash radius 12")
	failed += _expect(MobAI.NO_VALID_TARGET_SEC == 5.0, "no-valid-target 5s")
	failed += _expect(MobAI.is_returning({"ai_state": MobAI.AI_RETURN_HOME}), "is_returning true")
	failed += _expect(not MobAI.is_returning({"ai_state": MobAI.AI_CHASE}), "is_returning false on chase")

	# Unit: beyond_leash Chebyshev
	var home := Vector2i(10, 10)
	failed += _expect(not MobAI.beyond_leash(Vector2i(10, 10), home, 10), "at home not beyond")
	failed += _expect(not MobAI.beyond_leash(Vector2i(20, 10), home, 10), "cheb 10 == radius not beyond")
	failed += _expect(MobAI.beyond_leash(Vector2i(21, 10), home, 10), "cheb 11 > 10 beyond")
	failed += _expect(not MobAI.beyond_leash(Vector2i(30, 10), home, -1), "leash <0 disabled")

	failed += _expect(
		MobAI.target_in_engage_range(Vector2i(0, 0), Vector2i(15, 0), 15),
		"engage at edge"
	)
	failed += _expect(
		not MobAI.target_in_engage_range(Vector2i(0, 0), Vector2i(16, 0), 15),
		"engage beyond"
	)

	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_mob_leash: FAIL no MockServer")
		quit(1)
		return
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var pack = TilemapPack.load_pack("res://demo_map")
	if pack == null or pack.collision == null:
		print("test_mob_leash: FAIL no demo pack")
		quit(1)
		return

	srv.map_collision = pack.collision
	srv.map_tile_size = pack.tile_size
	srv.map_collision.clear_extra_blocked()
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	srv.combat_stats.clear_npcs()
	srv.npc_spawn_templates.clear()
	srv._npc_respawn_at.clear()
	srv._pending_tick_actions.clear()
	srv.set_player_cell(30, 12)

	# --- 1) home_cell + leash_radius seeded on register_npc / spawn ---
	var spawn := {
		"id": "leash_mob",
		"name": "Leash Mob",
		"charset": "Monster",
		"index": 0,
		"cell": {"x": 15, "y": 12},
		"direction": 6,
		"hostile": true,
		"aggressive": true,
		"wander_radius": 0,
		"group_id": 0,
		"leash_radius": 10,
		"respawn_sec": 30.0,
	}
	srv.register_npc("leash_mob", 15, 12, true, true, 6, 0, 0, spawn)
	failed += _expect(srv.combat_stats.npc_ai.has("leash_mob"), "ai seeded")
	var ai0: Dictionary = srv.combat_stats.npc_ai["leash_mob"]
	failed += _expect(MobAI.get_home_cell(ai0) == Vector2i(15, 12), "home_cell = spawn")
	failed += _expect(int(ai0.get("leash_radius", -1)) == 10, "leash_radius from spawn_data")
	failed += _expect(str(ai0.get("ai_state", "")) == MobAI.AI_IDLE, "starts idle")

	# --- 2) Pull far beyond leash → return_home, hate cleared, HP full, npc_reset ---
	srv.map_collision.set_extra_blocked(15, 12, false)
	srv.map_collision.set_extra_blocked(26, 12, true)
	srv.combat_stats.set_npc_cell("leash_mob", 26, 12)  # Chebyshev 11 > 10
	srv.combat_stats.npcs["leash_mob"]["hp"] = 3
	var hp_max: int = int(srv.combat_stats.npcs["leash_mob"].get("hp_max", 0))
	failed += _expect(hp_max > 3, "hp_max > damaged hp")
	srv.combat_stats.add_hate("leash_mob", "player", 40.0, 1.0)
	var ai1: Dictionary = srv.combat_stats.npc_ai["leash_mob"]
	ai1["chase_target"] = "player"
	ai1["victim_id"] = "player"
	ai1["ai_state"] = MobAI.AI_CHASE
	ai1["seen_target"] = true
	ai1["lose_sight_sec"] = 0.0
	ai1["no_target_sec"] = 0.0
	srv.combat_stats.npc_ai["leash_mob"] = ai1
	failed += _expect(srv.combat_stats.get_hate_list("leash_mob").size() > 0, "hate before leash")

	var acts: Array = srv._tick_mob_ai(0.5)
	var after: Dictionary = srv.combat_stats.npc_ai["leash_mob"]
	failed += _expect(str(after.get("ai_state", "")) == MobAI.AI_RETURN_HOME, "leash → return_home")
	failed += _expect(str(after.get("chase_target", "x")) == "", "chase_target cleared")
	failed += _expect(srv.combat_stats.get_hate_list("leash_mob").size() == 0, "hate cleared")
	failed += _expect(str(after.get("victim_id", "x")) == "", "victim cleared")
	failed += _expect(int(srv.combat_stats.npcs["leash_mob"].get("hp", 0)) == hp_max, "HP restored on leash")
	var got_reset := false
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "npc_reset":
			if str(a.get("npc_id", "")) == "leash_mob":
				got_reset = true
				break
	failed += _expect(got_reset, "npc_reset emitted")

	# --- 3) While RETURNING: no re-aggro even if player in vision; no counter-attack ---
	srv.set_player_cell(26, 13)  # adjacent / in cone of facing toward home likely
	# Face player so vision would otherwise aggro.
	after = srv.combat_stats.npc_ai["leash_mob"]
	after["facing"] = MobAI.facing_toward(Vector2i(26, 12), Vector2i(26, 13))
	after["ai_state"] = MobAI.AI_RETURN_HOME
	after["chase_target"] = ""
	srv.combat_stats.npc_ai["leash_mob"] = after
	# Place player in vision cone explicitly.
	var face_down := 2
	srv.combat_stats.npc_ai["leash_mob"]["facing"] = face_down
	srv.set_player_cell(26, 14)
	failed += _expect(
		MobAI.player_in_vision(Vector2i(26, 12), face_down, Vector2i(26, 14), srv.map_collision),
		"setup: player in vision during return"
	)
	srv._tick_mob_ai(0.5)
	var mid: Dictionary = srv.combat_stats.npc_ai["leash_mob"]
	failed += _expect(str(mid.get("ai_state", "")) != MobAI.AI_CHASE, "no re-aggro while returning")
	failed += _expect(str(mid.get("chase_target", "")) == "", "no chase_target while returning")

	# Ambient combat tick must not damage player while returning (adjacent).
	if srv.combat_engine == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.combat_engine == null:
		var skills = SkillCatalog.new()
		skills.load_catalog()
		var items = ItemCatalog.new()
		items.load_catalog()
		var inv = Inventory.new()
		srv.combat_engine = CombatEngine.new()
		srv.combat_engine.setup(srv.combat_stats, skills, items, inv, null)
	srv.combat_stats.reset_player(1)
	srv.combat_stats.set_npc_cell("leash_mob", 26, 12)
	srv.set_player_cell(26, 13)
	srv.combat_stats.npc_ai["leash_mob"]["ai_state"] = MobAI.AI_RETURN_HOME
	var php0: int = int(srv.combat_stats.player.get("hp", 0))
	var tick_r: Dictionary = srv.combat_engine.tick(26, 13, 1.5)
	var php1: int = int(srv.combat_stats.player.get("hp", 0))
	var dmg_acts := 0
	for a in tick_r.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "damage" and str(a.get("target", "")) == "player":
			dmg_acts += 1
	failed += _expect(php1 == php0, "player HP unchanged while mob returning")
	failed += _expect(dmg_acts == 0, "no counter-attack actions while returning")

	# --- 4) Walk home via return steps → idle at home_cell ---
	srv.map_collision.set_extra_blocked(26, 12, true)
	# Clear a corridor west toward home (15,12): unblock intermediates if needed.
	for x in range(15, 27):
		# occupancy only on current NPC cell
		pass
	srv.combat_stats.npc_ai["leash_mob"]["ai_state"] = MobAI.AI_RETURN_HOME
	srv.combat_stats.set_npc_cell("leash_mob", 26, 12)
	srv.set_player_cell(40, 40)  # far away so idle won't re-aggro after arrive
	var arrived := false
	var last_cell: Vector2i = Vector2i(26, 12)
	for _i in range(40):
		var step_acts: Array = srv._tick_mob_ai(0.5)
		last_cell = srv.combat_stats.get_npc_cell("leash_mob")
		var st: String = str(srv.combat_stats.npc_ai["leash_mob"].get("ai_state", ""))
		if last_cell == Vector2i(15, 12) and st == MobAI.AI_IDLE:
			arrived = true
			break
		# If path blocked permanently, allow teleport-style snap for test robustness:
		# not implemented — fail if cannot arrive.
	failed += _expect(arrived, "return_home reaches home_cell → idle")
	failed += _expect(MobAI.get_home_cell(srv.combat_stats.npc_ai["leash_mob"]) == Vector2i(15, 12), "home_cell unchanged")
	failed += _expect(srv.combat_stats.get_hate_list("leash_mob").size() == 0, "hate still empty at home")

	# --- 5) No-valid-target timeout while chasing far from player ---
	srv.combat_stats.clear_npcs()
	srv.map_collision.clear_extra_blocked()
	srv.register_npc("far_chase", 15, 12, true, true, 6, 0, 0, {
		"id": "far_chase",
		"hostile": true,
		"aggressive": true,
		"leash_radius": 40,
		"wander_radius": 0,
		"cell": {"x": 15, "y": 12},
	})
	srv.map_collision.set_extra_blocked(15, 12, true)
	# engage_r = max(leash 40, 15) = 40; Chebyshev must be > 40
	srv.set_player_cell(56, 12)
	var fai: Dictionary = srv.combat_stats.npc_ai["far_chase"]
	fai["ai_state"] = MobAI.AI_CHASE
	fai["chase_target"] = "player"
	fai["seen_target"] = true
	fai["no_target_sec"] = 0.0
	fai["lose_sight_sec"] = 0.0
	srv.combat_stats.npc_ai["far_chase"] = fai
	# Accumulate just under threshold — still chasing
	srv._tick_mob_ai(4.0)
	failed += _expect(
		str(srv.combat_stats.npc_ai["far_chase"].get("ai_state", "")) == MobAI.AI_CHASE,
		"under no-target threshold still chase"
	)
	srv._tick_mob_ai(1.5)  # total >= 5.0
	failed += _expect(
		str(srv.combat_stats.npc_ai["far_chase"].get("ai_state", "")) == MobAI.AI_RETURN_HOME
		or str(srv.combat_stats.npc_ai["far_chase"].get("chase_target", "x")) == "",
		"no-valid-target → return_home"
	)

	print("test_mob_leash: ", "FAIL" if failed else "OK", " (", failed, " failed)")
	quit(1 if failed else 0)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
