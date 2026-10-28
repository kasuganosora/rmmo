extends "res://tools/test_house_geometry_identity_reuse.gd"
func run()->void:
	var policy=preload("res://scripts/world3d/runtime_package_policy.gd");policy.verify_packages=false
	var data:=fixture();var vertices:=PackedVector3Array();vertices.resize(240000)
	for i in vertices.size():vertices[i]=Vector3(i%3,(i/3)%2,0)
	data.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX]=vertices
	data.meshes[0].surfaces[0][Mesh.ARRAY_INDEX]=null
	data.meshes[0].bounds=AABB(Vector3.ZERO,Vector3(2,1,0))
	var value:=encode(data);var source:=record(value)
	var bounds:=House.local_bounds(value);var metadata:Dictionary=House._decoded[value.sha256]
	check(bounds.known and bounds.bounds.is_equal_approx(data.meshes[0].bounds.grow(.0001)),"bounds-only request uses the authored envelope")
	check(not metadata.geometry_ready and metadata.geometry_keys.is_empty() and not metadata.has("collision_faces"),"spatial classification computes neither geometry hashes nor triangle expansion")
	check(all_sealed(metadata),"metadata-only decoded owner is recursively sealed")
	bounds.bounds=AABB(Vector3.ONE,Vector3.ONE)
	check(House.local_bounds(value).bounds==metadata.local_bounds.bounds,"caller bounds edits cannot reach retained data")
	var ready:=Semaphore.new();var start:=Semaphore.new();var threads:Array=[]
	var trace=preload("res://scripts/world3d/load_trace.gd");trace.minimum_event_us=0;trace.start()
	for i in 4:
		var worker:=Thread.new();worker.start(func():ready.post();start.wait();return House.prepare_cpu(source));threads.append(worker)
	for i in threads.size():ready.wait()
	for i in threads.size():start.post()
	var results:Array=[]
	for worker:Thread in threads:results.append(worker.wait_to_finish())
	var events:Array=trace.stop().events;var canonical:Dictionary=House._decoded[value.sha256]
	check(events.filter(func(e):return e.label=="prefab.keys_begin").size()==1 and events.filter(func(e):return e.label=="prefab.decode_begin").is_empty(),"four geometry consumers coalesce one upgrade without decoding again")
	check(canonical.geometry_ready and canonical.has("collision_faces") and is_same(canonical.data,metadata.data),"geometry promotion retains the same sealed decoded arrays")
	check(not metadata.geometry_ready and metadata.geometry_keys.is_empty(),"old metadata readers keep their immutable packet")
	for result:Dictionary in results:check(prepared_keys_valid(result) and result.collision_faces[0]==vertices,"every consumer receives the exact geometry identity and ordered faces")
	check(is_same(House._decode_packet(value,false,true),canonical),"later spatial queries never downgrade a full packet")
	# Simultaneous cold metadata and real-geometry requests must work in either
	# flight order, including a consumer joining the metadata decoder.
	for round_ in 8:
		evict(value.sha256);threads.clear();trace.start()
		for i in 4:
			var worker:=Thread.new();var bounds_request:bool=i%2==0
			worker.start(func():ready.post();start.wait();return House._decode_packet(value,not bounds_request,bounds_request));threads.append(worker)
		for i in threads.size():ready.wait()
		for i in threads.size():start.post()
		for i in threads.size():
			var packet:Dictionary=threads[i].wait_to_finish()
			check(not packet.is_empty() and (i%2==0 or (packet.geometry_ready and packet.has("collision_faces"))),"mixed cold reader receives its requested readiness "+str(round_)+"/"+str(i))
		events=trace.stop().events
		check(events.filter(func(e):return e.label=="prefab.decode_begin").size()==1 and House._decoding.is_empty(),"mixed cold requests decode once and drain flights "+str(round_))
	var timings:Array=[]
	for enabled:bool in [false,true,true,false]:
		House.bounds_only_decode_enabled=enabled;var began:=Time.get_ticks_usec()
		for i in 24:evict(value.sha256);House.local_bounds(value)
		timings.append({"bounds_only":enabled,"calls":24,"us":Time.get_ticks_usec()-began})
	House.bounds_only_decode_enabled=true;evict(value.sha256)
	policy.verify_packages=true;House.local_bounds(value)
	check(House._decoded[value.sha256].geometry_ready and House._decoded[value.sha256].verified,"explicit diagnostic verification preserves its full decode contract")
	evict(value.sha256);policy.verify_packages=false;House.local_bounds(value)
	check(House.warm(value) and House._decoded[value.sha256].geometry_ready,"public warm retains its geometry-ready contract")
	House.evict_geometry({value.sha256:true})
	check(House._decoded_bytes==0 and House._decoding.is_empty(),"both metadata and geometry owners retire with exact accounting")
	print("PREFAB_BOUNDS_ONLY_DECODE ",JSON.stringify({"checks":checks,"failures":failures,"timings":timings}));quit(1 if failures else 0)
