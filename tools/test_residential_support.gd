extends SceneTree
## Pure CPU geometry regressions; no game/editor scene or user map is opened.
const Support = preload("res://scripts/world_editor/residential_support.gd")
const Terrain = preload("res://scripts/world3d/terrain_surface.gd")
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const House = preload("res://scripts/world3d/house_prefab.gd")
var failures := 0
var checks: Array = []
var report: Dictionary = {}


class Document:
	extends RefCounted
	var records: Array = []


func _init() -> void:
	run.call_deferred()


func check(condition: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"ok": condition, "label": label, "detail": detail})
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures += 1


func field(id := "terrain", cells := 64, at := Vector3.ZERO, yaw := 0.0, elevation := 0.0) -> Dictionary:
	var heights: Array = []; heights.resize((cells + 1) * (cells + 1)); heights.fill(elevation)
	var holes: Array = []; holes.resize(cells * cells); holes.fill(false)
	return {"uuid": id, "kind": "box", "surface_id": "ground", "position": [at.x, at.y, at.z],
		"rotation": [0.0, yaw, 0.0], "size": [8.0, 1.0, 8.0], "collision": "walk",
		"terrain_mesh": {"version": 1, "columns": cells, "rows": cells, "floor": -8.0, "heights": heights, "holes": holes}}


func residence() -> Array:
	return [{"uuid": "floor", "kind": "box", "position": [0.0, 0.3, 0.0], "rotation": [0, 0, 0],
		"size": [4.0, 0.2, 4.0], "collision": "walk",
		"building": {"part": "main/floor", "floor": 0, "floor_y": 0.3, "role": "floor"}},
		{"uuid": "base", "kind": "box", "position": [0.0, -0.4, 0.0], "rotation": [0, 0, 0],
		"size": [4.0, 1.2, 4.0], "collision": "walk",
		"building": {"part": "main/floor/foundation", "floor": 0, "floor_y": 0.3, "role": "foundation"}}]


func solve(terrain_records: Array, records: Array = [], origin := Vector3.ZERO, yaw := 0.0, options: Dictionary = {}) -> Dictionary:
	var doc := Document.new(); doc.records = terrain_records
	return Support.solve(doc, residence() if records.is_empty() else records, origin, yaw,
		{"layout": "townhouse", "base_height": 0.3, "foundation_depth": 1.0}, options)


func old_samples_are_flat(terrain: Dictionary) -> bool:
	for x in 9:
		for z in 9:
			if Terrain.sample(terrain, Vector3(-2.0 + x * 0.5, 0, -2.0 + z * 0.5)) != 0.0:
				return false
	return true


func corridor(terrain_records: Array, polygon: Variant = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]) -> Dictionary:
	var doc := Document.new(); doc.records = terrain_records
	return Support.terrain_region(doc, polygon)


func open_frozen_foundation(records: Array) -> Array:
	var result := records.duplicate(true)
	for record: Dictionary in result:
		if not record.has("house_prefab") or record.building.floor != 0 or record.building.role != "shell" or record.has("fixture"):
			continue
		var data := House.decode(record.house_prefab)
		var slot: int = data.entries[0][1][1]
		var faces: Array = Support.frozen_faces(record).faces
		var kept := PackedVector3Array()
		for i in range(0, faces.size(), 3):
			var a: Vector3 = faces[i]; var b: Vector3 = faces[i + 1]; var c: Vector3 = faces[i + 2]
			# Remove the real foundation bottom skins, then issue a valid new SHA.
			# Remaining side/top triangles must not masquerade as a closed solid.
			if absf(a.y - b.y) < 1e-5 and absf(a.y - c.y) < 1e-5 and a.y + record.position[1] < -0.9:
				continue
			kept.append(a); kept.append(b); kept.append(c)
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = kept
		data.meshes[slot].surfaces = [arrays]
		var bytes := var_to_bytes(data)
		var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(bytes)
		record.house_prefab = {"version": 1, "sha256": digest.finish().hex_encode(), "length": bytes.size(),
			"data": Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	return result


func run() -> void:
	var started := Time.get_ticks_usec()
	var flat := field()
	var records := residence()
	var before := var_to_bytes([flat, records])
	var result := solve([flat], records, Vector3.ZERO, 0.0, {"input_version": "fixture-v1"})
	check(result.ok and result.position == Vector3.ZERO, "ordinary foundation accepts continuous flat terrain", result)
	if result.ok:
		check(absf(result.support.interval[0] + 0.2) < 1e-6 and absf(result.support.interval[1] - 1.0) < 1e-6, "interval derives from actual slab bottom and foundation bottom")
		check(result.input_version == "fixture-v1" and result.support.requires_native_placement_validation, "version and native-validation scope stay explicit")
	check(before == var_to_bytes([flat, records]), "solver never mutates source records")
	var high := solve([flat], records, Vector3(0, 4, 0))
	check(high.ok and absf(high.position.y - 1.0) < 1e-6, "floating placement moves down into the feasible interval")
	var low := solve([flat], records, Vector3(0, -4, 0))
	check(low.ok and absf(low.position.y + 0.2) < 1e-6, "buried placement moves above actual floor intrusion")
	check(solve([flat], records, Vector3(0, 4, 0), 0.0, {"max_shift": 0.5}).get("code") == "residential_support_height_limit", "bounded adjustment rejects unreachable support")
	check(solve([flat], records, Vector3.ZERO, 0.0, {"min_y": 0.4, "max_y": 0.6}).get("position", Vector3.ZERO).y > 0.39, "caller world-height interval participates in the solution")
	check(solve([flat], records, Vector3.ZERO, 0.0, {"area_tolerance": 1.0}).get("code") == "residential_support_invalid_input", "caller cannot enlarge geometric tolerances")

	var hole := flat.duplicate(true); hole.terrain_mesh.holes[18 * 64 + 18] = true
	check(old_samples_are_flat(hole), "narrow hole lies between all former 9 by 9 samples")
	var missing := solve([hole])
	check(missing.get("code") == "residential_support_coverage_gap" and missing.get("missing_area", 0) > 0.015, "continuous coverage detects the unsampled hole", missing)
	check(missing.get("terrain_id") == "terrain" and missing.get("cell", []).size() == 2 and missing.get("gap_polygon", []).size() >= 3, "hole failure includes reproducible source and polygon witness")
	for height in [-3.0, 3.0]:
		var narrow := flat.duplicate(true); narrow.terrain_mesh.heights[18 * 65 + 18] = height
		check(old_samples_are_flat(narrow), "narrow %s lies between former samples" % ("trench" if height < 0 else "peak"))
		var rejected := solve([narrow])
		check(rejected.get("code") == "residential_support_height_interval", "actual relief defeats shallow foundation for unsampled %s" % height, rejected)
		check(rejected.get("lower_witness", {}).get("position", []).size() == 3 and rejected.get("upper_witness", {}).get("position", []).size() == 3, "incompatible elevation constraints identify both limiting positions")
	var partial := solve([flat], [], Vector3(3, 0, 0))
	check(partial.get("code") == "residential_support_coverage_gap", "terrain boundary cannot support a partially floating floor")
	var duplicate := flat.duplicate(true); duplicate.uuid = "duplicate"
	check(solve([flat, duplicate]).get("code") == "residential_support_unsupported", "overlapping heightfields are not silently combined")
	check(solve([hole, duplicate]).get("code") == "residential_support_unsupported", "extra overlapping area cannot cancel a real hole in coverage accounting")
	var eave := {"uuid": "eave", "kind": "box", "position": [0, 4, 0], "size": [20, 0.2, 20], "rotation": [0, 0, 0],
		"building": {"part": "roof/eave", "floor": 0, "floor_y": 0.3, "role": "roof_tiles"}}
	check(solve([flat], records + [eave]).ok, "overhanging eaves do not enlarge floor support domain")
	check(solve([flat], [records[0]]).get("code") == "residential_support_unsupported", "missing physical foundation is unsupported")
	var offset := records.duplicate(true); offset[1].position[0] = 0.2
	check(solve([flat], offset).get("code") == "residential_support_unsupported", "misaligned foundation cannot support the full floor")
	var tiny_base := records.duplicate(true); tiny_base[1].size[1] = 0.1; tiny_base[1].position[1] = 0.15
	var doc := Document.new(); doc.records = [flat]
	var metadata := Support.solve(doc, tiny_base, Vector3.ZERO, 0.0, {"layout": "townhouse", "foundation_depth": 3.0, "base_height": 0.9})
	check(metadata.ok and metadata.support.interval[1] < -0.099, "metadata cannot invent deeper or higher foundations")
	var tilted := flat.duplicate(true); tilted.rotation[0] = 0.01
	check(solve([tilted]).get("code") == "residential_support_unsupported", "tilted heightfield explicitly unsupported")
	var furrows := flat.duplicate(true); furrows.terrain_regions = {"regions": [{"furrows": {"height": 0.2}}]}
	check(solve([furrows]).get("code") == "residential_support_unsupported", "raised furrows explicitly unsupported")
	var hidden := flat.duplicate(true); hidden.editor_hidden = true
	check(solve([hidden]).get("code") == "residential_support_unsupported", "hidden terrain cannot supply editor collision support")
	var no_collision := flat.duplicate(true); no_collision.collision = "none"
	check(solve([no_collision]).get("code") == "residential_support_unsupported", "terrain with collision disabled cannot supply support")
	var locked := flat.duplicate(true); locked.editor_locked = true
	check(solve([locked]).ok, "locked visible terrain remains valid read-only support")
	for config: Array in [[10000.0, -10000.0, 37.0], [-500.0, 320.0, 90.0]]:
		var origin := Vector3(config[0], 7.0, config[1])
		var translated := field("translated", 64, origin, config[2])
		var translated_result := solve([translated], [], origin, config[2])
		check(translated_result.ok and absf(translated_result.position.y - 7.0) < 1e-5, "world translation and yaw preserve continuous support at %s" % origin, translated_result)
		translated.terrain_mesh.holes[18 * 64 + 18] = true
		check(solve([translated], [], origin, config[2]).get("code") == "residential_support_coverage_gap", "far rotated hole remains visible to continuous clipping")
	var far := field("unrelated", 64, Vector3(100, 20, 100), 0.0, 3.0)
	var reference := solve([flat]); var extra := solve([far, flat])
	check(reference == extra, "unrelated far terrain leaves deterministic result unchanged")

	var left := field("left", 8, Vector3(-4, 0, 0))
	var right := field("right", 16, Vector3(4, 0, 0), 0, 0.3)
	var walk := corridor([left, right])
	check(walk.ok and absf(walk.max_seam_step - 0.3) < 1e-5 and walk.max_grade == 0.0, "mixed-grid flat tiles report a real 30 cm boundary step", walk)
	check(walk.ok and walk.seam_witness.get("terrain_ids", []).size() == 2, "seam diagnostic identifies both terrain owners")
	right.terrain_mesh.heights.fill(0.0)
	var joined := corridor([left, right])
	check(joined.ok and joined.max_seam_step == 0.0, "continuous mixed-grid T junction has no invented step")
	var slope := field("slope", 8)
	for z in 9:
		for x in 9:
			slope.terrain_mesh.heights[z * 9 + x] = (x - 4) * 0.25
	var graded := corridor([slope])
	check(graded.ok and absf(graded.max_grade - 0.25) < 1e-6 and absf(graded.height_range[1] - 0.25) < 1e-6, "corridor reports analytic plane slope and clipped height extrema")
	check(corridor([hole], [Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)]).get("code") == "residential_support_coverage_gap", "corridor uses continuous hole coverage too")
	check(corridor([flat], [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(1, 1), Vector2(-1, 1)]).get("code") == "residential_support_unsupported", "nonconvex corridor rejects instead of using its convex hull")

	var parameters: Dictionary = Blueprint.defaults().merged({"layout": "townhouse", "template": "house", "width": 9.0, "depth": 11.0,
		"floors": 1, "floor_height": 3.5, "base_height": 0.3, "foundation_depth": 1.0, "style": "plaster",
		"roof_axis": "depth", "roof_pitch": 36.0, "chimney": false, "front_canopy": false}, true)
	var plan := Blueprint.generate(parameters)
	check(plan.ok, "real native townhouse generates for frozen-payload regression")
	if plan.ok:
		var broad := field("broad", 16); broad.size = [24.0, 1.0, 24.0]
		doc.records = [broad]
		var native := Support.solve(doc, plan.records, Vector3.ZERO, 0.0, parameters)
		check(native.ok, "actual generated foundation passes continuous solver", native)
		var frozen := House.bake(plan.records)
		check(frozen.ok, "native bake creates actual frozen collision payload")
		if frozen.ok:
			var payload_before := var_to_bytes(frozen.records)
			var frozen_result := Support.solve(doc, frozen.records, Vector3.ZERO, 0.0, parameters)
			check(frozen_result.ok, "actual frozen floor and merged shell prove physical foundation", frozen_result)
			if frozen_result.ok and native.ok:
				check(absf(frozen_result.support.interval[0] - native.support.interval[0]) < 1e-5 and absf(frozen_result.support.interval[1] - native.support.interval[1]) < 1e-5, "frozen geometry interval matches native geometry without regeneration")
			check(payload_before == var_to_bytes(frozen.records), "frozen analysis preserves exact payload bytes")
			var far_field := field("far-frozen", 16, Vector3(10000, 7, -10000), 37.0); far_field.size = [24.0, 1.0, 24.0]
			doc.records = [far_field]
			var rotated_frozen := Support.solve(doc, frozen.records, Vector3(10000, 7, -10000), 37.0, parameters)
			check(rotated_frozen.ok, "frozen collision support survives far placement and yaw", rotated_frozen)
			doc.records = [broad]
			var open_base := open_frozen_foundation(frozen.records)
			check(Support.solve(doc, open_base, Vector3.ZERO, 0.0, parameters).get("code") == "residential_support_unsupported", "validly rehashed open foundation geometry is not a closed support solid")
			var damaged: Array = frozen.records.duplicate(true)
			for record: Dictionary in damaged:
				if record.has("house_prefab") and record.building.floor == 0 and record.building.role == "shell" and not record.has("fixture"):
					record.house_prefab.sha256 = "0".repeat(64); break
			check(not Support.solve(doc, damaged, Vector3.ZERO, 0.0, parameters).ok, "changed frozen SHA cannot reuse a previous support proof")
			var absent := House.bake(plan.records.filter(func(r): return r.building.role != "foundation"))
			check(absent.ok and Support.solve(doc, absent.records, Vector3.ZERO, 0.0, parameters).get("code") == "residential_support_unsupported", "frozen missing foundation cannot borrow its recipe depth")
			report.frozen = {"source_count": plan.records.size(), "frozen_count": frozen.records.size(), "result": frozen_result}
		var fractional_parameters := parameters.merged({"width": 9.3, "depth": 11.2}, true)
		var fractional := Blueprint.generate(fractional_parameters)
		var fractional_frozen := House.bake(fractional.records) if fractional.ok else {"ok": false}
		check(fractional_frozen.ok and Support.solve(doc, fractional_frozen.records, Vector3.ZERO, 0.0, fractional_parameters).ok,
			"fractional native dimensions retain frozen foundation support")
	var output := "D:/code/rmmo_runtime/review_artifacts/editor_reliability/residential_support"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	report.merge({"failures": failures, "checks": checks, "elapsed_ms": (Time.get_ticks_usec() - started) / 1000.0,
		"scope": "headless CPU geometry; no gameplay, GPU, UI or HTTP acceptance"})
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
	print("test_residential_support: checks=%d failures=%d elapsed_ms=%.3f" % [checks.size(), failures, report.elapsed_ms])
	quit(0 if failures == 0 else 1)
