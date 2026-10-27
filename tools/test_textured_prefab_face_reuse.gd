extends "res://tools/test_house_geometry_identity_reuse.gd"
## Triangle expansion is independent of material projection. Exercise real
## textured-mode controls, mixed coverage upgrades and private worker outputs.
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Binary=preload("res://scripts/world3d/prefab_binary_cache.gd")
const Faces=preload("res://scripts/world3d/prefab_face_arrays.gd")
func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	Binary.enabled=false;Controls.white_materials=false;Controls.discard_map_textures=false
	var data:=fixture();var indices:=PackedInt32Array();indices.resize(120000)
	for i:int in indices.size():indices[i]=i%3
	data.meshes[0].surfaces[0][Mesh.ARRAY_INDEX]=indices
	data.meshes.append(data.meshes[0].duplicate(true));data.entries[0][1]=[0,1]
	data.materials[0]["values"].albedo_color=Color(.25,.5,.75)
	var value:=encode(data);var source:=record(value);var expected:Array=[]
	for mesh:Dictionary in data.meshes:expected.append(Faces.build(mesh))
	var metadata:=House._decode_packet(value)
	check(not metadata.has("collision_faces"),"metadata requests remain lazy in textured mode")
	check(House.raw_face_reuse_active(),"textured mode can share material-independent raw face work")
	var trace=preload("res://scripts/world3d/load_trace.gd");trace.minimum_event_us=0;trace.start()
	var ready:=Semaphore.new();var start:=Semaphore.new();var threads:Array=[]
	for i:int in 4:
		var worker:=Thread.new();worker.start(func():ready.post();start.wait();return House.prepare_cpu(source));threads.append(worker)
	for i:int in threads.size():ready.wait()
	for i:int in threads.size():start.post()
	var results:Array=[]
	for worker:Thread in threads:results.append(worker.wait_to_finish())
	var log:=trace.stop()
	check(log.events.filter(func(e):return e.label=="prefab.faces_begin").size()==1,"four concurrent textured jobs expand one shared face packet")
	var canonical:Dictionary=House._decoded[value.sha256]
	check(canonical.has("collision_faces") and is_same(canonical.data,metadata.data),"upgrade reuses canonical decoded arrays without material projection")
	check(House._decoded_bytes==int(value.length)+2*(120000*12+16),"both full face slots count against the existing cache ceiling")
	for result:Dictionary in results:
		check(result.collision_faces==expected,"textured worker receives every exact ordered triangle")
		check(var_to_bytes(result.data.materials)==var_to_bytes(data.materials),"textured material definitions stay byte-identical")
	results[0].collision_faces[0][0]=Vector3(99,98,97)
	check(results[1].collision_faces==expected and House.prepare_cpu(source).collision_faces==expected,"worker mutation cannot reach siblings or the canonical cache")
	House.evict_geometry({value.sha256:true})
	check(House._decoded_bytes==0 and House._decoding.is_empty(),"logical eviction releases shared face accounting and flights")
	check(results[1].collision_faces==expected,"admitted worker results survive canonical eviction")
	Controls.enable_white_materials();Controls.discard_map_textures=true
	var white:=House.prepare_cpu(source,{},true,false)
	check(white.collision_faces[0].is_empty() and white.collision_faces[1]==expected[1],"white source-only preparation remains selective")
	Controls.white_materials=false;Controls.discard_map_textures=false
	House.raw_face_reuse_enabled=false
	var uncached:=House.prepare_cpu(source,{},true,false)
	check(uncached.collision_faces==expected,"disabled reuse still fills slots missing from a prior white partial packet")
	House.raw_face_reuse_enabled=true
	var full:=House.prepare_cpu(source,{},true,false)
	check(full.collision_faces==expected and full.data.materials==data.materials,"textured consumer upgrades a white partial packet to every face slot")
	check(House._decoded[value.sha256].get("collision_face_slots",{}).size()==2,"coverage upgrade is retained for following textured consumers")
	var queue:=preload("res://scripts/world3d/deferred_asset_loader.gd").new();queue._configure_admission_budget()
	check(queue.profile.prefab_decode_reserved_bytes==House.DECODE_BUDGET,"textured task admission reserves the bounded shared decode ceiling")
	queue.free()
	var timings:Array=[]
	for fast:bool in [false,true,true,false]:
		House.raw_face_reuse_enabled=fast;evict(value.sha256);House._decode_packet(value)
		var began:=Time.get_ticks_usec();var last:Dictionary={}
		for i:int in 12:last=House.prepare_cpu(source)
		timings.append({"reuse":fast,"calls":12,"face_vertices_per_call":240000,"us":Time.get_ticks_usec()-began})
		check(last.collision_faces==expected and last.data.materials==data.materials,"fixed ABBA retains all triangles and material definitions")
	House.raw_face_reuse_enabled=true
	if "--gpu" in OS.get_cmdline_user_args():
		House.evict_geometry({value.sha256:true})
		check(House.publish_prepared(source,full,{},{}),"textured packet publishes after canonical eviction")
		var entry:Dictionary=House.geometry(source);var uploaded:Mesh=entry.mesh.restore()
		check(uploaded.get_surface_count()==1 and uploaded.surface_get_arrays(0)==data.meshes[0].surfaces[0],"actual GPU render channels match the authored geometry")
		var material:StandardMaterial3D=uploaded.surface_get_material(0)
		check(material!=null and material.albedo_color==Color(.25,.5,.75),"shared collision preparation does not replace the real colored material")
	House.evict_geometry({value.sha256:true})
	check(House._decoded_bytes==0 and House._decoding.is_empty(),"final eviction leaves no canonical face reservation or unfinished flight")
	print("TEXTURED_PREFAB_FACE_REUSE ",JSON.stringify({"timings":timings,"failures":failures}));quit(1 if failures else 0)
