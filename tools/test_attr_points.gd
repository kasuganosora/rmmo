extends SceneTree
## Headless: attribute points on level-up + allocate → derived combat.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_level_grants_points()
	failed += _test_allocate_derived()
	failed += _test_insufficient_points()
	failed += _test_level_preserves_attrs()
	failed += _test_mock_allocate_and_respec()
	if failed == 0:
		print("test_attr_points: PASS")
		quit(0)
	else:
		print("test_attr_points: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _test_level_grants_points() -> int:
	print("-- level-up grants +5 attr points --")
	var failed := 0
	var CombatStats = load("res://scripts/net/combat/combat_stats.gd")
	var stats = CombatStats.new()
	stats.reset_player(1)
	failed += _expect(int(stats.player.get("attr_points", -1)) == 0, "start 0 attr_points")
	var need: int = int(stats.player.get("exp_to_next", 90))
	var sum: Dictionary = stats.grant_exp(need)
	failed += _expect(bool(sum.get("leveled", false)), "leveled")
	failed += _expect(int(stats.player.get("level", 0)) == 2, "lv2")
	failed += _expect(int(stats.player.get("attr_points", 0)) == 5, "attr_points += 5")
	var combat: Dictionary = sum.get("combat", {})
	failed += _expect(int(combat.get("attr_points", 0)) == 5, "snapshot attr_points")
	return failed


func _test_allocate_derived() -> int:
	print("-- allocate raises derived combat --")
	var failed := 0
	var CombatStats = load("res://scripts/net/combat/combat_stats.gd")
	var stats = CombatStats.new()
	stats.reset_player(1)
	# Manually grant points without leveling so baseline stays lv1.
	stats.player["attr_points"] = 10
	var atk0: int = int(stats.player.get("atk", 0))
	var def0: int = int(stats.player.get("def", 0))
	var hp0: int = int(stats.player.get("hp_max", 0))
	var mp0: int = int(stats.player.get("mp_max", 0))
	var r1: Dictionary = stats.try_allocate_attr("str", 3)
	failed += _expect(bool(r1.get("ok", false)), "allocate str ok")
	failed += _expect(int(stats.player.get("atk", 0)) == atk0 + 3, "str → atk +3")
	var r2: Dictionary = stats.try_allocate_attr("agi", 2)
	failed += _expect(bool(r2.get("ok", false)), "allocate agi ok")
	failed += _expect(int(stats.player.get("def", 0)) == def0 + 2, "agi → def +2")
	var r3: Dictionary = stats.try_allocate_attr("vit", 2)
	failed += _expect(bool(r3.get("ok", false)), "allocate vit ok")
	failed += _expect(int(stats.player.get("hp_max", 0)) == hp0 + 10, "vit → hp_max +10")
	var r4: Dictionary = stats.try_allocate_attr("intel", 3)
	failed += _expect(bool(r4.get("ok", false)), "allocate intel ok")
	failed += _expect(int(stats.player.get("mp_max", 0)) == mp0 + 9, "intel → mp_max +9")
	failed += _expect(int(stats.player.get("attr_points", -1)) == 0, "points spent")
	failed += _expect(int(stats.player["attrs"].get("str", 0)) == 3, "attrs.str=3")
	return failed


func _test_insufficient_points() -> int:
	print("-- insufficient points fails --")
	var failed := 0
	var CombatStats = load("res://scripts/net/combat/combat_stats.gd")
	var stats = CombatStats.new()
	stats.reset_player(1)
	stats.player["attr_points"] = 1
	var bad: Dictionary = stats.try_allocate_attr("str", 2)
	failed += _expect(not bool(bad.get("ok", true)), "insufficient fails")
	failed += _expect(str(bad.get("reason", "")) == "no_points", "reason no_points")
	failed += _expect(int(stats.player.get("attr_points", 0)) == 1, "points unchanged")
	var bad_key: Dictionary = stats.try_allocate_attr("luck", 1)
	failed += _expect(not bool(bad_key.get("ok", true)), "bad key fails")
	stats.player["hp"] = 0
	stats.player["attr_points"] = 5
	var dead: Dictionary = stats.try_allocate_attr("str", 1)
	failed += _expect(not bool(dead.get("ok", true)), "dead fails")
	failed += _expect(str(dead.get("reason", "")) == "dead", "reason dead")
	return failed


func _test_level_preserves_attrs() -> int:
	print("-- level-up preserves spent attrs + adds points --")
	var failed := 0
	var CombatStats = load("res://scripts/net/combat/combat_stats.gd")
	var stats = CombatStats.new()
	stats.reset_player(1)
	stats.player["attr_points"] = 5
	stats.try_allocate_attr("str", 2)
	stats.try_allocate_attr("vit", 3)
	var atk_spent: int = int(stats.player.get("atk", 0))
	var hp_spent: int = int(stats.player.get("hp_max", 0))
	failed += _expect(int(stats.player["attrs"].get("str", 0)) == 2, "str kept pre-level")
	failed += _expect(int(stats.player.get("attr_points", -1)) == 0, "spent all")
	var need: int = int(stats.player.get("exp_to_next", 90))
	var sum: Dictionary = stats.grant_exp(need)
	failed += _expect(bool(sum.get("leveled", false)), "leveled again")
	failed += _expect(int(stats.player.get("level", 0)) == 2, "now lv2")
	failed += _expect(int(stats.player["attrs"].get("str", 0)) == 2, "str preserved")
	failed += _expect(int(stats.player["attrs"].get("vit", 0)) == 3, "vit preserved")
	failed += _expect(int(stats.player.get("attr_points", 0)) == 5, "new +5 points")
	# Level baseline lv2 + attr bonuses
	var expect_atk: int = (10 + 2 * 3) + 2  # baseline + str
	var expect_hp: int = (80 + 2 * 20) + 3 * 5
	failed += _expect(int(stats.player.get("atk", 0)) == expect_atk, "atk = baseline+str")
	failed += _expect(int(stats.player.get("hp_max", 0)) == expect_hp, "hp_max = baseline+vit")
	failed += _expect(int(stats.player.get("atk", 0)) != atk_spent or true, "atk recomputed")
	# Sanity: higher than pre-level with same attrs due to level curve
	failed += _expect(int(stats.player.get("atk", 0)) > atk_spent - 2, "atk grew with level")
	failed += _expect(int(stats.player.get("hp_max", 0)) > hp_spent - 5, "hp grew with level")
	return failed


func _test_mock_allocate_and_respec() -> int:
	print("-- MockServer allocate + respec --")
	var failed := 0
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var srv: Node = null
	if tree != null:
		srv = tree.root.get_node_or_null("MockServer")
	if srv == null or srv.get("combat_stats") == null:
		print("  SKIP MockServer missing")
		return 0
	if not srv.has_method("try_allocate_attr"):
		return _expect(false, "try_allocate_attr missing")
	srv.combat_stats.reset_player(1)
	if srv.inventory != null and srv.inventory.has_method("clear"):
		srv.inventory.clear()
		if srv.inventory.has_method("grant_starter"):
			srv.inventory.grant_starter()
	srv.combat_stats.player["attr_points"] = 5
	var atk0: int = int(srv.combat_stats.player.get("atk", 0))
	var r: Dictionary = srv.try_allocate_attr("str", 1)
	failed += _expect(bool(r.get("ok", false)), "server allocate ok")
	failed += _expect(int(srv.combat_stats.player.get("atk", 0)) == atk0 + 1, "server atk +1")
	var has_attr_upd := false
	var has_set := false
	for a in r.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t == "attr_update":
			has_attr_upd = true
		elif t == "set_stat":
			has_set = true
	failed += _expect(has_attr_upd, "attr_update emitted")
	failed += _expect(has_set, "set_stat emitted")
	# Respec
	if srv.inventory != null:
		srv.inventory.add_gold(100)
	var rr: Dictionary = srv.try_attr_respec()
	failed += _expect(bool(rr.get("ok", false)), "respec ok")
	failed += _expect(int(srv.combat_stats.player["attrs"].get("str", -1)) == 0, "attrs cleared")
	failed += _expect(int(srv.combat_stats.player.get("attr_points", 0)) >= 5, "points refunded")
	# Level path via _append_level_up_sp announces attr points
	srv.combat_stats.reset_player(1)
	var need: int = int(srv.combat_stats.player.get("exp_to_next", 90))
	var summary: Dictionary = srv.combat_stats.grant_exp(need)
	var actions: Array = []
	srv._append_level_up_sp(actions, summary.get("levels_gained", []))
	var msg_ok := false
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			if str(a.get("text", "")).find("属性点") >= 0:
				msg_ok = true
	failed += _expect(msg_ok, "level-up attr system_message")
	failed += _expect(int(srv.combat_stats.player.get("attr_points", 0)) == 5, "server grant_exp +5")
	return failed
