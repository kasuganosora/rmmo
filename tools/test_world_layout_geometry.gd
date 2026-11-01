extends SceneTree
const Geometry = preload("res://scripts/world3d/world_layout_geometry.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _placement(id: String, number: String, origin: Array, rect: Array) -> Dictionary:
	return {"id": id, "pack_id": "demo", "map_number": number, "origin_m": origin, "ownership_xz_m": rect}

func _seam(id: String, a: String, b: String, ea: String, eb: String, ia: Array, ib: Array) -> Dictionary:
	return {"id": id, "a": {"placement_id": a, "edge": ea, "interval_m": ia}, "b": {"placement_id": b, "edge": eb, "interval_m": ib}, "mode": "continuous"}

func _layout() -> Dictionary:
	return {"schema_version": 1, "world_key": "demo_world", "units": "meters", "up_axis": "Y", "spaces": [{"id": "outdoor", "placements": [_placement("city", "001", [0, 0, 0], [0, 0, 1200, 800]), _placement("field", "2", [1200, 20, 0], [0, 0, 2400, 800])], "seams": [_seam("city_field", "city", "field", "x_max", "x_min", [0, 800], [0, 800])]}]}

func _has(result: Dictionary, code: String) -> bool:
	for row: Dictionary in result.get("diagnostics", []):
		if row.code == code: return true
	return false

func _address(number: String, point: Array) -> Dictionary:
	return {"pack_id": "demo", "map_number": number, "position_m": point}

func _run() -> void:
	var layout := _layout(); var before := JSON.stringify(layout, "", true, true)
	var result := Geometry.validate(layout)
	_check(result.ok, "different sizes and Y origins accepted")
	_check(result.layout.spaces[0].placements[0].map_number == "1", "map number normalized")
	_check(JSON.stringify(layout, "", true, true) == before, "validation leaves input untouched")
	result.layout.spaces[0].placements[0].origin_m[0] = 77
	_check(layout.spaces[0].placements[0].origin_m[0] == 0, "normalized output independent")
	var resolved := Geometry.resolve(layout, _address("2", [0, 5, 100]))
	_check(resolved.ok and resolved.space_position_m == [1200.0, 25.0, 100.0] and resolved.local_position_m == [0.0, 5.0, 100.0], "address to space translation")
	_check(resolved.membership == "inside" and not resolved.surface_validated and not resolved.physics_ready, "resolution grants no surface or physics")
	var located := Geometry.locate(layout, "outdoor", [1200, 25, 100])
	_check(located.ok and located.placement_id == "field" and located.local_position_m == [0.0, 5.0, 100.0], "boundary ownership is half open")
	_check(Geometry.locate(layout, "outdoor", [1199, 0, 100]).placement_id == "city", "left boundary approach")
	_check(Geometry.resolve(layout, _address("1", [1200, 0, 100])).reason_code == "outside_ownership", "local maximum excluded")
	_check(Geometry.locate(layout, "outdoor", [3600, 0, 100]).reason_code == "outside_ownership", "external world maximum excluded")
	_check(Geometry.locate(layout, "outdoor", [0, 0, 800]).reason_code == "outside_ownership", "z maximum excluded")
	_check(Geometry.locate(layout, "missing", [0, 0, 0]).reason_code == "space_not_found", "missing space")
	_check(Geometry.locate(layout, "", [0, 0, 0]).reason_code == "invalid_context", "locate requires space")
	_check(not Geometry.resolve(layout, {"pack_id": "demo", "map_number": 1, "position_m": [1, 2, 3]}).ok, "resolve rejects numeric map number")
	_check(not Geometry.locate(layout, "outdoor", [true, 0, 0]).ok, "locate rejects bool coordinate")
	_check(Geometry.resolve(layout, _address("3", [0, 0, 0])).reason_code == "map_not_in_world", "unknown map")
	var negative := _layout()
	negative.spaces[0].placements = [_placement("negative", "1", [-100, 0, -100], [-50, -20, 50, 80])]; negative.spaces[0].seams = []
	_check(Geometry.validate(negative).ok, "negative origins and local bounds")
	_check(Geometry.locate(negative, "outdoor", [-150, 2, -120]).local_position_m == [-50.0, 2.0, -20.0], "negative minimum included")
	_check(not Geometry.locate(negative, "outdoor", [-50, 0, -100]).ok, "negative maximum excluded")
	var large := negative.duplicate(true)
	large.spaces[0].placements[0].origin_m = [900000000000.0, 0, -900000000000.0]
	_check(Geometry.validate(large).ok, "large finite scalar origin")
	resolved = Geometry.resolve(large, _address("1", [0.125, 2, -0.125]))
	_check(resolved.ok and resolved.space_position_m[0] - 900000000000.0 == 0.125, "large origin retains submeter precision")
	located = Geometry.locate(large, "outdoor", resolved.space_position_m)
	_check(located.ok and located.local_position_m == [0.125, 2.0, -0.125], "large origin conversion roundtrip")
	var t := _layout()
	t.spaces[0].placements = [_placement("city", "1", [0, 0, 0], [0, 0, 1200, 800]), _placement("north", "2", [1200, 0, 0], [0, 0, 600, 400]), _placement("south", "3", [1200, 0, 400], [0, 0, 600, 400])]
	t.spaces[0].seams = [_seam("north_join", "city", "north", "x_max", "x_min", [0, 400], [0, 400]), _seam("south_join", "city", "south", "x_max", "x_min", [400, 800], [0, 400])]
	result = Geometry.validate(t)
	_check(result.ok, "T junction shared interval endpoint")
	_check(_has(result, "corner_contact"), "T junction corner diagnostic")
	_check(_has(result, "adjacent_uncovered"), "unconnected north south edge informational")
	_check(Geometry.locate(t, "outdoor", [1200, 0, 400]).placement_id == "south", "T junction deterministic ownership")
	var four := _layout(); four.spaces[0].placements = []; four.spaces[0].seams = []
	for z in 2:
		for x in 2: four.spaces[0].placements.append(_placement("p%d%d" % [x,z], str(1 + x + z * 2), [x * 100 - 100, 0, z * 100 - 100], [0, 0, 100, 100]))
	result = Geometry.validate(four)
	_check(result.ok and _has(result, "corner_contact"), "four corners valid with diagnostics")
	_check(Geometry.locate(four, "outdoor", [0, 0, 0]).placement_id == "p11", "four corner half open ownership")
	var changed := _layout()
	changed.spaces[0].placements[1].origin_m[0] = 1200.01
	result = Geometry.validate(changed)
	_check(not result.ok and _has(result, "seam_mismatch"), "mismatched edges fail")
	var fault: Dictionary = result.diagnostics.filter(func(d): return d.code == "seam_mismatch")[0]
	_check(fault.local_a_m == [1200.0, 0.0, 0.0] and fault.local_b_m == [0.0, 0.0, 0.0] and fault.placement_ids == ["city", "field"], "seam diagnostic local positions")
	_check(fault.space_segment_a_m.size() == 2 and fault.horizontal_error_m > 0.009 and fault.tolerance_m == 0.001, "seam diagnostic error and segments")
	changed.spaces[0].placements[1].origin_m[0] = 1200.0005
	result = Geometry.validate(changed)
	_check(result.ok and _has(result, "seam_small_offset"), "explicit millimeter structural tolerance")
	_check(result.layout.spaces[0].placements[1].origin_m[0] == 1200.0005, "tolerance does not snap authored origin")
	_check(not Geometry.locate(changed, "outdoor", [1200.0002, 0, 10]).ok, "structural tolerance does not invent ownership")
	changed = _layout(); changed.spaces[0].placements[1].origin_m[0] = 1199.9999
	result = Geometry.validate(changed)
	_check(not result.ok and _has(result, "ownership_overlap"), "positive overlap rejected even below seam tolerance")
	fault = result.diagnostics.filter(func(d): return d.code == "ownership_overlap")[0]
	_check(fault.has("local_a_m") and fault.overlap_xz_m[2] > fault.overlap_xz_m[0], "overlap reports measured rectangle")
	changed = _layout(); changed.spaces[0].seams[0].b.edge = "z_min"
	_check(_has(Geometry.validate(changed), "seam_edge_mismatch"), "nonopposed edges rejected")
	changed = _layout(); changed.spaces[0].seams[0].a.interval_m = [0, 801]
	_check(_has(Geometry.validate(changed), "seam_interval_outside"), "out of bounds seam interval")
	changed = _layout(); changed.spaces[0].seams[0].a.interval_m = [1, 1]
	_check(not Geometry.validate(changed).ok, "zero length seam")
	changed = _layout(); changed.spaces[0].seams.append(changed.spaces[0].seams[0].duplicate(true)); changed.spaces[0].seams[1].id = "duplicate"
	_check(_has(Geometry.validate(changed), "duplicate_seam_interval"), "duplicate interior intervals rejected")
	changed = _layout(); changed.spaces[0].seams[0].b.placement_id = "missing"
	_check(_has(Geometry.validate(changed), "invalid_seam_placement"), "missing seam placement")
	changed = _layout(); changed.spaces[0].seams[0].a.interval_m = [0, 400]; changed.spaces[0].seams[0].b.interval_m = [0, 400]
	result = Geometry.validate(changed)
	_check(result.ok and _has(result, "adjacent_uncovered"), "partial seam leaves informational uncovered interval")
	changed = _layout(); changed.spaces.append(changed.spaces[0].duplicate(true)); changed.spaces[1].id = "indoor"
	_check(Geometry.validate(changed).ok, "different spaces may overlap and reuse maps")
	_check(Geometry.resolve(changed, _address("1", [20, 0, 20])).reason_code == "ambiguous_context", "cross space ambiguity")
	_check(Geometry.resolve(changed, _address("1", [20, 0, 20]), "indoor").space_id == "indoor", "explicit space resolves ambiguity")
	_check(Geometry.resolve(changed, _address("1", [20, 0, 20]), "", "city").reason_code == "ambiguous_context", "placement id not globally unique")
	changed = _layout(); changed.spaces[0].placements[1].map_number = "0001"
	_check(Geometry.validate(changed).reason_code == "duplicate_map_placement", "normalized duplicate map")
	changed = _layout(); changed.spaces[0].placements[1].id = "city"
	_check(Geometry.validate(changed).reason_code == "duplicate_placement", "duplicate placement id")
	changed = _layout(); changed.spaces[0].placements[0].pack_version = "1.0.0"
	result = Geometry.validate(changed)
	_check(result.ok and result.layout.spaces[0].placements[0].pack_version == "1.0.0", "optional package version preserved")
	_check(Geometry.validate(result.get("layout", {})).ok, "normalized layout remains valid")
	_check(Geometry.resolve(changed, _address("1", [1, 2, 3])).get("pack_version") == "1.0.0", "resolution retains version selector")
	for version: Variant in ["", 1, "bad\nversion", "x".repeat(129)]:
		changed.spaces[0].placements[0].pack_version = version
		_check(not Geometry.validate(changed).ok, "invalid package version " + str(version))
	for field: String in ["root", "space", "placement", "seam", "endpoint"]:
		changed = _layout()
		match field:
			"root": changed.rotation = 0
			"space": changed.spaces[0].foo = 0
			"placement": changed.spaces[0].placements[0].rotation = [0,0,0]
			"seam": changed.spaces[0].seams[0].foo = 0
			"endpoint": changed.spaces[0].seams[0].a.foo = 0
		_check(Geometry.validate(changed).reason_code == "unknown_layout_field", "unknown field " + field)
	for origin: Variant in [[INF, 0, 0], [NAN, 0, 0], [true, 0, 0], ["0", 0, 0], [1e13, 0, 0], [0, 0], Vector3.ZERO]:
		changed = _layout(); changed.spaces[0].placements[0].origin_m = origin
		_check(not Geometry.validate(changed).ok, "invalid origin " + str(origin))
	changed = negative.duplicate(true); changed.spaces[0].placements[0].origin_m = [1e12, 0, 0]
	_check(Geometry.validate(changed).reason_code == "coordinate_out_of_range", "translated bound exceeds envelope")
	changed.spaces[0].placements[0].ownership_xz_m = [-1e-12, 0, 0, 1]
	_check(Geometry.validate(changed).reason_code == "coordinate_precision_loss", "translated positive width cannot collapse")
	changed = negative.duplicate(true); changed.spaces[0].placements[0].origin_m[1] = 1e12
	_check(Geometry.resolve(changed, _address("1", [0, 1e12, 0])).reason_code == "coordinate_out_of_range", "resolved Y sum remains bounded")
	for version: Variant in [true, "1", 2]:
		changed = _layout(); changed.schema_version = version
		_check(not Geometry.validate(changed).ok, "strict schema version " + str(version))
	changed = _layout(); changed.spaces = []
	_check(not Geometry.validate(changed).ok, "world requires at least one space")
	for i in 33: changed.spaces.append({"id": "s%d" % i, "placements": [], "seams": []})
	_check(Geometry.validate(changed).reason_code == "layout_limit_exceeded", "space limit")
	changed = _layout(); changed.spaces[0].placements = []
	for i in 129: changed.spaces[0].placements.append({})
	_check(Geometry.validate(changed).reason_code == "layout_limit_exceeded", "placement limit")
	changed = _layout(); changed.spaces[0].seams = []
	for i in 257: changed.spaces[0].seams.append({})
	_check(Geometry.validate(changed).reason_code == "layout_limit_exceeded", "seam limit")
	_check(not Geometry.resolve(changed, _address("1", [1, 2, 3])).ok, "resolve cannot bypass layout validation")
	print("WORLD_LAYOUT_GEOMETRY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
