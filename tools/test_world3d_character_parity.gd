extends SceneTree
const Model = preload("res://scripts/char/character_model_3d.gd")
const View = preload("res://scripts/char/character_view_3d.gd")
const Rig = preload("res://scripts/char/character_imported_rig.gd")
var failed := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failed += 1
func run() -> void:
	var session = root.get_node("GameSession")
	var server = root.get_node("MockServer")
	var login = load("res://scenes/login.tscn").instantiate()
	root.add_child(login)
	var has_shortcut := false
	for button in login.find_children("*", "Button", true, false):
		if button.text in ["3D 试玩", "3D 编辑"]: has_shortcut = true
	check(not has_shortcut, "homepage exposes normal login without 3D bypass buttons")
	login.free()
	check(not session.has_active_character(), "empty session has no invented appearance")
	var rejected = load("res://scenes/world_3d.tscn").instantiate()
	root.add_child(rejected)
	check(rejected.is_world_ready() and rejected._player == null, "direct world entry without character does not invent a male body")
	rejected.free()
	server.login("character_parity", "test", "local")
	await server.login_finished
	var custom := Customization.new().to_dict()
	custom["part_ids"] = {"Body": 1, "FrontHair1": 15, "Eyes": 1}
	custom["bust_size"] = 0.65
	custom["eye_color"] = "#5276a5"
	server.create_character("统一人物", "warrior", "1", "female", custom)
	var created: Array = await server.character_created
	check(bool(created[0]), "create character through shared account service")
	session.selected_character = created[2]
	check(not session.has_world3d_snapshot(), "selected character requires authoritative equipment snapshot before playtest")
	server.enter_world3d(int(created[2].id))
	var entered: Array = await server.enter_world_ready
	check(bool(entered[0]), "normal world entry supplies appearance and equipment")
	session.spawn_data = entered[2]
	check(session.has_world3d_snapshot(), "preview can reuse the same authoritative snapshot")
	var character: Dictionary = session.active_character()
	var parts := View.equipment_parts(character.gender, session.spawn_data.equipment, server.item_catalog)
	var doc := preload("res://scripts/world3d/world_document.gd").new()
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(20, 0.2, 20))
	var dir := preload("res://scripts/world3d/map_paths.gd").cache_directory("body_parity_%d" % Time.get_ticks_usec())
	var path := dir.path_join("map.gltf")
	check(doc.save(path) == OK, "save isolated actor parity map")
	session.world3d_map_path = path
	session.world3d_spawn = Vector3(0, 0.9, 0)
	var world = load("res://scenes/world_3d.tscn").instantiate()
	root.add_child(world)
	while not world.is_world_ready(): await process_frame
	world._player.set_physics_process(false)
	world.set_process(false)
	var actor = world._player._model
	actor.set_process(false)
	actor.pose_at(0)
	var preview := View.new()
	root.add_child(preview)
	preview.configure(character.gender, character.customization, parts)
	preview.set_process(false)
	preview.model.set_process(false)
	preview.model.pose_at(0)
	var npc := Model.create_npc({"gender": character.gender, "customization": character.customization, "equipment": parts})
	root.add_child(npc)
	npc.set_process(false)
	npc.pose_at(0)
	for other in [preview.model, npc]:
		check(actor.body_type == other.body_type and actor.appearance == other.appearance and actor.equipment == other.equipment, "player preview and NPC share exact appearance and equipment recipe")
		check(actor.imported_rig != null and other.imported_rig != null and actor.rig.scale.is_equal_approx(other.rig.scale), "all entrances use the imported approved rig at the same proportions")
		var same: bool = actor.skeleton.get_bone_count() == other.skeleton.get_bone_count()
		for category in actor.gear:
			if actor.gear[category].size() != other.gear[category].size(): same = false; continue
			for i in actor.gear[category].size():
				var a: MeshInstance3D = actor.gear[category][i]
				var b: MeshInstance3D = other.gear[category][i]
				var geometry_equal: bool = a.mesh == b.mesh or a.mesh.get_faces() == b.mesh.get_faces()
				if not geometry_equal or a.visible != b.visible: print("MISMATCH ", category, " ", a.name, " geometry=", geometry_equal, " visibility=", a.visible, "/", b.visible)
				same = same and geometry_equal and a.visible == b.visible
		check(same, "same recipe retains identical mesh geometry and garment visibility")
	var female_path := Rig.source_path("female")
	check(female_path.ends_with("characters/imported/female/character.glb") and Rig.source_path("male").ends_with("characters/imported/male/character.glb"), "adult source paths never fall back to old Artoria or blockout assets")
	print("APPROVED_BODY=", female_path, " SHA256=", FileAccess.get_sha256(female_path))
	var original: Dictionary = session.selected_character.duplicate(true)
	session.selected_character = {"id": 999999, "gender": "male", "customization": {}}
	check(session.active_character().id == 999999 and not session.has_world3d_snapshot(), "stale spawn snapshot cannot replace a newly selected character")
	session.selected_character = original
	await process_frame
	await process_frame
	npc.free()
	preview.free()
	world.free()
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(dir)
	print("test_world3d_character_parity: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
