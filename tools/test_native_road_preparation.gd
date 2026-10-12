extends SceneTree
## Headless CPU-only regression; never creates a Mesh or edits an author map.
const Prepare = preload("res://scripts/world3d/native_road_preparation.gd")
const Road = preload("res://scripts/world3d/road_surface.gd")
const Kerb = preload("res://scripts/world3d/road_kerb.gd")
const Chunk = preload("res://scripts/world3d/chunk_reference_preparation.gd")
const Index = preload("res://scripts/world3d/map_dependency_index.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Fixtures = preload("res://tools/test_map_dependency_index.gd")
var passed := 0
var failures := 0

class Token extends RefCounted:
	var checks := 0
	var after := 1
	func is_cancelled() -> bool:
		checks += 1
		return checks >= after

class MutationToken extends RefCounted:
	var checks := 0
	var path := ""
	var bytes := PackedByteArray()
	func is_cancelled() -> bool:
		checks += 1
		# One road: the eighth check is the post-array cancellation boundary.
		if checks == 8:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(bytes); file.close()
		return false

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS: " if value else "FAIL: ", label)
	if value: passed += 1
	else: failures += 1

func road() -> Dictionary:
	return {"uuid":"road", "kind":"box", "position":[321,0,160], "rotation":[0,37,0], "size":[32,.18,32], "surface_id":"block", "collision":"block", "road_mesh":{"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[320,0,160]}}

func part(cap_a: bool, cap_b: bool) -> Dictionary:
	return {"a":Kerb.section(Vector3(-3,.09,-2),Vector2(0,1),Kerb.defaults(),[0,0]), "b":Kerb.section(Vector3(3,.09,-2),Vector2(0,1),Kerb.defaults(),[0,0]), "u":7.25, "length":6, "cap_a":cap_a, "cap_b":cap_b}

func vertices(arrays: Array) -> int:
	var count := 0
	for surface: Array in arrays: count += surface[Mesh.ARRAY_VERTEX].size()
	return count

func entry(index: Dictionary) -> Array:
	var row: Dictionary = index.rows[0]
	return [{"record_index":0,"compact_record":index.extras.rmmo_records[0],"bounds":row.bounds,"group_id":row.group_id,"asset_path":row.asset_path}]

func run() -> void:
	var cases: Array = [road()]
	var grade := road(); grade.uuid = "grade"
	grade.road_mesh.grade = [.035,-.02]
	grade.road_mesh.polygons = [[[-.5,-.5],[-.1,-.5],[-.1,.5],[-.5,.5]],[[.1,-.5],[.5,-.5],[.5,.5],[.1,.5]]]
	cases.append(grade)
	for caps in [[false,false],[true,false],[false,true],[true,true]]:
		var kerbed := road(); kerbed.uuid = "kerb_%s_%s" % caps
		kerbed.road_mesh.kerbs = [part(caps[0],caps[1])]
		cases.append(kerbed)
	for record: Dictionary in cases:
		var original := var_to_bytes(record)
		var expected := Road.arrays(record)
		var estimate := Prepare.estimate(record)
		var worker := Thread.new(); worker.start(Prepare.prepare.bind(record))
		var actual: Dictionary = worker.wait_to_finish()
		check(actual.error.is_empty() and var_to_bytes(actual.arrays) == var_to_bytes(expected), "%s: worker vertices/normals/UV/tangents and surface order exactly match author generator" % record.uuid)
		check(estimate.ok and vertices(actual.arrays) <= estimate.vertex_limit and estimate.output_bytes == estimate.vertex_limit * 48 and actual.estimated_bytes > estimate.output_bytes * 2, "%s: retained output and working arrays charged conservatively" % record.uuid)
		check(var_to_bytes(record) == original, "%s: author pose, material references and persisted geometry unchanged" % record.uuid)
	var workers: Array = []
	var shared: Dictionary = cases[-1]
	for i in 3:
		var worker := Thread.new(); worker.start(Prepare.prepare.bind(shared)); workers.append(worker)
	var expected := var_to_bytes(Road.arrays(shared)); var equal := true
	for worker: Thread in workers:
		var actual: Dictionary = worker.wait_to_finish()
		equal = equal and actual.error.is_empty() and var_to_bytes(actual.arrays) == expected
	check(equal, "independent workers do not share mutable SurfaceTool state")
	for at in [1,2,3]:
		var token := Token.new(); token.after = at
		var cancelled := Prepare.prepare(shared, token)
		check(cancelled.cancelled and cancelled.arrays.is_empty() and not cancelled.error.is_empty(), "cancellation boundary %d exposes no partial arrays" % at)
	var invalid := road(); invalid.road_mesh.polygons[0].reverse()
	check(not Prepare.estimate(invalid).ok and not Prepare.prepare(invalid).error.is_empty(), "invalid polygon rejected before SurfaceTool")
	var ordinary := road(); ordinary.erase("road_mesh")
	check(not Prepare.estimate(ordinary).ok and not Prepare.prepare(ordinary).error.is_empty(), "non-road records do not acquire a native road preparation budget")
	var largest := road(); var polygon: Array = []
	for i in 40:
		var point := Vector2.from_angle(TAU * i / 40.0) * .49; polygon.append([point.x,point.y])
	largest.road_mesh.polygons = []; largest.road_mesh.kerbs = []
	for i in 512: largest.road_mesh.polygons.append(polygon)
	for i in 8192: largest.road_mesh.kerbs.append(part(true,true))
	var maximum := Prepare.estimate(largest)
	check(maximum.ok and maximum.estimated_bytes == Prepare.MAX_ESTIMATED_BYTES and maximum.vertex_limit == 731136, "maximum legal polygon/8192-cap workload has bounded 616497152-byte admission estimate; no geometry generated")
	largest.road_mesh.kerbs.append(part(false,false))
	check(not Prepare.estimate(largest).ok, "over-limit kerb count rejected without generating arrays")
	# Exercise final author validation after road arrays are already produced.
	var helper := Fixtures.new(); helper.content_root = Paths.external_root()
	helper.folder = Paths.cache_directory("native_road_preparation_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(helper.folder)
	var f: Dictionary = helper.fixture("road", [shared])
	var index := Index.build(f.path,helper.content_root,[shared])
	check(index.ok, "temporary reference map and spatial road directory build")
	if index.ok:
		var before := FileAccess.get_file_as_bytes(f.path)
		var prepared := Chunk.prepare(index,entry(index),f.path,helper.content_root)
		check(prepared.error.is_empty() and prepared.surface_arrays.size() == 1 and var_to_bytes(prepared.surface_arrays[shared.uuid]) == expected and prepared.read_profile.road_instances == 1, "verified reference transaction publishes exact arrays keyed by instance UUID")
		var mutator := MutationToken.new(); mutator.path = f.path; mutator.bytes = before + " ".to_utf8_buffer()
		var changed := Chunk.prepare(index,entry(index),f.path,helper.content_root,mutator)
		check(mutator.checks >= 8 and not changed.error.is_empty() and changed.surface_arrays.is_empty(), "author replacement after CPU generation rejects all prepared output")
		helper.write_bytes(f.path,before)
		var token := Token.new(); token.after = 8
		var cancelled := Chunk.prepare(index,entry(index),f.path,helper.content_root,token)
		check(cancelled.cancelled and cancelled.surface_arrays.is_empty() and cancelled.records.is_empty(), "reference cancellation after array generation retains no publishable records or arrays")
		check(FileAccess.get_file_as_bytes(f.path) == before, "successful and cancelled preparation leave author map bytes unchanged")
	for path: String in helper.created:
		if Paths.allowed(path,helper.content_root) and FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(helper.folder.path_join("road.gltf.resources"))
	DirAccess.remove_absolute(helper.folder); helper.free()
	print("NATIVE_ROAD_PREPARATION passed=",passed," failures=",failures)
	quit(0 if failures == 0 else 1)
