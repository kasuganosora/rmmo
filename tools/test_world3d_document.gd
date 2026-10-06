extends SceneTree
## A record that is not in the current view is still written and read back.

const Document = preload("res://scripts/world3d/world_document.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var doc = Document.new()
	var kept: String = doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(4, 0.2, 4))
	var view: Node3D = doc.build()
	view.get_child(0).free()
	var hidden: String = doc.add_box("block", Vector3(1.25, 1, -2.5), Vector3(0.4, 2, 2))
	var dir := Paths.cache_directory("p3_document")
	failed += _expect(dir != "", "external content root")
	if dir == "":
		quit(1)
		return
	var path := dir.path_join("map.gltf")
	var err: Error = doc.save(path)
	view.free()
	failed += _expect(err == OK, "atomic save")
	var loaded := Io.load_scene(path)
	failed += _expect(loaded != null, "reload")
	if loaded != null:
		failed += _expect(Io.find_named(loaded, kept) != null, "existing record survived")
		var hidden_node := Io.find_named(loaded, hidden)
		failed += _expect(hidden_node != null, "record absent from the view was saved")
		if hidden_node != null:
			var extras := Io.extras_of(hidden_node)
			failed += _expect(str(extras.get("uuid", "")) == hidden, "uuid roundtrip")
			failed += _expect(hidden_node.position.distance_to(Vector3(1.25, 1, -2.5)) <= 0.001, "decimal position roundtrip")
		loaded.free()
	_remove_dir(dir)
	print("test_world3d_document: %s" % ("FAIL %d" % failed if failed else "PASS"))
	quit(1 if failed else 0)


func _expect(ok: bool, label: String) -> int:
	if not ok:
		print("test_world3d_document: FAIL %s" % label)
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
