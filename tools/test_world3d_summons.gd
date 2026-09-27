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
	var dir := preload("res://scripts/world3d/map_paths.gd").cache_directory("summons_%d" % Time.get_ticks_usec())
	var doc := Doc.new()
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(30, 0.2, 30))
	doc.add_box_silent("ramp", Vector3(5, 1, 0), Vector3(8, 0.2, 8), Vector3(0, 0, 10))
	var enemy: String = doc.add_npc(Vector3(-6, 0.8, 0), "dummy", "")
	doc._find(enemy).merge({"hostile": true, "hp_max": 1000})
	var path := dir.path_join("map.gltf")
	check(doc.save(path) == OK, "save summon fixture")
	session.world3d_map_path = path
	session.world3d_spawn = Vector3(0, 0.9, 4)
	var world = load("res://scenes/world_3d.tscn").instantiate()
	root.add_child(world)
	while not world.is_world_ready(): await process_frame
	world._combat.set_physics_process(false)
	world._player.set_physics_process(false)
	server.inventory.clear()
	check(not server.try_pet_summon().ok, "summon requires whistle")
	server.inventory.add_item("pet_whistle", 1)
	world._player.position = Vector3(100, 0.9, 100)
	check(not world._combat.use_item("pet_whistle").ok and server.inventory.has_item("pet_whistle", 1), "off-navigation summon rejects without consuming whistle")
	world._player.position = session.world3d_spawn
	check(server.try_pet_summon().ok, "HUD facade summons physical companion")
	check(not server.try_pet_summon().ok and server.inventory.has_item("pet_whistle", 1), "repeat summon cannot duplicate companion or consume whistle")
	var id := "summoned_pet"
	check(world._combat.actors[id].feet().distance_to(world._player.position - Vector3.UP * 0.9) >= 1, "summon lands outside player capsule")
	var pet_state: Dictionary = server.snapshot_pet()
	check(pet_state.active and pet_state.resident and pet_state.position_m is Vector3 and not pet_state.has("cell"), "pet query returns current meter-space state")
	var pet = world._combat.actors[id]
	pet.position = Vector3(-4, 0.9, 0)
	world._combat.selected = enemy
	var hp: int = server.combat_stats.npcs[enemy].hp
	server.pet_assist = true
	await physics_frame
	world._combat.summons.tick(1.5)
	check(server.combat_stats.npcs[enemy].hp < hp, "pet assist uses shared combat damage")
	hp = server.combat_stats.npcs[enemy].hp
	pet.position.y += 3
	world._combat.summons.tick(1.5)
	check(server.combat_stats.npcs[enemy].hp == hp, "pet assist cannot attack across floors")
	pet.position.y -= 3
	server.combat_stats.npcs[id].hp = 7
	check(await world.transfer_map(path, Vector3(2, 0.9, 5)), "summoned companion follows map transfer")
	world._combat.set_physics_process(false)
	check(world._combat.actors.has(id) and int(server.combat_stats.npcs[id].hp) == 7, "transfer preserves one pet and HP")
	check(server.try_pet_dismiss().ok and not world._combat.actors.has(id), "dismiss removes pet collider and session record")
	check(server.try_use_item("pet_whistle").ok and int(server.combat_stats.npcs[id].hp) == 7, "dismiss and resummon cannot heal pet for free")
	check(server.try_pet_dismiss().ok, "dismiss before slope summon")
	world._player.position = Vector3(5, 1 + 0.1 / cos(deg_to_rad(10)) + 0.9, 0)
	await physics_frame
	check(server.try_pet_summon().ok, "summon can land on an inclined navigation surface")
	var slope_feet: Vector3 = world._combat.actors[id].feet()
	var expected_height := 1 + (slope_feet.x - 5) * tan(deg_to_rad(10)) + 0.1 / cos(deg_to_rad(10))
	check(absf(slope_feet.y - expected_height) < 0.01, "summoned feet match physical slope height")
	world._player.position = Vector3(2, 0.9, 5)
	server.party_id = "test_party"
	server._party_members = [{"id": server._party_self_id(), "name": "self"}, {"id": "friend", "name": "Friend", "online": true}]
	server.item_catalog.register_item({"id": "test_summon", "type": "consumable", "use_effect": "party_summon", "cooldown": 0})
	server.inventory.add_item("test_summon", 2)
	check(world._combat.use_item("test_summon").ok and server.inventory.has_item("test_summon", 1), "party invite consumes exactly one item")
	var invitation: Dictionary = server.snapshot_party_summon()
	check(invitation.active and invitation.invites.has("friend") and invitation.caster_position_m is Vector3, "party query exposes current 3D invitation")
	check(server.try_party_summon_accept("friend").ok, "mock teammate accepts into a valid three-dimensional landing")
	check(not server.try_party_summon_accept("friend").ok and world._combat.actors.has("summoned_party_friend"), "accepted invitation cannot duplicate actor")
	check(not world._combat.use_item("test_summon").ok and server.inventory.has_item("test_summon", 1), "no eligible recipients does not consume item")
	world._combat.summons.remove("summoned_party_friend")
	check(world._combat.use_item("test_summon").ok, "new party invite starts after prior completion")
	world._combat.summons.pending.expires = -1
	check(not server.try_party_summon_accept("friend").ok, "expired invite cannot spawn actor")
	server.inventory.add_item("test_summon", 1)
	check(world._combat.use_item("test_summon").ok and server.try_party_summon_decline("friend").ok, "recipient can decline an invitation")
	check(not server.try_party_summon_accept("friend").ok, "declined invitation cannot be accepted again")
	server.inventory.add_item("test_summon", 1)
	check(world._combat.use_item("test_summon").ok, "create invite before party change")
	server.party_id = "different_party"
	check(not server.try_party_summon_accept("friend").ok and not server.snapshot_party_summon().active, "changing parties invalidates pending invitation")
	world.free()
	check(server.world3d_summons.get_ref() == null, "summon facade does not retain freed scene")
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(dir)
	print("test_world3d_summons: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
