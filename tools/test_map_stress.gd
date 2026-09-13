extends SceneTree
## Stress + regression: ext collision, chunk stream, radar MV-only, overview textures.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_ext_collision()
	failed += _test_dense_and_unknown()
	failed += _test_demo_and_street()
	failed += _test_radar_ignores_ext()
	failed += _test_chunk_stream_stress()
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


func _test_ext_collision() -> int:
	var failed := 0
	var MapExt = load("res://scripts/map/map_ext.gd")
	var MapCollision = load("res://scripts/map/map_collision.gd")
	# 4x4 open floor (tile 1, flags 0 = all dirs passable).
	var w := 4
	var h := 4
	var data := PackedInt32Array()
	data.resize(w * h * 6)
	# Fill z0 and z1 so void-filler detector does not treat the floor as outdoor padding.
	for i in range(w * h):
		data[i] = 1
		data[w * h + i] = 1
	var flags := PackedInt32Array()
	flags.resize(8)
	flags[1] = 0
	var col = MapCollision.new()
	col.setup(w, h, data, flags)
	failed += _expect(col.is_passable(1, 1, 6), "open floor passable before ext")
	var ext = MapExt.new()
	ext._ingest({
		"format": "map_ext_v1",
		"width": w,
		"height": h,
		"layers": [
			{"id": "meta", "encoding": "sparse", "cells": [
				[2, 1, MapExt.META_FORCE_BLOCK],
				[3, 1, MapExt.META_FORCE_PASS],
				[0, 2, MapExt.META_WATER],
			]},
			{"id": "water", "encoding": "sparse", "cells": [[1, 2, 50]]},
			{"id": "settings", "encoding": "sparse", "cells": [[1, 1, MapExt.pack_settings(4, 9, 1)]]},
		],
	}, w, h)
	col.set_ext(ext)
	failed += _expect(not col.is_passable(2, 1, 6), "force_block stops passage")
	failed += _expect(col.is_passable(3, 1, 6), "force_pass allows passage")
	failed += _expect(not col.is_passable(0, 2, 6), "meta water blocks")
	failed += _expect(not col.is_passable(1, 2, 6), "water tile blocks")
	failed += _expect(col.settings_at(1, 1) == MapExt.pack_settings(4, 9, 1), "settings_at packed")
	failed += _expect(col.can_pass(1, 1, 6) == false, "cannot walk onto force_block 2,1")
	failed += _expect(col.can_pass(3, 0, 2) == true, "can walk onto force_pass 3,1 from open 3,0")
	# AStar must see ext after set_ext (graph is lazy).
	var ast: AStar2D = col.ensure_path_graph()
	failed += _expect(ast != null and ast.get_point_count() == w * h, "astar points")
	var path: PackedInt64Array = ast.get_id_path(1 + 1 * w, 3 + 1 * w)
	failed += _expect(path.size() > 0, "astar path around/over force_pass")
	return failed


func _test_dense_and_unknown() -> int:
	var failed := 0
	var MapExt = load("res://scripts/map/map_ext.gd")
	var ext = MapExt.new()
	var dense: Array = []
	dense.resize(9)
	for i in range(9):
		dense[i] = 0
	dense[4] = 99
	ext._ingest({
		"format": "map_ext_v1",
		"width": 3,
		"height": 3,
		"layers": [
			{"id": "roof", "encoding": "dense", "data": dense},
			{"id": "not_a_layer", "encoding": "sparse", "cells": [[0, 0, 1]]},
		],
	}, 3, 3)
	failed += _expect(ext.valid, "dense ingest valid")
	failed += _expect(ext.has_tiles("roof"), "dense roof has tiles")
	failed += _expect(ext.tile("roof", 1, 1) == 99, "dense index 4 is cell 1,1")
	failed += _expect(not ext.has_tiles("not_a_layer"), "unknown layer skipped")
	failed += _expect(ext.tile_z(6 + 5, 1, 1) == 99, "tile_z roof id offset")
	return failed


func _test_demo_and_street() -> int:
	var failed := 0
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	for pack_dir in ["res://demo_map", "res://street_map", "res://bath_map"]:
		var pack = TilemapPack.load_pack(pack_dir)
		failed += _expect(pack != null and pack.width > 0, "pack loads %s" % pack_dir)
		if pack == null:
			continue
		var col = pack.collision
		var landable := 0
		var blocked := 0
		var sample := 0
		for y in range(col.height):
			for x in range(col.width):
				sample += 1
				if col.is_landable(x, y):
					landable += 1
					for d in [2, 4, 6, 8]:
						col.can_pass(x, y, d)
				else:
					blocked += 1
		failed += _expect(landable > 0, "%s has landable cells (%d/%d)" % [pack_dir, landable, sample])
		print("STATS %s landable=%d blocked=%d size=%dx%d" % [pack_dir, landable, blocked, col.width, col.height])
	return failed


func _test_radar_ignores_ext() -> int:
	var failed := 0
	var MapFieldScript = load("res://scripts/map/map_field.gd")
	var mf = MapFieldScript.new()
	mf.pack_path = "res://demo_map"
	root.add_child(mf)
	mf.rebuild()
	var a1: Image = mf.get_radar_atlas_image()
	failed += _expect(a1 != null, "radar atlas exists")
	# Inject visual ext tiles into live pack and rebake radar — pixels must match.
	if mf.pack != null and mf.pack.ext != null:
		var ext = mf.pack.ext
		ext._ingest({
			"format": "map_ext_v1",
			"width": mf.grid_width,
			"height": mf.grid_height,
			"layers": [
				{"id": "roof", "encoding": "sparse", "cells": [[15, 18, 1536], [16, 18, 1536]]},
				{"id": "far", "encoding": "sparse", "cells": [[10, 10, 2000]]},
				{"id": "light", "encoding": "sparse", "cells": [[12, 12, 2100]]},
			],
		}, mf.grid_width, mf.grid_height)
		mf.collision.set_ext(ext)
		mf._bake_radar_mv_only(false, Callable())
		var a2: Image = mf.get_radar_atlas_image()
		failed += _expect(a2 != null and a1.get_width() == a2.get_width(), "rebake same size")
		var diff := 0
		if a1 != null and a2 != null:
			for y in range(mini(a1.get_height(), a2.get_height())):
				for x in range(mini(a1.get_width(), a2.get_width())):
					if a1.get_pixel(x, y) != a2.get_pixel(x, y):
						diff += 1
		failed += _expect(diff == 0, "radar pixels unchanged after ext visual tiles (%d diffs)" % diff)
	var gtex = mf.get_ground_texture()
	failed += _expect(gtex != null, "overview ground texture available")
	var utex = mf.get_upper_texture()
	failed += _expect(utex != null, "overview upper texture available")
	mf.queue_free()
	return failed


func _test_chunk_stream_stress() -> int:
	var failed := 0
	var MapFieldScript = load("res://scripts/map/map_field.gd")
	var mf = MapFieldScript.new()
	mf.pack_path = "res://street_map"
	root.add_child(mf)
	var t0 := Time.get_ticks_usec()
	mf.rebuild()
	var bake_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH street rebuild %.1f ms chunks=%d" % [bake_ms, mf._chunks.size()])
	failed += _expect(mf._chunks.size() > 0, "street spawn chunks > 0")
	failed += _expect(mf.grid_width == 75, "street width")
	# Sweep observer across the map to force load/unload.
	var seen_max: int = int(mf._chunks.size())
	for x in range(0, mf.grid_width, 8):
		for y in range(0, mf.grid_height, 8):
			mf.set_observer(Vector2i(x, y), 6)
			mf._refresh_chunk_set()
			var guard := 0
			while not mf._chunk_queue.is_empty() and guard < 64:
				mf._bake_next_chunk()
				guard += 1
			seen_max = maxi(seen_max, mf._chunks.size())
	print("BENCH street stream max_loaded_chunks=", seen_max, " cells=", mf.grid_width * mf.grid_height)
	failed += _expect(seen_max < 40, "streaming does not keep every chunk (max=%d)" % seen_max)
	# Rebuild twice more (leak / crash check).
	mf.rebuild()
	mf.rebuild()
	failed += _expect(mf.get_radar_atlas_image() != null, "radar survives rebuilds")
	# Indoor roof toggle should not crash with no roof sprites.
	mf.set_observer(Vector2i(10, 10), 2)
	mf._apply_indoor_from_cell(Vector2i(10, 10))
	mf.queue_free()
	return failed
