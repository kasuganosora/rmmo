extends SceneTree
## Undo, separate residency, one-way import loss, and a one-shot gather.

const Document = preload("res://scripts/world3d/world_document.gd")
const Residency = preload("res://scripts/world3d/world_residency.gd")
const Import = preload("res://scripts/world3d/world_import.gd")
const Travel = preload("res://scripts/world3d/world_travel.gd")
const Startup = preload("res://scripts/world3d/startup_profile.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var failed := 0
	var doc = Document.new()
	doc.add_box("ground", Vector3.ZERO, Vector3.ONE)
	var added: String = doc.add_box("block", Vector3(1, 1, 1), Vector3.ONE)
	failed += _expect(doc.undo() and not doc.has_uuid(added), "undo removes the last box")
	failed += _expect(doc.records.size() == 1, "the earlier box stays")
	var records := [
		{"uuid": "near", "position": [0, 0, 0]},
		{"uuid": "mid", "position": [70, 0, 0]},
		{"uuid": "far", "position": [200, 0, 0]},
	]
	var bands: Dictionary = Residency.classify(Vector3.ZERO, records)
	failed += _expect(bands.render.has("near") and bands.collision.has("near"), "nearby object is drawn and solid")
	failed += _expect(not bands.render.has("mid") and bands.collision.has("mid"), "mid object keeps collision without a mesh")
	failed += _expect(not bands.collision.has("far"), "far object is not loaded yet")
	var host := Node3D.new()
	root.add_child(host)
	var map := Node3D.new()
	host.add_child(map)
	_box(map, "near", Vector3.ZERO)
	_box(map, "mid", Vector3(70, 0, 0))
	_box(map, "far", Vector3(200, 0, 0))
	Residency.sync(map, host, Vector3.ZERO)
	var near := map.get_node_or_null("near") as MeshInstance3D
	var mid := map.get_node_or_null("mid") as MeshInstance3D
	failed += _expect(near != null and near.visible and host.get_node_or_null("near_body") != null, "sync draws and solids the nearby mesh")
	failed += _expect(mid != null and not mid.visible and host.get_node_or_null("mid_body") != null, "sync keeps the mid mesh solid and hidden")
	failed += _expect(map.get_node_or_null("far") == null and host.get_node_or_null("far_body") == null, "sync does not load the far mesh or its body")
	host.free()
	failed += await _scene_residency()
	var imported: Dictionary = Import.import_row([true, false])
	failed += _expect(int(imported.one_way_lost) == 1, "one-way edge is reported")
	failed += _expect(imported.boxes.size() == 1, "only the walkable cell becomes ground")
	var travel = Travel.new()
	failed += _expect(travel.gather("herb") == "采到了草药", "first gather")
	failed += _expect(travel.gather("herb") == "这里已经采过", "gather does not repeat")
	failed += _expect(Startup.current() == Startup.PROFILE_3D, "shipped profile is the 3D world")
	failed += _expect(Startup.startup_scene() == "res://scenes/world_3d.tscn", "startup scene is the 3D world")
	failed += _expect(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/login.tscn", "boot keeps login before selected world profile")
	var world2d = load(Startup.SCENE_2D)
	failed += _expect(world2d is PackedScene, "the 2D world scene still loads")
	if world2d is PackedScene:
		var world = (world2d as PackedScene).instantiate()
		failed += _expect(world != null, "the 2D world still instantiates")
		if world != null:
			world.free()
	print("startup_profile=%s" % Startup.current())
	print("startup_scene=%s" % Startup.startup_scene())
	print("main_scene=%s" % str(ProjectSettings.get_setting("application/run/main_scene")))
	print("world2d_scene=%s" % Startup.SCENE_2D)
	print("test_world3d_rest: %s" % ("FAIL %d" % failed if failed else "PASS"))
	quit(1 if failed else 0)


func _scene_residency() -> int:
	var session = root.get_node("GameSession")
	session.world3d_map_path = ""
	session.world3d_spawn = Vector3.ZERO
	var packed := load("res://scenes/world_3d.tscn") as PackedScene
	if packed == null:
		print("test_world3d_rest: FAIL world_3d scene missing")
		return 1
	change_scene_to_packed(packed)
	var world: Node = null
	for _i in 90:
		await process_frame
		world = current_scene
		if world != null and world.get("_player") != null and not world._player.input_locked:
			break
	if world == null or world.get("_map_root") == null or world._player == null:
		print("test_world3d_rest: FAIL world_3d did not finish loading")
		return 1
	world._player.global_position = Vector3.ZERO
	_box(world._map_root, "mid_probe", Vector3(70, 0, 0))
	_box(world._map_root, "far_probe", Vector3(200, 0, 0))
	world._apply_residency()
	var mid := world._map_root.get_node_or_null("mid_probe") as MeshInstance3D
	var failed := 0
	failed += _expect(mid == null and world.get_node_or_null("mid_probe_body") != null, "play path keeps 70 m solid without a visual")
	failed += _expect(world._map_root.get_node_or_null("far_probe") == null and world.get_node_or_null("far_probe_body") == null, "play path does not load 200 m")
	return failed


func _box(parent: Node, box_name: String, at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = box_name
	var shape := BoxMesh.new()
	shape.size = Vector3.ONE
	mesh.mesh = shape
	mesh.position = at
	parent.add_child(mesh)


func _expect(ok: bool, label: String) -> int:
	if not ok:
		print("test_world3d_rest: FAIL %s" % label)
		return 1
	return 0
