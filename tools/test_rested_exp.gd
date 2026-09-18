extends SceneTree
## Headless: rested EXP — sit in safe zone accumulates; outside no gain; cap; kill spend 2×.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_rested_exp: FAIL no MockServer")
		quit(1)
		return

	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.combat_stats != null, "combat_stats ready")
	failed += _expect(srv.has_method("_tick_rested_accumulate"), "has _tick_rested_accumulate")
	failed += _expect(srv.combat_stats.has_method("rested_exp_max"), "has rested_exp_max")
	failed += _expect(srv.combat_stats.has_method("spend_rested_for_kill"), "has spend_rested_for_kill")

	srv.combat_stats.reset_player(3)
	var need: int = int(srv.combat_stats.player.get("exp_to_next", 0))
	var expect_cap: int = mini(500, maxi(need, 1))
	failed += _expect(int(srv.combat_stats.rested_exp_max()) == expect_cap, "cap = min(500, exp_to_next) (%d)" % expect_cap)
	failed += _expect(int(srv.combat_stats.get_rested_exp()) == 0, "start rested 0")

	var snap: Dictionary = srv.combat_stats.snapshot_player_stats()
	failed += _expect(snap.has("rested_exp"), "snapshot has rested_exp")
	failed += _expect(snap.has("rested_exp_max"), "snapshot has rested_exp_max")
	failed += _expect(int(snap.get("rested_exp_max", -1)) == expect_cap, "snapshot max matches")

	# Ensure demo_map + known cells
	srv.map_pack_id = "demo_map"
	srv._rested_cap_notified = false

	# --- Sit outside safe zone → no gain ---
	srv.set_player_cell(17, 12)  # slime cell outside
	failed += _expect(not srv.player_in_safe_zone(), "outside safe zone")
	srv.sitting = true
	srv._sit_acc = 0.0
	srv._pending_tick_actions.clear()
	srv._tick_sit(1.0)
	failed += _expect(int(srv.combat_stats.get_rested_exp()) == 0, "outside sit → no rested gain")
	failed += _expect(not _has_type(srv._pending_tick_actions, "rested_update"), "outside no rested_update")

	# --- Sit inside safe zone for a few ticks → pool increases ---
	srv.set_player_cell(12, 12)  # inn inside
	failed += _expect(srv.player_in_safe_zone(), "inside safe zone")
	srv.sitting = true
	srv._sit_acc = 0.0
	srv.combat_stats.player["rested_exp"] = 0
	srv._rested_cap_notified = false
	# Drain HP so regen path also runs (optional); keep rested path independent
	srv.combat_stats.player["hp"] = int(srv.combat_stats.player.get("hp_max", 100))
	srv.combat_stats.player["mp"] = int(srv.combat_stats.player.get("mp_max", 50))
	srv._pending_tick_actions.clear()
	srv._tick_sit(1.0)
	failed += _expect(int(srv.combat_stats.get_rested_exp()) == 5, "tick1 → +5 rested")
	failed += _expect(_has_type(srv._pending_tick_actions, "rested_update"), "tick1 emits rested_update")
	failed += _expect(_has_msg(srv._pending_tick_actions, "开始积攒休息经验。"), "empty→nonzero system msg")
	srv._pending_tick_actions.clear()
	srv._tick_sit(1.0)
	failed += _expect(int(srv.combat_stats.get_rested_exp()) == 10, "tick2 → 10")
	failed += _expect(not _has_msg(srv._pending_tick_actions, "开始积攒休息经验。"), "no repeat empty msg")

	# Partial tick does not grant
	var mid: int = int(srv.combat_stats.get_rested_exp())
	srv._tick_sit(0.4)
	failed += _expect(int(srv.combat_stats.get_rested_exp()) == mid, "partial tick no gain")

	# --- Cap respected ---
	srv.combat_stats.player["rested_exp"] = expect_cap - 3
	srv._rested_cap_notified = false
	srv._sit_acc = 0.0
	srv._pending_tick_actions.clear()
	srv._tick_sit(1.0)
	failed += _expect(int(srv.combat_stats.get_rested_exp()) == expect_cap, "clamp to cap (%d)" % expect_cap)
	failed += _expect(_has_msg(srv._pending_tick_actions, "休息经验已满。"), "cap system msg once")
	srv._pending_tick_actions.clear()
	srv._tick_sit(1.0)
	failed += _expect(int(srv.combat_stats.get_rested_exp()) == expect_cap, "at cap stays")
	failed += _expect(not _has_msg(srv._pending_tick_actions, "休息经验已满。"), "no repeat cap msg")
	failed += _expect(not _has_type(srv._pending_tick_actions, "rested_update"), "no update while already capped")

	# Unit: spend_rested_for_kill
	srv.combat_stats.player["rested_exp"] = 40
	var bonus_u: int = int(srv.combat_stats.spend_rested_for_kill(25))
	failed += _expect(bonus_u == 25, "spend min(pool, base)=25")
	failed += _expect(int(srv.combat_stats.get_rested_exp()) == 15, "pool left 15")
	failed += _expect(int(srv.combat_stats.spend_rested_for_kill(100)) == 15, "spend remaining 15")
	failed += _expect(int(srv.combat_stats.get_rested_exp()) == 0, "pool empty")
	failed += _expect(int(srv.combat_stats.spend_rested_for_kill(10)) == 0, "empty → 0 bonus")

	# --- Kill EXP consumes pool and increases granted amount ---
	if srv.has_method("_party_clear"):
		srv._party_clear()
	var npc_id := "rested_exp_slime"
	srv.combat_stats.ensure_npc(npc_id, true)
	srv.combat_stats.npcs[npc_id]["level"] = 5
	var base_formula: int = srv.combat_stats.kill_exp_for_npc_level(5)
	srv.combat_stats.reset_player(3)
	srv.combat_stats.player["rested_exp"] = base_formula  # exactly one full bonus
	var acts: Array = srv.grant_kill_exp(npc_id)
	var amt: int = _exp_amount(acts)
	failed += _expect(amt == base_formula * 2, "kill with full rest → 2× (%d)" % amt)
	failed += _expect(_rested_bonus(acts) == base_formula, "rested_bonus field")
	failed += _expect(_has_msg_contains(acts, "休息加成 +"), "休息加成 chat")
	failed += _expect(int(srv.combat_stats.get_rested_exp()) == 0, "pool spent to 0")
	failed += _expect(_has_type(acts, "rested_update"), "spend emits rested_update")

	# Partial pool
	srv.combat_stats.reset_player(3)
	srv.combat_stats.player["rested_exp"] = 7
	var acts2: Array = srv.grant_kill_exp(npc_id)
	failed += _expect(_exp_amount(acts2) == base_formula + 7, "partial rest → base+7")
	failed += _expect(_rested_bonus(acts2) == 7, "bonus 7")
	failed += _expect(int(srv.combat_stats.get_rested_exp()) == 0, "pool drained")

	# No rest → same as base
	srv.combat_stats.reset_player(3)
	srv.combat_stats.player["rested_exp"] = 0
	var acts3: Array = srv.grant_kill_exp(npc_id)
	failed += _expect(_exp_amount(acts3) == base_formula, "no rest → base")
	failed += _expect(not _has_msg_contains(acts3, "休息加成"), "no bonus chat")

	if failed == 0:
		print("test_rested_exp: PASS")
		quit(0)
	else:
		print("test_rested_exp: FAIL count=%d" % failed)
		quit(1)


func _exp_amount(actions: Array) -> int:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "exp_gain":
			return int(a.get("amount", 0))
	return -1


func _rested_bonus(actions: Array) -> int:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "exp_gain":
			return int(a.get("rested_bonus", 0))
	return -1


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _has_msg(actions: Array, text: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			if str(a.get("text", "")) == text:
				return true
	return false


func _has_msg_contains(actions: Array, frag: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			if frag in str(a.get("text", "")):
				return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
