extends "res://tools/benchmark_road_prepare.gd"
## Exact independent pre-optimization chain. No result fields, IDs or types omitted.
## Same --report and --case options as benchmark; no formal timing claims.
const OriginalRoads = preload("res://review_artifacts/road_prepare_20261016/road_tools_full_chain_ref.gd")
const Projector = preload("res://scripts/world3d/terrain_projection.gd")
const OriginalProjection = preload("res://review_artifacts/road_prepare_20261016/terrain_projection_ref.gd")
const Adaptive = preload("res://scripts/world3d/road_terrain_fit.gd")
const OriginalAdaptive = preload("res://review_artifacts/road_prepare_20261016/road_terrain_fit_ref.gd")
const Plan = preload("res://scripts/world3d/road_plan.gd")
const Surface = preload("res://scripts/world3d/road_surface.gd")
const City = preload("res://scripts/world3d/city_layout.gd")
var cases: Array = []
var correctness_cases: Array = []

func first_difference(a: Variant, b: Variant, path := "$") -> String:
	if typeof(a) != typeof(b): return path + " type"
	if a is Dictionary:
		if a.keys() != b.keys(): return path + " keys or key order"
		for key: Variant in a:
			var difference := first_difference(a[key], b[key], path + "." + str(key))
			if not difference.is_empty(): return difference
	elif a is Array:
		if a.size() != b.size(): return path + " length"
		for index in a.size():
			var difference := first_difference(a[index], b[index], path + "[%d]" % index)
			if not difference.is_empty(): return difference
	elif a != b: return path + " value"
	return ""

func record_comparison(name_: String, actual: Dictionary, expected: Dictionary, inputs: Variant, expected_ok: Variant = null, conflict := "") -> void:
	var current_bytes := var_to_bytes(actual); var old_bytes := var_to_bytes(expected)
	var identical := current_bytes == old_bytes
	check(identical, name_ + " full bytes equal", {"first_difference": first_difference(actual, expected)})
	if expected_ok is bool: check(actual.get("ok", false) == expected_ok, name_ + " expected outcome", {} if actual.get("ok", false) else actual)
	if not conflict.is_empty(): check(actual.get("conflicts", []) == [conflict], name_ + " exact first conflict", actual.get("conflicts", []))
	cases.append({"name": name_, "ok": actual.get("ok", false), "identical": identical,
		"input_sha256": value_sha(inputs), "current_sha256": bytes_sha(current_bytes), "reference_sha256": bytes_sha(old_bytes),
		"error": actual.get("error", ""), "conflicts": actual.get("conflicts", [])})
	if not identical:
		write_bytes(report_path.get_base_dir().path_join(name_ + "_input.bin"), var_to_bytes(inputs))
		write_bytes(report_path.get_base_dir().path_join(name_ + "_actual.bin"), current_bytes)
		write_bytes(report_path.get_base_dir().path_join(name_ + "_expected.bin"), old_bytes)

func compare_context(name_: String, context: Node3D, args: Dictionary, current: RefCounted, original: RefCounted, expected_ok: Variant = null, conflict := "") -> Dictionary:
	var before := var_to_bytes([Fixture.state(context), args])
	current.profile_enabled = true
	var actual: Dictionary = current.prepare(args)
	var expected: Dictionary = original.prepare(args)
	record_comparison(name_, actual, expected, [Fixture.state(context), args], expected_ok, conflict)
	current.profile_enabled = false
	var disabled: Dictionary = current.prepare(args)
	check(var_to_bytes(disabled) == var_to_bytes(actual) and current.last_profile.is_empty(), name_ + " ON/OFF exact and disabled profile empty")
	check(before == var_to_bytes([Fixture.state(context), args]), name_ + " state, history, authoring and arguments unchanged")
	return actual

func compare_prepare(fixture: Dictionary, expected_ok: Variant = null, conflict := "") -> Dictionary:
	check(fixture.construction_error.is_empty(), fixture.name + " fixture construction", fixture.construction_error)
	if not fixture.construction_error.is_empty(): return {}
	var context := Fixture.context(fixture)
	var current := Roads.new(); current.editor = context
	var original := OriginalRoads.new(); original.editor = context
	var actual := compare_context(fixture.name, context, fixture.args, current, original, expected_ok, conflict)
	current.editor = null; original.editor = null; context._waterways.editor = null; context.free()
	return actual

func lane(name_: String) -> Dictionary:
	return Fixture.make(name_, [Fixture.box("ground", [0., -.25, 0.], [80., .5, 80.])],
		Fixture.graph([[[-12., 0., 0.], [12., 0., 0.]]]))

func obstacle(id := "obstacle", position: Array = [-8., 1., 0.]) -> Dictionary:
	return Fixture.box(id, position, [1., 2., 1.], "wood")

func prepare_matrix() -> void:
	for name_: String in Fixture.names():
		if selected.is_empty() or selected == name_: compare_prepare(Fixture.build(name_), true)
	if not selected.is_empty(): return
	for flag: String in ["ordinary", "editor_hidden", "collision_none", "editor_locked"]:
		var test := lane("near_obstacle_" + flag); var prop := obstacle()
		if flag == "collision_none": prop.collision = "none"
		elif flag != "ordinary": prop[flag] = true
		test.records.append(prop); compare_prepare(test, false, "obstacle")
	for reverse in [false, true]:
		var test := lane("first_conflict_reverse_" + str(reverse))
		var added := [obstacle("first"), obstacle("second")]
		if reverse: added.reverse()
		test.records.append_array(added); compare_prepare(test, false, "second" if reverse else "first")
	for flag: String in ["hidden", "locked"]:
		var test := lane("protected_graph_" + flag); test.layout.roads.nodes[0][flag] = true
		compare_prepare(test, false)
	var rotated := lane("rotated_scaled_asset_clearance")
	var asset := obstacle("rotated_asset"); asset.kind = "asset"; asset.size = [2., .75, 1.5]
	asset.bounds_position = [-.5, -1., -.5]; asset.bounds_size = [1., 2., 1.]
	asset.asset_path = "res://fixture_geometry_only.glb"; asset.rotation = [17., 37., -9.]
	rotated.records.append(asset); compare_prepare(rotated, false, asset.uuid)
	var inclined := lane("inclined_existing_road_clearance")
	var raised := road_patch([Vector2(-4., -2.), Vector2(4., -2.), Vector2(4., 2.), Vector2(-4., 2.)], Vector3(-8., 4., 0.))
	raised.uuid = "inclined_road"; raised.erase("road_source"); raised.rotation = [0., 0., 42.]
	inclined.records.append(raised); compare_prepare(inclined, false, "inclined_road")
	var sloped := lane("sloped_new_road_obstacle")
	sloped.layout.roads = Fixture.graph([[[-20., 0., 0.], [20., 4., 0.]]])
	sloped.records.append(obstacle("on_ramp", [-8., 2., 0.])); compare_prepare(sloped, false, "on_ramp")
	var tilted_ground := lane("tilted_terrain_not_flat_support")
	var tilted := Fixture.terrain("tilted_ground", 8, Vector3.ZERO, 32.); tilted.rotation = [2., 25., 0.]
	tilted_ground.records = [tilted]; compare_prepare(tilted_ground, false, "tilted_ground")
	var furrows := lane("raised_furrow_occupancy")
	var farm := Fixture.terrain("farm", 8, Vector3.ZERO, 32.)
	farm.terrain_regions = {"materials": [Fixture.MaterialTool.new().library.find("builtin:white")], "regions": [{
		"id": "field", "polygon": [[-14., -5.], [14., -5.], [14., 5.], [-14., 5.]], "feather": 1., "opacity": 1., "layer": 0,
		"furrows": {"spacing": 1.2, "height": .3, "angle": 20., "phase": .15, "margin": .5}}]}
	furrows.records = [farm]; compare_prepare(furrows, false, "farm")
	var two_tiles := lane("per_road_supporting_terrain_ids")
	two_tiles.records = [Fixture.terrain("left_tile", 8, Vector3(-20., 0., 0.), 32.), Fixture.terrain("right_tile", 8, Vector3(20., .7, 0.), 32.)]
	two_tiles.layout.roads = Fixture.graph([[[-28., 0., 0.], [-12., 0., 0.]], [[12., .7, 0.], [28., .7, 0.]]])
	two_tiles.args = {"follow_terrain": true}; compare_prepare(two_tiles, true)
	var river := Fixture.river_bridge(); river.name = "waterway_tampered_member"
	river.records[0].position[1] += .1; compare_prepare(river, false)
	var bridge := Fixture.stone_bridge(); bridge.name = "stone_bridge_moved_source"
	bridge.records[-1].position[0] += .1; compare_prepare(bridge, false)
	var wing := Fixture.stone_bridge(); wing.name = "actual_stone_wing_post"
	wing.layout.roads.nodes.append_array([{"id": "bad_a", "position": [23., 0., 19.22]}, {"id": "bad_b", "position": [25., 0., 19.22]}])
	wing.layout.roads.edges.append({"id": "through_wing_post", "from": "bad_a", "to": "bad_b", "width_start": 1., "width_end": 1., "kind": "ground"})
	compare_prepare(wing, false, "fixture_bridge")
	preservation_matrix()
	mutation_sequence()

func preservation_matrix() -> void:
	var base := lane("preservation_seed"); var context := Fixture.context(base)
	var original := OriginalRoads.new(); original.editor = context
	var prepared: Dictionary = original.prepare(base.args)
	check(prepared.get("ok", false), "original native pavement seed succeeds")
	original.editor = null; context._waterways.editor = null; context.free()
	if not prepared.get("ok", false): return
	base.records.append_array(prepared.records.duplicate(true)); base.layout.roads = prepared.graph.duplicate(true)
	base.layout.road_surface = prepared.manifest.duplicate(true)
	base.name = "unchanged_existing_pavement"; compare_prepare(base, true)
	var custom := base.duplicate(true); custom.name = "preserve_event_and_group"
	custom.records[-1].event = {"fixture_marker": 17}; custom.records[-1].editor_group = "retained_group"
	custom.records[-1].editor_name = "retained_name"
	# Explicitly migrated from original-byte parity: the old path rebuilt the
	# same fields in a different insertion order. Correctness now requires the
	# existing author record's exact bytes. All other parity cases stay strict.
	compare_record_order_correctness(custom)
	custom = custom.duplicate(true); custom.name = "event_rejects_changed_geometry"
	custom.layout.roads.edges[0].width_start += .5; compare_prepare(custom, false)
	var modified := base.duplicate(true); modified.name = "tampered_pavement_source"
	modified.records[-1].position[1] += .03; compare_prepare(modified, false)
	for flag: String in ["editor_hidden", "editor_locked"]:
		var protected := base.duplicate(true); protected.name = "protected_pavement_" + flag
		protected.records[-1][flag] = true; compare_prepare(protected, false)

func compare_record_order_correctness(fixture: Dictionary) -> void:
	var context := Fixture.context(fixture); var current := Roads.new(); var original := OriginalRoads.new()
	current.editor = context; original.editor = context; current.profile_enabled = true
	var before := var_to_bytes([Fixture.state(context), fixture.args])
	var previous: Dictionary = fixture.records[-1].duplicate(true)
	var actual: Dictionary = current.prepare(fixture.args); var legacy: Dictionary = original.prepare(fixture.args)
	var name_: String = fixture.name + "_author_byte_preservation"
	check(actual.get("ok", false) and legacy.get("ok", false), name_ + " both paths succeed")
	var current_records: Array = actual.get("records", []).filter(func(record): return record.uuid == previous.uuid)
	var legacy_records: Array = legacy.get("records", []).filter(func(record): return record.uuid == previous.uuid)
	check(current_records.size() == 1 and legacy_records.size() == 1, name_ + " exact target identity exists")
	if current_records.size() == 1 and legacy_records.size() == 1:
		var old_record: Dictionary = legacy_records[0]
		check(var_to_bytes(current_records[0]) == var_to_bytes(previous), name_ + " current record retains every input byte")
		check(old_record.size() == previous.size() and previous.keys().all(func(key): return old_record.has(key) and var_to_bytes(old_record[key]) == var_to_bytes(previous[key])), name_ + " old values and numeric types are exact; only top-level key order differs")
		check(old_record.keys() != previous.keys(), name_ + " legacy insertion-order defect is actually exercised")
		var intended := legacy.duplicate(true)
		for index in intended.records.size():
			if intended.records[index].uuid == previous.uuid: intended.records[index] = previous.duplicate(true)
		check(var_to_bytes(actual) == var_to_bytes(intended), name_ + " every other return byte remains identical to legacy")
	check(var_to_bytes(actual) != var_to_bytes(legacy), name_ + " intentional legacy/current difference remains visible")
	current.profile_enabled = false
	check(var_to_bytes(current.prepare(fixture.args)) == var_to_bytes(actual) and current.last_profile.is_empty(), name_ + " ON/OFF exact and disabled profile empty")
	check(before == var_to_bytes([Fixture.state(context), fixture.args]), name_ + " document, history and arguments unchanged")
	var evidence := {"name": name_, "migrated_from_strict_case": fixture.name,
		"reason": "Correctness fix preserves an already equivalent author record instead of rebuilding its dictionary order. No global comparator normalization.",
		"input_previous_sha256": value_sha(previous), "legacy_result_sha256": value_sha(legacy), "current_result_sha256": value_sha(actual),
		"legacy_current_identical": var_to_bytes(actual) == var_to_bytes(legacy), "first_difference": first_difference(actual, legacy),
		"input_previous": previous, "legacy_record": legacy_records[0] if legacy_records.size() == 1 else {},
		"current_record": current_records[0] if current_records.size() == 1 else {}}
	correctness_cases.append(evidence)
	var evidence_path := report_path.get_basename() + "_record_order.json"
	var file := FileAccess.open(evidence_path, FileAccess.WRITE)
	check(file != null, name_ + " separate correctness evidence opened")
	if file != null: file.store_string(JSON.stringify(evidence, "  ")); file.close()
	write_bytes(report_path.get_basename() + "_record_order_current.bin", var_to_bytes(actual))
	write_bytes(report_path.get_basename() + "_record_order_legacy.bin", var_to_bytes(legacy))
	write_bytes(report_path.get_basename() + "_record_order_previous.bin", var_to_bytes(previous))
	current.editor = null; original.editor = null; context._waterways.editor = null; context.free()

func mutation_sequence() -> void:
	var test := lane("same_instance"); test.records.append(obstacle("moving", [200., 1., 200.]))
	var context := Fixture.context(test); var current := Roads.new(); var original := OriginalRoads.new()
	current.editor = context; original.editor = context
	compare_context("mutation_far", context, test.args, current, original, true)
	context._doc.checkpoint_recovery(); context._doc.records[-1].position = [-8., 1., 0.]
	compare_context("mutation_same_uuid_near", context, test.args, current, original, false, "moving")
	check(context._doc.undo(), "native undo moving obstacle")
	compare_context("mutation_native_undo", context, test.args, current, original, true)
	check(context._doc.redo(), "native redo moving obstacle")
	compare_context("mutation_native_redo", context, test.args, current, original, false, "moving")
	context._doc.checkpoint_recovery(); context._doc.records.pop_back()
	compare_context("mutation_delete", context, test.args, current, original, true)
	check(context._doc.undo(), "native undo deleted obstacle")
	compare_context("mutation_restore_deleted", context, test.args, current, original, false, "moving")
	current.editor = null; original.editor = null; context._waterways.editor = null; context.free()

func road_patch(points: Array, center := Vector3.ZERO) -> Dictionary:
	var out := Fixture.box("projection_source", [center.x, center.y - .075, center.z], [32., .2, 32.], "road")
	out.road_source = "projection_source"; out.road_clearance = 3.
	out.road_mesh = {"polygons": [points.map(func(point: Vector2): return [point.x / 32., point.y / 32.])], "uv_origin": [center.x, center.y, center.z]}
	return out

func compare_projection(name_: String, record: Dictionary, terrains: Array, expected_ok: Variant = null, adaptive_limit := -1) -> void:
	var before := var_to_bytes([record, terrains])
	var actual: Dictionary; var expected: Dictionary
	if adaptive_limit >= 0:
		actual = Adaptive.fit([record], terrains, .025, adaptive_limit)
		expected = OriginalAdaptive.fit([record], terrains, .025, adaptive_limit)
	else:
		actual = Projector.fit(record, terrains)
		expected = OriginalProjection.fit(record, terrains)
	record_comparison(name_, actual, expected, [record, terrains, adaptive_limit], expected_ok)
	check(before == var_to_bytes([record, terrains]), name_ + " exact inputs unchanged")
	if actual.get("ok", false):
		var records: Array = actual.records if adaptive_limit >= 0 else [actual.record]
		check(records.all(func(r): return Surface.valid(r)), name_ + " native surface validity")

func projection_matrix() -> void:
	var polygon := [Vector2(-4., -1.), Vector2(4., -1.), Vector2(4., 1.), Vector2(-4., 1.)]
	var source := road_patch(polygon)
	for entry: Array in [[0., 0., 0.], [10000., -10000., 37.], [-10000., 9999., -73.], [-48., -32., 90.]]:
		var center := Vector3(entry[0], 0., entry[1]); var tile := Fixture.terrain("rotated", 16, center, 32.); tile.rotation[1] = entry[2]
		compare_projection("projection_yaw_%s_%s" % [entry[0], entry[2]], road_patch(polygon, center), [tile], true)
	var random := RandomNumberGenerator.new(); random.seed = 810613
	for index in 12:
		var center := Vector3(random.randf_range(-10000., 10000.), 0., random.randf_range(-10000., 10000.))
		var tile := Fixture.terrain("seeded", 8 + (index % 3) * 8, center, 32.)
		tile.rotation[1] = 0. if index % 2 == 0 else random.randf_range(-180., 180.)
		for i in tile.terrain_mesh.heights.size(): tile.terrain_mesh.heights[i] = random.randf_range(-.015, .015)
		compare_projection("seeded_rotated_%02d" % index, road_patch(polygon, center), [tile], true)
	var tile := Fixture.terrain("holes", 16, Vector3.ZERO, 32.)
	tile.terrain_mesh.holes[8 * 16 + 8] = true
	compare_projection("projection_narrow_hole", source, [tile], false)
	tile.terrain_mesh.holes.fill(false); tile.terrain_mesh.holes[0] = true
	compare_projection("projection_far_hole", source, [tile], true)
	tile.terrain_mesh.holes.fill(true); compare_projection("projection_all_holes", source, [tile], false)
	tile = Fixture.terrain("grade", 16, Vector3.ZERO, 32.)
	for grade: float in [.1, .3]:
		for z in 17:
			for x in 17: tile.terrain_mesh.heights[z * 17 + x] = (x - 8.) * 2. * grade
		compare_projection("projection_grade_" + str(grade), source, [tile], grade < .15)
	for tilt: Array in [[.00009, 27., 0.], [0., -31., -.00009], [.001, 0., 0.]]:
		tile = Fixture.terrain("tilted", 16, Vector3.ZERO, 32.); tile.rotation = tilt
		tile.terrain_mesh.heights[8 * 17 + 8] = 15.
		compare_projection("projection_tilt_" + str(tilt[0]) + "_" + str(tilt[2]), source, [tile], false)
	var left := Fixture.terrain("coarse", 4, Vector3(-8., 0., 0.), 16.)
	var right := Fixture.terrain("fine", 16, Vector3(8., 0., 0.), 16.)
	compare_projection("projection_mixed_grid_seam", source, [left, right], true)
	compare_projection("projection_overlapping_tiles", source, [Fixture.terrain("a", 8), Fixture.terrain("b", 16)], false)
	var boundary := road_patch([Vector2(-.004, -1.), Vector2(.004, -1.), Vector2(.004, 1.), Vector2(-.004, 1.)], Vector3(10000., 0., -10000.))
	compare_projection("projection_millimetre_strip_at_10km", boundary, [Fixture.terrain("boundary", 16, Vector3(10000., 0., -10000.), 32.)])
	var exact_grid := road_patch([Vector2(-2., 0.), Vector2(2., 0.), Vector2(2., 2.), Vector2(-2., 2.)])
	compare_projection("projection_exact_cell_lines", exact_grid, [Fixture.terrain("grid", 16, Vector3.ZERO, 32.)], true)
	var non_square := Fixture.terrain("non_square", 8, Vector3(-96., 0., -64.), 32.)
	non_square.size = [35., 1., 19.]; non_square.terrain_mesh.columns = 7; non_square.terrain_mesh.rows = 19
	non_square.terrain_mesh.heights.resize(8 * 20); non_square.terrain_mesh.heights.fill(0.)
	non_square.terrain_mesh.holes.resize(7 * 19); non_square.terrain_mesh.holes.fill(false)
	compare_projection("projection_non_square_negative", road_patch(polygon, Vector3(-96., 0., -64.)), [non_square], true)
	# A 1m / 32-cell tile places the proposed double precision guard either
	# side of pad == half-cell near 16 km. Both must preserve the legacy bytes.
	for origin: float in [10000., 16000., 17000., -17000.]:
		var at := Vector3(origin, 0., -origin)
		var fine_tile := Fixture.terrain("fine_far", 32, at, 1.)
		var patch := road_patch([Vector2(-.0625, -.03125), Vector2(.0625, -.03125), Vector2(.0625, .03125), Vector2(-.0625, .03125)], at)
		compare_projection("projection_microgrid_guard_" + str(origin), patch, [fine_tile])
	var fragmented := Fixture.terrain("fragmented", 16, Vector3.ZERO, 32.)
	for index in fragmented.terrain_mesh.holes.size(): fragmented.terrain_mesh.holes[index] = index % 3 == 1
	compare_projection("projection_fragmented_holes", source, [fragmented], false)
	var dense := Fixture.terrain("dense", 64, Vector3.ZERO, 16.)
	var square := road_patch([Vector2(-4., -4.), Vector2(4., -4.), Vector2(4., 4.), Vector2(-4., 4.)])
	compare_projection("projection_512_piece_limit", square, [dense], false)
	compare_projection("adaptive_512_piece_split", square, [dense], true, 0)
	compare_projection("adaptive_256_paint_split", square, [dense], true, 256)
	var settings: Dictionary = Plan.defaults().merged({"kerb_enabled": true, "kerb_material_id": "builtin:white"}, true)
	var road := Plan.build(Fixture.graph([[[-6., 0., 0.], [6., 0., 0.]]]), settings)
	check(road.ok, "native continuous kerb fixture built")
	var slope := Fixture.terrain("kerb_slope", 16, Vector3.ZERO, 40.)
	for z in 17:
		for x in 17: slope.terrain_mesh.heights[z * 17 + x] = (x - 8.) * 2.5 * .05
	for index in road.get("records", []).size(): compare_projection("kerb_sampled_height_%d" % index, road.records[index], [slope], true)

func window_path_checks() -> void:
	var terrain_api = preload("res://scripts/world3d/terrain_surface.gd")
	var tile := Fixture.terrain("path_check", 64)
	var wanted := Rect2(-4., -1., 8., 2.).grow(.001)
	var window: Rect2i = Projector._cell_window(tile, terrain_api.transform(tile), wanted)
	check(window.has_area() and window.size.x * window.size.y < 64 * 64, "local 64 grid actually selects the bounded construction window", str(window))
	var paths: Array = [{"case": "local64", "window": [window.position.x, window.position.y, window.size.x, window.size.y]}]
	for angles: Array in [[0., 17., 0.], [.00001, 0., 0.], [0., 0., -.00001]]:
		tile.rotation = angles
		window = Projector._cell_window(tile, terrain_api.transform(tile), wanted)
		check(window == Rect2i(0, 0, 64, 64), "yaw or tiny X/Z tilt actually uses original full scan: " + str(angles), str(window))
	for origin: float in [16000., 17000., -17000.]:
		tile = Fixture.terrain("guard_check", 32, Vector3(origin, 0., -origin), 1.)
		wanted = Rect2(origin - .0625, -origin - .03125, .125, .0625).grow(.001)
		window = Projector._cell_window(tile, terrain_api.transform(tile), wanted)
		var full := window == Rect2i(0, 0, 32, 32)
		check(full == (absf(origin) > 16000.), "microgrid precision guard chooses expected path at " + str(origin), str(window))
		paths.append({"case": "microgrid_" + str(origin), "full_scan": full, "window": [window.position.x, window.position.y, window.size.x, window.size.y]})
	tile = Fixture.terrain("invalid_extent", 32); tile.size[0] = 0.
	check(Projector._cell_window(tile, terrain_api.transform(tile), Rect2(-1., -1., 2., 2.)) == Rect2i(0, 0, 32, 32), "untrusted nonpositive extent keeps full scan")
	tile = Fixture.terrain("pose_guard", 32)
	check(Projector._cell_window(tile, Transform3D(Basis.IDENTITY.scaled(Vector3(1.1, 1., 1.)), Vector3.ZERO), Rect2(-1., -1., 2., 2.)) == Rect2i(0, 0, 32, 32), "nonidentity basis keeps full scan")
	report.window_path_checks = paths

func run() -> void:
	report_path = "res://review_artifacts/road_prepare_20261016/differential/result.json"
	if not initialize(): finish(); return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://review_artifacts/road_prepare_20261016/full_chain_metadata.json"))
	for filename: String in manifest.files:
		check(FileAccess.get_sha256("res://review_artifacts/road_prepare_20261016/" + filename) == manifest.files[filename], "independent reference SHA " + filename)
	var reference_root := "res://review_artifacts/road_prepare_20261016/"
	check(FileAccess.get_sha256(reference_root + "terrain_projection.gd.txt") == "5241610fe9ab43be91f6a554f8232dfae2e7def8bb268a76fb52e7c6d5355391", "projection original byte SHA pinned")
	check(FileAccess.get_sha256(reference_root + "road_terrain_fit.gd.txt") == "3a7a25f49c4702a7d0334d705d733b3e8ae0d68223fbd8e8d6e714e85dc570fc", "adaptive fit original byte SHA pinned")
	check(FileAccess.get_file_as_string(reference_root + "road_terrain_fit_ref.gd") == FileAccess.get_file_as_string(reference_root + "road_terrain_fit.gd.txt").replace("res://scripts/world3d/terrain_projection.gd", reference_root + "terrain_projection_ref.gd"), "fit adapter only redirects the frozen projection preload")
	check(FileAccess.get_file_as_string(reference_root + "road_tools_full_chain_ref.gd") == FileAccess.get_file_as_string(REFERENCE).replace("res://scripts/world3d/road_terrain_fit.gd", reference_root + "road_terrain_fit_ref.gd"), "prepare adapter only redirects the frozen adaptive preload")
	report.method = {"type": "strict CPU differential, not a timing run", "comparison": "var_to_bytes entire return; no exclusions, normalization, rounding or sorted fields",
		"reference": "Frozen original road_tools -> frozen original adaptive fit -> byte-identical original projection. Only recorded single preload substitutions redirect this chain.",
		"other_dependencies": "All other helpers remain shared and are recorded by SHA. This proves only the road_tools/terrain_projection/road_terrain_fit change boundary.",
		"scope": "In-memory CPU preparation and exact geometry/errors/state. No native publication, save/reopen, HTTP, GPU or traversal claim."}
	prepare_matrix()
	if selected.is_empty():
		projection_matrix()
		window_path_checks()
	report.cases = cases; report.case_count = cases.size(); report.reference_manifest = manifest
	report.correctness_cases = correctness_cases; report.correctness_case_count = correctness_cases.size()
	finish()
