extends SceneTree
## CPU-only temporary fixtures: complete slab/kerb bounds and demanded closure.
const Index = preload("res://scripts/world3d/map_dependency_index.gd")
const Road = preload("res://scripts/world3d/road_surface.gd")
const Kerb = preload("res://scripts/world3d/road_kerb.gd")
const Prepare = preload("res://scripts/world3d/chunk_reference_preparation.gd")
const RoadPreparation = preload("res://scripts/world3d/native_road_preparation.gd")
const Fixtures = preload("res://tools/test_map_dependency_index.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
var passed := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS: " if value else "FAIL: ", label)
	if value: passed += 1
	else: failures += 1

func road(id: String, x: float, with_kerbs: bool = true) -> Dictionary:
	var result := {"uuid":id,"kind":"box","position":[x,.5,0],"rotation":[0,0,0],"size":[32,.2,20],"surface_id":"road","collision":"walk","editor_name":"Sloped paved road","surface_paint":[],"road_clearance":3.0,"road_source":"main_street","road_mesh":{"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[x,.5,0],"grade":[.1,.03]}}
	if with_kerbs:
		# Persisted geometry may extend beyond the slab's nominal size. The
		# directory must cover these actual points, even for an edited profile.
		result.road_mesh.kerbs=[{"a":Kerb.section(Vector3(18,.2,-5),Vector2.RIGHT,Kerb.defaults(),[.1,.03]),"b":Kerb.section(Vector3(18,.2,5),Vector2.RIGHT,Kerb.defaults(),[.1,.03]),"u":7.0,"length":10.0,"cap_a":true,"cap_b":true}]
		result.road_kerb_material={"name":"Test limestone","color":[.6,.6,.55,1.0],"roughness":.9}
	return result

func entry(index: Dictionary, at: int) -> Dictionary:
	var row: Dictionary = index.rows[at]
	return {"record_index":at,"compact_record":index.extras.rmmo_records[at],"bounds":row.bounds,"group_id":row.group_id,"asset_path":row.asset_path}

func encloses_arrays(record: Dictionary, bounds: AABB) -> bool:
	var pose := Transform3D(Basis.from_euler(Index._vec(record.rotation)*PI/180.0),Index._vec(record.position))
	for arrays: Array in Road.arrays(record):
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			if not bounds.has_point(pose*vertex): return false
	return true

func run() -> void:
	var helper := Fixtures.new()
	helper.content_root=Paths.external_root(); helper.folder=Paths.cache_directory("road_dependency_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(helper.folder)
	var record := road("road",0)
	var row := Index._classify(record,helper.content_root,{})
	check(Road.valid(record) and row.classification=="spatial" and row.reason=="native_road", "validated standalone road becomes spatial")
	check(row.bounds.position.y < -.9 and row.bounds.end.y > 2.4 and row.bounds.end.x > 18.27, "grade, bottom slab and kerbs exceed the locator box and stay included")
	check(encloses_arrays(record,row.bounds), "bounds contain every generated slab and persisted kerb triangle")
	check(row.terrain_halo==0.0 and row.owner_keys.is_empty() and row.asset_path.is_empty(), "road adds no neighbour halo or external model identity")
	var all_poses := true
	for i in 12:
		var posed := record.duplicate(true)
		posed.position=[-49999.12+i*31.2,74.75,42990.25-i*17.3]
		posed.rotation=[i*11.75,i*29.9,-i*7.75]
		posed.size=[16.0+i,.125+i*.075,30.0-i]
		var placed := Index._classify(posed,helper.content_root,{})
		all_poses = all_poses and placed.classification=="spatial" and encloses_arrays(posed,placed.bounds)
	check(all_poses, "nonuniform dimensions, full Euler pose and large coordinates conservatively enclose real vertices")
	var plain := road("plain",0,false); plain.erase("road_clearance"); plain.erase("road_source")
	check(Index._classify(plain,helper.content_root,{}).reason=="native_road", "optional author clearance and source identifier are not runtime neighbours")
	var future := record.duplicate(true); future.future_geometry={"extrude":100}
	check(Index._classify(future,helper.content_root,{}).classification=="global", "unknown top-level geometry remains global")
	future=record.duplicate(true); future.road_mesh.future_geometry=100
	check(Index._classify(future,helper.content_root,{}).classification=="global", "unknown nested road field remains global")
	future=record.duplicate(true); future.road_mesh.kerbs[0].future_profile=100
	check(Index._classify(future,helper.content_root,{}).classification=="global", "unknown nested kerb field remains global")
	future=record.duplicate(true); future.road_mesh.grade=[.15,.15]
	check(Index._classify(future,helper.content_root,{}).classification=="global", "invalid slope cannot acquire trusted spatial bounds")
	for key in ["event","wind_response","bridge_mesh","bank_wetness"]:
		future=record.duplicate(true); future[key]={}
		check(Index._classify(future,helper.content_root,{}).classification=="global", "unproved road behavior stays global: "+key)
	for key in ["building","fortification","fixture"]:
		future=record.duplicate(true); future[key]={"id":"owned"}
		check(Index._classify(future,helper.content_root,{}).classification=="global", "road cannot bypass ownership: "+key)
	var channel := plain.duplicate(true); channel.uuid="channel"; channel.position[0]=3000
	channel.channel_mesh=channel.road_mesh; channel.erase("road_mesh")
	check(Index._classify(channel,helper.content_root,{}).classification=="global", "channel canonicalisation remains outside this road-only proof")
	future=helper.box("rock",4000); future.rock_bank={}
	check(Index._classify(future,helper.content_root,{}).classification=="global", "rock noise geometry stays global")
	var terrain := helper.box("terrain",5000)
	terrain.size=[32,1,32]; terrain.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-2,"heights":[0,1,2,0,1,2,0,1,2],"holes":[false,false,false,false]}
	var terrain_row := Index._classify(terrain,helper.content_root,{})
	check(terrain_row.classification=="global" and terrain_row.terrain_halo==24.0, "terrain normal and height context remains global with original halo")
	var far := road("far",512,false); far.color=[.2,.3,.4]
	var records: Array=[record,far,channel,terrain]
	var fixture: Dictionary=helper.fixture("mixed",records)
	var built := Index.build(fixture.path,helper.content_root,records)
	check(built.ok, "road directory persists against exact reference definitions")
	if built.ok:
		var read := Index.read(fixture.path,helper.content_root)
		check(read.ok and read.rows[0].reason=="native_road", "persistent schema accepts native road proof and generator")
		var selected := Index.select(read,[AABB(Vector3(-1,-10,-1),Vector3(2,20,2))])
		check(selected.record_indices==[0,2,3] and selected.deferred_indices==[1], "selected source order skips distant road while retaining global channel and terrain")
		check(selected.deferred_entries[0].reason=="native_road" and selected.deferred_entries[0].compact_record==fixture.extras.rmmo_records[1], "deferred descriptor retains reason, author pose and reference for revisit")
		check(selected.extras.custom.complete_metadata and read.extras.rmmo_records.size()==4 and not selected.closure_complete, "selected closure does not replace complete author metadata")
		var kerb_clip := Index.select(read,[AABB(Vector3(18.25,-100,-1),Vector3(.02,200,2))])
		check(kerb_clip.record_indices.has(0), "kerb-only overlap outside nominal slab selects its complete record")
		var estimate := RoadPreparation.estimate(record)
		check(estimate.ok and int(read.rows[0].memory_bytes)>int(estimate.estimated_bytes), "directory admission includes CPU road working set beyond reference bytes")
		var worker := Thread.new()
		worker.start(Prepare.prepare.bind(read,[entry(read,1)],fixture.path,helper.content_root))
		var prepared: Dictionary=worker.wait_to_finish()
		check(prepared.error.is_empty() and prepared.record_indices==[1] and Index._json_equal(prepared.records[0],JSON.parse_string(JSON.stringify(far)),0,[2000000]), "native singleton hydrates on worker with exact road, paint, collision and UUID data")
		if not prepared.error.is_empty(): print(prepared.error)
		check(prepared.get("surface_arrays",{}).has("far") and prepared.get("read_profile",{}).get("road_instances",0)==1, "demanded road includes worker-owned CPU geometry for publication")
		check(prepared.get("selected_closure_verified",false) and not prepared.get("closure_complete",true), "demanded singleton proves only its verified closure")
		var smaller := read.duplicate(true); smaller.rows[1].bounds=AABB(Vector3(512,0,0),Vector3(.01,.01,.01))
		check(not Prepare.prepare(smaller,[entry(smaller,1)],fixture.path,helper.content_root).error.is_empty(), "demand re-derives geometry and rejects forged tiny directory bounds")
		var low_memory := read.duplicate(true); low_memory.rows[1].memory_bytes=65536
		check(not Prepare.prepare(low_memory,[entry(low_memory,1)],fixture.path,helper.content_root).error.is_empty(), "forged undersized road working-set reservation is rejected before geometry")
		var far_path: String=helper.folder.path_join(fixture.extras.rmmo_records[1].rmmo_ref.uri)
		var original_far := FileAccess.get_file_as_bytes(far_path); DirAccess.remove_absolute(far_path)
		check(Index.read(fixture.path,helper.content_root).ok and Prepare.prepare(read,[entry(read,0)],fixture.path,helper.content_root).error.is_empty(), "missing undemanded road payload cannot block a verified near road")
		check(not Prepare.prepare(read,[entry(read,1)],fixture.path,helper.content_root).error.is_empty(), "missing far road fails locally when it is demanded")
		helper.write_bytes(far_path,original_far)
		var original_cache := FileAccess.get_file_as_bytes(read.index_path)
		var payload: Dictionary=bytes_to_var(original_cache.slice(49)); payload.generator="0".repeat(64)
		helper.replace_payload(read.index_path,payload)
		check(not Index.read(fixture.path,helper.content_root).ok, "old geometry generator cannot reuse a native road directory")
		helper.write_bytes(read.index_path,original_cache)
		var author := FileAccess.get_file_as_bytes(fixture.path); helper.write_bytes(fixture.path,author+" ".to_utf8_buffer())
		check(not Index.read(fixture.path,helper.content_root).ok and not Prepare.prepare(read,[entry(read,0)],fixture.path,helper.content_root).error.is_empty(), "full author source SHA still gates index and demanded preparation")
	else: print(built)
	for path: String in helper.created:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(helper.folder.path_join("mixed.gltf.resources")); DirAccess.remove_absolute(helper.folder)
	helper.free()
	print("ROAD_DEPENDENCY_INDEX passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
