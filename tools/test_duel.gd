extends SceneTree
## Headless: MockServer player duel shell (challenge / forfeit / timeout / hit).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_duel: FAIL no MockServer")
		quit(1)
		return

	if srv.has_method("_duel_force_clear_silent"):
		srv._duel_force_clear_silent()
	if srv.has_method("try_remote_despawn"):
		srv.try_remote_despawn("")
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.combat_stats != null:
		srv.combat_stats.reset_player(3)
	srv.set_player_cell(10, 10)

	failed += _expect(srv.has_method("try_duel_challenge"), "has challenge")
	failed += _expect(srv.has_method("try_duel_accept"), "has accept")
	failed += _expect(srv.has_method("try_duel_decline"), "has decline")
	failed += _expect(srv.has_method("try_duel_forfeit"), "has forfeit")
	failed += _expect(srv.has_method("snapshot_duel"), "has snapshot")
	failed += _expect(not srv.in_duel(), "not in duel")

	# Unknown target fails
	var miss: Dictionary = srv.try_duel_challenge("不存在的旅人XYZ")
	failed += _expect(not bool(miss.get("ok", true)), "unknown fails")
	failed += _expect(str(miss.get("reason", "")) == "not_found", "reason not_found")
	failed += _expect(_has(miss, "system_message"), "unknown system_message")
	failed += _expect(not srv.in_duel(), "still idle after miss")

	# Spawn remote and challenge → active (shell remotes auto-accept / instant start)
	var sp: Dictionary = srv.try_remote_debug_spawn("旅人甲")
	failed += _expect(bool(sp.get("ok", false)), "spawn 旅人甲")
	var remotes: Array = srv.snapshot_remote_players()
	failed += _expect(remotes.size() >= 1, "has remote")
	var rid := ""
	for r in remotes:
		if typeof(r) == TYPE_DICTIONARY and str(r.get("name", "")) == "旅人甲":
			rid = str(r.get("id", ""))
			break
	failed += _expect(rid != "", "remote id")

	# Place player adjacent for attack path
	var rd: Dictionary = srv.get_remote_player(rid)
	var cell: Dictionary = rd.get("cell", {})
	var rx: int = int(cell.get("x", 10))
	var ry: int = int(cell.get("y", 10))
	srv.set_player_cell(rx - 1, ry)

	var ch: Dictionary = srv.try_duel_challenge("旅人甲")
	failed += _expect(bool(ch.get("ok", false)), "challenge ok")
	failed += _expect(bool(ch.get("auto_accepted", false)), "auto_accepted flag")
	failed += _expect(srv.in_duel(), "challenge→active")
	failed += _expect(_has(ch, "duel_update"), "challenge duel_update")
	failed += _expect(_has(ch, "system_message"), "challenge system_message")
	var snap: Dictionary = srv.snapshot_duel()
	failed += _expect(bool(snap.get("active", false)), "snap active")
	failed += _expect(str(snap.get("opponent_id", "")) == rid, "opponent id")
	failed += _expect(str(snap.get("opponent_name", "")) == "旅人甲", "opponent name")
	failed += _expect(float(snap.get("ends_at", 0.0)) > float(snap.get("started_at", 0.0)), "ends after start")
	failed += _expect(int(snap.get("opponent_hp", 0)) > 0, "stub hp > 0")
	failed += _expect(int(snap.get("opponent_hp_max", 0)) >= int(snap.get("opponent_hp", 0)), "hp_max >= hp")

	# Challenge by id also blocked while active
	var again: Dictionary = srv.try_duel_challenge(rid)
	failed += _expect(not bool(again.get("ok", true)), "second challenge rejected")

	# Real attack path against remote opponent
	srv.combat_randf = func() -> float: return 0.5  # force hit, no crit
	var atk: Dictionary = srv.try_attack(rid, rx - 1, ry)
	failed += _expect(bool(atk.get("ok", false)), "try_attack remote ok")
	failed += _expect(_has(atk, "damage") or _has(atk, "duel_update"), "attack damage/update")
	var snap2: Dictionary = srv.snapshot_duel()
	failed += _expect(int(snap2.get("opponent_hp", 999)) < int(snap.get("opponent_hp", 0)), "hp dropped after attack")

	# Debug hit can finish (or forfeit path)
	var hp_left: int = int(srv.snapshot_duel().get("opponent_hp", 0))
	if hp_left > 0 and srv.has_method("try_duel_debug_hit"):
		var hit: Dictionary = srv.try_duel_debug_hit(hp_left + 5)
		failed += _expect(bool(hit.get("ok", false)), "debug hit ok")
		failed += _expect(not srv.in_duel(), "win clears duel")
		failed += _expect(_has(hit, "system_message"), "win system_message")
	else:
		# Already dead from attack
		failed += _expect(not srv.in_duel() or hp_left <= 0, "ended or zero hp")

	# Forfeit clears
	srv._duel_force_clear_silent()
	srv.try_remote_despawn("")
	srv.try_remote_debug_spawn("旅人乙")
	var ch2: Dictionary = srv.try_duel_challenge("旅人乙")
	failed += _expect(bool(ch2.get("ok", false)) and srv.in_duel(), "re-challenge 旅人乙")
	var ff: Dictionary = srv.try_duel_forfeit()
	failed += _expect(bool(ff.get("ok", false)), "forfeit ok")
	failed += _expect(not srv.in_duel(), "forfeit clears")
	failed += _expect(_has(ff, "duel_update"), "forfeit duel_update")
	failed += _expect(_has(ff, "system_message"), "forfeit system_message")
	var snap_idle: Dictionary = srv.snapshot_duel()
	failed += _expect(not bool(snap_idle.get("active", true)), "snap inactive")

	# Accept / decline via pending helper
	srv.try_remote_despawn("")
	srv.try_remote_debug_spawn("旅人丙")
	if srv.has_method("try_duel_debug_pending"):
		var pend: Dictionary = srv.try_duel_debug_pending("旅人丙")
		failed += _expect(bool(pend.get("ok", false)), "debug pending ok")
		failed += _expect(not srv.in_duel(), "pending not active yet")
		failed += _expect(bool(srv.snapshot_duel().get("pending", false)), "snap pending")
		var dec: Dictionary = srv.try_duel_decline()
		failed += _expect(bool(dec.get("ok", false)), "decline ok")
		failed += _expect(not bool(srv.snapshot_duel().get("pending", true)), "pending cleared")

		srv.try_duel_debug_pending("旅人丙")
		var acc: Dictionary = srv.try_duel_accept()
		failed += _expect(bool(acc.get("ok", false)), "accept ok")
		failed += _expect(srv.in_duel(), "accept→active")
		srv.try_duel_forfeit()

	# Timeout via _tick_duel
	srv._duel_force_clear_silent()
	srv.try_remote_despawn("")
	srv.try_remote_debug_spawn("旅人甲")
	srv.try_duel_challenge("旅人甲")
	failed += _expect(srv.in_duel(), "active before timeout")
	srv._duel["ends_at"] = 0.0
	var to_acts: Array = srv._tick_duel()
	failed += _expect(not srv.in_duel(), "timeout clears")
	failed += _expect(to_acts.size() >= 1, "timeout actions")
	var has_msg := false
	for a in to_acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			has_msg = true
	failed += _expect(has_msg, "timeout system_message")

	# Menu id
	var PCM = load("res://scripts/ui/player_context_menu.gd")
	if PCM != null:
		failed += _expect(PCM.Action.DUEL == 7, "duel id=7")
		failed += _expect(PCM.label_for(PCM.Action.DUEL) == "决斗", "duel label")

	if failed == 0:
		print("test_duel: PASS")
		quit(0)
		return
	print("test_duel: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
