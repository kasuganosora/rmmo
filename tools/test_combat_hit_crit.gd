extends SceneTree
## Headless: combat_engine hit miss / crit via forced combat_randf.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	var Net = load("res://scripts/net/net.gd")
	var srv = Net.server()
	var failed := 0
	if srv == null:
		print("FAIL no MockServer")
		quit(1)
		return
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _test_miss_path(srv)
	failed += _test_crit_path(srv)
	failed += _test_normal_hit(srv)
	failed += _test_npc_to_player_miss(srv)

	srv.combat_randf = Callable()

	if failed == 0:
		print("test_combat_hit_crit: PASS")
		quit(0)
	else:
		print("test_combat_hit_crit: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _reset_fight(srv, npc_id: String = "hitcrit_mob") -> void:
	srv.combat_randf = Callable()
	if srv.combat_engine != null:
		srv.combat_engine.combat_randf = Callable()
	srv.awaiting_respawn = false
	srv.combat_stats.reset_player(5)
	srv.combat_stats.player["atk"] = 20
	srv.combat_stats.player["def"] = 0
	srv.combat_stats.ensure_skill_book()
	if srv.combat_stats.skill_book.has_method("grant_starters"):
		srv.combat_stats.skill_book.grant_starters(srv.skill_catalog)
	# Clear leftover NPCs from prior cases.
	for k in srv.combat_stats.npcs.keys().duplicate():
		srv.combat_stats.remove_npc(str(k))
	srv.combat_stats.ensure_npc(npc_id, true)
	srv.combat_stats.set_npc_cell(npc_id, 5, 6)
	srv.combat_stats.npcs[npc_id]["hp"] = 200
	srv.combat_stats.npcs[npc_id]["hp_max"] = 200
	srv.combat_stats.npcs[npc_id]["def"] = 0
	srv.combat_stats.npcs[npc_id]["atk"] = 10
	srv.combat_stats.npcs[npc_id]["level"] = 5
	srv.combat_stats.npcs[npc_id]["hostile"] = true
	srv.set_player_cell(5, 5)
	# Ready attack CD
	srv.combat_stats.attack_ready_at = 0.0
	if srv.combat_stats.skill_ready_at.has("basic_attack"):
		srv.combat_stats.skill_ready_at.erase("basic_attack")


func _find_actions(actions: Array, typ: String) -> Array:
	var out: Array = []
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == typ:
			out.append(a)
	return out


func _test_miss_path(srv) -> int:
	var failed := 0
	_reset_fight(srv)
	# First roll >= hit chance (0.90 same-level) → miss; no second roll.
	srv.combat_randf = func() -> float: return 0.95
	var hp0: int = int(srv.combat_stats.npcs["hitcrit_mob"].get("hp", 0))
	var r: Dictionary = srv.try_attack("hitcrit_mob", 5, 5)
	failed += _expect(bool(r.get("ok", false)), "miss: try_attack ok")
	var actions: Array = r.get("actions", [])
	var misses: Array = _find_actions(actions, "miss")
	var dmgs: Array = _find_actions(actions, "damage")
	# Filter damage to npc (counter may damage player)
	var npc_dmgs: Array = []
	for d in dmgs:
		if str(d.get("target", "")) == "npc":
			npc_dmgs.append(d)
	failed += _expect(misses.size() >= 1, "miss: emits miss action")
	if misses.size() >= 1:
		failed += _expect(str(misses[0].get("target", "")) == "npc", "miss: target npc")
		failed += _expect(str(misses[0].get("id", "")) == "hitcrit_mob", "miss: id")
	failed += _expect(npc_dmgs.is_empty(), "miss: no npc damage action")
	var hp1: int = 0
	if srv.combat_stats.npcs.has("hitcrit_mob"):
		hp1 = int(srv.combat_stats.npcs["hitcrit_mob"].get("hp", 0))
	failed += _expect(hp1 == hp0, "miss: npc HP unchanged (%d→%d)" % [hp0, hp1])
	var has_log := false
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			if "未命中" in str(a.get("text", "")):
				has_log = true
	failed += _expect(has_log, "miss: Chinese combat log")
	return failed


func _test_crit_path(srv) -> int:
	var failed := 0
	_reset_fight(srv)
	# roll 0.0 → hit ( < 0.90 ) then crit ( < 0.08 )
	srv.combat_randf = func() -> float: return 0.0
	var atk: int = int(srv.combat_engine._effective_atk_player())
	var expect_raw: int = maxi(1, int(round(float(atk) * 1.5)))
	var expect_dealt: int = maxi(1, expect_raw - 0)  # npc def 0
	var hp0: int = int(srv.combat_stats.npcs["hitcrit_mob"].get("hp", 0))
	var r: Dictionary = srv.try_attack("hitcrit_mob", 5, 5)
	failed += _expect(bool(r.get("ok", false)), "crit: try_attack ok")
	var actions: Array = r.get("actions", [])
	var npc_dmgs: Array = []
	for d in _find_actions(actions, "damage"):
		if str(d.get("target", "")) == "npc":
			npc_dmgs.append(d)
	failed += _expect(npc_dmgs.size() == 1, "crit: one npc damage")
	if npc_dmgs.size() == 1:
		failed += _expect(bool(npc_dmgs[0].get("crit", false)), "crit: crit:true on damage")
		failed += _expect(int(npc_dmgs[0].get("amount", 0)) == expect_dealt, "crit: amount ~1.5x (got %d want %d)" % [int(npc_dmgs[0].get("amount", 0)), expect_dealt])
	var hp1: int = int(srv.combat_stats.npcs["hitcrit_mob"].get("hp", 0)) if srv.combat_stats.npcs.has("hitcrit_mob") else 0
	failed += _expect(hp0 - hp1 == expect_dealt, "crit: HP reduced by crit dmg")
	failed += _expect(_find_actions(actions, "miss").is_empty(), "crit: no miss")
	return failed


func _test_normal_hit(srv) -> int:
	var failed := 0
	_reset_fight(srv)
	# 0.5 → hit, no crit (crit needs < 0.08)
	srv.combat_randf = func() -> float: return 0.5
	var atk: int = int(srv.combat_engine._effective_atk_player())
	var expect_dealt: int = maxi(1, atk - 0)
	var hp0: int = int(srv.combat_stats.npcs["hitcrit_mob"].get("hp", 0))
	var r: Dictionary = srv.try_attack("hitcrit_mob", 5, 5)
	failed += _expect(bool(r.get("ok", false)), "hit: try_attack ok")
	var actions: Array = r.get("actions", [])
	var npc_dmgs: Array = []
	for d in _find_actions(actions, "damage"):
		if str(d.get("target", "")) == "npc":
			npc_dmgs.append(d)
	failed += _expect(npc_dmgs.size() == 1, "hit: one npc damage")
	if npc_dmgs.size() == 1:
		failed += _expect(not bool(npc_dmgs[0].get("crit", false)), "hit: not crit")
		failed += _expect(int(npc_dmgs[0].get("amount", 0)) == expect_dealt, "hit: normal amount")
	var hp1: int = int(srv.combat_stats.npcs["hitcrit_mob"].get("hp", 0)) if srv.combat_stats.npcs.has("hitcrit_mob") else 0
	failed += _expect(hp0 - hp1 == expect_dealt, "hit: HP reduced")
	failed += _expect(_find_actions(actions, "miss").is_empty(), "hit: no miss")
	return failed


func _test_npc_to_player_miss(srv) -> int:
	var failed := 0
	_reset_fight(srv)
	srv.combat_randf = func() -> float: return 0.95
	var hp0: int = int(srv.combat_stats.player.get("hp", 0))
	var actions: Array = []
	srv.combat_engine._damage_player(15, actions, "hitcrit_mob")
	failed += _expect(_find_actions(actions, "miss").size() == 1, "npc→player miss action")
	failed += _expect(int(srv.combat_stats.player.get("hp", 0)) == hp0, "npc→player HP unchanged")
	failed += _expect(_find_actions(actions, "damage").is_empty(), "npc→player no damage")
	return failed
