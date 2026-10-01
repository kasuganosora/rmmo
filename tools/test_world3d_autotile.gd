extends SceneTree
const Doc = preload("res://scripts/world3d/world_document.gd")
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
const TileMesh = preload("res://scripts/world3d/auto_tile_mesh.gd")
const Stroke = preload("res://scripts/world_editor/auto_tile_stroke.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
var failed := 0


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failed += 1


func add(doc, cell: Vector2i, family: String, elevation: float = 0.0) -> Dictionary:
	var uuid: String = doc.add_box_silent("ground", Vector3.ZERO, Vector3.ONE)
	var record: Dictionary = doc._find(uuid)
	Rules.configure(record, cell, family, 4.0, elevation)
	return record


func stroke_at(doc, family: String, from: Vector3, to: Vector3, erase: bool = false, height: float = 0.0) -> Array[String]:
	var stroke := Stroke.new()
	stroke.begin(doc, family, 4.0, height, erase)
	var result := stroke.paint(from)
	result.append_array(stroke.paint(to))
	stroke.finish()
	return result


func run() -> void:
	# Every cardinal configuration, including isolated, endpoint, elbow, T and cross.
	for family in ["road", "wall"]:
		var all_ok := true
		for mask in 16:
			var doc = Doc.new()
			var center := add(doc, Vector2i.ZERO, family)
			for i in 4:
				if mask & (1 << i): add(doc, Rules.OFFSETS[i], family)
			Rules.refresh_all(doc.records)
			var mesh := TileMesh.build(center.tile3d)
			all_ok = all_ok and int(center.tile3d.mask) == mask and mesh.get_surface_count() == 1 and mesh.get_faces().size() > 0
		check(all_ok, family + " covers all 16 connected module variants")
	var terrain_cases := 0
	var all_ok := true
	for mask in 256:
		var valid := mask
		for i in 4:
			if not (mask & (1 << i) and mask & (1 << ((i + 1) % 4))): valid &= ~(1 << (i + 4))
		if valid != mask: continue
		terrain_cases += 1
		var sample = Doc.new()
		var center := add(sample, Vector2i.ZERO, "grass")
		for i in 8:
			if mask & (1 << i): add(sample, Rules.OFFSETS[i], "grass")
		Rules.refresh_all(sample.records)
		all_ok = all_ok and int(center.tile3d.mask) == mask and TileMesh.build(center.tile3d).get_faces().size() > 0
	check(all_ok and terrain_cases == 47, "all 47 terrain edge / inner / outer corner neighborhoods")
	var doc = Doc.new()
	stroke_at(doc, "road", Vector3(-7, 0, -7), Vector3(13, 0, 9))
	check(doc.records.size() == 10, "fast diagonal stroke fills a cardinally connected path across negative cells")
	check(doc._undo.size() == 1 and doc.undo() and doc.records.is_empty() and doc.redo() and doc.records.size() == 10, "one stroke and all neighbor variants undo / redo together")
	var undo_count: int = doc._undo.size()
	stroke_at(doc, "road", Vector3(-7, 0, -7), Vector3(13, 0, 9))
	check(doc.records.size() == 10 and doc._undo.size() == undo_count, "repainting an existing path adds neither duplicate cells nor history")
	var index := Rules.index_records(doc.records)
	var removed: Dictionary = index[Rules.key(Vector2i.ZERO, "road", 4, 0)]
	var removed_id := str(removed.uuid)
	stroke_at(doc, "road", Vector3(1, 0, 1), Vector3(1, 0, 1), true)
	check(not doc.has_uuid(removed_id) and doc.records.size() == 9, "eraser removes just the selected family cell")
	check(doc.undo() and doc.has_uuid(removed_id), "erase restores cell identity and neighbor masks on undo")
	var cancel := Stroke.new()
	var before: Array = doc.records.duplicate(true)
	var redo_count: int = doc._redo.size()
	cancel.begin(doc, "road", 4, 0, false)
	cancel.paint(Vector3(21, 0, 21))
	cancel.finish(true)
	check(doc.records == before and doc._redo.size() == redo_count, "cancel restores the entire stroke without clearing redo")
	doc = Doc.new()
	var lower := add(doc, Vector2i.ZERO, "wall", 0)
	add(doc, Vector2i.RIGHT, "wall", 3)
	add(doc, Vector2i.RIGHT, "road", 0)
	Rules.refresh_all(doc.records)
	check(lower.tile3d.mask == 0, "other floors and module types never connect")
	var same_floor := add(doc, Vector2i.RIGHT, "wall", 0)
	Rules.refresh_all(doc.records)
	check(lower.tile3d.mask == 2 and same_floor.tile3d.mask == 8, "same-floor modules join in both directions")
	Rules.detach(same_floor)
	Rules.refresh_all(doc.records)
	check(lower.tile3d.mask == 0 and same_floor.tile3d.mask == 8, "detaching preserves the moved module shape and repairs old neighbors")
	doc = Doc.new()
	var left := add(doc, Vector2i.ZERO, "grass")
	var right := add(doc, Vector2i.RIGHT, "water")
	add(doc, Vector2i(0, 1), "dirt")
	add(doc, Vector2i(1, 1), "grass")
	Rules.refresh_all(doc.records)
	var seams := true
	for step in 9:
		var z := step / 8.0 - 0.5
		seams = seams and TileMesh.sample_color(left.tile3d, Vector2(0.5, z)).is_equal_approx(TileMesh.sample_color(right.tile3d, Vector2(-0.5, z)))
	check(seams, "mixed grass / dirt / water transitions agree along shared edges and diagonal corners")
	var kept_uuid: String = left.uuid
	stroke_at(doc, "dirt", Vector3(1, 0, 1), Vector3(1, 0, 1))
	check(doc.records.size() == 4 and doc._find(kept_uuid).tile3d.family == "dirt", "painting another terrain replaces material while preserving instance identity")
	var protected: Dictionary = doc._find(kept_uuid)
	protected.editor_locked = true
	var history_before: int = doc._undo.size()
	stroke_at(doc, "grass", Vector3(1, 0, 1), Vector3(1, 0, 1))
	stroke_at(doc, "dirt", Vector3(1, 0, 1), Vector3(1, 0, 1), true)
	check(doc.has_uuid(kept_uuid) and protected.tile3d.family == "dirt" and doc._undo.size() == history_before, "locked cell cannot be repainted or erased and adds no history")
	protected.erase("editor_locked")
	protected.editor_hidden = true
	stroke_at(doc, "dirt", Vector3(1, 0, 1), Vector3(1, 0, 1), true)
	check(doc.has_uuid(kept_uuid) and doc._undo.size() == history_before, "hidden cell is protected from accidental brush erasure")
	protected.erase("editor_hidden")
	# Save includes generated geometry, and both editor and runtime regenerate the same mesh.
	var dir: String = preload("res://scripts/world3d/map_paths.gd").cache_directory("autotile_%d" % Time.get_ticks_usec())
	var path := dir.path_join("map.gltf")
	check(doc.save(path) == OK, "save procedural 3D modules to glTF")
	var reopened = Doc.open_file(path)
	check(reopened != null and reopened.records.size() == 4 and reopened._find(kept_uuid).tile3d.family == "dirt", "reload retains logical cell family and rules")
	var exported: Node = Io.load_scene(path)
	var visual := Io.find_named(exported, kept_uuid) as MeshInstance3D
	check(visual != null and visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR].size() > 0, "exported glTF retains actual transition mesh and vertex colors")
	exported.free()
	var loader := preload("res://scripts/world3d/map_loader.gd").new()
	root.add_child(loader)
	loader.start(path)
	var loaded: Array = await loader.finished
	var runtime: Node3D = loaded[0]
	check(runtime != null and runtime.get_meta("stream_library", []).size() == 4, "runtime record loader includes all terrain modules")
	var host := Node3D.new()
	root.add_child(host)
	host.add_child(runtime)
	preload("res://scripts/world3d/world_stream.gd").sync(runtime, host, Vector3.ZERO)
	await physics_frame
	await process_frame
	var hit := host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(2, 4, 2), Vector3(2, -1, 2)))
	check(not hit.is_empty() and absf(hit.position.y) < 0.001 and hit.normal.y > 0.99, "terrain top has upward-facing collision at the requested elevation")
	host.free()
	Io._remove_tree(dir)
	check(TileMesh._cache.size() <= 128, "procedural mesh cache stays bounded")
	print("test_world3d_autotile: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
