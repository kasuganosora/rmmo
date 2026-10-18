extends "res://tools/test_asset_residency_gpu.gd"
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const FAR=Vector3(2400,.9,4)
func building_glb(path:String)->Error:
	var result:=textured_fixture(path)
	if result!=OK:return result
	var bytes:=FileAccess.get_file_as_bytes(path);var length:=bytes.decode_u32(12)
	var data:Dictionary=JSON.parse_string(bytes.slice(20,20+length).get_string_from_utf8())
	var binary:=bytes.slice(28+length)
	data.nodes=[{"name":"LegacyBuilding","children":[1,2,3],"extras":{"delivery_stage":"textured_repair_v2"}},{"name":"Trim","mesh":0,"translation":[-2,0,0]},{"name":"Foundation","mesh":0,"extras":{"semantic_group":"00_Foundation"}},{"name":"Door","mesh":0,"translation":[2,0,0],"extras":{"rmmo_hinge":{"id":"entry","pivot":[-.5,0,0],"angle":90.,"open":0.}}}]
	var encoded:=JSON.stringify(data).to_utf8_buffer()
	while encoded.size()%4:encoded.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(28+encoded.size()+binary.size())
	file.store_32(encoded.size());file.store_32(0x4e4f534a);file.store_buffer(encoded)
	file.store_32(binary.size());file.store_32(0x004e4942);file.store_buffer(binary);file.close();return OK
func make_building_map()->Dictionary:
	var base:=make_map()
	if not base.ok:return base
	var records:Array=base.records
	for record:Dictionary in records:
		if record.uuid=="ground_c":record.position[0]=FAR.x
	records.append({"uuid":"ground_mid","kind":"box","surface_id":"ground","collision":"walk","position":[700,-.1,0],"rotation":[0,0,0],"size":[32,.2,32]})
	var path:String=base.path;var stored:=Store.write_records(records,path,Paths.external_root())
	if not stored.ok:return {"ok":false}
	var extras:={"rmmo_format":Format.FORMAT,"rmmo_version":Format.FORMAT_VERSION,"rmmo_storage":Format.STORAGE,"rmmo_unit":"m","rmmo_records":stored.records,"rmmo_resource_dependencies":stored.dependencies,"spawn":[0,.9,4]}
	var data:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":extras}]}
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data))
	return {"ok":Directory.build(path,Paths.external_root(),records).ok,"path":path}
func adopt_initial()->bool:
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		Stream.sync(map_root,host,A,Stream.LOAD_BUDGET)
		if map_root.get_meta("stream_chunk",Vector2i(2147483647,0))==Stream.chunk_key(A):return true
		await process_frame
	return false
func run()->void:
	create_timer(180).timeout.connect(func():quit(2))
	folder=Paths.cache_directory("imported_building_retire_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	asset_path=folder.path_join("building.glb")
	check(building_glb(asset_path)==OK and Compiled.build(asset_path).ok,"compile isolated GLB with legacy component floors and a real hinge")
	var fixture:=make_building_map();check(fixture.ok,"write two ordinary model references without a declared model_building group")
	if not fixture.ok:quit(1);return
	var path:String=fixture.path;var sha:=FileAccess.get_sha256(path)
	host=Host.new();root.add_child(host);host._ready_for_play=true;host._hud=Control.new();host.add_child(host._hud);host._status=Label.new();host.add_child(host._status)
	loader=Loader.new();loader.near_first=true;host.add_child(loader);loader.start(path,A)
	var result:Array=await loader.finished;map_root=result[0];result.clear()
	check(map_root!=null,"real loader prepares initial imported building")
	if map_root==null:quit(1);return
	host.add_child(map_root);host._map_root=map_root;host._map_path=path
	deferred=map_root.get_node("DeferredAssets");check(await adopt_initial(),"initial imported namespace adopts completely")
	navigation=Navigation.new();host.add_child(navigation);host._navigation=navigation
	host._map_data.build(map_root);host._bind_deferred_geometry(map_root,navigation)
	residency=map_root.get_node("NativeResidency");residency.set_process(false);residency.grace_msec=1
	var ordinary:Node=map_root.get_node("AssetResidency");ordinary.set_process(false)
	navigation.build(map_root.get_meta("stream_library"),A);deferred.activate(host);deferred.release_demand("entry_safety")
	if not await settle(A,"imported A"):await cleanup();quit(1);return
	var original:=prop_ids("prop_a")
	check(original.size()==3 and residency._resident.has("asset:prop_a") and residency._resident["asset:prop_a"].ids.size()==3,"all namespaced parts map back to one native imported owner")
	check(not ordinary._resident.has("prop_a") and deferred._runtime_building_records.has("prop_a"),"ordinary owner hands off and long-view reload demand remembers the verified adaptation")
	var rows:Array=Fixtures.list_runtime(map_root,"prop_a")
	check(rows.size()==1 and Fixtures.set_runtime(map_root,"prop_a",rows[0].id,.7,0.).ok,"real imported hinge changes before retirement")
	var watches:=resource_watches("prop_a")
	if not await settle(B,"imported B"):await cleanup();quit(1);return
	check(prop_ids("prop_b").size()==3,"second imported building uses the same complete source")
	if not await settle(FAR,"imported departure"):await cleanup();quit(1);return
	await poll_retirement()
	check(prop_ids("prop_a").is_empty() and prop_ids("prop_b").is_empty(),"all parts of both imported namespaces retire beyond the long render ring")
	check(not Assets.has_cached_scene(asset_path),"last imported native owner releases the map's model template")
	await probe_released(watches,"imported departure")
	var clip:=AABB(Vector3(-8,-1000,-8),Vector3(24,2000,24))
	deferred.set_demand("building_probe",clip,-3,"building")
	check(deferred.set_demand_scope(["building_probe"]),"restrict reconstruction to one allowed building ticket")
	var deadline:=Time.get_ticks_msec()+30000
	while prop_ids("prop_a").is_empty() and Time.get_ticks_msec()<deadline:
		Stream.sync(map_root,host,FAR,Stream.FRAME_BUDGET);await process_frame
	check(prop_ids("prop_a")==original and map_root.get_meta("stream_by_id").has("ground_a"),"scoped building demand includes verified support closure before model publication")
	check(prop_ids("prop_b").is_empty(),"scoped support closure does not pull unrelated model instances")
	deferred.set_demand_scope([]);deferred.release_demand("building_probe")
	# 700 m is outside the ordinary 128 m model demand, but inside the existing
	# building draw ring. A retired derived building must return at this distance.
	if not await settle(Vector3(700,.9,4),"imported long-view revisit"):await cleanup();quit(1);return
	check(prop_ids("prop_a")==original,"retired imported building reloads through long-view demand under original UUIDs")
	check(map_root.get_meta("stream_by_id").has("ground_a"),"long-view imported reload restores its supporting landscape outside ordinary player demand")
	rows=Fixtures.list_runtime(map_root,"prop_a")
	check(rows.size()==1 and is_equal_approx(float(rows[0].open),.7),"original imported hinge identity and open state survive whole-asset retirement")
	check(deferred.error.is_empty() and navigation.geometry_error.is_empty() and FileAccess.get_sha256(path)==sha,"imported reconstruction preserves source bytes and geometry/navigation contracts")
	await cleanup();print("IMPORTED_BUILDING_RETIREMENT checks=",passed+failures," failures=",failures);quit(1 if failures else 0)
