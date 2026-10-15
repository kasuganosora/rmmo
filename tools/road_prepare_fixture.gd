extends RefCounted
## Disposable in-memory inputs, using the same native producers as road/bridge tests.
const City = preload("res://scripts/world3d/city_layout.gd")
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const BridgeTools = preload("res://scripts/world_editor/bridge_tools.gd")
const BridgeData = preload("res://scripts/world3d/bridge_data.gd")
const Ports = preload("res://scripts/world3d/road_bridges.gd")

class MaterialTool:
	extends RefCounted
	# No directory is created or shared library changed; builtins are native entries.
	var library = preload("res://scripts/world_editor/surface_material_library.gd").new("res://review_artifacts/road_prepare_20261016/nonexistent_material_library")

class Context:
	extends Node3D
	var _doc = preload("res://scripts/world3d/world_document.gd").new()
	var _authoring = preload("res://scripts/world_editor/authoring_view.gd").new()
	var _material_tool = MaterialTool.new()
	var _waterways = preload("res://scripts/world_editor/waterway_tools.gd").new()
	func _init() -> void:
		_waterways.editor = self
	func _record_editable(record: Dictionary) -> bool:
		return preload("res://scripts/world_editor/selection_geometry.gd").editable(record) and _authoring.includes(record)

static func context(fixture: Dictionary) -> Node3D:
	var out := Context.new()
	out._doc.records = fixture.records.duplicate(true)
	out._doc.map_meta = {"editor_layout": fixture.layout.duplicate(true)}
	return out

static func state(context_: Node3D) -> Array:
	return [context_._doc.recovery_snapshot(), context_._doc._undo, context_._doc._redo,
		context_._doc.editor_dirty, context_._doc.authoring_revision, context_._authoring.settings]

static func box(id: String, position: Array, size: Array, surface := "ground") -> Dictionary:
	return {"uuid": id, "kind": "box", "surface_id": surface, "position": position,
		"rotation": [0., 0., 0.], "size": size, "color": [.3, .4, .2], "collision": "walk"}

static func terrain(id: String, cells: int, at := Vector3.ZERO, span := 40.) -> Dictionary:
	var out := box(id, [at.x, at.y, at.z], [span, 1., span])
	var heights: Array = []; heights.resize((cells + 1) * (cells + 1)); heights.fill(0.)
	var holes: Array = []; holes.resize(cells * cells); holes.fill(false)
	out.terrain_mesh = {"version": 1, "columns": cells, "rows": cells, "floor": -8., "heights": heights, "holes": holes}
	return out

static func graph(paths: Array, width := 3.5) -> Dictionary:
	var result := {"nodes": [], "edges": []}; var ids := {}
	for path: Array in paths:
		var previous := ""
		for xyz: Array in path:
			var key := str(xyz)
			if not ids.has(key):
				ids[key] = "node_%d" % ids.size()
				result.nodes.append({"id": ids[key], "position": xyz})
			if not previous.is_empty():
				result.edges.append({"id": "edge_%d" % result.edges.size(), "from": previous, "to": ids[key],
					"kind": "ground", "width_start": width, "width_end": width})
			previous = ids[key]
	return result

static func make(name_: String, records: Array, graph_: Dictionary, args: Dictionary = {}) -> Dictionary:
	var layout := City.defaults(); layout.roads = graph_
	return {"name": name_, "records": records, "layout": layout, "args": args,
		"expected_ok": true, "dependencies": {}, "construction_error": ""}

static func ordinary() -> Dictionary:
	return make("junction_kerbs", [box("ground", [0., -.25, 0.], [64., .5, 64.])],
		graph([[[-12., 0., 0.], [12., 0., 0.]], [[0., 0., -12.], [0., 0., 12.]]]),
		{"kerb_enabled": true, "kerb_material_id": "builtin:white", "material_id": "builtin:white"})

static func local_terrain(far := false) -> Dictionary:
	var records: Array = [terrain("local_ground", 64)]
	if far:
		for index in 6:
			records.append(terrain("far_ground_%d" % index, 32, Vector3(160. + index * 48., 0., 160.), 32.))
		var parameters := Blueprint.defaults().merged({"layout": "townhouse", "template": "house", "width": 9., "depth": 11.,
			"floors": 1, "rooms_per_floor": 1, "base_height": .3, "foundation_depth": 1., "seed": 7261}, true)
		var generated := Blueprint.generate(parameters)
		if not generated.get("ok", false):
			var failed := make("terrain64_far_complex", records, {"nodes": [], "edges": []})
			failed.construction_error = str(generated); return failed
		# Full native components (walls, roof, floor and hinged fixtures), not cut-down surrogates.
		for house in 1:
			for index in generated.records.size():
				var record: Dictionary = generated.records[index].duplicate(true)
				record.uuid = "far_house_%d_part_%d" % [house, index]
				record.position[0] += 160. + house * 48.; record.position[2] += 160.
				record.building.id = "far_house_%d" % house
				records.append(record)
		for index in 128:
			var prop := box("far_prop_%d" % index, [256. + (index % 16) * 3., 1., 220. + floori(index / 16.) * 3.], [1.2, 2., .8], "wood")
			prop.rotation[1] = float(index * 17 % 180); records.append(prop)
	return make("terrain64_far_complex" if far else "terrain64_local", records,
		graph([[[-14., 0., 0.], [14., 0., 0.]]]), {"follow_terrain": true, "material_id": "builtin:white"})

static func river_bridge() -> Dictionary:
	var source := box("river_source", [0., -.25, 0.], [96., .5, 96.])
	var settings: Dictionary = preload("res://scripts/world3d/waterway_data.gd").defaults().merged({
		"id": "fixture_river", "points": [[0., -36.], [0., 36.]], "ground_ids": ["river_source"],
		"bridges": [{"id": "crossing", "segment": 0, "t": .5, "width": 5., "approach": 3., "rail_height": 1.1}]}, true)
	var built: Dictionary = preload("res://scripts/world3d/waterway_plan.gd").new().build(settings, [source])
	var out := make("waterway_bound_bridge", built.get("records", []), {"nodes": [], "edges": []}, {"material_id": "builtin:white"})
	if not built.get("ok", false): out.construction_error = str(built); return out
	var parts: Array = []
	for record: Dictionary in built.records:
		parts.append({"id": record.uuid, "role": built.roles[record.uuid], "signature": City.token(record)})
	out.layout.waterways = [{"version": 1, "settings": settings, "sources": [source], "parts": parts}]
	var port := Ports.geometry(settings, settings.bridges[0])
	var a: Array = port.endpoints[0]; var b: Array = port.endpoints[1]
	var outside_a := City.vec(a) + (City.vec(a) - City.vec(b)).normalized() * 20.
	var outside_b := City.vec(b) + (City.vec(b) - City.vec(a)).normalized() * 20.
	out.layout.roads = graph([[City.xyz(outside_a), a, b, City.xyz(outside_b)]], port.width)
	out.layout.roads.edges[1].kind = "bridge"
	out.layout.roads.edges[1].bridge_ref = {"waterway_id": settings.id, "bridge_id": settings.bridges[0].id}
	return out

static func stone_bridge() -> Dictionary:
	var out := make("frozen_stone_bridge_approaches", [terrain("flat_ground", 16, Vector3(16., 0., 16.), 32.)],
		graph([[[6., 0., 16.], [26., 0., 16.]]], 4.), {"follow_terrain": true, "material_id": "builtin:white"})
	var prefab := BridgeData.preset("stone_segmental")
	var material := MaterialTool.new().library.find("builtin:white")
	prefab.materials = {"deck": material.duplicate(true), "masonry": material.duplicate(true), "trim": material.duplicate(true)}
	var args := {"id": "fixture_bridge", "start": [10., .025, 16.], "end": [22., .025, 16.],
		"width": 5.2, "depth": 2., "camber": .25, "arches": 1, "wing_length": 1.5}
	var record := BridgeTools.make_record(args, prefab)
	out.dependencies[record.asset_path] = FileAccess.get_sha256(record.asset_path)
	var baked: Dictionary = preload("res://scripts/world3d/structure_prefab.gd").bridge(record)
	if not baked.get("ok", false): out.construction_error = str(baked); return out
	record = baked.record; out.records.append(record)
	var edge: Dictionary = out.layout.roads.edges[0]; edge.kind = "bridge"
	var nodes: Dictionary = {}
	for node: Dictionary in out.layout.roads.nodes: nodes[node.id] = node
	edge.stone_bridge = {"id": record.uuid, "start": args.start, "end": args.end, "width": args.width,
		"signature": City.token(record), "source_token": Ports.stone_source(edge, nodes)}
	return out

static func names() -> Array[String]:
	return ["junction_kerbs", "terrain64_local", "terrain64_far_complex", "waterway_bound_bridge", "frozen_stone_bridge_approaches"]

static func build(name_: String) -> Dictionary:
	match name_:
		"junction_kerbs": return ordinary()
		"terrain64_local": return local_terrain()
		"terrain64_far_complex": return local_terrain(true)
		"waterway_bound_bridge": return river_bridge()
		"frozen_stone_bridge_approaches": return stone_bridge()
	return {"construction_error": "Unknown fixture: " + name_}
