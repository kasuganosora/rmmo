extends SceneTree
## Headless: chunk coordinate math and spawn-ring bake on demo_map.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var MapFieldScript = load("res://scripts/map/map_field.gd")
	var mf = MapFieldScript.new()
	mf.pack_path = "res://demo_map"
	root.add_child(mf)
	mf.rebuild()
	failed += _expect(mf.grid_width == 30 and mf.grid_height == 36, "demo grid size")
	failed += _expect(mf.get("CHUNK_CELLS") == 16 or mf.CHUNK_CELLS == 16, "chunk size 16")
	var c00: Vector2i = mf.cell_to_chunk(Vector2i(15, 15))
	failed += _expect(c00 == Vector2i(0, 0), "cell 15,15 in chunk 0,0")
	var c11: Vector2i = mf.cell_to_chunk(Vector2i(16, 0))
	failed += _expect(c11 == Vector2i(1, 0), "cell 16,0 in chunk 1,0")
	var chunks: Dictionary = mf._chunks
	failed += _expect(chunks.size() > 0, "spawn ring baked at least one chunk")
	var atlas: Image = mf.get_radar_atlas_image()
	failed += _expect(atlas != null, "radar still full-map MV")
	# Ground full-map sprite should stay hidden (VRAM on chunks).
	var gspr = mf.get_node_or_null("Ground")
	if gspr is Sprite2D:
		failed += _expect((gspr as Sprite2D).visible == false, "legacy full Ground sprite hidden")
	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
