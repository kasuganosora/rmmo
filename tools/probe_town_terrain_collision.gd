extends SceneTree
## Read-only isolated physics comparison: identical authored triangles, different grouping.
const MAP := "D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const UUID := "town_terrain_5_4"
const START := Vector3(321.2, .9, 160.3)
const Store = preload("res://scripts/world3d/map_resource_store.gd")
const Terrain = preload("res://scripts/world3d/terrain_surface.gd")
const Cpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Slicer = preload("res://scripts/world3d/terrain_collision_preparer.gd")
const WARM_TICKS := 30
const SAMPLE_TICKS := 180
var report: Dictionary = {"failures": 0, "checks": 0, "runs": [], "ray_checks": []}
var _ray_reference: Array = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	report.checks += 1
	if not ok: report.failures += 1
	print("PASS " if ok else "FAIL ", label)

func digest(value: Variant) -> String:
	var hash_ := HashingContext.new()
	hash_.start(HashingContext.HASH_SHA256)
	hash_.update(var_to_bytes(value))
	return hash_.finish().hex_encode()

func partition(faces: PackedVector3Array, mode: String) -> Dictionary:
	var groups: Dictionary = {}
	for i in range(0, faces.size(), 3):
		var key: Variant = 0
		if mode == "current_slices": key = i / Slicer.SLICE_VERTICES
		elif mode == "spatial_slices":
			# Assign whole triangles once by centroid; do not clip/simplify/snap vertices.
			var middle := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
			key = Vector2i(floori(middle.x / 25.), floori(middle.z / 25.))
		if not groups.has(key): groups[key] = []
		groups[key].append(i)
	var chunks: Array[PackedVector3Array] = []
	var original_offsets: Array[PackedInt32Array] = []
	for key: Variant in groups:
		# Keep the production per-shape face cap in the spatial variant as well.
		var limit := faces.size() if mode == "single_shape" else Slicer.SLICE_VERTICES
		var chunk := PackedVector3Array()
		var offsets := PackedInt32Array()
		for offset: int in groups[key]:
			if chunk.size() == limit:
				chunks.append(chunk); original_offsets.append(offsets)
				chunk = PackedVector3Array(); offsets = PackedInt32Array()
			for j in 3: chunk.append(faces[offset + j])
			offsets.append(offset)
		if not chunk.is_empty(): chunks.append(chunk); original_offsets.append(offsets)
	var seen: Dictionary = {}
	var exact := true
	for k in chunks.size():
		for j in original_offsets[k].size():
			var offset: int = original_offsets[k][j]
			if seen.has(offset): exact = false
			seen[offset] = true
			for v in 3:
				if chunks[k][j * 3 + v] != faces[offset + v]: exact = false
	return {"chunks": chunks, "exact": exact and seen.size() * 3 == faces.size()}

func statistics(values: Array[float]) -> Dictionary:
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.
	for value: float in ordered: total += value
	return {"samples": ordered.size(), "total_ms": total, "mean_ms": total / ordered.size(),
		"p50_ms": ordered[floori((ordered.size() - 1) * .5)],
		"p95_ms": ordered[floori((ordered.size() - 1) * .95)],
		"p99_ms": ordered[floori((ordered.size() - 1) * .99)], "max_ms": ordered.back()}

func ray_points(record: Dictionary) -> Array:
	var points: Array = []
	var t: Dictionary = record.terrain_mesh
	# Terrain.sample describes the base surface only. Authored cultivation is a
	# real raised collision surface, so include its original triangle intersections.
	var cultivation: Dictionary = preload("res://scripts/world3d/terrain_furrows.gd").generate(record)
	var raised: PackedVector3Array = cultivation.vertices
	var raised_triangles: Array = []
	for i in range(0, raised.size(), 3):
		var a := raised[i]; var b := raised[i + 1]; var c := raised[i + 2]
		var low := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
		var high := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
		raised_triangles.append({"bounds": Rect2(low, high - low), "a": a, "b": b, "c": c})
	for z in int(t.rows):
		for x in int(t.columns):
			if not Terrain.solid(t, x, z): continue
			var corners: Array[Vector3] = Terrain.cell(record, x, z)
			var low := minf(minf(corners[0].y, corners[1].y), minf(corners[2].y, corners[3].y))
			var high := maxf(maxf(corners[0].y, corners[1].y), maxf(corners[2].y, corners[3].y))
			if low == 0. and high == 0. and (x % 8 != 0 or z % 8 != 0): continue
			var p := corners[0].lerp(corners[1], .31).lerp(corners[3].lerp(corners[2], .31), .63)
			p.y = Terrain.sample(record, p)
			var base_y := p.y
			for triangle: Dictionary in raised_triangles:
				if not triangle.bounds.has_point(Vector2(p.x, p.z)): continue
				var crossing: Variant = Geometry3D.segment_intersects_triangle(p + Vector3.UP * 20., p - Vector3.UP * 20., triangle.a, triangle.b, triangle.c)
				if crossing is Vector3: p.y = maxf(p.y, crossing.y)
			points.append({"local": p, "base_y": base_y, "class": "cultivation" if p.y - base_y > .001 else ("slope" if high - low > .001 else ("riverbed" if low < -.001 else "flat"))})
	return points

func validate_rays(host: Node3D, body: CharacterBody3D, record: Dictionary, points: Array, mode: String) -> void:
	var hits: Array = []
	var max_height_error := 0.
	var max_reference_error := 0.
	var max_normal_error := 0.
	var missing := 0
	var classes := {"flat": 0, "riverbed": 0, "slope": 0, "cultivation": 0}
	var pose := Terrain.transform(record)
	for i in points.size():
		var point: Vector3 = pose * points[i].local
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 20., point - Vector3.UP * 20.)
		query.exclude = [body.get_rid()]
		var hit := host.get_world_3d().direct_space_state.intersect_ray(query)
		classes[points[i].class] += 1
		if hit.is_empty():
			missing += 1; hits.append({}); continue
		max_height_error = maxf(max_height_error, hit.position.distance_to(point))
		hits.append({"position": hit.position, "normal": hit.normal})
		if not _ray_reference.is_empty() and not _ray_reference[i].is_empty():
			max_reference_error = maxf(max_reference_error, hit.position.distance_to(_ray_reference[i].position))
			max_normal_error = maxf(max_normal_error, hit.normal.distance_to(_ray_reference[i].normal))
	if _ray_reference.is_empty(): _ray_reference = hits
	check(missing == 0 and max_height_error < .002 and max_reference_error < .002 and max_normal_error < .001,
		mode + " flat/slope/riverbed/cultivation rays preserve authored height and reference normals")
	report.ray_checks.append({"mode": mode, "count": points.size(), "classes": classes, "missing": missing,
		"height_max_error_m": max_height_error, "reference_max_error_m": max_reference_error, "normal_max_error": max_normal_error})

func measure(record: Dictionary, definition: Dictionary, mode: String, round_: int, points: Array) -> void:
	var host := Node3D.new()
	root.add_child(host)
	var terrain_body := StaticBody3D.new()
	host.add_child(terrain_body)
	terrain_body.global_transform = Terrain.transform(record)
	var began := Time.get_ticks_usec()
	var copied_exact := true
	for faces: PackedVector3Array in definition.chunks:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		copied_exact = copied_exact and shape.get_faces() == faces
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		terrain_body.add_child(shape_node)
	var cook_ms := (Time.get_ticks_usec() - began) / 1000.
	check(copied_exact, mode + " actual physics shapes retain every source triangle")
	var body := CharacterBody3D.new()
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3; capsule.height = 1.8
	collider.shape = capsule
	body.add_child(collider); host.add_child(body)
	body.global_position = START; body.floor_snap_length = .2
	await physics_frame; await physics_frame
	if round_ == 0: validate_rays(host, body, record, points, mode)
	var moves: Array[float] = []
	var cameras: Array[float] = []
	var casts: Array[float] = []
	var min_fraction := 1.
	for tick in WARM_TICKS + SAMPLE_TICKS:
		await physics_frame
		body.velocity.x = 0.; body.velocity.z = 0.
		body.velocity.y -= 9.8 * body.get_physics_process_delta_time()
		began = Time.get_ticks_usec()
		body.move_and_slide()
		var move_ms := (Time.get_ticks_usec() - began) / 1000.
		# Same production radius/margin/default orbit; separate query setup from engine cast.
		began = Time.get_ticks_usec()
		var sphere := SphereShape3D.new(); sphere.radius = .2
		var query := PhysicsShapeQueryParameters3D.new()
		var focus := body.global_position + Vector3.UP * (clampf(1.9 * .84, 1.4, 1.7) - .9)
		query.shape = sphere; query.transform = Transform3D(Basis.IDENTITY, focus)
		query.motion = Vector3(0, sin(deg_to_rad(18.)), cos(deg_to_rad(18.))) * 6.
		query.margin = .015; query.collide_with_areas = false; query.exclude = [body.get_rid()]
		var cast_started := Time.get_ticks_usec()
		var fractions := host.get_world_3d().direct_space_state.cast_motion(query)
		var cast_ms := (Time.get_ticks_usec() - cast_started) / 1000.
		var camera_ms := (Time.get_ticks_usec() - began) / 1000.
		if tick >= WARM_TICKS:
			moves.append(move_ms); cameras.append(camera_ms); casts.append(cast_ms)
			min_fraction = minf(min_fraction, fractions[0])
	check(body.is_on_floor() and body.global_position.distance_to(START) < .002, mode + " idle capsule retains exact support")
	var row := {"mode": mode, "round": round_, "shape_count": definition.chunks.size(), "cook_ms": cook_ms,
		"move": statistics(moves), "camera_total": statistics(cameras), "camera_cast": statistics(casts),
		"camera_min_safe_fraction": min_fraction, "final_position": body.global_position,
		"floor_normal": body.get_floor_normal(), "contacts": body.get_slide_collision_count()}
	report.runs.append(row)
	print("TERRAIN_RUN ", JSON.stringify(row))
	host.free()
	await physics_frame; await physics_frame

func run() -> void:
	create_timer(90.).timeout.connect(func(): push_error("terrain probe timeout"); quit(2))
	var source_hash := FileAccess.get_sha256(MAP)
	var gltf: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP))
	var compact: Array = gltf.nodes[0].extras.rmmo_records.filter(func(record): return record.uuid == UUID)
	var hydrated := Store.read_records(compact, MAP, "D:/code/rmmo_runtime")
	check(hydrated.ok and hydrated.records.size() == 1, "single authored terrain definition is read and verified")
	if not hydrated.ok or hydrated.records.size() != 1: quit(1); return
	var record: Dictionary = hydrated.records[0]
	check(Terrain.valid(record), "terrain schema valid")
	var cpu := Cpu.new()
	cpu.surfaces = Terrain.arrays(record)
	var faces: PackedVector3Array = cpu.collision_faces()
	var definitions := {}
	for mode: String in ["current_slices", "single_shape", "spatial_slices"]:
		definitions[mode] = partition(faces, mode)
		check(definitions[mode].exact, mode + " partitions each original triangle exactly once without geometry changes")
	report.source = {"map": MAP, "map_sha256": source_hash, "uuid": UUID, "record_sha256": digest(record),
		"triangles_sha256": digest(faces), "face_vertices": faces.size(), "position": record.position,
		"size": record.size, "columns": record.terrain_mesh.columns, "rows": record.terrain_mesh.rows}
	report.environment = {"version": Engine.get_version_info(), "physics_ticks_per_second": Engine.physics_ticks_per_second,
		"physics_engine_setting": ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"),
		"headless": DisplayServer.get_name(), "cpu": OS.get_processor_name(), "warm_ticks": WARM_TICKS,
		"sample_ticks_per_run": SAMPLE_TICKS, "scope": "single real terrain body; no nearby town colliders or traversal guard",
		"camera": "production default orbit/radius/margin, no nearby building occluders"}
	var points := ray_points(record)
	for mode: String in ["current_slices", "single_shape", "spatial_slices"]:
		await measure(record, definitions[mode], mode, 0, points)
	for mode: String in ["spatial_slices", "single_shape", "current_slices"]:
		await measure(record, definitions[mode], mode, 1, points)
	check(FileAccess.get_sha256(MAP) == source_hash, "formal map remains unchanged")
	var output := "D:/code/rmmo_runtime/review_artifacts/town_terrain_collision_probe_20261011.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: push_error("cannot write terrain probe report"); quit(2); return
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("TERRAIN_PROBE ", report.checks, " checks / ", report.failures, " failures; ", output)
	quit(int(report.failures))
