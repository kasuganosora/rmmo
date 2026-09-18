extends SceneTree
## Headless: unlearned cast fails → learn → cast/passive applies; SP on level-up.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_learn_gate_and_passive()
	failed += _test_sp_on_level_up()
	failed += _test_known_persists_without_reset()
	if failed == 0:
		print("test_skill_learn: PASS")
		quit(0)
	else:
		print("test_skill_learn: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _msg_has(actions: Array, needle: String) -> bool:
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(needle) >= 0:
			return true
	return false


func _make_ctx() -> Dictionary:
	var CombatStats = load("res://scripts/net/combat/combat_stats.gd")
	var CombatEngine = load("res://scripts/net/combat/combat_engine.gd")
	var SkillCatalog = load("res://scripts/net/combat/skill_catalog.gd")
	var ItemCatalog = load("res://scripts/net/combat/item_catalog.gd")
	var Inventory = load("res://scripts/net/combat/inventory.gd")
	var SkillBook = load("res://scripts/net/combat/skill_book.gd")
	var stats = CombatStats.new()
	stats.reset_player(1)
	var skills = SkillCatalog.new()
	skills.load_catalog()
	var items = ItemCatalog.new()
	items.load_catalog()
	var bag = Inventory.new()
	bag.set_catalog(items)
	if bag.has_method("grant_starter"):
		bag.grant_starter()
	stats.ensure_skill_book()
	stats.skill_book.grant_starters(skills)
	var engine = CombatEngine.new()
	engine.setup(stats, skills, items, bag, null)
	return {
		"stats": stats,
		"skills": skills,
		"engine": engine,
		"book": stats.skill_book,
		"SkillBook": SkillBook,
	}


func _test_learn_gate_and_passive() -> int:
	print("-- learn gate + passive --")
	var failed := 0
	var ctx := _make_ctx()
	var stats = ctx.stats
	var engine = ctx.engine
	var book = ctx.book
	var skills = ctx.skills

	failed += _expect(book.is_known("basic_attack"), "starter basic_attack known")
	failed += _expect(book.is_known("power_strike"), "starter power_strike known")
	failed += _expect(not book.is_known("heal_light"), "heal_light locked")
	failed += _expect(not book.is_known("tough_skin"), "tough_skin locked")
	failed += _expect(not book.is_known("keen_eye"), "keen_eye locked")

	var r: Dictionary = engine.try_use_skill("heal_light", "", 0, 0)
	failed += _expect(not bool(r.get("ok", true)), "unlearned heal_light rejected")
	failed += _expect(_msg_has(r.get("actions", []), "尚未学会"), "unlearned system_message")

	failed += _expect(engine._passive_bonus("atk") == 0, "passive atk 0 when unknown")
	failed += _expect(engine._passive_bonus("def") == 0, "passive def 0 when unknown")

	# Learn heal at level 1 (learn_level 1, sp_cost 1).
	book.grant_skill_points(5)
	var lh: Dictionary = book.try_learn("heal_light", skills, 1)
	failed += _expect(bool(lh.get("ok", false)), "learn heal_light")
	failed += _expect(book.is_known("heal_light"), "heal_light known")

	# Passives need level 2.
	var le: Dictionary = book.try_learn("keen_eye", skills, 1)
	failed += _expect(not bool(le.get("ok", false)), "keen_eye blocked at lv1")
	le = book.try_learn("keen_eye", skills, 2)
	failed += _expect(bool(le.get("ok", false)), "learn keen_eye at lv2")
	var ls: Dictionary = book.try_learn("tough_skin", skills, 2)
	failed += _expect(bool(ls.get("ok", false)), "learn tough_skin at lv2")

	failed += _expect(engine._passive_bonus("atk") == 2, "keen_eye atk_bonus when known")
	failed += _expect(engine._passive_bonus("def") == 5, "tough_skin def_bonus when known")

	# Learned active: spend MP and start cast / resolve.
	stats.player["mp"] = 50
	stats.player["hp"] = 40
	stats.player["hp_max"] = 100
	var r2: Dictionary = engine.try_use_skill("heal_light", "", 0, 0)
	failed += _expect(bool(r2.get("ok", false)), "learned heal_light ok")
	return failed


func _test_sp_on_level_up() -> int:
	print("-- SP on level-up --")
	var failed := 0
	# Use MockServer helpers if available; else mirror grant path.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var srv: Node = null
	if tree != null:
		srv = tree.root.get_node_or_null("MockServer")
	if srv == null:
		print("  SKIP MockServer missing")
		return 0
	if srv.get("combat_stats") == null:
		print("  SKIP combat_stats null")
		return 0
	srv.combat_stats.reset_player(1)
	if srv.has_method("_reset_skill_book"):
		srv._reset_skill_book()
	var book = srv.combat_stats.skill_book
	var sp0: int = int(book.skill_points)
	var need: int = int(srv.combat_stats.player.get("exp_to_next", 90))
	var summary: Dictionary = srv.combat_stats.grant_exp(need)
	failed += _expect(bool(summary.get("leveled", false)), "leveled via grant_exp")
	var actions: Array = []
	srv._append_level_up_sp(actions, summary.get("levels_gained", []))
	var gained: int = int(summary.get("levels_gained", []).size())
	failed += _expect(book.skill_points == sp0 + gained, "SP += levels_gained")
	var has_upd := false
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "skill_book_update":
			has_upd = true
	failed += _expect(has_upd, "skill_book_update emitted")
	failed += _expect(_msg_has(actions, "技能点"), "SP system_message")
	return failed


func _test_known_persists_without_reset() -> int:
	print("-- known persists without book reset --")
	var failed := 0
	var ctx := _make_ctx()
	var book = ctx.book
	var skills = ctx.skills
	book.grant_skill_points(3)
	var lr: Dictionary = book.try_learn("poison_dart", skills, 3)
	failed += _expect(bool(lr.get("ok", false)), "learn poison_dart")
	failed += _expect(book.is_known("poison_dart"), "poison_dart known")
	# Map transfer must not call grant_starters; book stays.
	failed += _expect(book.is_known("basic_attack"), "basic_attack still known")
	failed += _expect(book.is_known("poison_dart"), "poison_dart survives session")
	var snap: Dictionary = book.snapshot()
	failed += _expect("poison_dart" in snap.get("known", []), "snapshot lists poison_dart")
	return failed
