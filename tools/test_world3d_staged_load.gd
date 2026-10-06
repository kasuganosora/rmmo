extends SceneTree
const Loader = preload("res://scripts/world3d/map_loader.gd")
const Stream = preload("res://scripts/world3d/world_stream.gd")
var failed := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failed += 1
func run() -> void:
	var dir := preload("res://scripts/world3d/map_paths.gd").cache_directory("staged_%d" % Time.get_ticks_usec())
	var scene := Node3D.new()
	scene.position = Vector3(3.125, 0, 2.375)
	scene.set_meta("extras", {"map_ref": "test/external"})
	var nested := Node3D.new()
	nested.rotation.y = 0.3
	nested.scale = Vector3(2, 1, 1)
	scene.add_child(nested)
	var visual := MeshInstance3D.new()
	visual.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.2, 0.1)
	visual.material_override = material
	visual.position = Vector3(1.125, 0, 0)
	visual.set_meta("extras", {"uuid": "external_mesh", "surface_id": "ground"})
	nested.add_child(visual)
	var expected := scene.transform * nested.transform * visual.transform
	var path := dir.path_join("external.glb")
	check(preload("res://scripts/world3d/gltf_map_io.gd").save_scene(scene, path) == OK, "save external nested glb")
	scene.free()
	var loader := Loader.new()
	root.add_child(loader)
	loader.start(path)
	var result: Array = await loader.finished
	var loaded: Node = result[0]
	check(loaded != null and loaded.get_meta("static_stream_load", false), "external static glb uses incremental importer")
	var specs: Array = loaded.get_meta("stream_library", [])
	check(specs.size() == 1, "external mesh count preserved")
	if specs.size() == 1:
		check(specs[0].transform.is_equal_approx(expected), "nested translation rotation and scale preserved")
		check(specs[0].uuid == "external_mesh" and specs[0].mesh.get_surface_count() > 0, "external mesh data and authored identity preserved")
		check(specs[0].mesh.surface_get_material(0).albedo_color.is_equal_approx(material.albedo_color), "instance material survives incremental import")
	loaded.free()
	var doc = preload("res://scripts/world3d/world_document.gd").new()
	for i in 12: doc.add_box_silent("ground", Vector3(-10 + i * 20, -0.1, 0), Vector3(20, 0.2, 16))
	var source := doc.build()
	var host := Node3D.new()
	root.add_child(host)
	host.add_child(source)
	Stream.sync(source, host, Vector3.ZERO)
	var nav = preload("res://scripts/world3d/world_navigation.gd").new()
	host.add_child(nav)
	var begin := Time.get_ticks_msec()
	nav.build(source.get_meta("stream_library"), Vector3.ZERO)
	while not nav.ready_for_queries: await process_frame
	var first := Time.get_ticks_msec() - begin
	check(not nav.fully_ready and nav.near_surface(Vector3(5, 0, 0)), "spawn-area navigation publishes before full map")
	check(not nav.near_surface(Vector3(180, 0, 0)), "unbaked distant area cannot be traversed")
	while not nav.fully_ready: await process_frame
	check(nav.find_path(Vector3(5, 0, 0), Vector3(180, 0, 0)).ok, "background bake extends navigation without losing local connectivity")
	check(nav.nearby_source_count < nav.full_source_count and nav.full_source_count == 12, "distant source geometry is deferred until local navigation is available")
	check(nav.face_extractions == 1, "local and full bake share a single unit cube for all boxes")
	check(nav.version == 2, "navigation publishes two synchronized versions")
	print("NAV_METRICS first_ms=%d full_ms=%d" % [first, Time.get_ticks_msec() - begin])
	var geometry: Array = source.get_meta("stream_library")
	host.free()
	var cancelled = preload("res://scripts/world3d/world_navigation.gd").new()
	root.add_child(cancelled)
	cancelled.build(geometry, Vector3.ZERO)
	while not cancelled.ready_for_queries: await process_frame
	cancelled.free()
	await create_timer(0.3).timeout
	check(true, "teardown during asynchronous bake is safe")
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(dir)
	print("test_world3d_staged_load: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
