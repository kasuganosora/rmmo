extends SceneTree
## Headless: town safe-zone rects, duel/attack block, enter/leave action, hostile no-aggro.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_safe_zone: FAIL no MockServer")
		quit(1)
		return

	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.safe_zone_catalog == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.combat_stats != null:
		srv.combat_stats.reset_player(3)

	failed += _expect(srv.has_method("is_in_safe_zone"), "has is_in_safe_zone")
	failed += _expect(srv.has_method("player_in_safe_zone"), "has player_in_safe_zone")
	failed += _expect(srv.safe_zone_catalog != null, "catalog loaded")

	# Cell inside / outside (demo_map rect 5,11–16,19 living room + hallway)
	failed += _expect(srv.is_in_safe_zone("demo_map", 6, 13), "inn (6,13) inside")
	failed += _expect(srv.is_in_safe_zone("demo_map", 5, 15), "blacksmith (5,15) inside")
	failed += _expect(srv.is_in_safe_zone("demo_map", 15, 18), "spawn (15,18) inside")
	failed += _expect(srv.is_in_safe_zone("demo_map", 5, 11), "corner min inside")
	failed += _expect(srv.is_in_safe_zone("demo_map", 16, 19), "corner max inside")
	failed += _expect(srv.is_in_safe_zone("demo_map", 10, 12), "living room inside")
	failed += _expect(not srv.is_in_safe_zone("demo_map", 17, 12), "kitchen (17,12) outside")
	failed += _expect(not srv.is_in_safe_zone("demo_map", 10, 10), "(10,10) outside (duel tests)")
	failed += _expect(not srv.is_in_safe_zone("demo_map", 4, 12), "west outside")
	failed += _expect(not srv.is_in_safe_zone("demo_map", 12, 10), "north outside")
	failed += _expect(not srv.is_in_safe_zone("other_map", 12, 12), "wrong map outside")

	if srv.safe_zone_catalog.has_method("zones_for_map"):
		failed += _expect(srv.safe_zone_catalog.zones_for_map("demo_map").size() >= 1, "zones_for_map")

	# Enter / leave emits safe_zone action
	srv._safe_zone_known = false
	srv.set_player_cell(12, 12)
	failed += _expect(srv.player_in_safe_zone(), "player inside at inn")
	var enter_acts: Array = srv._safe_zone_transition_actions(true)
	failed += _expect(_has_safe(enter_acts, true), "force enter inside=true")
	failed += _expect(srv._safe_zone_transition_actions().is_empty(), "no emit while still inside")
	srv.set_player_cell(17, 12)
	failed += _expect(not srv.player_in_safe_zone(), "player outside at slime")
	var leave_acts: Array = srv._safe_zone_transition_actions()
	failed += _expect(_has_safe(leave_acts, false), "leave inside=false")
	failed += _expect(not bool(srv.snapshot_safe_zone().get("inside", true)), "snapshot outside")

	# Duel challenge fails inside, succeeds outside
	if srv.has_method("_duel_force_clear_silent"):
		srv._duel_force_clear_silent()
	if srv.has_method("try_remote_despawn"):
		srv.try_remote_despawn("")
	var sp: Dictionary = srv.try_remote_debug_spawn("旅人安区")
	failed += _expect(bool(sp.get("ok", false)), "spawn remote")
	var remotes: Array = srv.snapshot_remote_players()
	var rid := ""
	for r in remotes:
		if typeof(r) == TYPE_DICTIONARY and str(r.get("name", "")) == "旅人安区":
			rid = str(r.get("id", ""))
			break
	failed += _expect(rid != "", "remote id")
	var rd: Dictionary = srv.get_remote_player(rid)
	var rcell: Dictionary = rd.get("cell", {})
	var rx: int = int(rcell.get("x", 20))
	var ry: int = int(rcell.get("y", 20))

	srv.set_player_cell(12, 12)
	failed += _expect(srv.player_in_safe_zone(), "inside before duel fail")
	var ch_in: Dictionary = srv.try_duel_challenge("旅人安区")
	failed += _expect(not bool(ch_in.get("ok", true)), "duel fails inside")
	failed += _expect(str(ch_in.get("reason", "")) == "safe_zone", "reason safe_zone")
	failed += _expect(_msg_has(ch_in, "安全区内无法决斗"), "duel msg")
	failed += _expect(not srv.in_duel(), "still not in duel")

	# Outside: place beside remote; if that cell is safe, push both to (20,20)/(21,20)
	srv.set_player_cell(rx - 1, ry)
	if srv.player_in_safe_zone():
		# Force remote + player outside town rect
		if srv._remote_players.has(rid):
			var row: Dictionary = srv._remote_players[rid]
			row["cell"] = {"x": 21, "y": 20}
			srv._remote_players[rid] = row
		srv.set_player_cell(20, 20)
		rx = 21
		ry = 20
	failed += _expect(not srv.player_in_safe_zone(), "outside before duel ok")
	var ch_out: Dictionary = srv.try_duel_challenge("旅人安区")
	failed += _expect(bool(ch_out.get("ok", false)), "duel ok outside")
	failed += _expect(srv.in_duel(), "duel active outside")

	# Attack while outside (adjacent)
	srv.combat_randf = func() -> float: return 0.5
	var atk_ok: Dictionary = srv.try_attack(rid, srv.player_cell.x, srv.player_cell.y)
	failed += _expect(bool(atk_ok.get("ok", false)), "attack remote ok outside")

	# Move into safe zone → attack blocked
	srv.set_player_cell(12, 12)
	failed += _expect(srv.player_in_safe_zone(), "inside for attack block")
	var atk_block: Dictionary = srv.try_attack(rid, 12, 12)
	failed += _expect(not bool(atk_block.get("ok", true)), "attack blocked inside")
	failed += _expect(str(atk_block.get("reason", "")) == "safe_zone", "attack reason safe_zone")
	failed += _expect(_msg_has(atk_block, "安全区内无法决斗"), "attack msg")

	if srv.has_method("try_duel_forfeit"):
		srv.try_duel_forfeit()
	if srv.has_method("_duel_force_clear_silent"):
		srv._duel_force_clear_silent()

	# Attack blocked inside even without duel
	srv.set_player_cell(13, 12)
	var atk2: Dictionary = srv.try_attack(rid, 13, 12)
	failed += _expect(not bool(atk2.get("ok", true)), "attack remote blocked inside (no duel)")
	failed += _expect(str(atk2.get("reason", "")) == "safe_zone", "attack2 reason")

	# Hostile aggro suppressed while player inside
	srv.set_player_cell(15, 12)
	failed += _expect(srv.player_in_safe_zone(), "player inside for aggro test")
	if srv.has_method("register_npc"):
		srv.register_npc("sz_wolf", 16, 12, true, true, 4, 2, 0, {
			"name": "安区狼",
			"hostile": true,
			"aggressive": true,
			"wander_radius": 2,
		})
	if srv.combat_stats != null and srv.combat_stats.npc_ai.has("sz_wolf"):
		var ai: Dictionary = srv.combat_stats.npc_ai["sz_wolf"]
		ai["facing"] = 4
		ai["ai_state"] = "idle"
		ai["chase_target"] = ""
		ai["aggressive"] = true
		srv.combat_stats.npc_ai["sz_wolf"] = ai
		var hp_before: int = int(srv.combat_stats.player.get("hp", 0))
		for _i in range(5):
			srv._tick_mob_ai(0.5)
		var ai_after: Dictionary = srv.combat_stats.npc_ai.get("sz_wolf", {})
		failed += _expect(
			str(ai_after.get("ai_state", "")) != "chase" and str(ai_after.get("chase_target", "")) == "",
			"no chase while player in safe zone"
		)
		var hp_after: int = int(srv.combat_stats.player.get("hp", hp_before))
		failed += _expect(hp_after >= hp_before, "no damage while in safe zone")

		# Break existing chase when player enters safe zone
		srv.set_player_cell(17, 12)
		ai = srv.combat_stats.npc_ai["sz_wolf"]
		ai["ai_state"] = "chase"
		ai["chase_target"] = "player"
		ai["facing"] = 6
		srv.combat_stats.npc_ai["sz_wolf"] = ai
		srv.set_player_cell(14, 12)
		failed += _expect(srv.player_in_safe_zone(), "re-enter safe zone")
		srv._tick_mob_ai(0.2)
		var ai3: Dictionary = srv.combat_stats.npc_ai.get("sz_wolf", {})
		failed += _expect(
			str(ai3.get("ai_state", "")) != "chase" and str(ai3.get("chase_target", "")) == "",
			"chase broken on safe-zone enter"
		)

	if failed == 0:
		print("test_safe_zone: PASS")
		quit(0)
		return
	print("test_safe_zone: FAIL count=%d" % failed)
	quit(1)


func _has_safe(acts: Array, inside: bool) -> bool:
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "safe_zone" and bool(a.get("inside", not inside)) == inside:
			return true
	return false


func _msg_has(result: Dictionary, frag: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "system_message" and frag in str(a.get("text", "")):
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
