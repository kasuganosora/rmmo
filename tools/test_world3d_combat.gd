extends SceneTree
var failed := 0
const Doc = preload("res://scripts/world3d/world_document.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failed += 1
func run() -> void:
	create_timer(240).timeout.connect(func():push_error("New body combat timeout");quit(2))
	var session = root.get_node("GameSession")
	var appearance:Dictionary={"body_model":"female_base_v2","body_shapes":{"height":-.25},"part_ids":{"FrontHair1":202}}
	session.selected_character={"id":-100,"name":"新底模战斗验收","gender":"female","customization":appearance}
	session.spawn_data={}
	var npc_recipe:Dictionary={"gender":"female","customization":appearance,"equipment":{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE}}
	var server = root.get_node("MockServer")
	var dir := Paths.cache_directory("battle_test_%d" % Time.get_ticks_usec())
	var doc := Doc.new()
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(20, 0.2, 20))
	var id: String = doc.add_npc(Vector3(0, 0.8, 0), "enemy", "")
	doc._find(id).merge({"hostile": true, "hp_max": 100, "level": 1, "atk": 10, "def": 1})
	doc._find(id)["appearance"]=npc_recipe
	var path := dir.path_join("map.gltf")
	check(doc.save(path) == OK, "save hostile definition")
	session.world3d_map_path = path
	session.world3d_spawn = Vector3(0, 0.9, 1.6)
	var world = load("res://scenes/world_3d.tscn").instantiate()
	root.add_child(world)
	while not world.is_world_ready(): await process_frame
	world._combat.set_physics_process(false)
	var resident_actor = world._combat.actors[id]
	check(world._player._model.axis_rig!=null and resident_actor.model.axis_rig!=null,"player and NPC both use accepted native body")
	var original_position: Vector3 = resident_actor.position
	resident_actor.position.x = 200
	resident_actor.velocity = Vector3.DOWN * 5
	var suspended_position: Vector3 = resident_actor.position
	world._combat._tick_actors(0.2)
	check(resident_actor.position.is_equal_approx(suspended_position) and resident_actor.velocity == Vector3.ZERO, "distant actor cannot fall through unloaded collision")
	resident_actor.position = original_position
	await physics_frame
	server.combat_engine.combat_randf = func(): return 0.5
	check(world._combat.in_range(id, 1), "3D melee accepts nearby target")
	var hp: int = server.combat_stats.npcs[id].hp
	check(world._combat.attack(id).ok and server.combat_stats.npcs[id].hp < hp, "attack uses shared damage rules")
	check(not world._combat.attack(id).ok, "attack cooldown cannot be bypassed")
	world._player.global_position.y += 3
	check(not world._combat.in_range(id, 100), "high range cannot hit a different floor")
	world._player.global_position.y -= 3
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 0.2)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.position = Vector3(0, 1, 0.8)
	await physics_frame
	await process_frame
	check(not world._combat.in_range(id, 1), "melee rejects wall occlusion")
	wall.free()
	server.skill_catalog.register_skill({"id": "review_ground", "name": "测试范围", "target_mode": "ground", "effect": "aoe_damage", "aoe_radius": 2, "range": 5, "power": 0.1, "mp_cost": 1, "cooldown": 0})
	server.combat_stats.skill_book.known["review_ground"] = true
	var mp: int = server.combat_stats.player.mp
	check(not world._combat.use_skill("review_ground", Vector3(0, 3, 0)).ok and server.combat_stats.player.mp == mp, "invalid elevated ground cast rejects before spending mana")
	var area_hp: int = server.combat_stats.npcs[id].hp
	check(world._combat.use_skill("review_ground", Vector3(0, 0, 0.4)).ok and server.combat_stats.npcs[id].hp < area_hp, "ground area skill applies shared damage at decimal 3D location")
	world._combat.actors[id].position.y += 3
	check(not world._combat.area_targets(5, 8, "circle").has(id), "area damage excludes enemies on another floor")
	world._combat.actors[id].position.y -= 3
	var actions: Array = []
	await world.request_sit(true)
	check(server.sitting and world._player._model.action=="sit_down_ground","new body enters actual sitting before fatal hit")
	server.combat_engine._damage_player(9999, actions, id, false)
	world._combat._apply({"actions": actions})
	check(world._player.input_locked and not server.combat_stats.player_alive(), "death locks movement")
	check(not server.sitting and world._player._model.action=="death", "fatal damage clears sitting without replacing death by recovery")
	check(not server.try_move_world(99999, Vector3.RIGHT, 4).ok, "authority rejects dead actor movement intent")
	var occupied := StaticBody3D.new()
	var occupied_shape := CollisionShape3D.new()
	var occupied_box := BoxShape3D.new()
	occupied_box.size = Vector3(1, 2, 1)
	occupied_shape.shape = occupied_box
	occupied.add_child(occupied_shape)
	world.add_child(occupied)
	occupied.position = world._combat.respawn_point
	await physics_frame
	await process_frame
	check(not world._combat.respawn() and not server.combat_stats.player_alive(), "occupied respawn point does not revive inside blocker")
	occupied.free()
	check(world._combat.respawn(), "dead character respawns on valid navigation surface")
	check(server.combat_stats.player_alive() and not world._player.input_locked and world._player.global_position.is_equal_approx(session.world3d_spawn), "revive restores stats and exact spawn")
	check(not world._combat.respawn(), "living player cannot exploit respawn teleport")
	for i in world._combat.loot.size(): check(world._combat.pickup_nearby(), "recover own death drop after respawn")
	server.loot_catalog.rng_roll = func(): return 0.0
	server.combat_stats.npcs[id].hp = 1
	server.combat_stats.attack_ready_at = 0
	var exp_before: int = server.combat_stats.player.get("exp", 0)
	check(world._combat.attack(id).ok and not server.combat_stats.npcs.has(id), "killing blow removes combat target")
	check(int(server.combat_stats.player.get("exp", 0)) > exp_before, "kill grants shared progression experience")
	check(not world._combat.loot.is_empty(), "kill creates loot in meter space")
	world._player.global_position.y += 3
	check(not world._combat.pickup_nearby(), "cannot collect drops through a floor")
	world._player.global_position.y -= 3
	check(world._combat.pickup_nearby() and world._combat.loot.is_empty(), "nearby loot reaches shared inventory")
	check(not world._combat.pickup_nearby(), "consumed loot cannot be collected twice")
	var after_kill: int = server.combat_stats.player.get("exp", 0)
	world._combat._apply({"actions": [{"type": "kill_npc", "npc_id": id}]})
	check(int(server.combat_stats.player.get("exp", 0)) == after_kill, "duplicate death action cannot grant experience twice")
	world._player.global_position = Vector3(0, 0.9, 4)
	world._combat.actors[id].respawn_remaining = 0.01
	world._combat._tick_actors(0.02)
	check(server.combat_stats.npcs.has(id) and world._combat.actors[id].collision_layer != 0, "NPC respawn restores stats and physical collider")
	world.free()
	check(not server.combat_engine.spatial_range.is_valid(), "world teardown removes spatial adapter")
	var bridge_doc = Doc.sample_yard()
	bridge_doc.map_meta["spawn"] = [0, 3.9, -2]
	var bridge_enemy: String = bridge_doc.add_npc(Vector3(-4, 0.8, 4), "chaser", "")
	bridge_doc._find(bridge_enemy)["hostile"] = true
	bridge_doc._find(bridge_enemy)["appearance"]=npc_recipe
	var bridge_path := dir.path_join("bridge.gltf")
	check(bridge_doc.save(bridge_path) == OK, "save multilayer combat fixture")
	session.world3d_map_path = bridge_path
	session.world3d_spawn = Vector3(0, 3.9, -2)
	world = load("res://scenes/world_3d.tscn").instantiate()
	root.add_child(world)
	while not world.is_world_ready(): await process_frame
	world._combat.set_physics_process(false)
	world._player.set_physics_process(false)
	check(not world._combat.in_range(bridge_enemy, 10), "NPC cannot attack bridge from the ground")
	for i in 900:
		await physics_frame
		world._combat._tick_actors(1.0 / 60.0)
		if world._combat.in_range(bridge_enemy, 1): break
	var actor = world._combat.actors[bridge_enemy]
	check(actor.feet().y > 2.8 and world._combat.in_range(bridge_enemy, 1), "actual NPC capsule follows navigation up ramp before attacking: " + str(actor.feet()))
	world.free()
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(dir)
	print("test_world3d_combat: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
