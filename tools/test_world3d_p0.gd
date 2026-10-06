extends SceneTree
## P0: meter location contract and an external 1 m glTF roundtrip. Does not change the default world.

const WorldLocation = preload("res://scripts/world3d/world_location.gd")
const WorldMapPaths = preload("res://scripts/world3d/map_paths.gd")
const GltfMapIo = preload("res://scripts/world3d/gltf_map_io.gd")

const FEET := Vector3(12.375, 0.180, -7.625)
const SURFACE := "bridge_deck"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _expect(WorldLocation.chunk_index(-0.01, 0.0, 32.0) == -1, "negative chunk uses floor")
	failed += _expect(WorldLocation.chunk_index(0.0, 0.0, 32.0) == 0, "zero stays in chunk 0")
	failed += _expect(not WorldLocation.map_ref_ok("D:/maps/yard"), "map_ref rejects a filesystem path")
	failed += _expect(not WorldLocation.map_ref_ok("../pack/map"), "map_ref rejects dot segments")
	var bad = WorldLocation.make("p0/calibrate", Vector3(NAN, 0.0, 0.0), SURFACE)
	failed += _expect(not bad.valid(), "NaN position is rejected")
	var loc = WorldLocation.make("p0/calibrate", FEET, SURFACE)
	failed += _expect(loc.valid(), "decimal location is valid")
	var restored = WorldLocation.from_dictionary(loc.to_dictionary())
	failed += _expect(loc.matches(restored, WorldLocation.POSITION_ROUNDTRIP_M), "location dictionary keeps millimeters")

	var fixture := WorldMapPaths.cache_directory("p0_calibrate")
	failed += _expect(not fixture.is_empty(), "external content root is configured")
	if fixture.is_empty():
		quit(1)
		return
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var fixture_key := fixture.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	failed += _expect(fixture_key != project and not fixture_key.begins_with(project + "/"), "fixture stays outside the project")

	var gltf_path := fixture.path_join("map.gltf")
	var built := _calibration_scene()
	root.add_child(built)
	var expected_child: Vector3 = built.get_node("scaled_parent/scaled_child").global_position
	var expected_feet: Vector3 = built.get_node("feet").global_position
	var save_err := GltfMapIo.save_scene(built, gltf_path)
	built.queue_free()
	failed += _expect(save_err == OK, "save external glTF (%s)" % error_string(save_err))
	failed += _expect(FileAccess.file_exists(gltf_path), "map.gltf exists outside the project")
	if save_err != OK:
		quit(1)
		return

	var loaded := GltfMapIo.load_scene(gltf_path)
	failed += _expect(loaded != null, "load external glTF")
	if loaded == null:
		quit(1)
		return
	root.add_child(loaded)
	var cube := GltfMapIo.find_named(loaded, "cal_cube")
	failed += _expect(cube is MeshInstance3D, "calibration cube survived")
	if cube is MeshInstance3D:
		var size: Vector3 = (cube as MeshInstance3D).get_aabb().size
		failed += _expect(_near(size, Vector3.ONE), "cube stays 1 m, got %s" % size)
	var east := GltfMapIo.find_named(loaded, "marker_east")
	var up := GltfMapIo.find_named(loaded, "marker_up")
	var south := GltfMapIo.find_named(loaded, "marker_south")
	failed += _expect(east != null and _near(east.global_position, Vector3(1, 0, 0)), "east marker stays +X")
	failed += _expect(up != null and _near(up.global_position, Vector3(0, 1, 0)), "up marker stays +Y")
	failed += _expect(south != null and _near(south.global_position, Vector3(0, 0, 1)), "south marker stays +Z")
	var child := GltfMapIo.find_named(loaded, "scaled_child")
	failed += _expect(child != null and _near(child.global_position, expected_child), "parent rotation and scale roundtrip")
	var feet := GltfMapIo.find_named(loaded, "feet")
	failed += _expect(feet != null and _near(feet.global_position, expected_feet), "decimal feet position roundtrip")
	var extras := GltfMapIo.extras_of(feet)
	var feet_loc = WorldLocation.from_dictionary(extras)
	failed += _expect(feet_loc.matches(loc, WorldLocation.POSITION_ROUNDTRIP_M), "extras keep map_ref, surface, and millimeters")
	var root_extras := GltfMapIo.extras_of(loaded)
	if root_extras.is_empty():
		var named := GltfMapIo.find_named(loaded, "rmmo_world")
		root_extras = GltfMapIo.extras_of(named)
	failed += _expect(str(root_extras.get("rmmo_format", "")) == WorldLocation.FORMAT, "format marker survived")
	failed += _expect(int(root_extras.get("rmmo_version", 0)) == WorldLocation.FORMAT_VERSION, "format version survived")
	loaded.queue_free()
	_remove_dir(fixture)
	print("test_world3d_p0: %s" % ("FAIL %d" % failed if failed else "PASS"))
	quit(1 if failed else 0)


func _calibration_scene() -> Node3D:
	var world := Node3D.new()
	world.name = "rmmo_world"
	world.set_meta("extras", {
		"rmmo_format": WorldLocation.FORMAT,
		"rmmo_version": WorldLocation.FORMAT_VERSION,
		"rmmo_unit": "m",
	})
	var cube := MeshInstance3D.new()
	cube.name = "cal_cube"
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	cube.mesh = box
	world.add_child(cube)
	world.add_child(_marker("marker_east", Vector3(1, 0, 0)))
	world.add_child(_marker("marker_up", Vector3(0, 1, 0)))
	world.add_child(_marker("marker_south", Vector3(0, 0, 1)))
	var parent := Node3D.new()
	parent.name = "scaled_parent"
	parent.scale = Vector3(2, 2, 2)
	parent.rotation_degrees = Vector3(0, 90, 0)
	var child := Node3D.new()
	child.name = "scaled_child"
	child.position = Vector3(0.5, 0.25, -0.125)
	parent.add_child(child)
	world.add_child(parent)
	var feet := Node3D.new()
	feet.name = "feet"
	feet.position = FEET
	var loc = WorldLocation.make("p0/calibrate", FEET, SURFACE)
	feet.set_meta("extras", loc.to_dictionary())
	world.add_child(feet)
	return world


func _marker(marker_name: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = marker_name
	node.position = at
	return node


func _near(got: Vector3, want: Vector3) -> bool:
	return got.distance_to(want) <= WorldLocation.POSITION_ROUNDTRIP_M


func _expect(ok: bool, label: String) -> int:
	if not ok:
		print("test_world3d_p0: FAIL %s" % label)
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
