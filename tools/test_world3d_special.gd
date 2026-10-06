extends SceneTree
const Doc = preload("res://scripts/world3d/world_document.gd")
var failed := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failed += 1
func run() -> void:
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var server = root.get_node("MockServer")
	var session = root.get_node("GameSession")
	var dir := preload("res://scripts/world3d/map_paths.gd").cache_directory("special_%d" % Time.get_ticks_usec())
	var doc := Doc.new()
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(30, 0.2, 30))
	var enemy: String = doc.add_npc(Vector3(0, 0.8, 0), "enemy", "")
	doc._find(enemy).merge({"hostile": true, "hp_max": 1000})
	var ally: String = doc.add_npc(Vector3(-3, 0.8, 0), "ally", "")
	doc._find(ally)["ally"] = true
	var path := dir.path_join("map.gltf")
	check(doc.save(path) == OK, "save ally and hostile records")
	session.world3d_map_path = path
	session.world3d_spawn = Vector3(0, 0.9, 5)
	var world = load("res://scenes/world_3d.tscn").instantiate()
	root.add_child(world)
	while not world.is_world_ready(): await process_frame
	world._combat.set_physics_process(false)
	world._player.set_physics_process(false)
	server.combat_engine.combat_randf = func(): return 0.5
	server.skill_catalog.register_skill({"id": "test_charge", "effect": "charge", "requires_target": true, "range": 5, "min_range": 1, "mp_cost": 2, "cooldown": 0, "power": 0.1})
	server.skill_catalog.register_skill({"id": "test_revive", "effect": "revive", "requires_target": true, "range": 5, "mp_cost": 2, "cooldown": 0, "cast_time": 0.1, "heal_pct": 0.3})
	server.combat_stats.skill_book.known.merge({"test_charge": true, "test_revive": true})
	world._combat.selected = enemy
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 0.2)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.position = Vector3(0, 1, 2.5)
	await physics_frame
	await process_frame
	var mp: int = server.combat_stats.player.mp
	check(not world._combat.use_skill("test_charge").ok and server.combat_stats.player.mp == mp, "blocked charge rejects before mana consumption")
	wall.free()
	check(world._combat.use_skill("test_charge").ok and absf(world._player.global_position.z - 1.1) < 0.01, "charge sweeps to decimal landing beside target")
	check(server.combat_stats.statuses.move_speed_mul(enemy) == 0, "shared charge applies root")
	var actor = world._combat.actors[enemy]
	actor.route = PackedVector3Array([Vector3(3, 0, 0)])
	var before: Vector3 = actor.global_position
	await physics_frame
	actor.follow_path(1.0 / 60.0, server.combat_stats.statuses.move_speed_mul(enemy))
	check(Vector2(actor.position.x, actor.position.z).distance_to(Vector2(before.x, before.z)) < 0.001, "rooted NPC cannot move along route")
	var actions: Array = []
	server.combat_engine._damage_npc(ally, 10000, actions, false)
	world._combat._apply({"actions": actions})
	check(server.combat_stats.npcs[ally].hp == 0 and world._combat.actors[ally].collision_layer == 0, "ally retains revivable corpse")
	world._combat.selected = ally
	check(world._combat.use_skill("test_revive").ok, "revive cast starts on dead ally")
	world._combat._apply({"actions": server.combat_engine.tick_cast(0.2)})
	check(server.combat_stats.npcs[ally].hp > 0 and world._combat.actors[ally].collision_layer == 1, "cast completion revives ally and restores collision")
	check(not world._combat.area_targets(10, 20, "circle").has(ally), "hostile area query excludes allies")
	world._player.global_position = Vector3(0, 0.9, 5)
	server.combat_stats.statuses.apply_status("player", {"id": "test_root", "duration": 10, "move_speed_mul": 0})
	await physics_frame
	before = world._player.global_position
	server.try_move_world(1000, Vector3.RIGHT, 1000)
	check(absf(world._player.position.x - before.x) < 0.001, "player root is enforced by authority even for oversized intent")
	server.combat_stats.statuses.clear_all("player")
	world._combat._create_loot(Vector3(2, 0, 2), [{"item_id": "rusty_coin", "qty": 3}])
	actions = []
	server.combat_engine._damage_npc(enemy, 10000, actions, false)
	world._combat._apply({"actions": actions})
	var drops: int = world._combat.loot.size()
	server.combat_stats.statuses.apply_status(ally, {"id": "persist_buff", "duration": 60, "move_speed_mul": 0.5})
	var ally_position: Vector3 = world._combat.actors[ally].position
	var other := Doc.new()
	other.add_box("ground", Vector3(0, -0.1, 0), Vector3(30, 0.2, 30))
	var other_path := dir.path_join("other.gltf")
	check(other.save(other_path) == OK, "save second map")
	check(await world.transfer_map(other_path, Vector3(1, 0.9, 3)), "transfer to second map")
	check(world._navigation.find_path(Vector3(1, 0, 3), Vector3(3, 0, 3)).ok, "transferred navigation RID stays queryable")
	server.item_catalog.register_item({"id": "test_recall", "type": "consumable", "consumable": true, "use_effect": "recall", "cooldown": 0})
	server.inventory.add_item("test_recall", 2)
	server.world3d_state.home.position = Vector3(100, 0.9, 100)
	check(world._combat.use_item("test_recall").ok, "recall prepares asynchronously")
	while world._transfer_pending: await process_frame
	check(world._map_path == other_path and server.inventory.has_item("test_recall", 2), "invalid recall keeps original map and both items")
	server.world3d_state.home.position = Vector3(0, 0.9, 5)
	check(world._combat.use_item("test_recall").ok, "valid recall starts")
	while world._transfer_pending: await process_frame
	world._combat.set_physics_process(false)
	check(world._map_path == path and server.inventory.has_item("test_recall", 1) and not server.inventory.has_item("test_recall", 2), "successful recall returns home and consumes exactly one item")
	check(world._combat.defeated.has(enemy) and not server.combat_stats.npcs.has(enemy), "returning preserves defeated enemy without duplicate reward")
	check(world._combat.loot.size() == drops, "returning preserves all uncollected drops exactly once")
	check(server.combat_stats.npcs[ally].hp > 0, "returning preserves living companion")
	check(server.world3d_state.read_map(path).actors[ally].position.is_equal_approx(ally_position) and world._combat.actors[ally].position.distance_to(ally_position) < 0.15, "returning preserves decimal companion position")
	check(server.combat_stats.statuses.has_status(ally, "persist_buff"), "returning restores companion status instances")
	world.free()
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(dir)
	print("test_world3d_special: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
