extends SceneTree
## Headless: party kill EXP bonus — solo base vs +5%/extra online same-map member (cap +25%).
## Stub allies have no separate EXP bars; only self is granted.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_party_exp: FAIL no MockServer")
		quit(1)
		return

	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.combat_stats != null, "combat_stats ready")
	failed += _expect(srv.has_method("grant_kill_exp"), "has grant_kill_exp")
	failed += _expect(srv.has_method("_party_kill_exp_with_bonus"), "has bonus helper")
	failed += _expect(srv.has_method("_party_online_same_map_count"), "has online count helper")

	# Formula unit checks (integer)
	failed += _expect(int(srv._party_kill_exp_with_bonus(100, 1)) == 100, "N=1 → 100")
	failed += _expect(int(srv._party_kill_exp_with_bonus(100, 2)) == 105, "N=2 → 105 (+5%)")
	failed += _expect(int(srv._party_kill_exp_with_bonus(100, 3)) == 110, "N=3 → 110 (+10%)")
	failed += _expect(int(srv._party_kill_exp_with_bonus(100, 6)) == 125, "N=6 → 125 (+25% cap)")
	failed += _expect(int(srv._party_kill_exp_with_bonus(100, 10)) == 125, "N=10 still capped 125")
	failed += _expect(int(srv._party_kill_exp_with_bonus(0, 3)) == 0, "base 0 → 0")
	failed += _expect(int(srv._party_kill_exp_with_bonus(1, 2)) == 1, "tiny base stays >=1")

	# Clear party
	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._party_poll_pending = false
	srv._stub_ally_seq = 1
	srv._session_character_id = "1"
	if srv.combat_stats.has_method("set_player_actor_id"):
		srv.combat_stats.set_player_actor_id("1")

	# Register a fixed-level NPC for kill EXP
	var npc_id := "party_exp_slime"
	srv.combat_stats.ensure_npc(npc_id, true)
	srv.combat_stats.npcs[npc_id]["level"] = 5
	var base_formula: int = srv.combat_stats.kill_exp_for_npc_level(5)
	failed += _expect(base_formula == maxi(5, 5 * 8 + 10), "base kill_exp formula (%d)" % base_formula)

	# --- Solo ---
	srv.combat_stats.reset_player(3)
	var solo_acts: Array = srv.grant_kill_exp(npc_id)
	var solo_amt: int = _exp_amount(solo_acts)
	failed += _expect(solo_amt == base_formula, "solo exp == base (%d == %d)" % [solo_amt, base_formula])
	failed += _expect(not _has_msg(solo_acts, "队伍加成"), "solo no 队伍加成")
	failed += _expect(not srv.in_party(), "solo not in party")

	# --- Party with 1 stub (N=2) ---
	srv.combat_stats.reset_player(3)
	var cr: Dictionary = srv.try_party_create()
	failed += _expect(bool(cr.get("ok", false)), "party create ok")
	var stub: Dictionary = srv._party_make_stub("stub_ally_exp1")
	srv._party_members.append(stub)
	failed += _expect(srv.in_party(), "in party")
	failed += _expect(int(srv._party_online_same_map_count()) == 2, "online same-map N=2")
	var party_acts: Array = srv.grant_kill_exp(npc_id)
	var party_amt: int = _exp_amount(party_acts)
	var expect_bonus: int = int(srv._party_kill_exp_with_bonus(base_formula, 2))
	failed += _expect(party_amt > solo_amt, "party exp > solo (%d > %d)" % [party_amt, solo_amt])
	failed += _expect(party_amt == expect_bonus, "party exp matches formula (%d == %d)" % [party_amt, expect_bonus])
	failed += _expect(_has_msg(party_acts, "队伍加成"), "party shows 队伍加成")
	failed += _expect(_has_msg_contains(party_acts, "获得经验 %d" % party_amt), "chat shows granted amount")

	# Offline stub does not count toward bonus
	srv.combat_stats.reset_player(3)
	srv._party_members[1]["online"] = false
	failed += _expect(int(srv._party_online_same_map_count()) == 1, "offline stub → N=1")
	var offline_acts: Array = srv.grant_kill_exp(npc_id)
	var offline_amt: int = _exp_amount(offline_acts)
	failed += _expect(offline_amt == base_formula, "offline-only-self → base exp")
	failed += _expect(not _has_msg(offline_acts, "队伍加成"), "no bonus msg when N=1")

	# Different map_id on stub excludes them
	srv.combat_stats.reset_player(3)
	srv._party_members[1]["online"] = true
	srv._party_members[1]["map_id"] = "other_map_xyz"
	failed += _expect(int(srv._party_online_same_map_count()) == 1, "other map → N=1")
	var far_acts: Array = srv.grant_kill_exp(npc_id)
	failed += _expect(_exp_amount(far_acts) == base_formula, "far map stub → base exp")

	# Cleanup
	if srv.has_method("_party_clear"):
		srv._party_clear()

	if failed == 0:
		print("test_party_exp: PASS")
		quit(0)
	else:
		print("test_party_exp: FAIL count=%d" % failed)
		quit(1)


func _exp_amount(actions: Array) -> int:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "exp_gain":
			return int(a.get("amount", 0))
	return -1


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
