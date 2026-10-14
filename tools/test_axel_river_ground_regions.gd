extends SceneTree
const Helper = preload("res://tools/axel_river_ground_regions.gd")
const Regions = preload("res://scripts/world3d/terrain_regions.gd")
const Terrain = preload("res://scripts/world3d/terrain_surface.gd")


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/axel_town_terrain_20261014/recipe.json"))
	var before := JSON.stringify(recipe)
	var calls: Array = Helper.requests(recipe)
	var failures := 0
	var by_id: Dictionary = {}
	var records: Dictionary = {}
	var maximum_work := 0
	var maximum_vertices := 0
	for record: Dictionary in recipe.records:
		records[record.uuid] = record.duplicate(true)
	for args: Dictionary in calls:
		if not Regions.S.validate(args, Regions.request_schema()).is_empty() or not Regions.polygon_valid(args.polygon):
			failures += 1
		if by_id.has(args.id) and by_id[args.id] != args.polygon:
			failures += 1
		by_id[args.id] = args.polygon
		var record: Dictionary = records[args.terrain_ids[0]]
		var inverse: Transform3D = Terrain.transform(record).affine_inverse()
		var local: Array = args.polygon.map(func(p: Array):
			var point: Vector3 = inverse * Vector3(p[0], record.position[1], p[1])
			return [point.x, point.z])
		var data: Dictionary = record.get("terrain_regions", {"materials": [{}], "regions": []})
		data.regions.append({"id": args.id, "polygon": local, "feather": args.feather, "opacity": args.opacity, "layer": 0})
		record.terrain_regions = data
		if not Regions.valid(record) or Regions.work(record) > 8000000:
			failures += 1
		maximum_work = maxi(maximum_work, Regions.work(record))
		var vertices := 0
		for region: Dictionary in data.regions:
			vertices += region.polygon.size()
		maximum_vertices = maxi(maximum_vertices, vertices)
	if calls.is_empty() or by_id.size() != 2 or JSON.stringify(recipe) != before:
		failures += 1
	# Use the production CPU mask, not a duplicate of its blending formula.
	var left: Dictionary = records.axel_terrain_03_01
	var right: Dictionary = records.axel_terrain_04_01
	var left_mask: Image = Regions.mask(left)
	var right_mask: Image = Regions.mask(right)
	var maximum_seam := 0.0
	for z in Regions.RESOLUTION:
		maximum_seam = maxf(maximum_seam, absf(left_mask.get_pixel(Regions.RESOLUTION - 1, z).r - right_mask.get_pixel(0, z).r))
	if maximum_seam > 1.0 / 255.0:
		failures += 1
	var stream: Dictionary = records.axel_terrain_06_02
	var stream_mask: Image = Regions.mask(stream)
	if stream_mask.get_pixel(128, 151).r < .99 or stream_mask.get_pixel(128, 32).r != 0.0 or stream_mask.get_pixel(128, 224).r != 0.0:
		failures += 1
	print("test_axel_river_ground_regions: failures=%d calls=%d main_vertices=%d s12_vertices=%d maximum_tile_vertices=%d maximum_call_work=%d mask_seam=%.9f" % [failures, calls.size(), by_id.get("axel_main_river_local_sand", []).size(), by_id.get("axel_s12_stream_local_sand", []).size(), maximum_vertices, maximum_work, maximum_seam])
	quit(0 if failures == 0 else 1)
