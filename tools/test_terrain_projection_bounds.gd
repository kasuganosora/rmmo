extends SceneTree
## End-to-end projection checks for rotated/elevated terrain, with unrelated
## dense tiles present. Assertions concern fitted geometry and real failures.
const Fit = preload("res://scripts/world3d/terrain_projection.gd")
const Poly = preload("res://scripts/world3d/roof_plan.gd")
var failures := 0


func _init() -> void:
	run.call_deferred()


func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures += 1


func ground(id: String, at: float, elevation: float, yaw: float, cells := 8, slope := .025) -> Dictionary:
	var heights: Array = []
	for z in cells + 1:
		for x in cells + 1:
			heights.append(slope * (float(x) / cells - .5) * 16.0 + .0125 * (float(z) / cells - .5) * 16.0)
	var holes: Array = []
	holes.resize(cells * cells)
	holes.fill(false)
	return {"uuid": id, "kind": "box", "surface_id": "ground", "position": [at, elevation, at],
		"rotation": [0.0, yaw, 0.0], "size": [16.0, 2.0, 16.0],
		"terrain_mesh": {"version": 1, "columns": cells, "rows": cells, "floor": -20.0, "heights": heights, "holes": holes}}


func water(at: float, bounds: Array = [-2.0, -1.0, 2.0, 1.0]) -> Dictionary:
	var polygon: Array = Poly.rect(bounds).map(func(point: Vector2): return [point.x / 32.0, point.y / 32.0])
	return {"uuid": "projected_water", "kind": "box", "surface_id": "water", "collision": "none",
		"position": [at, 0.0, at], "rotation": [0.0, 0.0, 0.0], "size": [32.0, .02, 32.0],
		"channel_mesh": {"polygons": [polygon], "uv_origin": [at, 0.0, at]}}


func run() -> void:
	var started := Time.get_ticks_usec()
	for config: Array in [[0.0, 3.0, 0.0], [500.0, 17.0, 90.0], [10000.0, -4.0, 37.0]]:
		var at: float = config[0]
		var terrain: Dictionary = ground("target", at, config[1], config[2])
		var source: Dictionary = water(at)
		var extras: Array = []
		for i in 14:
			# Deliberately steep distant terrain must not affect this local fit.
			extras.append(ground("distant_%d" % i, at + 100.0 + i * 20.0, 40.0 + i, 23.0, 64, .8))
		var reference: Dictionary = Fit.fit(source, [terrain], .025, .15)
		var with_extra: Dictionary = Fit.fit(source, extras + [terrain], .025, .15)
		check(reference.get("ok", false), "fit elevated yaw %.0f terrain at %.0f m: %s" % [config[2], at, reference.get("error", "")])
		check(with_extra == reference, "unrelated dense terrain leaves complete result unchanged at %.0f m" % at)
		if reference.get("ok", false):
			var total_area := 0.0
			var height_error := 0.0
			var angle: float = deg_to_rad(config[2])
			for index in reference.record.channel_mesh.polygons.size():
				var polygon: Array = reference.record.channel_mesh.polygons[index]
				var local: Array = polygon.map(func(point: Array): return Vector2(point[0] * 32.0, point[1] * 32.0))
				total_area += Poly.area(local)
				for j in local.size():
					# Independent analytic plane, not a copy of triangle clipping.
					var x: float = local[j].x * cos(angle) - local[j].y * sin(angle)
					var z: float = local[j].x * sin(angle) + local[j].y * cos(angle)
					var expected: float = config[1] + 2.0 * (.025 * x + .0125 * z) + .025
					height_error = maxf(height_error, absf(reference.record.channel_mesh.elevations[index][j] - expected))
			check(absf(total_area - 8.0) < .003 and height_error < .005, "fitted area and plane heights at %.0f m (area %.6f, height error %.6f)" % [at, total_area, height_error])
		var holed: Dictionary = terrain.duplicate(true)
		holed.terrain_mesh.holes[36] = true
		var gap: Dictionary = Fit.fit(source, extras + [holed], .025, .15)
		check(not gap.get("ok", false) and str(gap.get("error", "")).contains("缺口"), "real hole remains rejected at %.0f m" % at)
		var overlap: Dictionary = Fit.fit(source, [terrain, terrain.duplicate(true)], .025, .15)
		check(not overlap.get("ok", false) and str(overlap.get("error", "")).contains("重叠"), "overlapping ground remains rejected at %.0f m" % at)
	var steep: Dictionary = Fit.fit(water(0), [ground("steep", 0, 0, 0, 8, .5)], .025, .15)
	check(not steep.get("ok", false) and str(steep.get("error", "")).contains("坡度"), "intersecting steep slope still rejects")
	check(steep.get("code", "") == "terrain_projection_grade_limit" and steep.get("terrain_id", "") == "steep" and steep.get("record_id", "") == "projected_water", "slope failure identifies the actual terrain and projected record")
	check(absf(steep.get("grade", 0.0) - sqrt(1.0 + .025 * .025)) < .0001 and steep.get("max_grade", 0.0) == .15, "slope diagnostic reports independently known plane grade without changing its limit")
	var at: Array = steep.get("position", [])
	check(at.size() == 3 and absf(at[0]) <= 2.0 and absf(at[2]) <= 1.0 and absf(at[1] - at[0] - .025 * at[2]) < .0001, "diagnostic position lies on actual overlapping terrain, without pavement lift")
	check(steep.get("cell", []).size() == 2 and steep.get("triangle_index", -1) in [0, 1] and steep.get("triangle_world", []).size() == 3, "slope diagnostic includes the precise terrain cell and world triangle")
	var outside: Dictionary = Fit.fit(water(0, [7.0, -.5, 9.0, .5]), [ground("edge", 0, 0, 0)], .025, .15)
	check(not outside.get("ok", false) and str(outside.get("error", "")).contains("缺口"), "real terrain boundary still rejects")
	var dense: Dictionary = Fit.fit(water(0, [-8.0, -8.0, 8.0, 8.0]), [ground("dense", 0, 0, 0, 32)], .025, .15)
	check(not dense.get("ok", false) and str(dense.get("error", "")).contains("512"), "512-piece budget still rejects")
	print("test_terrain_projection_bounds: failures=%d elapsed_ms=%.3f" % [failures, (Time.get_ticks_usec() - started) / 1000.0])
	quit(0 if failures == 0 else 1)
