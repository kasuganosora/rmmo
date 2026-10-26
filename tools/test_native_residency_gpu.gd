extends "res://tools/test_asset_residency_gpu.gd"
const Doc=preload("res://scripts/world3d/world_document.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/runtime_completion_20261017/"
const FAR=Vector3(2400,.9,4)
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failures+=1
func fixture_native()->String:
	var doc:=Doc.new();doc.map_meta={"building_instances":{},"spawn":[0,.9,4]}
	for index in 2:
		var x:=index*2400.;var id:="house_%d"%index
		var tile:Dictionary=preload("res://tools/test_terrain_incremental.gd").fixture(16);tile.uuid="terrain_%d"%index;tile.position=[x,0,0];doc.records.append(tile)
		var texture:=folder.path_join("paint_%d.png"%index);var image:=Image.create(64,64,false,Image.FORMAT_RGBA8);image.fill(Color(.5+index*.1,.4,.3));image.save_png(texture)
		var definition:={"name":"native_%d"%index,"color":[1.,1.,1.,1.],"roughness":.8,"texture_path":texture}
		var cube:=BoxMesh.new();cube.size=Vector3(2,2,2);var arrays:Array=cube.surface_get_arrays(0)
		var data:={"materials":[{"paint":definition,"cull":0}],"meshes":[{"surfaces":[arrays],"materials":[0],"bounds":cube.get_aabb(),"box_size":Vector3.ZERO}],"entries":[[[0],[0,0]]]}
		var bytes:=var_to_bytes(data);var frozen:={"version":1,"sha256":Store._sha(bytes),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
		var registry:={"version":Blueprint.VERSION,"parameters":Blueprint.defaults(),"position":[x,0,0],"yaw":0.,"parts":{},"signatures":{},"baked":true}
		for i in 3:
			var part:String=["shell","roof","door"][i];var uuid:=id+"_"+part
			var record:={"uuid":uuid,"kind":"box","surface_id":"block","collision":"block","position":[x+i*4-4,1,0],"rotation":[0.,0.,0.],"size":[1.,1.,1.],"house_prefab":frozen,"prefab_locked":true,"prefab_materials":[definition],"building":{"id":id,"part":part,"role":part,"floor":0,"floor_y":0.}}
			if part=="door":record.fixture={"id":"entry","kind":"door","pivot":[-1.,0.,0.],"angle":90.,"open":0.}
			doc.records.append(record);registry.parts[part]=uuid;registry.signatures[part]="fixture_"+part
		doc.map_meta.building_instances[id]=registry
	var path:=folder.path_join("map.gltf");check(doc.save(path)==OK,"save native terrain plus complete frozen house/roof/door units")
	check(Directory.build(path,Paths.external_root(),doc.records).ok,"verify complete native fixture dependency directory")
	return path
func watches_native()->Dictionary:
	var spec:Dictionary=map_root.get_meta("stream_by_id")["house_0_shell"];var mesh:Mesh=spec.mesh
	var material:Material=mesh.surface_get_material(0)
	return {"mesh":weakref(mesh),"material":weakref(material),"texture":weakref(material.albedo_texture)}
func poll_retirement()->void:
	# Automatic _process is disabled for deterministic grace-period control.
	# Mirror its cleanup-before-observation order too: poll only unregisters;
	# the next frame drops preparation owners and requeues compact references.
	logical_msec=maxi(logical_msec+residency.grace_msec+1,Time.get_ticks_msec())
	residency._drain_cleanup();residency.poll(logical_msec)
	for i in 12:
		logical_msec+=residency.grace_msec+1
		residency._drain_cleanup();residency.poll(logical_msec)
		await process_frame
	residency._drain_cleanup()
	check(residency._cleanup_pending.is_empty(),"native retirement drains deferred ownership and reconstruction queue")
func run()->void:
	create_timer(180).timeout.connect(func():print("NATIVE_RESIDENCY_TIMEOUT");quit(2))
	folder=Paths.cache_directory("native_resident_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var path:=fixture_native();var sha:=FileAccess.get_sha256(path)
	host=Host.new();root.add_child(host);host._ready_for_play=true;host._hud=Control.new();host.add_child(host._hud);host._status=Label.new();host.add_child(host._status)
	loader=Loader.new();loader.near_first=true;host.add_child(loader);loader.start(path,A)
	var result:Array=await loader.finished;map_root=result[0];result.clear()
	check(map_root!=null,"real native MapLoader prepares initial district")
	if map_root==null:quit(1);return
	host.add_child(map_root);host._map_root=map_root;host._map_path=path
	var author:=var_to_bytes(map_root.get_meta("author_reference_extras"))
	deferred=map_root.get_node("DeferredAssets")
	Stream.sync(map_root,host,A)
	navigation=Navigation.new();host.add_child(navigation);host._navigation=navigation;host._map_data.build(map_root);host._bind_deferred_geometry(map_root,navigation)
	residency=map_root.get_node("NativeResidency");residency.set_process(false);residency.grace_msec=1
	map_root.get_node("AssetResidency").set_process(false)
	navigation.build(map_root.get_meta("stream_library"),A);deferred.activate(host)
	deferred.release_demand("entry_safety") # Production entry completion releases this pin.
	if not await settle(A,"native A"):await cleanup();quit(1);return
	check(map_root.get_meta("stream_by_id").has("house_0_shell") and not map_root.get_meta("stream_by_id").has("house_1_shell"),"complete A is resident while far B remains a compact reference")
	var weak:=watches_native();check(Fixtures.set_runtime(map_root,"house_0","entry",.7,0.).ok,"change real door pose before retirement")
	var digest:String=map_root.get_meta("stream_by_id")["house_0_shell"].ground_batch_record.house_prefab.sha256
	check(House._meshes.erase(digest),"simulate decoded instance-cache eviction while its independent render-cache owner survives")
	if not await settle(FAR,"native B"):await cleanup();quit(1);return
	Stream.pin_source(map_root,"source_guard",A);Stream.sync(map_root,host,FAR)
	await poll_retirement();check(map_root.get_meta("stream_by_id").has("house_0_shell"),"transfer source pin prevents full native retirement")
	Stream.release_source(map_root,"source_guard");await settle(FAR,"unpin native B");await poll_retirement()
	check(not map_root.get_meta("stream_by_id").has("house_0_shell") and not map_root.get_meta("stream_by_id").has("terrain_0"),"complete far house and its terrain leave the resident index")
	check(map_root.get_meta("stream_by_id").has("house_1_shell") and map_root.get_meta("stream_by_id").has("terrain_1"),"current district remains resident")
	await probe_released(weak,"native far district")
	for cycle in 2:
		await settle(A,"native revisit A %d"%cycle);await poll_retirement()
		var door:Dictionary=map_root.get_meta("stream_by_id").get("house_0_door",{})
		check(not door.is_empty() and is_equal_approx(float(door.extras.fixture.open),.7),"revisit restores original door identity and runtime open state %d"%cycle)
		check(map_root.get_meta("stream_by_id").has("terrain_0") and not map_root.get_meta("stream_by_id").has("terrain_1"),"revisit restores terrain while retiring the previous district %d"%cycle)
		await settle(FAR,"native revisit B %d"%cycle);await poll_retirement()
		check(map_root.get_meta("stream_library").size()==4,"repeated districts return to bounded native resident count %d"%cycle)
	check(var_to_bytes(map_root.get_meta("author_reference_extras"))==author and FileAccess.get_sha256(path)==sha,"runtime retirement preserves complete author metadata and disk source SHA")
	var report:={"passed":passed,"failures":failures,"native":residency.profile.duplicate(),"path":path,"sha256":sha}
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+"native_gpu.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	await cleanup();print("NATIVE_RESIDENCY_GPU ",JSON.stringify(report));quit(1 if failures else 0)
