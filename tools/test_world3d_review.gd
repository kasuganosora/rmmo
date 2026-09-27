extends SceneTree
## Regression coverage for runtime paths found in the 3D migration review.

const Document = preload("res://scripts/world3d/world_document.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const Stream = preload("res://scripts/world3d/world_stream.gd")
const Travel = preload("res://scripts/world3d/world_travel.gd")
const Motion = preload("res://scripts/world3d/world_motion.gd")
var failed := 0


func _init() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failed += 1


func _run() -> void:
	preload("res://tools/world3d_test_character.gd").ensure(self)
	check(not Travel.near(Vector3(0, 3.9, 0), Vector3(0, 0.1, 0), 1.2), "bridge does not trigger ground warp")
	check(Motion.approach(Vector3.ZERO, Vector3(0.06, 0, 0), 4, 0.1).is_equal_approx(Vector3(0.06, 0, 0)), "click approach cannot overshoot")
	var doc = Document.new()
	doc.map_meta["custom"] = {"uri": "not_a_dependency"}
	doc.add_box("ground", Vector3.ZERO, Vector3(400, 0.2, 4))
	doc.add_box("block", Vector3(110, 1, 0), Vector3.ONE)
	doc.add_box("block", Vector3(210, 1, 0), Vector3.ONE)
	var host := Node3D.new()
	root.add_child(host)
	var view: Node3D = doc.build()
	host.add_child(view)
	Stream.sync(view, host, Vector3(160, 0, 0))
	check(view.get_node_or_null("obj_1") != null and host.get_node_or_null("obj_1_body") != null, "large ground overlaps resident chunks despite distant center")
	Stream.sync(view, host, Vector3(210, 0, 0), 1)
	Stream.sync(view, host, Vector3(210, 0, 0), 1)
	Stream.sync(view, host, Vector3.ZERO)
	check(host.get_node_or_null("obj_3_body") == null, "interrupted chunk queue removes stale bodies")
	host.free()
	var transformed := Node3D.new()
	root.add_child(transformed)
	var parent := Node3D.new()
	parent.position = Vector3(100, 0, 0)
	transformed.add_child(parent)
	var nested := MeshInstance3D.new()
	nested.name = "nested"
	nested.mesh = BoxMesh.new()
	nested.scale = Vector3(2, 1, 3)
	parent.add_child(nested)
	Stream.sync(transformed, transformed, Vector3(100, 0, 0))
	var nested_bodies: Dictionary = transformed.get_meta("stream_bodies", {})
	check(nested_bodies.size() == 1 and nested_bodies.values()[0].global_position.is_equal_approx(Vector3(100, 0, 0)) and nested_bodies.values()[0].global_basis.get_scale().is_equal_approx(Vector3(2, 1, 3)), "nested glTF transform and scale survive residency")
	transformed.free()
	var dir := preload("res://scripts/world3d/map_paths.gd").cache_directory("review_%d" % Time.get_ticks_usec())
	check(dir != "", "external test directory")
	if dir == "":
		quit(1)
		return
	var path := dir.path_join("map.gltf")
	check(doc.save(path) == OK, "save ignores extras.uri as a dependency")
	var reopened = Document.open_file(path)
	check(reopened != null and JSON.parse_string(JSON.stringify(reopened.records)) == JSON.parse_string(JSON.stringify(doc.records)), "full document reload preserves every record")
	if reopened != null:
		var id: String = reopened.add_box("ground", Vector3(1.125, 0, 0), Vector3.ONE)
		check(id == "obj_4", "reload does not reuse UUIDs")
		check(reopened.save(path) == OK, "overwrite document succeeds")
		var again = Document.open_file(path)
		check(again != null and again.records.size() == 4, "second save persists edits")
	var legacy := doc.build()
	legacy.get_meta("extras").erase("rmmo_records")
	check(Io.save_scene_atomic(legacy, path) == OK, "save legacy box document")
	legacy.free()
	var recovered = Document.open_file(path)
	check(recovered != null and recovered.records.size() == doc.records.size(), "previous prototype documents reopen without data loss")
	await _runtime_motion(dir)
	Io._remove_tree(dir)
	print("test_world3d_review: %s" % ("PASS" if failed == 0 else "FAIL %d" % failed))
	quit(0 if failed == 0 else 1)


func _runtime_motion(dir: String) -> void:
	var session = root.get_node("GameSession")
	session.world3d_map_path = ""
	session.world3d_spawn = Vector3(0, 0.9, 4)
	var scene = load("res://scenes/world_3d.tscn").instantiate()
	root.add_child(scene)
	for i in 5:
		await physics_frame
	var player = scene._player
	check(player != null, "actual 3D scene boots")
	if player == null:
		scene.free()
		return
	while player.input_locked:
		await process_frame
	var around: Dictionary = scene._navigation.find_path(Vector3(6, 0, 2), Vector3(10, 0, 2))
	check(bool(around.get("ok")) and around["path"].size() > 2, "native navigation routes around the wall")
	var bridge: Dictionary = scene._navigation.find_path(Vector3(0, 0, -2), Vector3(0, 3, -2))
	check(bool(bridge.get("ok")) and bridge["path"].size() > 2 and bridge["path"][-1].is_equal_approx(Vector3(0, 3, -2)), "overlapping bridge and ground connect through ramp, preserving exact goal")
	check(not root.get_node("MockServer").try_move_world(-1, Vector3.ONE, 4).get("ok", true), "authority rejects replayed movement intent")
	if OS.get_cmdline_user_args().has("--capture"):
		for i in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := preload("res://scripts/asset/art_paths.gd").review_path("world3d_review.png")
		root.get_texture().get_image().save_png(screenshot)
		print("review_screenshot=" + screenshot)
	var old_ticks := Engine.physics_ticks_per_second
	var distances: Array[float] = []
	for ticks in [30, 60, 120]:
		Engine.physics_ticks_per_second = ticks
		for i in 4:
			await physics_frame
		player.global_position = Vector3(-10, 0.9, 4)
		player.velocity = Vector3.ZERO
		player.click_target = null
		await physics_frame
		player.set_click_target(Vector3(-10, 0, -15), "ground")
		var start: Vector3 = player.global_position
		for i in ticks:
			await physics_frame
		distances.append(Vector2(start.x, start.z).distance_to(Vector2(player.global_position.x, player.global_position.z)))
		player.click_target = null
	check(absf(distances[0] - 4) < 0.15 and absf(distances[1] - 4) < 0.15 and absf(distances[2] - 4) < 0.15, "real body moves 4 m at 30/60/120 physics Hz: %s" % str(distances))
	for i in 10:
		await physics_frame
	var feet_y: float = player.global_position.y + player.get_node("CharacterModel3D").position.y
	check(absf(feet_y) < 0.02, "visual feet agree with collision floor")
	check(absf(player.location().position_m.y - feet_y) < 0.001, "WorldLocation reports feet rather than capsule center")
	Engine.physics_ticks_per_second = 60
	player.global_position = Vector3(6, 0.9, 2)
	await physics_frame
	player.set_click_target(Vector3(10, 0, 2), "ground")
	for i in 300:
		await physics_frame
		if player.click_target == null:
			break
	check(player.global_position.distance_to(Vector3(10, 0.9, 2)) < 0.15, "real capsule follows route around wall")
	player.global_position = Vector3(0, 0.9, -2)
	await physics_frame
	player.set_click_target(Vector3(0, 3, -2), "bridge_deck")
	for i in 600:
		await physics_frame
		if player.click_target == null:
			break
	check(player.global_position.distance_to(Vector3(0, 3.9, -2)) < 0.2, "real capsule reaches upper bridge via ramp: %s" % player.global_position)
	player.click_target = null
	var target := dir.path_join("inn.gltf")
	check(Document.make_inn("").save(target) == OK, "prepare actual warp target")
	var warp := StaticBody3D.new()
	warp.set_meta("kind", "warp")
	warp.set_meta("center", Vector3(player.global_position.x, 0.1, player.global_position.z))
	warp.set_meta("target_path", target)
	warp.set_meta("spawn", [1.125, 0.9, 3.375])
	scene.add_child(warp)
	player.global_position.y = 3.9
	await scene._poll_warp()
	check(scene._map_path != target, "actual bridge-height player cannot warp through floor")
	player.global_position.y = 0.9
	await scene._poll_warp()
	check(scene._map_path == target and player.global_position.is_equal_approx(Vector3(1.125, 0.9, 3.375)), "actual transfer preserves fractional spawn")
	check(player.map_ref == "prototype/inn", "map identity updates during transfer")
	warp.free()
	Engine.physics_ticks_per_second = old_ticks
	scene.free()
