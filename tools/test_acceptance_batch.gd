extends SceneTree
## Headless acceptance tests: hate list / tank sticky, evade heal, LoS, loot roll, stack inventory.

const MobAI = preload("res://scripts/net/combat/mob_ai.gd")
const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")
const LootCatalog = preload("res://scripts/net/combat/loot_catalog.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_threat_sticky()
	failed += _test_hate_tank_hold()
	failed += _test_evade_heal()
	failed += _test_los_block()
	failed += _test_loot_roll()
	failed += _test_stack_inventory()
	failed += _test_kill_loot_grant()
	failed += _test_item_use_effect()

	if failed == 0:
		print("test_acceptance_batch: PASS")
		quit(0)
	else:
		print("test_acceptance_batch: FAIL count=", failed)
		quit(1)


func _test_threat_sticky() -> int:
	var failed := 0
	var stats = CombatStats.new()
	stats.reset_player(1)
	stats.ensure_npc("t1", true, true)
	stats.ensure_npc_ai("t1", 2, true, Vector2i(0, 0), 0)
	stats.set_npc_cell("t1", 0, 0)
	stats.add_threat("t1", "player", 100.0)
	failed += _expect(is_equal_approx(stats.get_threat("t1", "player"), 100.0), "threat add 100")
	failed += _expect(str(stats.npc_ai["t1"].get("chase_target", "")) == "player", "threat sets target")
	failed += _expect(str(stats.npc_ai["t1"].get("victim_id", "")) == "player", "victim_id set")
	failed += _expect(stats.get_hate_list("t1").size() == 1, "hate_list size 1")
	# Second player below 110% — no switch.
	stats.add_threat("t1", "p2", 105.0)
	failed += _expect(str(stats.npc_ai["t1"].get("chase_target", "")) == "player", "sticky hold <110%")
	failed += _expect(stats.get_hate_list("t1").size() == 2, "hate_list size 2")
	# Reach 110% — switch.
	stats.add_threat("t1", "p2", 5.0)  # p2 = 110
	failed += _expect(str(stats.select_victim("t1")) == "p2", "select_victim ≥110%")
	failed += _expect(str(stats.npc_ai["t1"].get("chase_target", "")) == "p2", "sticky switch ≥110%")
	stats.clear_chase("t1")
	failed += _expect(stats.get_threat("t1", "player") == 0.0, "clear_chase clears threat")
	failed += _expect(stats.get_hate_list("t1").is_empty(), "clear_chase clears hate_list")
	failed += _expect(str(stats.npc_ai["t1"].get("victim_id", "x")) == "", "victim cleared")
	failed += _expect(str(stats.npc_ai["t1"].get("chase_target", "")) == "", "chase cleared")
	return failed


## Tank A (mod 2.0) smaller raw damage still holds; DPS B needs ≥110% of A's applied threat.
func _test_hate_tank_hold() -> int:
	var failed := 0
	var stats = CombatStats.new()
	stats.reset_player(1)
	stats.set_player_actor_id("A")
	stats.set_actor_threat_mod("A", 2.0)
	stats.set_actor_threat_mod("B", 1.0)
	stats.ensure_npc("boss", true, true)
	stats.ensure_npc_ai("boss", 2, true, Vector2i(0, 0), 0)
	stats.set_npc_cell("boss", 0, 0)
	# A tanks: 50 raw * 2.0 = 100 hate
	stats.add_hate("boss", "A", 50.0, 2.0)
	failed += _expect(is_equal_approx(stats.get_threat("boss", "A"), 100.0), "tank applied hate 100")
	failed += _expect(str(stats.select_victim("boss")) == "A", "tank is victim")
	# B deals 105 raw * 1.0 = 105 (< 110) — no pull
	stats.add_hate("boss", "B", 105.0, 1.0)
	failed += _expect(str(stats.select_victim("boss")) == "A", "tank holds <110%")
	# B needs ≥110 to pull
	stats.add_hate("boss", "B", 5.0, 1.0)  # B = 110
	failed += _expect(str(stats.select_victim("boss")) == "B", "DPS pulls at ≥110%")
	# clear_hate on evade
	stats.clear_hate("boss")
	failed += _expect(stats.get_hate_list("boss").is_empty(), "clear_hate empties list")
	failed += _expect(str(stats.npc_ai["boss"].get("victim_id", "x")) == "", "clear_hate clears victim")
	# Heal stub accumulates 0.5x
	stats.add_hate("boss", "A", 40.0, 2.0)  # 80
	stats.add_hate_heal("boss", "A", 20.0, 1.0)  # +10
	failed += _expect(is_equal_approx(stats.get_threat("boss", "A"), 90.0), "heal hate 0.5x")
	return failed


func _test_evade_heal() -> int:
	var failed := 0
	var stats = CombatStats.new()
	stats.reset_player(1)
	stats.ensure_npc("ev", true, false)
	stats.ensure_npc_ai("ev", 2, false, Vector2i(5, 5), 0)
	stats.set_npc_cell("ev", 8, 5)
	stats.npcs["ev"]["hp"] = 3
	stats.enrage_npc("ev")
	stats.begin_chase("ev")
	stats.add_threat("ev", "player", 50.0)
	stats.clear_chase("ev")
	failed += _expect(int(stats.npcs["ev"].get("hp", 0)) == int(stats.npcs["ev"].get("hp_max", -1)), "evade full HP")
	failed += _expect(not bool(stats.npc_ai["ev"].get("enraged", true)), "evade clears enrage")
	failed += _expect(stats.get_hate_list("ev").is_empty(), "evade clears hate_list")
	failed += _expect(str(stats.npc_ai["ev"].get("ai_state", "")) == MobAI.AI_RETURN_HOME, "evade return_home")

	# MockServer _evade_npc emits npc_reset when available.
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("  SKIP evade npc_reset (no MockServer)")
		return failed
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	srv.combat_stats.clear_npcs()
	srv.combat_stats.ensure_npc("ev2", true, true)
	srv.combat_stats.ensure_npc_ai("ev2", 2, true, Vector2i(1, 1), 0)
	srv.combat_stats.set_npc_cell("ev2", 3, 1)
	srv.combat_stats.npcs["ev2"]["hp"] = 2
	srv.combat_stats.begin_chase("ev2")
	var acts: Array = srv._evade_npc("ev2")
	var got := false
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "npc_reset":
			got = true
			failed += _expect(int(a.get("hp", 0)) == int(a.get("hp_max", -1)), "npc_reset full hp")
			failed += _expect(str(a.get("reason", "")) == "evade", "npc_reset reason evade")
	failed += _expect(got, "npc_reset emitted")
	failed += _expect(int(srv.combat_stats.npcs["ev2"].get("hp", 0)) == int(srv.combat_stats.npcs["ev2"].get("hp_max", -1)), "srv evade HP")
	return failed


func _test_los_block() -> int:
	var failed := 0
	# Without collision, cone still works.
	failed += _expect(
		MobAI.player_in_vision(Vector2i(10, 10), 2, Vector2i(10, 14), null),
		"vision ok no collision"
	)
	# Simple collision stub: block cell (10,12) as wall.
	var stub := _SightStub.new()
	stub.blocked[Vector2i(10, 12)] = true
	failed += _expect(
		not MobAI.has_line_of_sight(stub, Vector2i(10, 10), Vector2i(10, 14)),
		"LoS blocked by wall cell"
	)
	failed += _expect(
		not MobAI.player_in_vision(Vector2i(10, 10), 2, Vector2i(10, 14), stub),
		"vision rejected by LoS"
	)
	failed += _expect(
		MobAI.has_line_of_sight(stub, Vector2i(10, 10), Vector2i(11, 10)),
		"adjacent clear LoS"
	)
	# Bresenham includes endpoints.
	var cells: Array[Vector2i] = MobAI.bresenham_cells(Vector2i(0, 0), Vector2i(3, 0))
	failed += _expect(cells.size() == 4, "bresenham 4 cells")
	failed += _expect(cells[0] == Vector2i(0, 0) and cells[3] == Vector2i(3, 0), "bresenham ends")
	return failed


func _test_loot_roll() -> int:
	var failed := 0
	var loot = LootCatalog.new()
	loot.load_catalog()
	# Force all chances to succeed (roll 0.0 never exceeds chance).
	var drops: Array = loot.roll_forced("street_slime", "retira_slime", 0.0)
	failed += _expect(not drops.is_empty(), "forced loot non-empty")
	var ids: Dictionary = {}
	for d in drops:
		ids[str(d.get("item_id", ""))] = true
	failed += _expect(ids.has("slime_jelly") or ids.has("potion_hp_small") or ids.has("rusty_coin"), "street slime items")
	# Charset fallback for pack mob.
	var pack: Array = loot.roll_forced("street_pack_a", "gnr_renegade001", 0.0)
	failed += _expect(not pack.is_empty(), "renegade charset loot")
	return failed


func _test_stack_inventory() -> int:
	var failed := 0
	var items = ItemCatalog.new()
	items.load_catalog()
	failed += _expect(items.has_item("slime_jelly"), "catalog slime_jelly")
	failed += _expect(str(items.get_item("potion_hp_small").get("type", "")) == "consumable", "type consumable")
	failed += _expect(int(items.get_item("potion_hp_small").get("stack_max", 0)) == 20, "stack_max 20")
	var bag = Inventory.new()
	bag.set_catalog(items)
	bag.clear()
	bag.max_slots = 3
	failed += _expect(bag.add_item("potion_hp_small", 5) == 5, "add potions")
	failed += _expect(bag.get_qty("potion_hp_small") == 5, "qty 5")
	failed += _expect(bag.add_item("slime_jelly", 2) == 2, "add jelly")
	failed += _expect(bag.add_item("torn_cloth", 1) == 1, "add cloth")
	failed += _expect(bag.slot_count() == 3, "3 slots used")
	failed += _expect(bag.add_item("rusty_coin", 1) == 0, "reject 4th slot")
	failed += _expect(not bag.can_accept("rusty_coin"), "cannot accept new")
	# Stack merge still works when slots full but room in stack.
	failed += _expect(bag.add_item("potion_hp_small", 3) == 3, "merge into existing")
	failed += _expect(bag.get_qty("potion_hp_small") == 8, "qty 8 after merge")
	# Cap at stack_max.
	bag.clear()
	bag.max_slots = 20
	var added: int = bag.add_item("potion_hp_small", 25)
	failed += _expect(added == 20, "cap at stack_max 20")
	failed += _expect(bag.get_qty("potion_hp_small") == 20, "qty at max")
	var r: Dictionary = bag.try_add_item("potion_hp_small", 1)
	failed += _expect(not bool(r.get("ok", true)), "stack_full reject")
	return failed


func _test_kill_loot_grant() -> int:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("  SKIP kill loot grant (no MockServer)")
		return 0
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	srv.combat_stats.clear_npcs()
	srv.npc_spawn_templates.clear()
	if srv.has_method("try_loot_close"):
		srv.try_loot_close()
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""
	if srv.inventory != null:
		srv.inventory.clear()
		srv.inventory.grant_starter()
	if srv.loot_catalog != null:
		srv.loot_catalog.rng_roll = func() -> float: return 0.0
	srv.npc_spawn_templates["street_slime"] = {
		"id": "street_slime",
		"charset": "retira_slime",
		"hostile": true,
		"home_cell": {"x": 5, "y": 5},
	}
	srv.set_player_cell(5, 5)
	var before: int = srv.inventory.get_qty("slime_jelly")
	var acts: Array = srv._roll_and_grant_loot("street_slime")
	var got_spawn := false
	var got_msg := false
	var got_open := false
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t in ["ground_spawn", "ground_update"]:
			got_spawn = true
		if t == "loot_open":
			got_open = true
		if t == "system_message" and "地上出现了掉落物" in str(a.get("text", "")):
			got_msg = true
	failed += _expect(got_spawn, "ground_spawn/update action")
	failed += _expect(got_msg, "地上出现了掉落物 message")
	failed += _expect(not got_open, "no auto loot_open on kill")
	failed += _expect(srv.inventory.get_qty("slime_jelly") == before, "no auto-grant until take")
	failed += _expect(srv.ground_bag_count() > 0, "ground bag created")
	var bid: String = srv.find_ground_bag_at(5, 5)
	var open_r: Dictionary = srv.try_open_ground_bag(bid)
	failed += _expect(bool(open_r.get("ok", false)), "open ground bag")
	failed += _expect(srv.has_pending_loot(), "pending after open")
	var take: Dictionary = srv.try_loot_take_all()
	failed += _expect(bool(take.get("ok", false)), "take_all ok")
	failed += _expect(srv.inventory.get_qty("slime_jelly") > before, "jelly granted on take")
	failed += _expect(not srv.has_pending_loot(), "pending cleared after take_all")
	failed += _expect(srv.ground_bag_count() == 0, "bag despawned when empty")
	# Restore RNG
	if srv.loot_catalog != null:
		srv.loot_catalog.rng_roll = Callable()
	return failed


func _test_item_use_effect() -> int:
	var failed := 0
	var stats = CombatStats.new()
	stats.reset_player(3)
	var skills = SkillCatalog.new()
	skills.load_catalog()
	var items = ItemCatalog.new()
	items.load_catalog()
	var bag = Inventory.new()
	bag.set_catalog(items)
	bag.grant_starter()
	var engine = CombatEngine.new()
	engine.setup(stats, skills, items, bag)
	stats.player["hp"] = 10
	var r: Dictionary = engine.try_use_item("potion_hp_small")
	failed += _expect(bool(r.get("ok", false)), "use_effect heal still works")
	failed += _expect(int(stats.player.get("hp", 0)) > 10, "hp healed via use_effect")
	return failed


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


## Minimal collision stub for LoS tests.
class _SightStub:
	var blocked: Dictionary = {}  # Vector2i -> true

	func is_valid(x: int, y: int) -> bool:
		return true

	func is_void_cell(x: int, y: int) -> bool:
		return false

	func is_passable(x: int, y: int, _d: int) -> bool:
		return not blocked.has(Vector2i(x, y))

	func can_pass_tiles(x: int, y: int, d: int) -> bool:
		var dx := 0
		var dy := 0
		match d:
			2:
				dy = 1
			4:
				dx = -1
			6:
				dx = 1
			8:
				dy = -1
		var nx: int = x + dx
		var ny: int = y + dy
		if blocked.has(Vector2i(nx, ny)) or blocked.has(Vector2i(x, y)):
			return false
		return true
