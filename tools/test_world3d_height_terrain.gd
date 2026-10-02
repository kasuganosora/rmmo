extends "res://tools/test_world3d_mcp.gd"
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
const TileMesh = preload("res://scripts/world3d/auto_tile_mesh.gd")
const Kits = preload("res://scripts/world3d/auto_tile_kit.gd")
const Prefabs = preload("res://scripts/world_editor/prefab_library.gd")
const Stream = preload("res://scripts/world3d/world_stream.gd")

class WalkBody extends CharacterBody3D:
	var surface_id := "ground"
	func _sense_surface(): pass

class WalkNavigation extends Node:
	var ready_for_queries := true
	func near_surface(_point, _flat, _vertical): return true

func physics() -> void:
	await settle()
	for i in 3: await physics_frame
	await settle()

func record(family: String, cell: Vector2i, layer: float = 0) -> Dictionary:
	return Rules.index_records(editor._doc.records).get(Rules.key(cell, family, 4, layer), {})

func paint(family: String, cell: Vector2i, height: float, options: Dictionary = {}) -> Dictionary:
	return await call_tool("paint_auto_tiles", {"family": family, "points": [[cell.x * 4 + 2, 0, cell.y * 4 + 2]], "height": height}.merged(options))

func manifest(directory: String, family: String) -> String:
	var folder := directory.path_join(family)
	DirAccess.make_dir_recursive_absolute(folder)
	var pieces := {}
	var keys: Array = ["top", "edge"] if family == "cliff" else (["default"] if family == "stairs" else Kits.masks(family))
	for key in keys:
		if key is int and not Kits.variant(pieces, key).is_empty(): continue
		var visual := MeshInstance3D.new()
		var tile := {"family": family, "mask": key if key is int else 0, "cell_size": 4, "neighbors": [], "options": Rules.normalized_options(family, {})}
		if family == "cliff":
			if key == "top":
				var plane := PlaneMesh.new(); plane.size = Vector2.ONE; visual.mesh = plane; visual.position.y = .5
			else:
				var plane := QuadMesh.new(); plane.size = Vector2.ONE; visual.mesh = plane; visual.position.z = -.5; visual.rotation.y = PI
		else: visual.mesh = TileMesh.build(tile)
		var root_node := Node3D.new(); root_node.name = "KitPiece"; root_node.add_child(visual)
		var file := str(key) + ".glb"
		check(Io.save_scene(root_node, folder.path_join(file)) == OK, "write " + family + " kit piece " + str(key))
		root_node.free()
		pieces[str(key)] = file
	var path := folder.path_join("kit.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "family": family, "name": "测试 " + family, "pieces": pieces})); file.close()
	return path

func vertex_keys(mesh: Mesh) -> Dictionary:
	var result := {}
	for surface in mesh.get_surface_count():
		for vertex: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			result[Vector3i(roundi(vertex.x * 1000), roundi(vertex.y * 1000), roundi(vertex.z * 1000))] = true
	return result

func check_kit_variants(kit: Dictionary) -> void:
	var correct := true
	var variants: Array = range(4) if kit.family == "stairs" else Kits.masks(kit.family)
	for variant in variants:
		var options := Rules.normalized_options(kit.family, {})
		if kit.family == "stairs": options.direction = variant
		var tile := {"family": kit.family, "mask": 0 if kit.family == "stairs" else variant, "cell_size": 4, "neighbors": [], "options": options}
		var expected := vertex_keys(TileMesh.build(tile))
		tile.options.kit = kit
		var actual := Kits.build(tile)
		correct = correct and actual != null and vertex_keys(actual) == expected
	check(correct, "custom " + str(kit.family) + " variants preserve geometry across every rotation")

func run() -> void:
	root.size = Vector2i(1280, 800); root.content_scale_size = root.size
	var directory := Paths.external_root().path_join("__height_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata := FileAccess.open(directory.path_join("metadata.json"), FileAccess.WRITE)
	metadata.store_string('{"id":"height_test","name":"高差临时测试包"}'); metadata.close()
	var path := directory.path_join("maps/test/map.gltf")
	var doc := Doc.new()
	var floor_id: String = doc.add_box("ground", Vector3(0, -.3, 0), Vector3(48, .2, 40))
	doc._find(floor_id).color = [.2, .25, .28]
	doc._find(floor_id).editor_locked = true
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = path; session.world3d_editor_doc = doc
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false; editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor)
	editor._auto_panel.library = Kits.new(directory.path_join("kits"))
	editor._safety.enabled = false
	editor._camera.position = Vector3(16, 19, 24); editor._camera.look_at(Vector3(0, 1, 0))
	await physics()
	var probe := TCPServer.new()
	while probe.listen(port, "127.0.0.1") != OK: port += 1
	probe.stop(); check(editor.start_mcp(port).ok, "start terrain HTTP fixture")
	var discovery := await rpc("tools/list")
	check(discovery.result.tools.size() == 109, "109 3D tools include kit import and discovery")
	var before: Array = doc.records.duplicate(true)
	var history: int = doc._undo.size()
	await paint("cliff", Vector2i(-2, -2), 2)
	var high_id: String = record("cliff", Vector2i(-2, -2)).uuid
	await paint("cliff", Vector2i(-1, -2), 2)
	check(record("cliff", Vector2i(-2, -2)).tile3d.drops[1] == 0, "equal-height plateaus remove shared cliff face")
	await paint("cliff", Vector2i(-2, -2), 4)
	check(record("cliff", Vector2i(-2, -2)).uuid == high_id and record("cliff", Vector2i(-2, -2)).tile3d.drops[1] == .5 and record("cliff", Vector2i(-1, -2)).tile3d.drops[3] == 0, "repaint preserves ID and exposes only the real two-meter height difference")
	var current: Array = doc.records.duplicate(true)
	await call_tool("undo"); check(record("cliff", Vector2i(-2, -2)).tile3d.elevation == 2, "height edit undo restores adjacency")
	await call_tool("redo"); check(doc.records == current, "height edit redo restores exact records")
	await paint("cliff", Vector2i(-2, -2), 4, {"erase": true})
	check(record("cliff", Vector2i(-1, -2)).tile3d.drops[3] == 1, "erase reveals full neighboring cliff")
	await call_tool("undo")
	before = doc.records.duplicate(true); history = doc._undo.size()
	await call_tool("paint_auto_tiles", {"family": "cliff", "points": [[0,0,0]], "height": 0}, false)
	await call_tool("paint_auto_tiles", {"family": "stairs", "points": [[0,0,0]], "rise": -1}, false)
	await call_tool("paint_auto_tiles", {"family": "roof", "points": [[0,0,0]], "direction": 1}, false)
	await call_tool("import_auto_tile_kit", {"path": "C:/outside.json"}, false)
	check(doc.records == before and doc._undo.size() == history, "invalid calls leave document and history untouched")
	doc._find(high_id).editor_locked = true
	await paint("cliff", Vector2i(-2, -2), 6)
	check(doc._find(high_id).tile3d.elevation == 4 and doc._undo.size() == history, "locked high terrain cannot be repainted")
	doc._find(high_id).erase("editor_locked")
	await paint("stairs", Vector2i(-1, -1), 0, {"rise": 2, "direction": 0})
	await paint("bridge", Vector2i(0, -2), 2)
	await paint("bridge", Vector2i(1, -2), 2)
	await paint("road", Vector2i(2, -2), 2)
	check(int(record("bridge", Vector2i(0, -2), 2).tile3d.mask) & 8 and int(record("bridge", Vector2i(1, -2), 2).tile3d.mask) & 2, "bridge removes rails at plateau and road entrances")
	check(int(record("road", Vector2i(2, -2), 2).tile3d.mask) & 8, "road reaches the bridge with reciprocal connection")
	await paint("bridge", Vector2i(-1, 0), 0)
	check(int(record("bridge", Vector2i(-1, 0)).tile3d.mask) & 1, "bridge connects to the lower end of a northbound staircase")
	await paint("bridge", Vector2i(2, -1), 5)
	check(record("bridge", Vector2i(2, -1), 5).tile3d.mask == 0, "different height bridge has no false connection")
	for x in range(0, 2):
		for z in range(1, 3): await paint("roof", Vector2i(x, z), 3, {"rise": 1.5})
	var roof: Dictionary = record("roof", Vector2i(0, 1), 3)
	check(int(roof.tile3d.mask) & 2 and int(roof.tile3d.mask) & 4 and int(roof.tile3d.mask) & 32, "roof joins sides and inside corner")
	# Every legal roof mask produces finite geometry with upward facing top triangles.
	var sane := true
	for mask in Kits.masks("roof"):
		var tile: Dictionary = roof.tile3d.duplicate(true); tile.mask = mask
		var mesh := TileMesh.build(tile)
		for vertex in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]: sane = sane and vertex.is_finite()
	check(sane, "all 47 roof neighborhoods produce finite geometry")
	var source_manifest := manifest(directory, "cliff")
	var imported := await call_tool("import_auto_tile_kit", {"path": source_manifest})
	var kit_id: String = imported.kit_id
	var listed := await call_tool("list_auto_tile_kits")
	check(listed.kits.size() == 1 and listed.kits[0].family == "cliff", "imported immutable kit is discoverable")
	await paint("cliff", Vector2i(-3, 1), 3, {"kit_id": kit_id})
	var custom_id: String = record("cliff", Vector2i(-3, 1)).uuid
	var custom: Dictionary = doc._find(custom_id)
	check(custom.tile3d.options.kit.pieces.top != source_manifest.get_base_dir().path_join("top.glb"), "tile embeds copied kit dependencies")
	before = doc.records.duplicate(true); history = doc._undo.size()
	await call_tool("paint_auto_tiles", {"family": "roof", "height": 3, "points": [[0,0,0]], "kit_id": kit_id}, false)
	check(doc.records == before and doc._undo.size() == history, "wrong-family kit rejected without edits")
	# Validate rotational variant coverage with a real custom road kit.
	var road_kit := await call_tool("import_auto_tile_kit", {"path": manifest(directory, "road")})
	check_kit_variants(editor._auto_panel.library.read(road_kit.kit_id).kit)
	await paint("road", Vector2i(2, -2), 2, {"kit_id": road_kit.kit_id})
	check(not editor._view.get_node(NodePath(record("road", Vector2i(2, -2), 2).uuid)).has_meta("tile_error"), "custom kit resolves rotated road endpoint")
	for family in ["stairs", "roof", "bridge"]:
		var imported_kit := await call_tool("import_auto_tile_kit", {"path": manifest(directory, family)})
		check_kit_variants(editor._auto_panel.library.read(imported_kit.kit_id).kit)
	var invalid_path := directory.path_join("invalid.json")
	var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid_file.store_string('{"version":1,"family":"road","name":"invalid","pieces":{"0":"../outside.glb"}}'); invalid_file.close()
	var count_before: int = editor._auto_panel.library.entries().size()
	await call_tool("import_auto_tile_kit", {"path": invalid_path}, false)
	check(editor._auto_panel.library.entries().size() == count_before, "invalid kit import leaves the resource library untouched")
	# Save a kit-backed selection as a relocatable prefab.
	var library = preload("res://scripts/world_editor/asset_library.gd").new(directory.path_join("prefab_assets"))
	var captured := Prefabs.capture([custom], library, "自定义高台")
	check(captured.ok, "capture kit-backed prefab with model dependencies")
	var relocated := directory.path_join("relocated_assets")
	check(DirAccess.rename_absolute(library.directory, relocated) == OK, "relocate temporary prefab fixture")
	var moved_library = preload("res://scripts/world_editor/asset_library.gd").new(relocated)
	var restored := Prefabs.read(moved_library.entries[0])
	check(restored.ok and str(restored.records[0].tile3d.options.kit.pieces.top).begins_with(relocated), "relocated prefab resolves its own kit models")
	check(Prefabs.place(doc, moved_library.entries[0], Vector3(-8, 0, 8)).ok, "place kit-backed prefab as independent frozen records")
	editor._rebuild()
	await call_tool("save_editor_draft")
	await call_tool("save_world")
	var map_hash := FileAccess.get_sha256(path)
	var dependency: String = custom.tile3d.options.kit.pieces.top
	check(DirAccess.rename_absolute(dependency, dependency + ".missing") == OK, "temporarily move an owned kit dependency")
	await call_tool("save_world", {}, false)
	check(FileAccess.get_sha256(path) == map_hash, "missing kit dependency cannot damage the saved map")
	check(DirAccess.rename_absolute(dependency + ".missing", dependency) == OK, "restore owned kit dependency")
	before = doc.records.duplicate(true)
	await call_tool("open_world", {"path": path})
	check(equivalent(editor._doc.records, before), "save/reopen preserves heights, adjacency and kit identity")
	# Real UI drag and Escape cancellation use the same height parameters.
	for i in editor._palette_items.size():
		if editor._palette_items[i].get("auto_family") == "cliff": editor._on_palette_selected(i); break
	editor._auto_panel.fields.base_height.value = -2
	editor._auto_height = 0
	editor._dock_tabs.current_tab = 4
	await physics()
	var location: Vector2 = editor._camera.unproject_position(Vector3(10, 0, 2)) + editor._canvas.global_position
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; event.position = location
	before = editor._doc.records.duplicate(true)
	Input.parse_input_event(event); await physics()
	check(editor._auto_stroke.active and not record("cliff", Vector2i(2, 0), -2).is_empty(), "real UI paints a high terrain layer from the panel settings")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true; Input.parse_input_event(escape); await physics()
	event = event.duplicate(); event.pressed = false; Input.parse_input_event(event); await physics()
	check(editor._doc.records == before, "Escape cancels UI terrain and all neighbor edits")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_height_terrain/overview.png"))
	# Separate runtime world, no overlapping editor collision bodies.
	editor.queue_free(); await settle()
	var loader := preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(path)
	var loaded: Array = await loader.finished
	var runtime: Node3D = loaded[0]
	check(runtime != null, "runtime loader rebuilds procedural and custom kit geometry")
	var host := Node3D.new(); root.add_child(host); host.add_child(runtime)
	Stream.sync(runtime, host, Vector3.ZERO)
	await physics()
	var space := host.get_world_3d().direct_space_state
	var upper := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-6, 8, -6), Vector3(-6, -1, -6)))
	check(not upper.is_empty() and is_equal_approx(upper.position.y, 4), "runtime high plateau collision matches the saved height")
	var rail := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(2, 2.85, -6), Vector3(2, 2.85, -9)))
	var exit_ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(2, 2.6, -6), Vector3(6, 2.6, -6)))
	check(not rail.is_empty() and exit_ray.is_empty(), "bridge outer rail blocks while connected exit stays open")
	var body := WalkBody.new(); body.position = Vector3(-2, .905, .5); body.floor_snap_length = .2
	var shape := CollisionShape3D.new(); var capsule := CapsuleShape3D.new(); capsule.radius = .3; capsule.height = 1.8; shape.shape = capsule; body.add_child(shape); host.add_child(body)
	var nav := WalkNavigation.new(); host.add_child(nav)
	var authority := preload("res://scripts/world3d/world_authority.gd").new(); authority.mount(body, nav, "test")
	for tick in 240:
		await physics_frame
		authority.move_intent(tick, Vector3.FORWARD, 2)
		if body.position.z < -4.5: break
	check(body.position.z < -4.2 and body.position.y > 2.7, "real authority capsule climbs staircase to the two-meter plateau")
	authority.release(); host.free()
	if failed == 0: Io._remove_tree(directory)
	else: print("fixture=" + directory)
	print("test_world3d_height_terrain: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
