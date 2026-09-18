extends SceneTree
## Headless: POI click resolve → path/move request non-empty for free cell.


const RadarPoi = preload("res://scripts/ui/radar_poi.gd")
const MapOverview = preload("res://scripts/ui/map_overview.gd")
const GridPath = preload("res://scripts/map/grid_path.gd")
const MapCollision = preload("res://scripts/map/map_collision.gd")
const TileId = preload("res://scripts/map/tile_id.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0

	var sample: Dictionary = {
		"npcs": [
			{"id": "innkeeper", "name": "旅店老板", "cell": {"x": 12, "y": 12}, "inn_rest": true},
			{"id": "blacksmith", "name": "铁匠", "cell": {"x": 14, "y": 12}, "blacksmith": true},
		],
		"gather": [
			{"id": "herb_a", "name": "药草", "cell": {"x": 10, "y": 8}, "depleted": false},
		],
		"fish": [],
	}
	var markers: Array = RadarPoi.build_markers(sample)
	failed += _expect(markers.size() == 3, "sample markers 3")

	# Pure helper: screen pick prefers nearest POI over fallback cell.
	var screen_of := func(cell: Vector2i) -> Vector2:
		return Vector2(float(cell.x) * 10.0 + 5.0, float(cell.y) * 10.0 + 5.0)
	var inn_screen: Vector2 = screen_of.call(Vector2i(12, 12))
	# Click slightly off the inn cell center but within hit radius.
	var click_near := inn_screen + Vector2(6.0, -4.0)
	var fallback := Vector2i(11, 11)  # different empty cell under cursor
	var resolved: Vector2i = RadarPoi.resolve_nav_cell(markers, click_near, screen_of, fallback, 14.0)
	failed += _expect(resolved == Vector2i(12, 12), "resolve prefers POI cell over fallback")

	var hit: Dictionary = RadarPoi.pick_marker_at(markers, click_near, screen_of, 14.0)
	failed += _expect(not hit.is_empty(), "pick_marker_at hits inn")
	failed += _expect(str(hit.get("id", "")) == "innkeeper", "picked innkeeper")
	failed += _expect(RadarPoi.marker_nav_label(hit) == "旅店老板", "nav label uses name")

	# Far click → fallback.
	var far := Vector2(5.0, 5.0)
	var resolved_far: Vector2i = RadarPoi.resolve_nav_cell(markers, far, screen_of, Vector2i(0, 0), 14.0)
	failed += _expect(resolved_far == Vector2i(0, 0), "far click uses fallback")

	# marker_at_cell
	var at: Dictionary = RadarPoi.marker_at_cell(markers, Vector2i(14, 12))
	failed += _expect(str(at.get("id", "")) == "blacksmith", "marker_at_cell smith")

	# MapOverview instance: set markers + resolve via screen mapping.
	var ov = MapOverview.new()
	ov.size = Vector2(200, 200)
	ov.set_poi_markers(markers)
	failed += _expect(ov.poi_marker_count() == 3, "overview stores markers")

	# Path from free cell to POI cell must be non-empty (move request target).
	var col = _open_grid(24, 24)
	var start := Vector2i(2, 2)
	var goal := RadarPoi.marker_cell(hit)  # (12,12)
	var path: Array[Vector2i] = GridPath.find_path_near(col, start, goal, 6)
	failed += _expect(not path.is_empty(), "path to free POI cell non-empty")
	failed += _expect(path[path.size() - 1] == goal, "path ends at POI cell")

	# Blocked POI cell → snap to adjacent walkable (still a move request).
	_block_cell(col, goal.x, goal.y)
	col._astar = null
	var path_near: Array[Vector2i] = GridPath.find_path_near(col, start, goal, 6)
	failed += _expect(not path_near.is_empty(), "path snaps near blocked POI")
	var last: Vector2i = path_near[path_near.size() - 1]
	failed += _expect(last != goal, "snap not on blocked goal")
	failed += _expect(maxi(absi(last.x - goal.x), absi(last.y - goal.y)) <= 6, "snap within radius")

	# Overview instance: size before pan so aspect/_clamp_pan are correct.
	var field = StubMapField.new()
	ov.bind(field, null, "test")
	ov.set_poi_markers(markers)
	ov.size = Vector2(400, 300)
	ov.set_cells_across(40.0)
	ov.set_pan_cell(Vector2(20, 20))
	var poi_local: Vector2 = ov._cell_to_screen(Vector2(12, 12) + Vector2(0.5, 0.5))
	var click_off := poi_local + Vector2(8.0, 0.0)
	var empty_under := ov.local_to_cell(click_off)
	var nav := ov.resolve_nav_cell(click_off)
	failed += _expect(nav == Vector2i(12, 12), "overview resolve_nav_cell prefers POI")
	# If empty_under drifted off the POI cell, priority still resolved to POI.
	if empty_under != Vector2i(12, 12):
		failed += _expect(nav != empty_under, "POI priority over neighbor cell")
	var ov_hit: Dictionary = ov.pick_poi_at(poi_local)
	failed += _expect(str(ov_hit.get("id", "")) == "innkeeper", "overview pick_poi_at at center")
	var lbl := ov.resolve_nav_label(poi_local)
	failed += _expect(lbl == "旅店老板", "overview resolve_nav_label")
	# consume_nav_label round-trip (simulate click stash)
	ov._pending_nav_label = lbl
	failed += _expect(ov.consume_nav_label() == "旅店老板", "consume_nav_label")
	failed += _expect(ov.consume_nav_label() == "", "consume clears")

	ov.free()
	field.free()

	if failed == 0:
		print("test_map_poi_path: PASS")
		quit(0)
	else:
		print("test_map_poi_path: FAIL %d" % failed)
		quit(1)


func _open_grid(w: int, h: int):
	var data := PackedInt32Array()
	data.resize(4 * w * h)
	for y in range(h):
		for x in range(w):
			data[y * w + x] = 1
	var flags := PackedInt32Array()
	flags.resize(16)
	var col = MapCollision.new()
	col.setup(w, h, data, flags)
	return col


func _block_cell(col, x: int, y: int) -> void:
	var w: int = int(col.width)
	var h: int = int(col.height)
	var data: PackedInt32Array = col.data
	data[(3 * h + y) * w + x] = 2
	col.data = data
	var flags: PackedInt32Array = col.flags
	if 2 >= flags.size():
		flags.resize(3)
	flags[2] = TileId.FLAG_DIRS
	col.flags = flags


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


## Minimal map_field duck for overview bind (grid size only).
class StubMapField extends Node2D:
	var grid_width: int = 40
	var grid_height: int = 40
	var tile_size: int = 48
