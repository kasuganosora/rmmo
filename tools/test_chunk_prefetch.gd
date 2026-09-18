extends SceneTree
## Walking (48,95)→(48,60) on a 96×96 town must not enqueue a bake mid-stride.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_town_loads_all()
	failed += _test_town_walk_95_to_60()
	failed += _test_large_face_prefetch()
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _drain(field: Node2D) -> void:
	var guard := 0
	while not field._chunk_queue.is_empty() and guard < 128:
		field._bake_next_chunk()
		guard += 1


func _test_town_loads_all() -> int:
	var failed := 0
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var pack = ContentPack.new()
	pack.new_blank("prefetch_town", "环形", 96, 96)
	failed += _expect(pack.save_dir(), "save 96 pack")
	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = false
	field.edit_doc = pack.get_map("Map001")
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.rebuild()
	_drain(field)
	failed += _expect(field._chunks.size() == 36, "play 96 loads all 36 HD chunks (%d)" % field._chunks.size())
	var wanted: Dictionary = field._wanted_chunks(Vector2i(48, 95), 8)
	failed += _expect(wanted.size() == 36, "wanted all 36 at south edge facing north")
	field.queue_free()
	return failed


func _test_town_walk_95_to_60() -> int:
	var failed := 0
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var pack = ContentPack.new()
	pack.new_blank("prefetch_walk", "走", 96, 96)
	failed += _expect(pack.save_dir(), "save walk pack")
	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = false
	field.edit_doc = pack.get_map("Map001")
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.rebuild()
	_drain(field)
	field.set_observer(Vector2i(48, 95), 8)
	field._refresh_chunk_set()
	failed += _expect(field._chunk_queue.is_empty(), "south edge already fully baked")
	var dest_key: String = "3,3"
	failed += _expect(field._chunks.has(dest_key), "chunk covering (48,60) already loaded")
	var new_bakes := 0
	for y in range(95, 59, -1):
		field.set_observer(Vector2i(48, y), 8)
		field._refresh_chunk_set()
		new_bakes += field._chunk_queue.size()
		_drain(field)
	print("walk 48,95→48,60 extra queue=", new_bakes)
	failed += _expect(new_bakes == 0, "walk 48,95→48,60 queues no new HD bakes (%d)" % new_bakes)
	field.queue_free()
	return failed


func _test_large_face_prefetch() -> int:
	var failed := 0
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var pack = ContentPack.new()
	pack.new_blank("prefetch_big", "大", 512, 512)
	failed += _expect(pack.save_dir(), "save 512 pack")
	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = false
	field.edit_doc = pack.get_map("Map001")
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.rebuild()
	var south: Dictionary = field._wanted_chunks(Vector2i(48, 400), 2)
	var north: Dictionary = field._wanted_chunks(Vector2i(48, 400), 8)
	failed += _expect(north.has("3,21") or north.has("2,21") or north.has("3,22"), "facing north prefetches extra rows")
	var min_n := 999
	var min_s := 999
	for k in north.keys():
		min_n = mini(min_n, int(north[k].y))
	for k2 in south.keys():
		min_s = mini(min_s, int(south[k2].y))
	print("512 face north min_cy=", min_n, " south min_cy=", min_s, " n=", north.size(), " s=", south.size())
	failed += _expect(min_n <= min_s - 2, "north facing min_cy is at least 2 rows earlier (%d vs %d)" % [min_n, min_s])
	failed += _expect(north.size() <= 49, "face prefetch does not explode (%d)" % north.size())
	field.queue_free()
	return failed
