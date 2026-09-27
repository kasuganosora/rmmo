extends SceneTree
var failed := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failed += 1

func run() -> void:
	var server = root.get_node("MockServer")
	var session = root.get_node("GameSession")
	server.login("review3d", "test", "local")
	await server.login_finished
	server.create_character("三维角色", "warrior", "1", "female", {"hair_color": "#884433"})
	var created: Array = await server.character_created
	check(bool(created[0]), "create real account character")
	var ch: Dictionary = created[2]
	session.selected_character = ch
	session.world3d_map_path = ""
	session.world3d_spawn = Vector3(0, 0.9, 4)
	session.loading_mode = ""
	change_scene_to_file("res://scenes/loading.tscn")
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:
			break
	var world = current_scene
	check(world != null and world.has_method("is_world_ready"), "login Loading hands off to 3D world")
	if world == null or not world.has_method("is_world_ready"):
		quit(1)
		return
	check(world._player != null and not world._player.input_locked, "controls unlock after prepared world")
	check(world._player.get_node("CharacterModel3D").body_type == "female", "selected body type preserved")
	check(world._player.character.get("customization", {}) == ch.get("customization", {}), "customization preserved")
	check(not session.spawn_data.has("cell") and session.spawn_data.get("world_mode") == "world3d", "3D spawn does not carry integer grid coordinates")
	check(world._hud != null and not session.spawn_data.get("equipment", []).is_empty(), "shared HUD and starter equipment initialized")
	var events = server.world3d_events
	var money: int = server.inventory.get_gold()
	var spec := {"uuid": "reward", "position": Vector3.ZERO, "extras": {"kind": "npc", "event": {"pages": [
		{"commands": [{"op": "give_gold", "amount": 7}, {"op": "set_self_switch", "letter": "A"}]},
		{"when": {"self_switch": "A"}, "commands": [{"op": "text", "text": "已领取"}]},
	]}}}
	events.mount("test/one", [spec])
	world.apply_actions(events.runtime.run_event("reward", events.context()))
	check(server.inventory.get_gold() == money + 7, "event commands mutate real inventory")
	events.mount("test/two", [spec])
	check(not events.runtime.get_self_switch("reward", "A"), "self-switch is namespaced by map")
	events.mount("test/one", [spec])
	world.apply_actions(events.runtime.run_event("reward", events.context()))
	check(server.inventory.get_gold() == money + 7, "returning to map does not duplicate reward")
	check(world._status.text == "已领取", "event page conditions use persisted self-switch")
	var trigger_mesh := BoxMesh.new()
	trigger_mesh.size = Vector3(1, 0.2, 1)
	var trigger := {"uuid": "touch", "position": Vector3.ZERO, "transform": Transform3D.IDENTITY, "mesh": trigger_mesh, "extras": {"kind": "event", "event": {"pages": [{"trigger": "player_touch", "commands": [{"op": "give_gold", "amount": 3}]}]}}}
	events.mount("test/touch", [trigger])
	money = server.inventory.get_gold()
	events.touch_segment(Vector3(-2, 3, 0), Vector3(2, 3, 0))
	check(server.inventory.get_gold() == money, "touch event does not trigger across floors")
	events.touch_segment(Vector3(-2, 0, 0), Vector3.ZERO)
	events.touch_segment(Vector3.ZERO, Vector3(0.1, 0, 0))
	check(server.inventory.get_gold() == money + 3, "swept touch event triggers once per entry")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		var path := preload("res://scripts/asset/art_paths.gd").review_path("world3d_flow.png")
		root.get_texture().get_image().save_png(path)
		print("capture=" + path)
	world.free()
	await process_frame
	await process_frame
	print("test_world3d_flow: %s" % ("PASS" if failed == 0 else "FAIL %d" % failed))
	quit(0 if failed == 0 else 1)
