extends SceneTree
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const Stream = preload("res://scripts/world3d/world_stream.gd")
var failed := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failed += 1
func box(parent: Node, name_: String, pos: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name_
	mesh.mesh = BoxMesh.new()
	mesh.position = pos
	mesh.set_meta("extras", {"uuid": name_, "rmmo_collision": "trimesh"})
	parent.add_child(mesh)
	return mesh
func run() -> void:
	var dir := preload("res://scripts/world3d/map_paths.gd").cache_directory("native_%d" % Time.get_ticks_usec())
	var source := Node3D.new()
	source.name = "Whitebox"
	box(source, "Floor", Vector3(0, -1, 0))
	box(source, "Moving", Vector3.ZERO)
	var hidden := box(source, "Hidden", Vector3(5, 0, 0))
	hidden.visible = false
	hidden.set_meta("extras", {"uuid": "Hidden", "rmmo_collision": "none"})
	var skeleton := Skeleton3D.new()
	skeleton.name = "Rig"
	source.add_child(skeleton)
	skeleton.add_bone("RootBone")
	skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	var skin_mesh := MeshInstance3D.new()
	skin_mesh.name = "Skinned"
	var arrays := BoxMesh.new().get_mesh_arrays()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for vertex in arrays[Mesh.ARRAY_VERTEX]:
		bones.append_array(PackedInt32Array([0, 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1, 0, 0, 0]))
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_blend_shape("WhiteboxMorph")
	var morph := []
	morph.resize(Mesh.ARRAY_MAX)
	var morph_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
	for i in morph_vertices.size(): morph_vertices[i] += Vector3(0.2, 0, 0)
	morph[Mesh.ARRAY_VERTEX] = morph_vertices
	morph[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
	morph[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [morph])
	skin_mesh.mesh = mesh
	skin_mesh.set_blend_shape_value(0, 0.65)
	skin_mesh.skin = skeleton.create_skin_from_rest_transforms()
	skeleton.add_child(skin_mesh)
	skin_mesh.skeleton = NodePath("..")
	var light := OmniLight3D.new()
	light.name = "Lamp"
	source.add_child(light)
	var camera := Camera3D.new()
	camera.name = "AuthoredCamera"
	source.add_child(camera)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	source.add_child(player)
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath("Moving"))
	animation.position_track_insert_key(track, 0, Vector3.ZERO)
	animation.position_track_insert_key(track, 1, Vector3(2, 0, 0))
	track = animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath("Rig:RootBone"))
	animation.position_track_insert_key(track, 0, Vector3.ZERO)
	animation.position_track_insert_key(track, 1, Vector3(0, 1, 0))
	var library := AnimationLibrary.new()
	library.add_animation("Move", animation)
	player.add_animation_library("", library)
	var path := dir.path_join("whitebox.glb")
	check(Io.save_scene(source, path) == OK, "export whitebox with skin animation light camera")
	var override_path := dir.path_join("override.gltf")
	check(Io.save_scene(source, override_path) == OK, "export editable morph fixture")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(override_path))
	for node in raw.nodes:
		if node.get("name") == "Skinned": node["weights"] = [0.85]
	var output := FileAccess.open(override_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(raw))
	output.close()
	var catalog := preload("res://scripts/world_editor/asset_library.gd").new(dir.path_join("library"))
	var imported_asset: Dictionary = catalog.import_file(override_path)
	check(imported_asset.ok, "library imports node-specific morph defaults")
	if imported_asset.ok:
		var asset := preload("res://scripts/world_editor/asset_library.gd").instantiate(imported_asset.entry.asset_path)
		var morphed := asset.find_child("Skinned", true, false) as MeshInstance3D
		check(morphed != null and absf(morphed.get_blend_shape_value(0) - 0.85) < 0.01, "library packaging preserves node weights overriding mesh defaults")
		asset.free()
	source.free()
	var loader := preload("res://scripts/world3d/map_loader.gd").new()
	root.add_child(loader)
	loader.start(path)
	var result: Array = await loader.finished
	var loaded: Node = result[0]
	check(loaded != null, "native glTF loads")
	if loaded == null:
		quit(1)
		return
	var host := Node3D.new()
	root.add_child(host)
	host.add_child(loaded)
	Stream.sync(loaded, host, Vector3.ZERO)
	check(loaded.get_meta("native_graph_preserved", false), "streaming preserves special native graph")
	var moving := loaded.find_child("Moving", true, false) as MeshInstance3D
	var imported_skin := loaded.find_child("Skinned", true, false) as MeshInstance3D
	check(imported_skin != null and imported_skin.skin != null and imported_skin.get_node_or_null(imported_skin.skeleton) is Skeleton3D, "skin and skeleton dependency survives adoption")
	check(imported_skin != null and imported_skin.mesh.get_blend_shape_count() == 1 and absf(imported_skin.get_blend_shape_value(0) - 0.65) < 0.01, "morph target and authored blend weight survive import")
	var imported_hidden := loaded.find_child("Hidden", true, false) as Node3D
	check(imported_hidden != null and not imported_hidden.visible, "hidden native node remains hidden")
	var players := loaded.find_children("*", "AnimationPlayer", true, false)
	check(players.size() == 1, "animation player retained")
	if players.size() == 1:
		var imported: AnimationPlayer = players[0]
		imported.play(imported.get_animation_list()[0])
		imported.seek(0.5, true)
		check(moving != null and absf(moving.position.x - 1) < 0.01, "native animation track still moves original node")
		if imported_skin != null:
			var rig := imported_skin.get_node(imported_skin.skeleton) as Skeleton3D
			check(absf(rig.get_bone_pose_position(0).y - 0.5) < 0.01, "bone animation survives import and streaming")
	check(moving != null and moving.get_node_or_null("NativeAnimatedCollision") is AnimatableBody3D, "explicit rigid animation collision follows node")
	check(loaded.find_children("*", "Light3D", true, false).size() == 1, "native light preserved")
	for item in loaded.find_children("*", "Camera3D", true, false):
		check(not item.current, "authored camera does not take over gameplay")
	Stream.sync(loaded, host, Vector3(300, 0, 300))
	Stream.sync(loaded, host, Vector3.ZERO)
	check(is_instance_valid(moving) and is_instance_valid(imported_skin), "chunk roundtrip retains original animated and skinned objects")
	for spec in loaded.get_meta("stream_library", []):
		if spec.uuid != "Floor": check(spec.extras.get("rmmo_collision") == "none", "dynamic geometry excluded from static collision/navigation")
	host.free()
	Io._remove_tree(dir)
	print("test_world3d_native_gltf: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
