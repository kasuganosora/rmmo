extends SceneTree
## Headless: authority boundary — friendly server wander, try_move facing, no client Timer API.

const MobAI = preload("res://scripts/net/combat/mob_ai.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_authority: FAIL no MockServer")
		quit(1)
		return

	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var pack = TilemapPack.load_pack("res://demo_map")
	if pack == null or pack.collision == null:
		print("test_authority: FAIL no demo pack")
		quit(1)
		return

	srv.map_collision = pack.collision
	srv.map_tile_size = pack.tile_size
	srv.map_collision.clear_extra_blocked()
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	srv.combat_stats.clear_npcs()
	srv._pending_tick_actions.clear()
	srv.set_player_cell(20, 20)

	# Friendly wander:true without wander_radius → default radius + AI blob.
	srv.register_npc(
		"actor_rest", 15, 10, false, false, 2, 0, 0,
		{"id": "actor_rest", "wander": true, "cell": {"x": 15, "y": 10}}
	)
	failed += _expect(srv.combat_stats.npcs.has("actor_rest"), "friendly in npcs")
	failed += _expect(not bool(srv.combat_stats.npcs["actor_rest"].get("hostile", true)), "friendly not hostile")
	failed += _expect(srv.combat_stats.npc_ai.has("actor_rest"), "friendly has AI")
	var wr: int = int(srv.combat_stats.npc_ai["actor_rest"].get("wander_radius", 0))
	failed += _expect(wr == srv.DEFAULT_FRIENDLY_WANDER_RADIUS, "default wander radius")
	failed += _expect(str(srv.combat_stats.npc_ai["actor_rest"].get("ai_state", "")) == MobAI.AI_IDLE, "friendly idle")

	# Force idle wander tick to emit npc_move (bypass interval).
	srv.map_collision.set_extra_blocked(15, 10, true)
	srv.combat_stats.npc_ai["actor_rest"]["idle_wander_acc"] = MobAI.IDLE_WANDER_INTERVAL_SEC
	var acts: Array = srv._tick_mob_ai(0.5)
	var moved := false
	var facing_ok := false
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "npc_move":
			continue
		if str(a.get("npc_id", "")) != "actor_rest":
			continue
		moved = true
		facing_ok = int(a.get("facing", 0)) in [2, 4, 6, 8]
		break
	failed += _expect(moved, "friendly idle emits npc_move")
	failed += _expect(facing_ok, "npc_move has facing")

	# Friendlies must not chase (no vision aggro).
	srv.set_player_cell(15, 11)
	srv.combat_stats.npc_ai["actor_rest"]["facing"] = 2
	srv.combat_stats.npc_ai["actor_rest"]["ai_state"] = MobAI.AI_IDLE
	srv.combat_stats.npc_ai["actor_rest"]["idle_wander_acc"] = 0.0
	var cell_before: Vector2i = srv.combat_stats.get_npc_cell("actor_rest")
	# Many ticks with player adjacent in cone — still idle-only (may wander but never chase).
	for _i in range(5):
		srv._tick_mob_ai(0.5)
	failed += _expect(
		str(srv.combat_stats.npc_ai["actor_rest"].get("ai_state", "")) != MobAI.AI_CHASE,
		"friendly never chase"
	)
	failed += _expect(str(srv.combat_stats.npc_ai["actor_rest"].get("chase_target", "")) == "", "no chase_target")

	# try_move returns facing.
	srv.set_player_cell(12, 12)
	var mv: Dictionary = srv.try_move(12, 12, 6)
	failed += _expect(bool(mv.get("ok", false)), "try_move ok")
	failed += _expect(int(mv.get("facing", 0)) == 6, "try_move facing")

	# Desync reject + resync coords.
	var bad: Dictionary = srv.try_move(0, 0, 2)
	failed += _expect(not bool(bad.get("ok", true)), "desync reject")
	failed += _expect(bool(bad.get("resync", false)), "resync flag")

	# NpcActor must not expose client wander timer API.
	var NpcActor = load("res://scripts/game/npc_actor.gd")
	var actor = NpcActor.new()
	failed += _expect(not actor.has_method("_start_wander_timer"), "no client wander timer")
	failed += _expect(not actor.has_method("_try_wander_step_sync"), "no client try_npc_move path")
	failed += _expect(actor.has_method("apply_server_move"), "has apply_server_move")
	actor.free()

	if failed == 0:
		print("test_authority: PASS")
		quit(0)
	else:
		print("test_authority: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
