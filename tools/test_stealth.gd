extends SceneTree
## Headless: stealth skill — invisible to aggro vision; attack cancels.

const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")
const MobAI = preload("res://scripts/net/combat/mob_ai.gd")


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
	engine.combat_randf = func() -> float: return 0.5

	stats.ensure_skill_book()
	if stats.skill_book.list_known().is_empty():
		stats.skill_book.grant_starters(skills)
	stats.skill_book.grant_skill_points(99)

	# --- Catalog ---
	failed += _expect(skills.has_skill("stealth"), "catalog has stealth")
	var def: Dictionary = skills.get_skill("stealth")
	failed += _expect(str(def.get("name", "")) == "潜行", "name 潜行")
	failed += _expect(str(def.get("effect", "")) == "apply_status", "effect apply_status")
	failed += _expect(int(def.get("mp_cost", 0)) > 0, "mp_cost > 0")
	failed += _expect(float(def.get("cooldown", 0.0)) > 0.0, "cooldown > 0")
	failed += _expect(not bool(def.get("requires_target", true)), "self buff no target")
	failed += _expect(not bool(def.get("starter", true)), "learnable not starter")
	failed += _expect(int(def.get("sp_cost", 0)) >= 1, "sp_cost learnable")
	var st_def: Dictionary = def.get("status", {}) if typeof(def.get("status", {})) == TYPE_DICTIONARY else {}
	failed += _expect(str(st_def.get("id", "")) == "stealth", "status id stealth")
	failed += _expect(str(st_def.get("kind", "")) == "buff", "status kind buff")
	failed += _expect(abs(float(st_def.get("duration", 0.0)) - 8.0) < 0.01, "duration 8s")

	# --- Learn via SP ---
	failed += _expect(not stats.skill_book.is_known("stealth"), "not known before learn")
	var learn: Dictionary = stats.skill_book.try_learn("stealth", skills, 99)
	failed += _expect(bool(learn.get("ok", false)), "learn ok")
	failed += _expect(stats.skill_book.is_known("stealth"), "known after learn")

	# --- Cast applies status ---
	stats.player["mp"] = 80
	stats.player["mp_max"] = 80
	stats.skill_ready_at.clear()
	var cast: Dictionary = engine.try_use_skill("stealth", "", 0, 0)
	failed += _expect(bool(cast.get("ok", false)), "cast stealth ok")
	failed += _expect(stats.statuses.has_status("player", "stealth"), "status applied")
	failed += _expect(engine.player_has_stealth(), "engine player_has_stealth")
	failed += _expect(_has_type(cast.get("actions", []), "status_update"), "status_update action")

	# --- Attack cancels stealth ---
	stats.ensure_npc("dummy", true, true)
	stats.ensure_npc_ai("dummy", 2, true, Vector2i(1, 0), 0)
	stats.set_npc_cell("dummy", 1, 0)
	stats.attack_ready_at = 0.0
	var atk: Dictionary = engine.try_attack("dummy", 0, 0)
	failed += _expect(bool(atk.get("ok", false)), "attack ok")
	failed += _expect(not stats.statuses.has_status("player", "stealth"), "attack cleared stealth")
	failed += _expect(not engine.player_has_stealth(), "not stealthed after attack")

	# --- Taking damage cancels stealth ---
	stats.statuses.apply_status("player", {
		"id": "stealth", "name": "潜行", "kind": "buff", "duration": 8.0,
	}, 8.0, "player")
	failed += _expect(engine.player_has_stealth(), "reapplied stealth")
	var dmg_acts: Array = []
	engine._damage_player(10, dmg_acts, "dummy", false)
	failed += _expect(not engine.player_has_stealth(), "damage cleared stealth")

	# --- Apply stealth breaks existing chase ---
	stats.ensure_npc("chaser", true, true)
	stats.ensure_npc_ai("chaser", 2, true, Vector2i(5, 5), 0)
	stats.set_npc_cell("chaser", 6, 5)
	stats.begin_chase("chaser")
	failed += _expect(str(stats.npc_ai["chaser"].get("ai_state", "")) == MobAI.AI_CHASE, "chaser chasing")
	stats.player["mp"] = 80
	stats.skill_ready_at.clear()
	# Force known + cast again
	var cast2: Dictionary = engine.try_use_skill("stealth", "", 0, 0)
	failed += _expect(bool(cast2.get("ok", false)), "cast stealth while chased")
	failed += _expect(engine.player_has_stealth(), "stealthed again")
	var ch_state: String = str(stats.npc_ai["chaser"].get("ai_state", ""))
	failed += _expect(
		ch_state == MobAI.AI_RETURN_HOME or ch_state == MobAI.AI_IDLE,
		"chase broken on stealth apply"
	)
	failed += _expect(str(stats.npc_ai["chaser"].get("chase_target", "")) == "", "chase_target cleared")

	# --- MockServer AI tick: stealthed adjacent aggressive does not start chase ---
	failed += _run_ai_no_aggro_while_stealthed()

	if failed == 0:
		print("test_stealth: PASS")
		quit(0)
	else:
		print("test_stealth: FAIL count=%d" % failed)
		quit(1)


func _run_ai_no_aggro_while_stealthed() -> int:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("  SKIP ai tick (no MockServer)")
		return 0
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var pack = TilemapPack.load_pack("res://demo_map")
	if pack == null or pack.collision == null:
		print("  SKIP ai tick (no demo pack)")
		return 0
	srv.map_collision = pack.collision
	srv.map_tile_size = pack.tile_size
	srv.map_pack_id = "demo_map"
	srv.map_collision.clear_extra_blocked()
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.combat_engine == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	srv.combat_stats.clear_npcs()
	srv.combat_stats.reset_player(3)
	srv.combat_stats.statuses.clear_everything()
	# Open LoS pair outside safe zone: mob (17,24) facing down → player (17,25).
	var mob_cell := Vector2i(17, 24)
	var ply_cell := Vector2i(17, 25)
	srv.set_player_cell(ply_cell.x, ply_cell.y)
	failed += _expect(not srv.player_in_safe_zone(), "player outside safe zone")
	srv.register_npc("stealth_agg", mob_cell.x, mob_cell.y, true, true, 2, 0)
	srv.map_collision.set_extra_blocked(mob_cell.x, mob_cell.y, true)
	srv.combat_stats.set_npc_cell("stealth_agg", mob_cell.x, mob_cell.y)
	var ai0: Dictionary = srv.combat_stats.npc_ai["stealth_agg"]
	ai0["facing"] = 2
	ai0["ai_state"] = MobAI.AI_IDLE
	ai0["chase_target"] = ""
	srv.combat_stats.npc_ai["stealth_agg"] = ai0

	# Confirm vision works without stealth.
	var cell: Vector2i = srv.combat_stats.get_npc_cell("stealth_agg")
	var facing: int = int(srv.combat_stats.npc_ai["stealth_agg"].get("facing", 2))
	failed += _expect(
		MobAI.player_in_vision(cell, facing, srv.player_cell, srv.map_collision),
		"baseline in vision"
	)
	failed += _expect(MobAI.wants_chase(srv.combat_stats.npc_ai["stealth_agg"]), "baseline wants_chase")

	# Without stealth → starts chase.
	var _acts0: Array = srv._tick_mob_ai(0.2)
	var state0: String = str(srv.combat_stats.npc_ai["stealth_agg"].get("ai_state", ""))
	failed += _expect(state0 == MobAI.AI_CHASE, "no-stealth starts chase")
	# Reset to idle at home.
	srv.combat_stats.clear_chase("stealth_agg")
	srv.combat_stats.set_npc_cell("stealth_agg", mob_cell.x, mob_cell.y)
	var ai_r: Dictionary = srv.combat_stats.npc_ai["stealth_agg"]
	ai_r["ai_state"] = MobAI.AI_IDLE
	ai_r["chase_target"] = ""
	ai_r["facing"] = 2
	ai_r["home_cell"] = mob_cell
	srv.combat_stats.npc_ai["stealth_agg"] = ai_r

	# Apply stealth — adjacent aggressive must NOT start chase.
	srv.combat_stats.statuses.apply_status("player", {
		"id": "stealth", "name": "潜行", "kind": "buff", "duration": 8.0,
	}, 8.0, "player")
	failed += _expect(srv.combat_stats.statuses.has_status("player", "stealth"), "stealthed for ai tick")
	var _acts1: Array = srv._tick_mob_ai(0.2)
	var state1: String = str(srv.combat_stats.npc_ai["stealth_agg"].get("ai_state", ""))
	var chase1: String = str(srv.combat_stats.npc_ai["stealth_agg"].get("chase_target", ""))
	failed += _expect(state1 != MobAI.AI_CHASE, "stealthed: no chase state")
	failed += _expect(chase1 == "", "stealthed: no chase_target")
	failed += _expect(
		state1 == MobAI.AI_IDLE or state1 == MobAI.AI_RETURN_HOME,
		"stealthed: idle/return"
	)

	# AI tick also breaks an existing chase while stealthed.
	srv.combat_stats.begin_chase("stealth_agg")
	failed += _expect(str(srv.combat_stats.npc_ai["stealth_agg"].get("ai_state", "")) == MobAI.AI_CHASE, "force chase")
	var _acts2: Array = srv._tick_mob_ai(0.2)
	var state2: String = str(srv.combat_stats.npc_ai["stealth_agg"].get("ai_state", ""))
	failed += _expect(state2 != MobAI.AI_CHASE, "ai tick breaks chase under stealth")
	failed += _expect(str(srv.combat_stats.npc_ai["stealth_agg"].get("chase_target", "")) == "", "ai tick cleared target")

	return failed


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _has_type(actions: Array, typ: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false
