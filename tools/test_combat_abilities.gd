extends SceneTree
## Headless: passive ATK/DEF, item apply_status / cleanse / recall (no catalog content).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_passives()
	failed += _test_item_status_and_cleanse()
	failed += _test_item_recall()
	failed += _test_skill_recall()
	if failed == 0:
		print("test_combat_abilities: PASS")
		quit(0)
	else:
		print("test_combat_abilities: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _engine():
	var CombatStats = load("res://scripts/net/combat/combat_stats.gd")
	var CombatEngine = load("res://scripts/net/combat/combat_engine.gd")
	var SkillCatalog = load("res://scripts/net/combat/skill_catalog.gd")
	var ItemCatalog = load("res://scripts/net/combat/item_catalog.gd")
	var Inventory = load("res://scripts/net/combat/inventory.gd")
	var stats = CombatStats.new()
	stats.reset_player(3)
	var skills = SkillCatalog.new()
	skills.load_catalog()
	var items = ItemCatalog.new()
	items.load_catalog()
	var bag = Inventory.new()
	bag.grant_starter()
	var engine = CombatEngine.new()
	engine.setup(stats, skills, items, bag)
	return {"stats": stats, "skills": skills, "items": items, "bag": bag, "engine": engine}


func _test_passives() -> int:
	var failed := 0
	var ctx = _engine()
	var stats = ctx.stats
	var engine = ctx.engine
	var skills = ctx.skills
	failed += _expect(skills.has_skill("tough_skin"), "tough_skin in catalog")
	failed += _expect(skills.has_skill("keen_eye"), "keen_eye in catalog")
	stats.ensure_skill_book()
	stats.skill_book.grant_skill_points(10)
	stats.skill_book.try_learn("keen_eye", skills, 99)
	stats.skill_book.try_learn("tough_skin", skills, 99)
	failed += _expect(stats.skill_book.is_known("keen_eye"), "keen_eye learned")
	failed += _expect(stats.skill_book.is_known("tough_skin"), "tough_skin learned")
	var base_atk: int = int(stats.player.get("atk", 0))
	var base_def: int = int(stats.player.get("def", 0))
	var skin: Dictionary = skills.get_skill("tough_skin")
	var eye: Dictionary = skills.get_skill("keen_eye")
	var want_atk: int = base_atk + int(eye.get("atk_bonus", 0))
	var want_def: int = base_def + int(skin.get("def_bonus", 0))
	failed += _expect(engine._effective_atk_player() == want_atk, "keen_eye atk_bonus in effective atk")
	failed += _expect(engine._effective_def_player() == want_def, "tough_skin def_bonus in effective def")
	# Extra DEF actually reduces incoming hit.
	stats.ensure_npc("hit", true)
	stats.set_npc_cell("hit", 1, 0)
	stats.npcs["hit"]["atk"] = 20
	stats.npcs["hit"]["def"] = 0
	stats.player["hp"] = 80
	stats.player["def"] = 0
	var hp0: int = int(stats.player.get("hp", 0))
	# Guaranteed hit (skip accuracy) — this case only checks DEF mitigation.
	engine._damage_player(20, [], "hit", false)
	var hp1: int = int(stats.player.get("hp", 0))
	var expect_dealt: int = maxi(1, 20 - engine._effective_def_player())
	failed += _expect(hp0 - hp1 == expect_dealt, "passive def reduces player damage")
	return failed


func _test_item_status_and_cleanse() -> int:
	var failed := 0
	var ctx = _engine()
	var stats = ctx.stats
	var items = ctx.items
	var bag = ctx.bag
	var engine = ctx.engine
	items.register_item({
		"id": "_cap_buff",
		"name": "test buff",
		"type": "consumable",
		"consumable": true,
		"use_effect": "apply_status",
		"status": {
			"id": "_cap_might",
			"name": "might",
			"kind": "buff",
			"duration": 8.0,
			"atk_add": 4,
		},
	})
	items.register_item({
		"id": "_cap_cleanse",
		"name": "test cleanse",
		"type": "consumable",
		"consumable": true,
		"use_effect": "cleanse",
	})
	bag.add_item("_cap_buff", 1)
	bag.add_item("_cap_cleanse", 1)
	var atk0: int = engine._effective_atk_player()
	var r: Dictionary = engine.try_use_item("_cap_buff")
	failed += _expect(bool(r.get("ok", false)), "apply_status item ok")
	failed += _expect(stats.statuses.has_status("player", "_cap_might"), "buff applied")
	failed += _expect(engine._effective_atk_player() == atk0 + 4, "atk_add from item buff")
	stats.statuses.apply_status("player", {
		"id": "poison",
		"kind": "dot",
		"duration": 6.0,
		"tick_interval": 1.0,
		"tick_hp": -4,
	}, 6.0, "npc")
	failed += _expect(stats.statuses.has_status("player", "poison"), "poison on player")
	engine.try_use_item("_cap_cleanse")
	failed += _expect(not stats.statuses.has_status("player", "poison"), "cleanse strips harmful")
	failed += _expect(stats.statuses.has_status("player", "_cap_might"), "cleanse keeps buff")
	return failed


func _test_item_recall() -> int:
	var failed := 0
	var MockServer = load("res://scripts/net/mock_server.gd")
	var srv = MockServer.new()
	root.add_child(srv)
	if srv.item_catalog != null:
		srv.item_catalog.register_item({
			"id": "_cap_recall",
			"name": "test recall",
			"type": "consumable",
			"consumable": true,
			"use_effect": "recall",
		})
	if srv.inventory != null:
		srv.inventory.add_item("_cap_recall", 1)
	srv.map_collision = null
	srv.last_safe_cell = Vector2i(12, 8)
	srv.respawn_cell = Vector2i(5, 6)
	srv.set_player_cell(3, 3)
	var r: Dictionary = srv.try_use_item("_cap_recall")
	failed += _expect(bool(r.get("ok", false)), "recall item ok")
	var has_recall := false
	var cell := Vector2i(-1, -1)
	for a in r.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "recall":
			continue
		has_recall = true
		var cv: Variant = a.get("cell", {})
		if typeof(cv) == TYPE_DICTIONARY:
			cell = Vector2i(int(cv.get("x", -1)), int(cv.get("y", -1)))
	failed += _expect(has_recall, "recall action emitted")
	failed += _expect(cell == Vector2i(5, 6), "recall cell is town spawn")
	failed += _expect(srv.player_cell == Vector2i(5, 6), "server player_cell teleported")
	srv.queue_free()
	return failed


func _test_skill_recall() -> int:
	var failed := 0
	var MockServer = load("res://scripts/net/mock_server.gd")
	var srv = MockServer.new()
	root.add_child(srv)
	if srv.skill_catalog != null and srv.skill_catalog.has_method("register_skill"):
		srv.skill_catalog.register_skill({
			"id": "_cap_recall_skill",
			"name": "test recall skill",
			"effect": "recall",
			"mp_cost": 0,
			"cooldown": 0,
			"requires_target": false,
		})

	if srv.combat_stats != null:
		srv.combat_stats.ensure_skill_book()
		srv.combat_stats.skill_book.known["_cap_recall_skill"] = true
	srv.map_collision = null
	srv.last_safe_cell = Vector2i(1, 1)
	srv.respawn_cell = Vector2i(7, 9)
	srv.set_player_cell(2, 2)
	var r: Dictionary = srv.try_use_skill("_cap_recall_skill")
	failed += _expect(bool(r.get("ok", false)), "recall skill ok")
	var has_recall := false
	var cell := Vector2i(-1, -1)
	for a in r.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "recall":
			continue
		has_recall = true
		var cv: Variant = a.get("cell", {})
		if typeof(cv) == TYPE_DICTIONARY:
			cell = Vector2i(int(cv.get("x", -1)), int(cv.get("y", -1)))
	failed += _expect(has_recall, "skill recall action emitted")
	failed += _expect(cell == Vector2i(7, 9), "skill recall cell is town spawn")
	failed += _expect(srv.player_cell == Vector2i(7, 9), "skill recall teleported")
	srv.queue_free()
	return failed
