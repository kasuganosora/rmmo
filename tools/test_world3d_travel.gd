extends SceneTree
## A missing target map does not commit, and a second talk is a different line.

const Travel = preload("res://scripts/world3d/world_travel.gd")
const Document = preload("res://scripts/world3d/world_document.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const JsonUtil = preload("res://scripts/util/json_util.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var failed := 0
	var stayed: Dictionary = Travel.commit("res://old", "res://missing", false)
	failed += _expect(not bool(stayed.get("ok", true)) and str(stayed.get("path", "")) == "res://old", "missing target keeps the current map")
	var moved: Dictionary = Travel.commit("res://old", "res://inn", true)
	failed += _expect(bool(moved.get("ok", false)) and str(moved.get("path", "")) == "res://inn", "existing target commits")
	var manifest := _content_manifest()
	var before := FileAccess.get_file_as_bytes(manifest) if manifest != "" else PackedByteArray()
	var talk = Travel.new()
	failed += _expect(talk.talk("guide") == "你好", "first talk")
	failed += _expect(talk.talk("guide") == "已经谈过了", "second talk does not repeat the introduction")
	var session = root.get_node("GameSession")
	session.world3d_switches = {}
	var npc := StaticBody3D.new()
	npc.set_meta("kind", "npc")
	npc.set_meta("npc_id", "guide")
	npc.set_meta("line", "桥在北边，坡道可以上去。")
	npc.set_meta("center", Vector3.ZERO)
	var first = session.world3d_travel()
	failed += _expect(Travel.interact_at(first, Vector3.ZERO, [npc]) == "桥在北边，坡道可以上去。", "scene talk uses the session bag")
	var reloaded = session.world3d_travel()
	failed += _expect(Travel.interact_at(reloaded, Vector3.ZERO, [npc]) == "已经谈过了", "talk survives a map reload")
	var herb := StaticBody3D.new()
	herb.set_meta("kind", "gather")
	herb.set_meta("node_id", "herb")
	herb.set_meta("center", Vector3(1, 0, 0))
	failed += _expect(Travel.interact_at(reloaded, Vector3(1, 0, 0), [herb]) == "采到了草药", "scene gather")
	var after_warp = session.world3d_travel()
	failed += _expect(Travel.interact_at(after_warp, Vector3(1, 0, 0), [herb]) == "这里已经采过", "gather survives a map reload")
	npc.free()
	herb.free()
	failed += await _scene_round_trip(manifest, before)
	var after := FileAccess.get_file_as_bytes(manifest) if manifest != "" else PackedByteArray()
	failed += _expect(manifest != "" and before == after, "talk and gather do not rewrite the content manifest")
	var yard_dir := Paths.cache_directory("p4_test_yard")
	var inn_dir := Paths.cache_directory("p4_test_inn")
	failed += _expect(yard_dir != "" and inn_dir != "", "external directories")
	if yard_dir == "":
		quit(1)
		return
	var yard := yard_dir.path_join("map.gltf")
	var inn := inn_dir.path_join("map.gltf")
	failed += _expect(Document.sample_yard(inn).save(yard) == OK, "save yard")
	failed += _expect(Document.make_inn(yard).save(inn) == OK, "save inn")
	var loaded := Io.load_scene(yard)
	var warp := _kind(loaded, "warp")
	failed += _expect(warp != null and str(Io.extras_of(warp).get("target_path", "")) == inn, "yard warp points at the inn")
	if loaded != null:
		loaded.free()
	_remove_dir(yard_dir)
	_remove_dir(inn_dir)
	print("test_world3d_travel: %s" % ("FAIL %d" % failed if failed else "PASS"))
	quit(1 if failed else 0)


func _scene_round_trip(manifest: String, before: PackedByteArray) -> int:
	var session = root.get_node("GameSession")
	session.world3d_switches = {}
	session.world3d_map_path = ""
	session.world3d_spawn = Vector3(0, 0.9, 4)
	session.editor_return = false
	var world = await _boot_world()
	if world == null:
		print("test_world3d_travel: FAIL yard did not boot")
		return 1
	var failed := 0
	var herb := _kind_body(world, "gather")
	failed += _expect(herb != null, "sample yard has a gather spot")
	if herb == null:
		return failed
	world._player.global_position = herb.get_meta("center")
	_press_e(world)
	failed += _expect(world._status.text == "采到了草药", "E on the yard gather spot")
	_press_e(world)
	failed += _expect(world._status.text == "这里已经采过", "second E on the gather spot")
	var guide := _kind_body(world, "npc")
	failed += _expect(guide != null, "sample yard has the guide")
	if guide == null:
		return failed
	world._player.global_position = guide.get_meta("center")
	_press_e(world)
	failed += _expect(world._status.text == "桥在北边，坡道可以上去。", "E talks to the guide")
	var warp := _kind_body(world, "warp")
	failed += _expect(warp != null, "sample yard has a warp")
	if warp == null:
		return failed
	world._player.global_position = warp.get_meta("center")
	world._poll_warp()
	var inn = await _boot_wait()
	failed += _expect(inn != null and str(inn._map_path).contains("p4_inn"), "go_world_3d loads the inn")
	if inn == null:
		return failed
	var back := _kind_body(inn, "warp")
	failed += _expect(back != null, "inn has a return warp")
	if back == null:
		return failed
	inn._player.global_position = back.get_meta("center")
	inn._poll_warp()
	var yard = await _boot_wait()
	failed += _expect(yard != null and str(yard._map_path).contains("p4_yard"), "go_world_3d returns to the yard")
	if yard == null:
		return failed
	var guide_again := _kind_body(yard, "npc")
	yard._player.global_position = guide_again.get_meta("center")
	_press_e(yard)
	failed += _expect(yard._status.text == "已经谈过了", "guide stays talked after yard to inn to yard")
	var after := FileAccess.get_file_as_bytes(manifest) if manifest != "" else PackedByteArray()
	failed += _expect(manifest != "" and before == after, "the scene round trip does not rewrite content.json")
	return failed


func _boot_world() -> Node:
	change_scene_to_file("res://scenes/world_3d.tscn")
	return await _boot_wait()


func _boot_wait() -> Node:
	for _i in 120:
		await process_frame
		var world := current_scene
		if world != null and world.get("_player") != null and not world._player.input_locked and str(world._map_path) != "":
			return world
	return null


func _kind_body(world: Node, kind: String) -> Node:
	for child in world.get_children():
		if str(child.get_meta("kind", "")) == kind:
			return child
	return null


func _press_e(world: Node) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.pressed = true
	world._unhandled_input(event)


func _content_manifest() -> String:
	var path := JsonUtil.content_root().path_join("content.json")
	return path if FileAccess.file_exists(path) else ""


func _kind(root: Node, kind: String) -> Node:
	if root == null:
		return null
	var extras := Io.extras_of(root)
	if str(extras.get("kind", "")) == kind:
		return root
	for child in root.get_children():
		var found := _kind(child, kind)
		if found != null:
			return found
	return null


func _expect(ok: bool, label: String) -> int:
	if not ok:
		print("test_world3d_travel: FAIL %s" % label)
		return 1
	return 0


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
