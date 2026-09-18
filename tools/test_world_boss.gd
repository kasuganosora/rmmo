extends SceneTree
## Headless: world boss register (high HP), kill announce+loot/exp, respawn schedule, radar POI.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	var failed := 0
	var Net = load("res://scripts/net/net.gd")
	var srv = Net.server()
	if srv == null:
		print("test_world_boss: FAIL no MockServer")
		quit(1)
		return
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	srv.combat_stats.clear_npcs()
	srv.npc_spawn_templates.clear()
	srv._npc_respawn_at.clear()
	if srv.inventory != null:
		srv.inventory.clear()
		srv.inventory.grant_starter()
	if srv.loot_catalog != null:
		srv.loot_catalog.load_catalog()
		srv.loot_catalog.rng_roll = func() -> float: return 0.0

	var RadarPoi = load("res://scripts/ui/radar_poi.gd")
	failed += _expect(RadarPoi != null and RadarPoi.KIND_BOSS == "boss", "radar KIND_BOSS")

	var spawn := {
		"id": "world_boss_king",
		"name": "森林霸主",
		"charset": "retira_slime",
		"index": 4,
		"cell": {"x": 24, "y": 17},
		"direction": 2,
		"hostile": true,
		"aggressive": true,
		"wander_radius": 2,
		"leash_radius": 20,
		"respawn_sec": 120,
		"hp_max": 800,
		"level": 20,
		"atk": 28,
		"def": 14,
		"world_boss": true,
		"boss_bonus_gold": 100,
		"boss_bonus_exp": 200,
	}
	srv.set_player_cell(24, 16)
	srv.register_npc("world_boss_king", 24, 17, true, true, 2, 2, 0, spawn)

	failed += _expect(srv.combat_stats.npcs.has("world_boss_king"), "boss registered")
	var st: Dictionary = srv.combat_stats.npcs["world_boss_king"]
	failed += _expect(int(st.get("hp_max", 0)) >= 800, "boss high hp_max (>=800)")
	failed += _expect(int(st.get("hp", 0)) == int(st.get("hp_max", 0)), "boss full hp")
	failed += _expect(int(st.get("level", 0)) == 20, "boss level 20")
	failed += _expect(int(st.get("atk", 0)) == 28, "boss atk override")
	failed += _expect(int(st.get("def", 0)) == 14, "boss def override")
	failed += _expect(srv._is_world_boss_npc("world_boss_king"), "is world boss")
	var ai: Dictionary = srv.combat_stats.npc_ai.get("world_boss_king", {})
	failed += _expect(int(ai.get("leash_radius", 0)) == 20, "boss large leash")
	failed += _expect(is_equal_approx(float(ai.get("respawn_sec", 0.0)), 120.0), "boss respawn_sec 120")

	# Radar POI when alive
	var markers_alive: Array = RadarPoi.build_markers({
		"npcs": [{
			"id": "world_boss_king",
			"name": "森林霸主",
			"cell": {"x": 24, "y": 17},
			"world_boss": true,
		}],
	})
	var counts_alive: Dictionary = RadarPoi.count_by_kind(markers_alive)
	failed += _expect(int(counts_alive.get(RadarPoi.KIND_BOSS, 0)) == 1, "POI boss kind when alive")

	var gold_before: int = int(srv.inventory.get_gold()) if srv.inventory != null else 0
	var exp_before: int = int(srv.combat_stats.player.get("exp", 0))

	# Kill via finalize path (same as combat engine kill_npc)
	var kill_result: Dictionary = srv._finalize_combat_result({
		"ok": true,
		"actions": [
			{"type": "kill_npc", "npc_id": "world_boss_king", "cell": {"x": 24, "y": 17}},
			{"type": "system_message", "text": "击败了敌人。"},
		],
	})
	var acts: Array = kill_result.get("actions", [])
	var got_announce := false
	var got_loot := false
	var got_exp := false
	var got_gold_msg := false
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t == "system_message" and str(a.get("text", "")).find("击败了森林霸主") >= 0:
			got_announce = true
		if t == "loot_drop" and str(a.get("npc_id", "")) == "world_boss_king":
			got_loot = true
		if t == "exp_gain" and int(a.get("amount", 0)) > 0:
			got_exp = true
		if t == "system_message" and str(a.get("text", "")).begins_with("获得金币"):
			got_gold_msg = true

	failed += _expect(got_announce, "kill grants 击败了森林霸主 announce")
	failed += _expect(got_loot, "kill grants loot_drop")
	failed += _expect(got_exp, "kill grants exp_gain")
	failed += _expect(got_gold_msg, "kill grants bonus gold message")
	failed += _expect(srv._npc_respawn_at.has("world_boss_king"), "respawn timer scheduled")
	var ready_at: float = float(srv._npc_respawn_at.get("world_boss_king", 0.0))
	var now: float = float(srv.combat_stats.now_sec())
	failed += _expect(ready_at >= now + 119.0, "respawn ~120s from now")

	if srv.inventory != null:
		failed += _expect(int(srv.inventory.get_gold()) >= gold_before + 100, "bonus gold applied")
	failed += _expect(int(srv.combat_stats.player.get("exp", 0)) > exp_before, "exp increased")

	# Dead: no combat blob → POI sample marks depleted/hidden
	var markers_dead: Array = RadarPoi.build_markers({
		"npcs": [{
			"id": "world_boss_king",
			"cell": {"x": 24, "y": 17},
			"world_boss": true,
			"depleted": true,
		}],
	})
	failed += _expect(markers_dead.is_empty(), "POI hidden when dead/depleted")

	if srv.loot_catalog != null:
		srv.loot_catalog.rng_roll = Callable()

	if failed == 0:
		print("test_world_boss: PASS")
		quit(0)
	else:
		print("test_world_boss: FAIL %d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
