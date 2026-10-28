extends "res://tools/test_house_geometry_identity_reuse.gd"
func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	var data:=fixture();var indices:=PackedInt32Array();indices.resize(120000)
	for i in indices.size():indices[i]=i%3
	data.meshes[0].surfaces[0][Mesh.ARRAY_INDEX]=indices
	var value:=encode(data);var source:=record(value)
	var metadata:=House._decode_packet(value)
	check(not metadata.has("collision_faces") and House.retained_decode_bytes(metadata)==int(value.length),"bounds and warm decode do not eagerly expand collision geometry")
	var ready:=Semaphore.new();var start:=Semaphore.new();var threads:Array=[]
	var trace=preload("res://scripts/world3d/load_trace.gd");trace.minimum_event_us=0;trace.start()
	for i in 4:
		var worker:=Thread.new()
		worker.start(func():ready.post();start.wait();return House.prepare_cpu(source));threads.append(worker)
	for i in threads.size():ready.wait()
	for i in threads.size():start.post()
	var results:Array=[]
	for worker:Thread in threads:results.append(worker.wait_to_finish())
	var events:Array=trace.stop().events
	check(events.filter(func(e):return e.label=="prefab.faces_begin").size()==1 and events.filter(func(e):return e.label=="prefab.decode_begin").is_empty(),"four cold consumers coalesce one face expansion and zero repeat decodes")
	var canonical:Dictionary=House._decoded[value.sha256]
	check(canonical.has("collision_faces") and canonical.collision_faces.is_read_only() and is_same(canonical.data,metadata.data),"lazy upgrade reuses the sealed decoded owner")
	check(not metadata.has("collision_faces"),"existing metadata readers retain their immutable packet")
	check(House._decoded_bytes==int(value.length)+120000*12+16,"face capacity is charged once to the bounded decode cache")
	var expected:=preload("res://scripts/world3d/prefab_face_arrays.gd").build(data.meshes[0])
	for result:Dictionary in results:check(result.collision_faces[0]==expected,"every concurrent job retains the exact ordered triangles")
	results[0].collision_faces[0][0]=Vector3(91,92,93)
	check(canonical.collision_faces[0]==expected and results[1].collision_faces[0]==expected and House.prepare_cpu(source).collision_faces[0]==expected,"job mutations cannot reach canonical or sibling packed storage")
	var timings:Array=[]
	for reuse:bool in [false,true,true,false]:
		House.raw_face_reuse_enabled=reuse;evict(value.sha256)
		House._decode_packet(value);var began:=Time.get_ticks_usec()
		for i in 24:House.prepare_cpu(source)
		timings.append({"reuse":reuse,"calls":24,"us":Time.get_ticks_usec()-began})
	House.raw_face_reuse_enabled=true;evict(value.sha256)
	House.prepare_cpu(source)
	check(House._decoded[value.sha256].has("collision_faces"),"full-material path shares the same geometry-only face cache")
	var queue:=preload("res://scripts/world3d/deferred_asset_loader.gd").new();queue._configure_admission_budget()
	check(queue.profile.prefab_decode_reserved_bytes==House.DECODE_BUDGET,"full shared decode ceiling is reserved outside task workspace")
	queue.free();House.evict_geometry({value.sha256:true})
	check(House._decoded_bytes==0 and House._decoding.is_empty(),"eviction releases expanded face accounting and all flights")
	print("RAW_PREFAB_FACE_REUSE ",JSON.stringify({"failures":failures,"timings":timings}));quit(1 if failures else 0)
