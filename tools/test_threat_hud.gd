extends SceneTree
## Headless: threat / aggro indicator — attack → threat_you, evade → false, util helpers.

const ThreatUtil = preload("res://scripts/ui/threat_hud_util.gd")
const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_util_helpers()
	failed += _test_snapshot_and_attack()
	failed += _test_evade_clears()

	if failed == 0:
		print("test_threat_hud: PASS")
		quit(0)
	else:
		print("test_threat_hud: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		return 0
	print("  FAIL: ", label)
	return 1


func _test_util_helpers() -> int:
	var failed := 0
	failed += _expect(ThreatUtil.chip_text(true) == "仇恨", "chip_text you")
	failed += _expect(ThreatUtil.chip_text(false) == "无仇恨", "chip_text other")
	failed += _expect(ThreatUtil.should_show(true), "should_show hostile")
	failed += _expect(not ThreatUtil.should_show(false), "should_show hide")
	var c_you: Color = ThreatUtil.chip_color(true)
	var c_other: Color = ThreatUtil.chip_color(false)
	failed += _expect(c_you.r > c_other.r or c_you.g > c_other.g, "you color warmer")
	var hate: Array = [
		{"id": "player", "threat": 100.0, "threat_mod": 1.0},
		{"id": "p2", "threat": 50.0, "threat_mod": 1.0},
	]
	var snap: Dictionary = ThreatUtil.compute_from_hate("player", "player", hate, "mob1")
	failed += _expect(bool(snap.get("threat_you", false)), "compute threat_you")
	failed += _expect(int(snap.get("threat_rank", 0)) == 1, "compute rank 1")
	failed += _expect(is_equal_approx(float(snap.get("threat_pct", 0.0)), 100.0), "compute pct 100")
	var snap2: Dictionary = ThreatUtil.compute_from_hate("player", "p2", hate, "mob1")
	failed += _expect(not bool(snap2.get("threat_you", true)), "compute not you when p2 victim")
	var n: Dictionary = ThreatUtil.normalize({"threat_you": true, "npc_id": "x", "threat_rank": 2})
	failed += _expect(bool(n.get("threat_you", false)) and str(n.get("npc_id", "")) == "x", "normalize")
	return failed


func _test_snapshot_and_attack() -> int:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_threat_hud: FAIL no MockServer")
		return 1
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.has_method("snapshot_threat"), "has snapshot_threat")
	failed += _expect(srv.combat_stats.has_method("snapshot_threat"), "stats.snapshot_threat")

	var stats = srv.combat_stats
	stats.reset_player(5)
	if stats.has_method("set_player_actor_id"):
		stats.set_player_actor_id("player")
	stats.ensure_npc("threat_mob", true, true)
	stats.ensure_npc_ai("threat_mob", 2, true, Vector2i(10, 10), 0)
	stats.set_npc_cell("threat_mob", 10, 10)
	stats.npcs["threat_mob"]["hp"] = 200
	stats.npcs["threat_mob"]["hp_max"] = 200
	stats.npcs["threat_mob"]["atk"] = 1
	stats.npcs["threat_mob"]["def"] = 0

	var empty: Dictionary = srv.snapshot_threat("threat_mob")
	failed += _expect(not bool(empty.get("threat_you", true)), "empty hate threat_you false")
	failed += _expect(str(empty.get("victim_id", "x")) == "", "empty victim")

	# Direct hate → victim = player
	stats.add_threat("threat_mob", "player", 40.0)
	var snap1: Dictionary = srv.snapshot_threat("threat_mob")
	failed += _expect(bool(snap1.get("threat_you", false)), "after hate threat_you true")
	failed += _expect(str(snap1.get("victim_id", "")) == "player", "victim is player")
	failed += _expect(int(snap1.get("threat_rank", 0)) == 1, "rank 1")

	# Second actor higher sticky threshold not met
	stats.add_threat("threat_mob", "p2", 30.0)
	var snap2: Dictionary = srv.snapshot_threat("threat_mob")
	failed += _expect(bool(snap2.get("threat_you", false)), "still tank (sticky)")

	# Clear and attack via try_attack so actions include threat_update
	stats.clear_hate("threat_mob")
	stats.clear_chase("threat_mob")
	stats.npcs["threat_mob"]["hp"] = 200
	stats.ensure_npc_ai("threat_mob", 2, true, Vector2i(10, 10), 0)
	stats.set_npc_cell("threat_mob", 10, 10)
	srv.set_player_cell(10, 10)
	srv.combat_randf = func() -> float: return 0.01  # hit + no crit bias low
	# Attack may need CD ready
	if stats.has_method("set_attack_cooldown"):
		stats.set_attack_cooldown(0.0)
	var atk: Dictionary = srv.try_attack("threat_mob", 10, 10)
	failed += _expect(bool(atk.get("ok", false)), "try_attack ok")
	var acts: Array = atk.get("actions", [])
	var thr_act := {}
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "threat_update":
			thr_act = a
			break
	failed += _expect(not thr_act.is_empty(), "threat_update in attack actions")
	failed += _expect(bool(thr_act.get("threat_you", false)), "attack threat_you true")
	var snap3: Dictionary = srv.snapshot_threat("threat_mob")
	failed += _expect(bool(snap3.get("threat_you", false)), "snapshot after attack true")
	failed += _expect(str(stats.npc_ai["threat_mob"].get("victim_id", "")) == "player", "victim player after attack")
	return failed


func _test_evade_clears() -> int:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		return 1
	var stats = srv.combat_stats
	stats.ensure_npc("evade_mob", true, true)
	stats.ensure_npc_ai("evade_mob", 2, true, Vector2i(5, 5), 0)
	stats.set_npc_cell("evade_mob", 5, 5)
	stats.add_threat("evade_mob", "player", 80.0)
	failed += _expect(bool(srv.snapshot_threat("evade_mob").get("threat_you", false)), "pre-evade you")

	var evade_acts: Array = srv._evade_npc("evade_mob")
	var found := false
	var threat_you_after := true
	for a in evade_acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "threat_update":
			found = true
			threat_you_after = bool(a.get("threat_you", true))
	failed += _expect(found, "evade emits threat_update")
	failed += _expect(not threat_you_after, "evade threat_you false")
	failed += _expect(not bool(srv.snapshot_threat("evade_mob").get("threat_you", true)), "snapshot after evade false")
	failed += _expect(stats.get_hate_list("evade_mob").is_empty(), "hate cleared")
	failed += _expect(str(stats.npc_ai["evade_mob"].get("victim_id", "x")) == "", "victim cleared")

	# clear_hate alone
	stats.add_threat("evade_mob", "player", 10.0)
	stats.clear_hate("evade_mob")
	failed += _expect(not bool(srv.snapshot_threat("evade_mob").get("threat_you", true)), "clear_hate → false")
	return failed
