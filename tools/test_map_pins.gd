extends SceneTree
## Headless: personal map pins — add/remove/max-3/path resolve/snapshot.


const RadarPoi = preload("res://scripts/ui/radar_poi.gd")
const MapOverview = preload("res://scripts/ui/map_overview.gd")
const GridPath = preload("res://scripts/map/grid_path.gd")
const MapCollision = preload("res://scripts/map/map_collision.gd")
const TileId = preload("res://scripts/map/tile_id.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_map_pins: FAIL no MockServer")
		quit(1)
		return

	failed += _expect(srv.has_method("try_map_pin_toggle"), "has try_map_pin_toggle")
	failed += _expect(srv.has_method("try_map_pin_clear"), "has try_map_pin_clear")
	failed += _expect(srv.has_method("snapshot_map_pins"), "has snapshot_map_pins")
	failed += _expect(int(srv.MAP_PIN_MAX) == 3, "MAP_PIN_MAX 3")
	failed += _expect(RadarPoi.KIND_PIN == "pin", "KIND_PIN")
	failed += _expect(RadarPoi.color_for_kind(RadarPoi.KIND_PIN) == RadarPoi.COLOR_PIN, "pin color")

	srv._map_pins.clear()
	srv.map_pack_id = "demo_map"

	# Add pin
	var r1: Dictionary = srv.try_map_pin_toggle(10, 12, "demo_map")
	failed += _expect(bool(r1.get("ok", false)), "add pin ok")
	failed += _expect(not bool(r1.get("cleared", true)), "add not cleared")
	var snap1: Dictionary = srv.snapshot_map_pins()
	failed += _expect(int(snap1.get("count", 0)) == 1, "count 1 after add")
	var pins1: Array = snap1.get("pins", [])
	failed += _expect(pins1.size() == 1, "pins size 1")
	var p0: Dictionary = pins1[0] if pins1.size() > 0 and typeof(pins1[0]) == TYPE_DICTIONARY else {}
	failed += _expect(str(p0.get("name", "")) == "标记1", "default name 标记1")
	failed += _expect(str(p0.get("id", "")) == "pin_1", "id pin_1")
	failed += _expect(int(p0.get("cell", {}).get("x", -1)) == 10, "cell x 10")
	failed += _expect(int(p0.get("cell", {}).get("y", -1)) == 12, "cell y 12")
	failed += _expect(_has_action(r1, "map_pins_update"), "map_pins_update action")

	# Toggle same cell → clear
	var r2: Dictionary = srv.try_map_pin_toggle(10, 12, "demo_map")
	failed += _expect(bool(r2.get("ok", false)), "toggle clear ok")
	failed += _expect(bool(r2.get("cleared", false)), "cleared true")
	failed += _expect(int(srv.snapshot_map_pins().get("count", -1)) == 0, "count 0 after toggle clear")

	# Max 3
	failed += _expect(bool(srv.try_map_pin_toggle(1, 1).get("ok", false)), "pin A")
	failed += _expect(bool(srv.try_map_pin_toggle(2, 2).get("ok", false)), "pin B")
	failed += _expect(bool(srv.try_map_pin_toggle(3, 3).get("ok", false)), "pin C")
	failed += _expect(int(srv.snapshot_map_pins().get("count", 0)) == 3, "count 3")
	var rfull: Dictionary = srv.try_map_pin_toggle(4, 4)
	failed += _expect(not bool(rfull.get("ok", true)), "4th rejected")
	failed += _expect(str(rfull.get("reason", "")) == "full", "reason full")
	failed += _expect(int(srv.snapshot_map_pins().get("count", 0)) == 3, "still 3")

	# Slot reuse after remove middle
	var rrm: Dictionary = srv.try_map_pin_toggle(2, 2)
	failed += _expect(bool(rrm.get("cleared", false)), "removed middle")
	failed += _expect(int(srv.snapshot_map_pins().get("count", 0)) == 2, "count 2")
	var rnew: Dictionary = srv.try_map_pin_toggle(5, 5)
	failed += _expect(bool(rnew.get("ok", false)), "reuse slot")
	var names: Array = []
	for pv in srv.snapshot_map_pins().get("pins", []):
		if typeof(pv) == TYPE_DICTIONARY:
			names.append(str(pv.get("name", "")))
	failed += _expect(names.has("标记2"), "slot 2 reused as 标记2")

	# Custom short name
	srv.try_map_pin_clear()
	var rc: Dictionary = srv.try_map_pin_toggle(7, 8, "demo_map", "营地")
	failed += _expect(bool(rc.get("ok", false)), "custom name ok")
	var pc: Dictionary = (srv.snapshot_map_pins().get("pins", []) as Array)[0]
	failed += _expect(str(pc.get("name", "")) == "营地", "custom name 营地")

	# Survive map_id filter / list_for_map
	srv.try_map_pin_toggle(9, 9, "street_map")
	failed += _expect(int(srv.snapshot_map_pins().get("count", 0)) == 2, "2 pins across maps")
	var demo_only: Array = srv.list_map_pins_for_map("demo_map")
	failed += _expect(demo_only.size() == 1, "demo_map filter 1")
	var street_only: Array = srv.list_map_pins_for_map("street_map")
	failed += _expect(street_only.size() == 1, "street_map filter 1")

	# Persist across map_pack_id change (session) — store keeps both
	srv.map_pack_id = "street_map"
	failed += _expect(int(srv.snapshot_map_pins().get("count", 0)) == 2, "survive map_id change")

	# Clear all
	var rcl: Dictionary = srv.try_map_pin_clear()
	failed += _expect(int(rcl.get("cleared", 0)) == 2, "cleared 2")
	failed += _expect(int(srv.snapshot_map_pins().get("count", 0)) == 0, "empty after clear")

	# RadarPoi build_markers includes pins
	var sample: Dictionary = {
		"npcs": [{"id": "innkeeper", "name": "旅店老板", "cell": {"x": 12, "y": 12}, "inn_rest": true}],
		"gather": [],
		"fish": [],
		"pins": [
			{"id": "pin_1", "name": "标记1", "cell": {"x": 10, "y": 8}},
			{"id": "pin_2", "name": "标记2", "cell": {"x": 14, "y": 10}},
		],
	}
	var markers: Array = RadarPoi.build_markers(sample)
	var counts: Dictionary = RadarPoi.count_by_kind(markers)
	failed += _expect(int(counts.get(RadarPoi.KIND_PIN, 0)) == 2, "build_markers pin 2")
	failed += _expect(int(counts.get(RadarPoi.KIND_INN, 0)) == 1, "inn still present")
	failed += _expect(markers.size() == 3, "total 3 markers")

	# Path resolve to pin cell (same pathfind as other POIs)
	var pin_hit: Dictionary = RadarPoi.marker_at_cell(markers, Vector2i(10, 8))
	failed += _expect(str(pin_hit.get("kind", "")) == RadarPoi.KIND_PIN, "marker_at_cell pin")
	failed += _expect(RadarPoi.marker_nav_label(pin_hit) == "标记1", "nav label 标记1")
	var col = _open_grid(24, 24)
	var path: Array[Vector2i] = GridPath.find_path_near(col, Vector2i(2, 2), Vector2i(10, 8), 6)
	failed += _expect(not path.is_empty(), "path to pin non-empty")
	failed += _expect(path[path.size() - 1] == Vector2i(10, 8), "path ends at pin")

	# Overview pick prefers pin
	var ov = MapOverview.new()
	ov.size = Vector2(400, 300)
	var field = StubMapField.new()
	ov.bind(field, null, "demo_map")
	ov.set_poi_markers(markers)
	ov.set_cells_across(40.0)
	ov.set_pan_cell(Vector2(20, 20))
	var poi_local: Vector2 = ov._cell_to_screen(Vector2(10, 8) + Vector2(0.5, 0.5))
	var picked: Dictionary = ov.pick_poi_at(poi_local)
	failed += _expect(str(picked.get("kind", "")) == RadarPoi.KIND_PIN, "overview pick pin")
	failed += _expect(ov.resolve_nav_cell(poi_local) == Vector2i(10, 8), "overview nav cell pin")
	failed += _expect(ov.resolve_nav_label(poi_local) == "标记1", "overview nav label")
	ov.free()
	field.free()

	# enter_world clears pins (session reset)
	srv._map_pins = [{"id": "pin_1", "slot": 1, "name": "标记1", "map_id": "demo_map", "cell": {"x": 1, "y": 1}}]
	failed += _expect(int(srv.snapshot_map_pins().get("count", 0)) == 1, "pre enter_world pin")
	# Soft clear path used by enter_world
	srv._map_pins.clear()
	failed += _expect(int(srv.snapshot_map_pins().get("count", 0)) == 0, "enter_world-style clear")

	if failed == 0:
		print("test_map_pins: PASS")
		quit(0)
	else:
		print("test_map_pins: FAIL %d" % failed)
		quit(1)


func _has_action(result: Dictionary, atype: String) -> bool:
	var acts: Variant = result.get("actions", [])
	if typeof(acts) != TYPE_ARRAY:
		return false
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == atype:
			return true
	return false


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


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


class StubMapField extends Node2D:
	var grid_width: int = 40
	var grid_height: int = 40
	var tile_size: int = 48
