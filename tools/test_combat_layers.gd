extends SceneTree
## Headless smoke test for MockServer combat layers (no tile art required).

const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")


func _init() -> void:
	var failed := 0
	failed += _expect(true, "boot")
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

	failed += _expect(skills.has_skill("power_strike"), "skill power_strike loaded")
	failed += _expect(items.has_item("potion_hp_small"), "item potion loaded")
	failed += _expect(bag.get_qty("potion_hp_small") == 5, "starter potions")

	stats.set_npc_cell("slime", 1, 0)
	stats.ensure_npc("slime", true)
	var atk: Dictionary = engine.try_attack("slime", 0, 0)
	failed += _expect(bool(atk.get("ok", false)), "try_attack ok")
	var actions: Array = atk.get("actions", [])
	failed += _expect(_has_type(actions, "damage"), "damage action")

	# Cooldown should block immediate re-attack.
	var atk2: Dictionary = engine.try_attack("slime", 0, 0)
	failed += _expect(not bool(atk2.get("ok", false)), "attack cooldown")

	# Force ready and use power_strike.
	stats.attack_ready_at = 0.0
	stats.skill_ready_at.clear()
	var sk: Dictionary = engine.try_use_skill("power_strike", "slime", 0, 0)
	failed += _expect(bool(sk.get("ok", false)), "power_strike ok")
	failed += _expect(int(stats.player.get("mp", 0)) < int(stats.player.get("mp_max", 0)), "mp spent")

	stats.skill_ready_at.clear()
	var heal: Dictionary = engine.try_use_skill("heal_light", "", 0, 0)
	failed += _expect(bool(heal.get("ok", false)), "heal_light ok")
	var heal_acts: Array = heal.get("actions", [])
	if engine.is_casting():
		failed += _expect(_has_type(heal_acts, "cast_start"), "heal cast_start")
		var t := 0.0
		while engine.is_casting() and t < 3.0:
			heal_acts.append_array(engine.tick_cast(0.25))
			t += 0.25
	failed += _expect(_has_type(heal_acts, "heal"), "heal action")

	stats.player["hp"] = 10
	var item_r: Dictionary = engine.try_use_item("potion_hp_small")
	failed += _expect(bool(item_r.get("ok", false)), "use potion ok")
	failed += _expect(_has_type(item_r.get("actions", []), "inventory_update"), "inventory_update")
	failed += _expect(bag.get_qty("potion_hp_small") == 4, "potion consumed")
	failed += _expect(int(stats.player.get("hp", 0)) > 10, "hp healed")

	# Unknown NPC cell must not trust client (reject).
	stats.attack_ready_at = 0.0
	stats.clear_npc_cell("ghost")
	var far: Dictionary = engine.try_attack("ghost", 0, 0)
	failed += _expect(not bool(far.get("ok", false)), "reject unknown cell attack")

	# Death flag when HP hits 0.
	stats.ensure_npc("ogre", true)
	stats.set_npc_cell("ogre", 1, 0)
	stats.npcs["ogre"]["atk"] = 999
	stats.player["hp"] = 5
	stats.player["def"] = 0
	stats.attack_ready_at = 0.0
	var lethal: Dictionary = engine.try_attack("ogre", 0, 0)
	failed += _expect(_has_type(lethal.get("actions", []), "player_died") or int(stats.player.get("hp", 1)) == 0, "player_died or hp0")

	# restore_after_death helper
	stats.restore_after_death(false)
	failed += _expect(stats.player_alive(), "restore alive")
	failed += _expect(int(stats.player.get("hp", 0)) == int(stats.player.get("hp_max", -1)), "full hp restore")

	failed += _expect(not skills.list_all().is_empty(), "skill list_all")
	failed += _expect(not items.list_all().is_empty(), "item list_all")
	failed += _expect(str(skills.get_skill("basic_attack").get("category", "")) == "physical", "basic_attack category")
	failed += _expect(str(skills.get_skill("heal_light").get("category", "")) == "magic", "heal_light category")
	failed += _expect(skills.has_skill("tough_skin"), "tough_skin loaded")
	failed += _expect(str(skills.get_skill("tough_skin").get("category", "")) == "passive", "tough_skin category")
	var passive_try: Dictionary = engine.try_use_skill("tough_skin", "", 0, 0)
	failed += _expect(not bool(passive_try.get("ok", true)), "passive not castable")
	var pmsg := ""
	for a in passive_try.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			pmsg = str(a.get("text", ""))
			break
	failed += _expect(pmsg.find("被动") >= 0, "passive reject message")

	if failed == 0:
		print("test_combat_layers: PASS")
		quit(0)
	else:
		print("test_combat_layers: FAIL count=", failed)
		quit(1)


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
