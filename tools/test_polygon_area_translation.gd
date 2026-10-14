extends SceneTree
## Headless regression: small world-space faces retain area after translation;
## the real terrain coverage validator still rejects an actual missing cell.
const Poly = preload("res://scripts/world3d/roof_plan.gd")
const TerrainProjection = preload("res://scripts/world3d/terrain_projection.gd")
var failures := 0


func _init() -> void:
	run.call_deferred()


func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures += 1


func translated(polygon: Array, shift: Vector2) -> Array:
	return polygon.map(func(point: Vector2): return point + shift)


func old_world_area(polygon: Array) -> float:
	var total := 0.0
	for i in polygon.size():
		total += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(total) * .5


func ground(at: float, with_hole: bool) -> Dictionary:
	var heights: Array = []
	heights.resize(25)
	heights.fill(0.0)
	var holes: Array = []
	holes.resize(16)
	holes.fill(false)
	holes[10] = with_hole # World x/z in [at, at+1], inside the strip below.
	return {"uuid": "coverage_ground", "kind": "box", "surface_id": "ground",
		"position": [at, 0.0, at], "rotation": [0.0, 0.0, 0.0], "size": [4.0, 1.0, 4.0],
		"terrain_mesh": {"version": 1, "columns": 4, "rows": 4, "floor": -2.0, "heights": heights, "holes": holes}}


func water(at: float) -> Dictionary:
	# Binary fractions remain exactly representable at 10 km. The test isolates
	# cancellation in area arithmetic, rather than unavoidable input quantization.
	return {"uuid": "coverage_water", "kind": "box", "surface_id": "water", "collision": "none",
		"position": [at, .5, at], "rotation": [0.0, 0.0, 0.0], "size": [4.0, .02, 4.0],
		"channel_mesh": {"polygons": [[[-.3125, .03125], [.3125, .03125], [.3125, .0390625], [-.3125, .0390625]]], "uv_origin": [at, .5, at]}}


func run() -> void:
	var rectangle: Array = Poly.rect([.125, -.25, .25, -.1875])
	var concave: Array = [Vector2(0, 0), Vector2(.375, 0), Vector2(.375, .125), Vector2(.125, .125), Vector2(.125, .375), Vector2(0, .375)]
	check(Poly.area([]) == 0.0 and Poly.area([Vector2.ZERO, Vector2.ONE]) == 0.0, "empty and degenerate polygons have zero area")
	var witnessed_old_loss := false
	for at: float in [0.0, 500.0, 1000.0, 10000.0]:
		var shift := Vector2(at, at)
		var moved: Array = translated(rectangle, shift)
		var actual: float = Poly.area(moved)
		var previous: float = old_world_area(moved)
		print("AREA at=%.0f fixed=%.9f old=%.9f expected=0.007812500" % [at, actual, previous])
		check(absf(actual - .0078125) < .000000001, "small rectangle area at %.0f m" % at)
		witnessed_old_loss = witnessed_old_loss or absf(previous - .0078125) > .001
		for start in concave.size():
			var reordered: Array = []
			for i in concave.size():
				reordered.append(concave[(start + i) % concave.size()] + shift)
			check(absf(Poly.area(reordered) - .078125) < .000000001, "concave signed fan at %.0f m, first vertex %d" % [at, start])
			reordered.reverse()
			check(absf(Poly.area(reordered) - .078125) < .000000001, "reversed concave winding at %.0f m, first vertex %d" % [at, start])
		var complete: Dictionary = TerrainProjection.fit(water(at), [ground(at, false)], 0.0, 1.0)
		check(complete.get("ok", false), "real terrain coverage accepts supported thin water at %.0f m: %s" % [at, complete.get("error", "")])
		if complete.get("ok", false):
			var covered := 0.0
			for polygon: Array in complete.record.channel_mesh.polygons:
				var local: Array = polygon.map(func(point: Array): return Vector2(point[0] * 4.0, point[1] * 4.0))
				covered += Poly.area(local)
			check(absf(covered - .078125) < .000001, "coverage preserves actual strip area at %.0f m" % at)
		var missing: Dictionary = TerrainProjection.fit(water(at), [ground(at, true)], 0.0, 1.0)
		check(not missing.get("ok", false) and str(missing.get("error", "")).contains("缺口"), "real terrain hole remains rejected at %.0f m" % at)
	check(witnessed_old_loss, "fixture reproduces the former world-space cancellation")
	print("test_polygon_area_translation: failures=%d" % failures)
	quit(0 if failures == 0 else 1)
