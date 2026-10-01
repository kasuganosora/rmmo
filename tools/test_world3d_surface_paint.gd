extends "res://tools/test_world3d_mcp.gd"
const SurfacePaint = preload("res://scripts/world3d/surface_materials.gd")
const Prefabs = preload("res://scripts/world_editor/prefab_library.gd")
const Library = preload("res://scripts/world_editor/asset_library.gd")

func physics() -> void:
	await settle()
	for i in 3: await physics_frame
	await settle()

func face_toward(rows: Array, normal: Vector3) -> Dictionary:
	for row in rows:
		if Vector3(row.normal[0], row.normal[1], row.normal[2]).dot(normal) > 0.99: return row
	return {}

func screen_of(row: Dictionary) -> Vector2:
	return editor._camera.unproject_position(Vector3(row.center[0], row.center[1], row.center[2]))

func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = editor._canvas.global_position + point
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	Input.parse_input_event(event)
	await physics()

func run() -> void:
	root.size = Vector2i(1280, 800); root.content_scale_size = root.size
	var directory := Paths.external_root().path_join("__surface_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata := FileAccess.open(directory.path_join("metadata.json"), FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"id": "surface_test", "name": "材质临时测试包"})); metadata.close()
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64: image.set_pixel(x, y, Color("c27243") if (x / 16 + y / 8) % 2 == 0 else Color("f1d8a4"))
	var texture_path := directory.path_join("brick_fixture.png")
	image.save_png(texture_path)
	var model := Node3D.new(); model.name = "Building"
	for label in ["Wall", "Roof"]:
		var mesh := MeshInstance3D.new(); mesh.name = label
		var box := BoxMesh.new(); box.size = Vector3(3, 2, 0.6) if label == "Wall" else Vector3(4, 0.4, 3)
		var material := StandardMaterial3D.new(); material.resource_name = "source_" + label
		material.albedo_color = Color("3a9375") if label == "Wall" else Color("466a91")
		box.material = material; mesh.mesh = box
		mesh.position = Vector3(0.5, 1, 0) if label == "Wall" else Vector3(0.5, 2.2, 0)
		model.add_child(mesh)
	var model_path := directory.path_join("building.glb")
	check(Io.save_scene(model, model_path) == OK, "create colored multi-node model")
	model.free()
	var model_hash := FileAccess.get_sha256(model_path)
	var path := directory.path_join("maps/test/map.gltf")
	var doc := Doc.new()
	var floor_id: String = doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(40, 0.2, 30))
	doc._find(floor_id).editor_locked = true
	var wall: String = doc.add_box("block", Vector3(-4, 1.5, 0), Vector3(4, 3, 0.4))
	doc._find(wall).color = [0.3, 0.6, 0.4]
	var roof: String = doc.add_box("block", Vector3(1, 1, -2), Vector3(4, 0.3, 3), Vector3(25, 0, 0))
	var model_entry := {"asset_path": model_path, "bounds_position": [-1.5, 0, -1.5], "bounds_size": [4, 2.4, 3]}
	var building: String = doc.add_asset(model_entry, Vector3(6, 0, 0))
	var other: String = doc.add_asset(model_entry, Vector3(11, 0, 0))
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = path; session.world3d_editor_doc = doc
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false
	editor._material_directory = directory.path_join("materials")
	editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor)
	editor._camera.position = Vector3(14, 13, 23); editor._camera.look_at(Vector3(1, 1, 0))
	await physics()
	var probe := TCPServer.new()
	while probe.listen(port, "127.0.0.1") != OK: port += 1
	probe.stop()
	check(editor.start_mcp(port).ok, "start surface-paint HTTP fixture")
	var discovery := await rpc("tools/list")
	check(discovery.result.tools.size() == 65, "surface material tools remain advertised alongside terrain tools")
	await call_tool("import_surface_material", {"path": "C:/outside.png"}, false)
	var imported := await call_tool("import_surface_material", {"path": texture_path, "name": "暖色砖纹"})
	var material_id: String = imported.material_id
	check(imported.material.texture_path != texture_path and FileAccess.file_exists(imported.material.texture_path), "texture import makes a persistent library copy")
	var materials := await call_tool("list_surface_materials", {"query": "砖纹", "limit": 1})
	check(materials.total == 1 and materials.materials[0].material_id == material_id, "material search and pagination return stable IDs")
	var faces := await call_tool("list_object_surfaces", {"id": wall})
	check(faces.total == 6 and faces.faces.all(func(row): return row.triangle_count == 2), "box exposes six connected planar faces")
	var front := face_toward(faces.faces, Vector3.BACK)
	if front.is_empty(): print(faces); quit(1); return
	var point := screen_of(front)
	var picked := await call_tool("pick_surface", {"screen": [point.x, point.y]})
	check(picked.id == wall and equivalent(picked.target, front.target), "screen picking resolves the actual front face")
	var before: Array = doc.records.duplicate(true)
	var history: int = doc._undo.size()
	var args := {"id": wall, "target": front.target, "material_id": material_id, "scale": [2, 3], "rotation": 90, "offset": [0.25, 0.1]}
	await call_tool("paint_surface", args)
	check(doc._undo.size() == history + 1 and doc._find(wall).surface_paint.size() == 1, "face painting is one document transaction")
	var visual: MeshInstance3D = editor._view.get_node(NodePath(wall))
	check(visual.mesh is ArrayMesh and visual.mesh.get_surface_count() == 2, "paint splits only the selected face from the source material")
	var vertex_count := 0
	for slot in visual.mesh.get_surface_count(): vertex_count += visual.mesh.surface_get_arrays(slot)[Mesh.ARRAY_VERTEX].size()
	check(vertex_count == SurfacePaint.source(visual).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), "painted box stores only referenced vertices without duplicating the whole mesh")
	var painted_slot := -1
	for slot in visual.mesh.get_surface_count():
		var material: Material = visual.get_active_material(slot)
		if material.resource_name == "暖色砖纹": painted_slot = slot
		else: check(material.albedo_color.is_equal_approx(Color(0.3, 0.6, 0.4)), "unpainted faces retain original color")
	check(painted_slot >= 0, "selected face uses imported texture")
	var arrays := visual.mesh.surface_get_arrays(painted_slot)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uv_bounds := Rect2(uv[indices[0]], Vector2.ZERO)
	for index in indices: uv_bounds = uv_bounds.expand(uv[index])
	check(uv_bounds.size.is_equal_approx(Vector2(2, 3)) and uv_bounds.get_center().is_equal_approx(Vector2(0.75, 0.6)), "repeat, rotation and offset are baked into UV coordinates")
	var turned_corner := false
	for index in indices:
		if arrays[Mesh.ARRAY_VERTEX][index].is_equal_approx(Vector3(2, 1.5, 0.2)): turned_corner = uv[index].is_equal_approx(Vector2(-0.25, 2.1))
	check(turned_corner, "90 degree rotation changes the expected front-face UV corner")
	await call_tool("paint_surface", args)
	check(doc._undo.size() == history + 1, "repainting identical settings is a no-op")
	await call_tool("undo")
	check(doc.records == before, "undo restores exact source records")
	await call_tool("redo")
	await call_tool("clear_surface_material", {"id": wall, "target": front.target})
	check(not doc._find(wall).has("surface_paint") and editor._view.get_node(NodePath(wall)).mesh is BoxMesh, "clear face reconstructs the original mesh and material")
	await call_tool("undo")
	before = doc.records.duplicate(true); history = doc._undo.size()
	var invalid := args.duplicate(true); invalid.scale = [0, 1]
	await call_tool("paint_surface", invalid, false)
	invalid = args.duplicate(true); invalid.target.geometry = "stale"
	await call_tool("paint_surface", invalid, false)
	invalid = args.duplicate(true); invalid.target.mesh = "../" + other
	await call_tool("paint_surface", invalid, false)
	invalid = args.duplicate(true); invalid.material_id = "missing"
	await call_tool("paint_surface", invalid, false)
	doc._find(wall).editor_locked = true
	await call_tool("paint_surface", args, false)
	doc._find(wall).erase("editor_locked")
	check(doc.records == before and doc._undo.size() == history, "invalid and locked edits leave document and history untouched")
	await call_tool("set_object_transform", {"id": wall, "size": [5, 3.5, 0.5]})
	visual = editor._view.get_node(NodePath(wall))
	# ArrayMesh pads zero-thickness surface bounds by a tiny renderer epsilon.
	check(visual.mesh.get_aabb().size.distance_to(Vector3(5, 3.5, 0.5)) < 0.0001 and not visual.has_meta("paint_error"), "painted box scaling rebuilds geometry and retains face mapping")
	var model_faces := await call_tool("list_object_surfaces", {"id": building})
	var model_face: Dictionary = model_faces.faces.filter(func(row): return str(row.target.mesh).ends_with("Wall") and Vector3(row.normal[0], row.normal[1], row.normal[2]).dot(Vector3.BACK) > 0.99)[0]
	await call_tool("paint_surface", {"id": building, "target": model_face.target, "material_id": material_id, "mapping": "uv", "rotation": 30})
	check(FileAccess.get_sha256(model_path) == model_hash and not doc._find(other).has("surface_paint"), "painting one imported instance preserves the asset and other instances")
	var building_view: Node3D = editor._view.get_node(NodePath(building))
	var roof_node: MeshInstance3D = SurfacePaint.meshes(building_view).filter(func(node): return str(node.name) == "Roof")[0]
	check(roof_node.get_active_material(0).resource_name == "source_Roof", "other mesh nodes retain their source material")
	var roof_faces := await call_tool("list_object_surfaces", {"id": roof})
	var top := face_toward(roof_faces.faces, Basis.from_euler(Vector3(25, 0, 0) * PI / 180).y)
	await call_tool("paint_surface", {"id": roof, "target": top.target, "material_id": "builtin:checker", "scale": [4, 4]})
	# Auto geometry is frozen before overrides are persisted.
	await call_tool("paint_auto_tiles", {"family": "road", "points": [[-8, 0, -5]], "cell_size": 2})
	var tile: Dictionary = doc.records.back()
	var tile_faces := await call_tool("list_object_surfaces", {"id": tile.uuid})
	await call_tool("paint_surface", {"id": tile.uuid, "target": tile_faces.faces[0].target, "material_id": "builtin:white"})
	check(not tile.tile3d.attached, "painting automatic tile freezes its current geometry")
	await call_tool("undo")
	check(doc.records.back().tile3d.attached and not doc.records.back().has("surface_paint"), "undo restores automatic adjacency and removes paint")
	# A saved reusable object carries texture dependencies as well as models.
	await call_tool("select_objects", {"ids": [building]})
	var prefab := await call_tool("save_prefab", {"name": "刷材质的房屋", "pack_root": directory})
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(prefab.entry.prefab_path))
	check(not str(payload.records[0].surface_paint[0].material.texture_path).is_absolute_path(), "prefab stores relative packed texture dependencies")
	var placed := await call_tool("place_asset", {"asset_id": prefab.asset_id, "position": [-9, 0, 3]})
	check(doc._find(placed.ids[0]).surface_paint.size() == 1, "prefab placement preserves editable material overrides")
	await call_tool("save_editor_draft")
	var draft_id: String = editor._safety.store.own_id(path)
	check(editor._safety.store.read(draft_id).ok, "painted records survive draft validation")
	for node in editor._view.get_children():
		if node.has_meta("paint_error"):
			print("PAINT DIAGNOSTIC ", node.name, ": ", node.get_meta("paint_error"), " record=", doc._find(str(node.name)).get("surface_paint", []))
			for mesh in SurfacePaint.meshes(node):
				var geometry := SurfacePaint.geometry(mesh)
				print(" mesh=", node.get_path_to(mesh), " geometry=", geometry.surfaces.map(func(slot): return slot.signature) if geometry.ok else geometry.error)
	await call_tool("save_world")
	if not FileAccess.file_exists(path): quit(1); return
	var saved: Array = doc.records.duplicate(true)
	await call_tool("open_world", {"path": path})
	doc = editor._doc
	check(equivalent(saved, doc.records), "save/reopen preserves surface targets, UV settings and texture references")
	var malicious: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	malicious.images[0].uri = "%43%3a%2foutside.png"
	var invalid_path := directory.path_join("bad.gltf")
	var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid_file.store_string(JSON.stringify(malicious)); invalid_file.close()
	var ops := preload("res://scripts/world_editor/mcp_ops.gd").new()
	check(not ops.validate_map_file(invalid_path).is_empty(), "lowercase encoded absolute texture URI is rejected before engine loading")
	check(Io.decode_dependency_uri("textures%2fbrick.png") == "textures/brick.png" and Io.decode_dependency_uri("textures%252fbrick.png").is_empty(), "URI decoder normalizes valid escapes and rejects double encoding")
	await call_tool("open_world", {"path": invalid_path, "discard_changes": true}, false)
	check(equivalent(saved, doc.records) and editor._path == path, "encoded external texture URI is rejected without replacing the document")
	var runtime := Io.load_scene(path)
	var textures := 0
	for node in SurfacePaint.meshes(runtime):
		for slot in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(slot)
			if material is StandardMaterial3D and material.albedo_texture != null: textures += 1
	check(textures >= 4, "runtime glTF contains the painted textures without editor overrides")
	runtime.free()
	if DisplayServer.get_name() != "headless":
		await exercise_ui(wall, roof, front, top)
	# Moving a complete prefab library and removing its original sources remains viable.
	var old_library := directory.path_join("assets")
	var moved_library := directory.path_join("moved_assets")
	check(DirAccess.rename_absolute(old_library, moved_library) == OK, "move owned prefab library fixture")
	var moved_entry: Dictionary = prefab.entry.duplicate(true)
	moved_entry.prefab_path = str(moved_entry.prefab_path).replace(old_library, moved_library)
	DirAccess.remove_absolute(texture_path)
	DirAccess.remove_absolute(imported.material.texture_path)
	var loaded := Prefabs.read(moved_entry)
	check(loaded.ok and SurfacePaint.missing(loaded.records).is_empty(), "moved prefab remains independent of source texture and original library")
	var moved_doc := Doc.new(); moved_doc.records = loaded.records
	var moved_view := moved_doc.build()
	check(moved_view.get_children().all(func(node): return not node.has_meta("paint_error")), "moved prefab reconstructs its painted mesh successfully")
	moved_view.free()
	check(editor._doc.save(path) == ERR_FILE_NOT_FOUND, "missing paint texture blocks formal save")
	editor._mcp.stop(); editor.queue_free(); await settle()
	session.world3d_editor_doc = null; session.world3d_editor_path = ""
	Io._remove_tree(directory)
	print("test_world3d_surface_paint: %s" % ("PASS" if failed == 0 else "FAIL (%d)" % failed))
	quit(0 if failed == 0 else 1)

func exercise_ui(wall: String, roof: String, front: Dictionary, top: Dictionary) -> void:
	editor._dock_tabs.current_tab = 3
	var panel = editor._material_panel
	panel.fields.rotation.value = 45
	panel.fields.scale_u.value = 2
	panel.find_child("BeginSurfacePaint", true, false).pressed.emit()
	check(editor._material_tool.active and editor._material_tool.options.rotation == 45, "panel activates brush with shared settings")
	await call_tool("clear_surface_material", {"id": wall}, false)
	var before: Array = editor._doc.records.duplicate(true)
	var history: int = editor._doc._undo.size()
	await mouse(screen_of(front), true)
	var motion := InputEventMouseMotion.new()
	motion.position = editor._canvas.global_position + screen_of(top)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion); await physics()
	await mouse(screen_of(top), false)
	check(editor._doc._undo.size() == history + 1, "one mouse stroke across faces creates one undo transaction")
	editor._material_tool.cancel()
	editor._undo()
	check(editor._doc.records == before, "stroke undo restores all painted faces")
	panel.find_child("BeginSurfacePaint", true, false).pressed.emit()
	await mouse(screen_of(front), true)
	var key := InputEventKey.new(); key.keycode = KEY_ESCAPE; key.pressed = true
	Input.parse_input_event(key); await physics()
	check(editor._doc.records == before and not editor._material_tool.active and editor._doc._undo.size() == history, "Escape cancels a live brush stroke and preserves history")
	panel.find_child("PickPaintFace", true, false).pressed.emit()
	var count: int = editor._doc.records.size()
	await mouse(screen_of(front), true)
	motion = InputEventMouseMotion.new(); motion.position = editor._canvas.global_position + screen_of(top); motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion); await physics()
	await mouse(screen_of(front), false)
	check(editor._doc.records.size() == count, "dragging in pick-only mode cannot place map objects")
	check(editor._material_tool.selected.get("id") == wall, "UI face selection resolves the wall")
	panel.find_child("ApplySurfacePaint", true, false).pressed.emit()
	check(editor._doc._find(wall).surface_paint[0].rotation == 45, "apply button updates selected face")
	root.size = Vector2i(1024, 720); root.content_scale_size = root.size
	editor._camera.position = Vector3(5, 8, 14); editor._camera.look_at(Vector3(1, 1, 0))
	await physics(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_surface_paint/materials_1024.png"))
	check(panel.size.x <= editor._dock_tabs.size.x and editor._canvas.size.x > 600, "material panel fits the 1024 pixel workspace")
