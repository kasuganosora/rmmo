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
	var dir := preload("res://scripts/world3d/map_paths.gd").cache_directory("npc_skills_%d" % Time.get_ticks_usec())
	var doc := Doc.new()
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(30, 0.2, 30))
	var id: String = doc.add_npc(Vector3(0, 0.8, 0), "mage", "")
	doc._find(id).merge({"hostile": true, "skills": ["test_bolt"], "hp_max": 1000})
	var path := dir.path_join("map.gltf")
	check(doc.save(path) == OK, "save NPC skill list")
	session.world3d_map_path = path
	session.world3d_spawn = Vector3(0, 0.9, 4)
	server.skill_catalog.register_skill({"id": "test_bolt", "effect": "damage", "range": 5, "cast_time": 0.2, "mp_cost": 1, "cooldown": 3, "power": 1})
	server.skill_catalog.register_skill({"id": "test_area", "effect": "aoe_damage", "range": 5, "aoe_radius": 1, "cast_time": 0.2, "mp_cost": 1, "cooldown": 0, "power": 1})
	var world = load("res://scenes/world_3d.tscn").instantiate()
	root.add_child(world)
	while not world.is_world_ready(): await process_frame
	world._combat.set_physics_process(false)
	world._player.set_physics_process(false)
	server.combat_engine.combat_randf = func(): return 0.5
	var combat = world._combat
	check(combat.targets[id].extras.skills == ["test_bolt"], "skill list survives map roundtrip")
	world._player.position.y += 3
	var mp: int = server.combat_stats.npcs[id].mp
	check(not combat.npc_use_skill(id, "test_bolt").ok and server.combat_stats.npcs[id].mp == mp, "cross-floor NPC cast rejected before mana")
	world._player.position.y -= 3
	check(combat.npc_use_skill(id, "test_bolt").ok, "NPC begins shared cast")
	check(not combat.npc_use_skill(id, "test_bolt").ok, "NPC cooldown blocks repeat")
	var hp: int = server.combat_stats.player.hp
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 3, 0.2)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.position = Vector3(0, 1, 2)
	await physics_frame
	await process_frame
	combat._apply({"actions": server.combat_engine.tick_npc_casts(0.3)})
	check(server.combat_stats.player.hp == hp, "wall added during cast prevents damage at resolution")
	wall.free()
	check(combat.npc_use_skill(id, "test_area").ok, "NPC ground cast starts")
	check(combat.actors[id].cast_label.visible and combat._npc_markers.has(id), "NPC cast exposes head label and ground warning")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("rmmo-npc-cast.png"))
	world._player.position.x += 3
	combat._apply({"actions": server.combat_engine.tick_npc_casts(0.3)})
	check(server.combat_stats.player.hp == hp, "player can dodge fixed ground footprint")
	check(not combat.actors[id].cast_label.visible and not combat._npc_markers.has(id), "cast completion clears warning and label")
	for footprint in ["cross", "line", "cone"]:
		server.skill_catalog.register_skill({"id": "shape_" + footprint, "name": footprint, "effect": "aoe_damage", "range": 10, "aoe_radius": 2, "aoe_shape": footprint, "cast_time": 0.2, "mp_cost": 0, "cooldown": 0})
		world._player.position = Vector3(0, 0.9, 4)
		check(combat.npc_use_skill(id, "shape_" + footprint).ok, footprint + " cast begins")
		var mat: ShaderMaterial = combat._npc_markers[id].material_override
		check(int(mat.get_shader_parameter("shape")) == {"cross": 1, "line": 2, "cone": 3}[footprint], footprint + " warning renders matching footprint")
		if OS.get_cmdline_user_args().has("--capture"):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("rmmo-area-" + footprint + ".png"))
		world._player.position = Vector3(2, 0.9, 5)
		var health: int = server.combat_stats.player.hp
		combat._apply({"actions": server.combat_engine.tick_npc_casts(0.3)})
		check(server.combat_stats.player.hp == health, footprint + " excludes point inside outer circle but outside footprint")
		combat._npc_ready.clear()
		world._player.position = Vector3(0, 0.9, 4)
		check(combat.npc_use_skill(id, "shape_" + footprint).ok, footprint + " repeat cast begins")
		world._player.position = Vector3(0, 0.9, 5)
		combat._apply({"actions": server.combat_engine.tick_npc_casts(0.3)})
		check(server.combat_stats.player.hp < health, footprint + " hits inside displayed footprint")
	world._player.position = Vector3(3, 0.9, 4)
	combat._npc_ready.clear()
	check(combat.npc_use_skill(id, "test_bolt").ok, "second bolt starts")
	combat._apply({"actions": server.combat_engine.tick_npc_casts(0.3)})
	check(server.combat_stats.player.hp < hp, "visible NPC cast deals shared damage")
	combat._npc_ready.clear()
	combat._tick_actors(0.01)
	check(server.combat_engine.is_npc_casting(id), "configured NPC AI starts a cast")
	combat.actors[id].position.x = 5
	combat.actors[id].returning = true
	combat._tick_actors(0.01)
	check(not server.combat_engine.is_npc_casting(id), "leashing cancels NPC cast")
	server.inventory.clear()
	server.inventory.add_gold(200)
	server.inventory.add_item("potion_hp_small", 10)
	server.inventory.add_item("wooden_sword", 1)
	server.inventory.set_locked("potion_hp_small", true)
	server.equipment.try_equip_from_bag(server.inventory, "wooden_sword", "weapon_main")
	var durability: int = server.equipment.get_durability("weapon_main")
	server.death_drop_randf = func(): return 0.0
	world._player.position = Vector3(1.234, 0.9, 4.567)
	server.combat_stats.player.hp = 0
	combat._apply({"actions": [{"type": "player_died"}]})
	check(server.inventory.get_gold() == 190 and server.inventory.has_item("potion_hp_small", 10), "death drops shared gold fraction and protects locked items")
	check(combat.loot.size() == 1 and combat.loot[0].feet.is_equal_approx(Vector3(1.234, 0, 4.567)), "death loot uses exact three-dimensional feet")
	check(server.equipment.get_durability("weapon_main") < durability, "death applies equipment durability wear")
	var worn: int = server.equipment.get_durability("weapon_main")
	combat._apply({"actions": [{"type": "player_died"}]})
	check(server.inventory.get_gold() == 190 and combat.loot.size() == 1 and server.equipment.get_durability("weapon_main") == worn, "duplicate death cannot deduct gold or wear twice")
	check(not combat.pickup_nearby(), "dead player cannot recover loot")
	check(not await world.transfer_map(path, session.world3d_spawn), "dead player cannot bypass respawn with map transfer")
	check(combat.respawn(), "respawn after death penalty")
	world._player.position = Vector3(1.234, 0.9, 4.567)
	check(combat.pickup_nearby() and server.inventory.has_item("rusty_coin", 10), "death gold recovers as rusty_coin items under shared rules")
	world.free()
	check(server.combat_engine.npc_casts.is_empty() and not server.combat_engine.spatial_npc_check.is_valid(), "teardown clears NPC casts and spatial callback")
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(dir)
	print("test_world3d_npc_skills: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
