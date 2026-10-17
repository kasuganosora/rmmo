extends SceneTree
## Real GLB/native-reference/physics/navigation regression. GPU execution must
## use tools/run_godot_background.py. Creates only a unique temporary directory.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Directory=preload("res://scripts/world3d/map_dependency_index.gd")
const Format=preload("res://scripts/world3d/world_location.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
class Host extends "res://scripts/world3d/world_3d.gd":
	# Keep production deferred/navigation/minimap binding, without unrelated
	# character loading, network simulation or automatic movement callbacks.
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func _exit_tree()->void:pass
var failures:=0
var passed:=0
var folder:=""
var asset_path:=""
var host:Node
var map_root:Node
var deferred:Node
var navigation:Node
var residency:Node
var loader:Node
var logical_msec:=0
var at:=Vector3(0,.9,4)
const A=Vector3(0,.9,4)
const B=Vector3(512,.9,4)
const C=Vector3(1024,.9,4)
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:
		failures+=1
		if is_instance_valid(map_root):dump_state(label)
func dump_state(label:String)->void:
	# Scalar-only diagnostics: the observer must not retain mesh/material owners.
	var specs:Array=[];var records:Array=[];var pending:Array=[];var visuals:Array=[];var compiled_owners:Array=[]
	for spec:Dictionary in map_root.get_meta("stream_library",[]):
		specs.append({"uuid":spec.get("uuid",""),"extra_uuid":spec.get("extras",{}).get("uuid",""),"record_uuid":spec.get("ground_batch_record",{}).get("uuid",""),"record_kind":spec.get("ground_batch_record",{}).get("kind",""),"mesh_id":spec.mesh.get_instance_id() if spec.get("mesh") is Mesh else 0,"origin":str(spec.get("transform",Transform3D.IDENTITY).origin)})
	for record:Dictionary in map_root.get_meta("extras",{}).get("rmmo_records",[]):records.append({"uuid":record.uuid,"kind":record.get("kind",""),"compact":record.has("rmmo_ref"),"asset":record.get("asset_path","")})
	var nodes:Array[Node]=[map_root]
	while not nodes.is_empty():
		var node:Node=nodes.pop_back();nodes.append_array(node.get_children())
		if node is MeshInstance3D:visuals.append({"path":str(node.get_path()),"extra_uuid":node.get_meta("extras",{}).get("uuid",""),"stream_instance":node.has_meta("stream_instance")})
		if node.has_meta("_compiled_resource_owner"):compiled_owners.append({"path":str(node.get_path()),"children":node.get_child_count(),"owner_id":node.get_meta("_compiled_resource_owner").get_instance_id()})
	if is_instance_valid(deferred):
		for item:Dictionary in deferred.pending:pending.append({"uuid":item.record.uuid,"published":item.get("published",false),"prepared":item.get("reference_prepared",false),"compact":item.record.has("rmmo_ref"),"native":item.get("native_reference",false)})
	print("ASSET_RESIDENCY_STATE ",JSON.stringify({"label":label,"specs":specs,"runtime_records":records,"pending":pending,"visuals":visuals,"compiled_owners":compiled_owners,"by_id":map_root.get_meta("stream_by_id",{}).keys(),"mesh_ids":map_root.get_meta("stream_meshes",{}).keys(),"body_ids":map_root.get_meta("stream_bodies",{}).keys(),"children_marker":map_root.get_meta("stream_children",-2),"children_actual":map_root.get_child_count(),"stream_chunk":str(map_root.get_meta("stream_chunk",null)),"resident":residency._resident if is_instance_valid(residency) else {},"nav_ids":navigation._spec_ids.keys() if is_instance_valid(navigation) else [],"cache_present":Assets.has_cached_scene(asset_path)}))
static func textured_fixture(path:String)->Error:
	# Standard glTF 2.0, embedded PNG, no exporter-specific extensions. All
	# material/texture weak-reference probes therefore test real imported assets.
	var binary:=PackedFloat32Array([-.5,-.5,-.5,.5,-.5,-.5,.5,.5,-.5,-.5,.5,-.5,-.5,-.5,.5,.5,-.5,.5,.5,.5,.5,-.5,.5,.5]).to_byte_array()
	binary.append_array(PackedInt32Array([0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5]).to_byte_array())
	binary.append_array(PackedFloat32Array([0,0,1,0,1,1,0,1,0,0,1,0,1,1,0,1]).to_byte_array())
	var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color(.6,.35,.12,1));image.set_pixel(1,1,Color(.2,.6,.3,1))
	var png:=image.save_png_to_buffer();var png_offset:=binary.size();binary.append_array(png)
	while binary.size()%4:binary.append(0)
	var data:Dictionary={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"ImportedRoot","children":[1]},{"name":"Crate","mesh":0}],"meshes":[{"primitives":[{"attributes":{"POSITION":0,"TEXCOORD_0":2},"indices":1,"material":0}]}],"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":.8}}],"textures":[{"source":0}],"images":[{"bufferView":3,"mimeType":"image/png"}],"accessors":[{"bufferView":0,"componentType":5126,"type":"VEC3","count":8,"min":[-.5,-.5,-.5],"max":[.5,.5,.5]},{"bufferView":1,"componentType":5125,"type":"SCALAR","count":36},{"bufferView":2,"componentType":5126,"type":"VEC2","count":8}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":96},{"buffer":0,"byteOffset":96,"byteLength":144},{"buffer":0,"byteOffset":240,"byteLength":64},{"buffer":0,"byteOffset":png_offset,"byteLength":png.size()}],"buffers":[{"byteLength":binary.size()}]}
	var bytes:=JSON.stringify(data).to_utf8_buffer()
	while bytes.size()%4:bytes.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_32(0x46546c67);file.store_32(2);file.store_32(28+bytes.size()+binary.size())
	file.store_32(bytes.size());file.store_32(0x4e4f534a);file.store_buffer(bytes)
	file.store_32(binary.size());file.store_32(0x004e4942);file.store_buffer(binary);file.close();return OK
func make_map()->Dictionary:
	var records:Array=[]
	for row in [["ground_a",0.0],["ground_b",512.0],["ground_c",1024.0]]:
		records.append({"uuid":row[0],"kind":"box","surface_id":"ground","collision":"walk","position":[row[1],-.1,0],"rotation":[0,0,0],"size":[32,.2,32]})
	for row in [["prop_a",4.0],["prop_b",516.0]]:
		records.append({"uuid":row[0],"kind":"asset","asset_path":asset_path,"surface_id":"model","collision":"block","position":[row[1],.5,4],"rotation":[0,0,0],"size":[1,1,1]})
	var path:=folder.path_join("map.gltf")
	var stored:=Store.write_records(records,path,Paths.external_root())
	if not stored.ok:return {"ok":false,"error":str(stored)}
	var extras:={"rmmo_format":Format.FORMAT,"rmmo_version":Format.FORMAT_VERSION,"rmmo_storage":Format.STORAGE,"rmmo_unit":"m","rmmo_records":stored.records,"rmmo_resource_dependencies":stored.dependencies,"spawn":[0,.9,4]}
	var data:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":extras}]}
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	var built:=Directory.build(path,Paths.external_root(),records)
	return {"ok":built.ok,"path":path,"records":records,"compact":stored.records,"error":str(built.get("reason",""))}
func prop_ids(prefix:String)->Array:
	var result:Array=[]
	for id:String in map_root.get_meta("stream_by_id",{}):
		if id.begins_with(prefix+"__"):result.append(id)
	result.sort();return result
func runtime_has(id:String)->bool:
	return map_root.get_meta("extras",{}).get("rmmo_records",[]).any(func(record):return record.uuid==id)
func author_difference(a:Variant,b:Variant,path:String="$",depth:int=0)->Dictionary:
	if depth>64:return {"path":path,"reason":"depth_limit"}
	if typeof(a)!=typeof(b):return {"path":path,"left_type":type_string(typeof(a)),"right_type":type_string(typeof(b)),"left":str(a),"right":str(b)}
	if a is Dictionary:
		if a.size()!=b.size():return {"path":path,"reason":"different_dictionary_size"}
		for key:Variant in a:
			if not b.has(key):return {"path":path,"reason":"missing_key","key":str(key)}
			var difference:=author_difference(a[key],b[key],path+"."+str(key),depth+1)
			if not difference.is_empty():return difference
	elif a is Array:
		if a.size()!=b.size():return {"path":path,"reason":"different_array_size"}
		for i in a.size():
			var difference:=author_difference(a[i],b[i],path+"[%d]"%i,depth+1)
			if not difference.is_empty():return difference
	elif a!=b:return {"path":path,"reason":"different_value","left":str(a),"right":str(b)}
	return {}
func resource_watches(prefix:String)->Dictionary:
	var ids:=prop_ids(prefix)
	if ids.is_empty():return {}
	var spec:Dictionary=map_root.get_meta("stream_by_id")[ids[0]]
	var mesh:Mesh=spec.mesh
	var material:Material=spec.get("material_override")
	if material==null and mesh.get_surface_count()>0:material=mesh.surface_get_material(0)
	var texture:Texture2D=material.albedo_texture if material is BaseMaterial3D else null
	if material==null or texture==null:return {}
	return {"mesh":weakref(mesh),"material":weakref(material),"texture":weakref(texture)}
func nav_idle()->bool:
	return navigation.ready_for_queries and navigation._phase in ["","waiting_geometry"] and navigation._nearby==null and navigation._nearby_request==null and navigation._face_worker==null and navigation._source_jobs.is_empty() and navigation._orphan_sources.is_empty() and navigation._bake_pending.is_empty() and navigation._baking_mesh==null and navigation._publish_wait==0 and navigation._nearby_publish_wait==0
func adopt_initial()->bool:
	# Match World3D's production startup/transfer order. MapLoader initially
	# returns ordinary GLBs as children, marked stream_children=-1; Stream must
	# adopt them before navigation, minimap and the residency observer snapshot.
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		Stream.sync(map_root,host,A,Stream.FRAME_BUDGET)
		if map_root.get_meta("stream_chunk",Vector2i(2147483647,0))==Stream.chunk_key(A) and map_root.get_meta("stream_jobs",[]).is_empty():
			check(prop_ids("prop_a").size()==1,"production initial adoption registers original GLB namespace before binding")
			return prop_ids("prop_a").size()==1
		await process_frame
	check(false,"initial adoption settles before deadline");return false
func settle(destination:Vector3,label:String)->bool:
	at=destination;deferred.prioritize(at)
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		Stream.sync(map_root,host,at,Stream.FRAME_BUDGET)
		navigation.follow(at)
		if not deferred.error.is_empty() or not navigation.geometry_error.is_empty():break
		if deferred.is_idle() and nav_idle() and map_root.get_meta("stream_chunk",Vector2i(2147483647,0))==Stream.chunk_key(at) and map_root.get_meta("stream_append_pending",[]).is_empty():
			await physics_frame;await physics_frame;await process_frame
			check(true,label+" settles real model/native workers, stream and navigation")
			return true
		await process_frame
	print("RESIDENCY_WAIT ",JSON.stringify({"label":label,"deferred":deferred.error,"navigation":navigation.geometry_error,"phase":navigation._phase,"nearby":navigation._nearby!=null,"request":str(navigation._nearby_request),"jobs":deferred.active_workers(),"profile":residency.profile,"resident":residency._resident.keys()}))
	check(false,label+" settles before deadline");return false
func poll_retirement()->void:
	logical_msec=maxi(logical_msec+residency.grace_msec+1,Time.get_ticks_msec())
	residency.poll(logical_msec)
	for i in 12:
		logical_msec+=residency.grace_msec+1;residency.poll(logical_msec)
		await process_frame
func ray(prefix:String,x:float)->void:
	await physics_frame;await physics_frame;await process_frame
	var query:=PhysicsRayQueryParameters3D.create(Vector3(x,5,4),Vector3(x,-2,4),1)
	var hit:Dictionary=host.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and str(hit.collider.get_meta("uuid","")).begins_with(prefix+"__"),"actual collider retains namespace: "+prefix)
func probe_released(watches:Dictionary,label:String)->void:
	for i in 20:await process_frame
	for key:String in watches:check(watches[key].get_ref()==null,label+" releases "+key+" after final consumer")
func cleanup()->void:
	if is_instance_valid(deferred):await deferred.quiesce()
	if is_instance_valid(host):host.queue_free()
	host=null;map_root=null;deferred=null;navigation=null;residency=null
	for i in 4:await process_frame
	Assets.evict_cached_scene(asset_path)
func run()->void:
	create_timer(150).timeout.connect(func():print("ASSET_RESIDENCY_GPU_TIMEOUT");quit(2))
	folder=Paths.cache_directory("asset_residency_gpu_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(folder)
	asset_path=folder.path_join("textured_crate.glb")
	print("ASSET_RESIDENCY_GPU_TEMP ",folder)
	check(textured_fixture(asset_path)==OK,"write isolated standard GLB with real embedded texture")
	check(preload("res://scripts/world3d/asset_bounds_manifest.gd").read(asset_path).known,"fixture is eligible for conservative deferred GLB path")
	var compiled:=Compiled.build(asset_path)
	check(compiled.ok,"explicitly compile the temporary GLB before map entry")
	if not compiled.ok:print(compiled);quit(1);return
	var hit:=Compiled.read(asset_path)
	check(hit.hit,"verify the native PackedScene cache product")
	if not hit.hit:print(hit);quit(1);return
	# This probe must not become the owner that prevents the WeakRef assertions.
	hit.clear()
	var fixture:=make_map();check(fixture.ok,"write native reference map with verified dependency directory")
	if not fixture.ok:print(fixture);quit(1);return
	var source_sha:=FileAccess.get_sha256(fixture.path)
	host=Host.new();root.add_child(host);host._ready_for_play=true
	host._hud=Control.new();host.add_child(host._hud);host._status=Label.new();host.add_child(host._status)
	loader=Loader.new();loader.near_first=true;host.add_child(loader)
	var loaded:={"done":false}
	loader.finished.connect(func(scene:Node,_path:String,error:String):loaded.done=true;loaded.scene=scene;loaded.error=error)
	loader.start(fixture.path,A)
	var deadline:=Time.get_ticks_msec()+30000
	while not loaded.done and Time.get_ticks_msec()<deadline:await process_frame
	check(loaded.done and loaded.get("scene") is Node and loaded.get("error","").is_empty(),"real MapLoader finishes local closure")
	if not loaded.get("scene") is Node:await cleanup();quit(1);return
	map_root=loaded.scene;loaded.clear();host.add_child(map_root);host._map_root=map_root;host._map_path=fixture.path
	# JSON reads turn numeric literals into floats. Compare writer/reader values
	# semantically once, then freeze the actual loaded representation so later
	# checks still reject any in-memory mutation (including a type-only change).
	var author_snapshot:Dictionary=map_root.get_meta("author_reference_extras",{}).duplicate(true)
	var initial_author_ok:=Directory._json_equal(author_snapshot.get("rmmo_records"),fixture.compact,0,[2000000])
	check(initial_author_ok,"initial authored references preserve exact JSON values from the writer")
	print("ASSET_RESIDENCY_AUTHOR_BASELINE ",JSON.stringify({"source_sha":source_sha,"writer_strict_equal":author_snapshot.get("rmmo_records")==fixture.compact,"semantic_equal":initial_author_ok,"first_difference":author_difference(author_snapshot.get("rmmo_records"),fixture.compact)}))
	if not initial_author_ok:await cleanup();quit(1);return
	check(map_root.get_meta("load_profile",{}).get("reference_index_hit",false) and map_root.get_meta("runtime_record_subset",false),"loader uses the dependency index and hydrated runtime subset")
	var parses:Array=map_root.get_meta("load_profile",{}).get("asset_parses",[])
	check(parses.size()==1 and parses[0].get("compiled",false),"initial MapLoader consumes the verified compiled PackedScene")
	if parses.size()!=1 or not parses[0].get("compiled",false):await cleanup();quit(1);return
	deferred=map_root.get_node_or_null("DeferredAssets")
	if deferred==null:check(false,"real DeferredAssets exists");await cleanup();quit(1);return
	if not await adopt_initial():await cleanup();quit(1);return
	navigation=Navigation.new();host.add_child(navigation);host._navigation=navigation
	host._map_data.build(map_root);host._bind_deferred_geometry(map_root,navigation)
	# This regression isolates ordinary-model ownership. Native retirement has a
	# separate full-consumer test; production completes and releases entry pins.
	map_root.get_node("NativeResidency").set_process(false)
	residency=map_root.get_node_or_null("AssetResidency")
	check(residency!=null and navigation.streaming_geometry,"production World3D binding creates residency and streaming navigation")
	if residency==null:await cleanup();quit(1);return
	residency.set_process(false);residency.grace_msec=25
	navigation.build(map_root.get_meta("stream_library"),A);deferred.activate(host)
	if not await settle(A,"initial A"):await cleanup();quit(1);return
	deferred.end_entry_loading();deferred.release_demand("entry_safety")
	while is_instance_valid(loader) and Time.get_ticks_msec()<deadline:await process_frame
	check(not is_instance_valid(loader),"initial loader releases its model preparation owners")
	var original_a:=prop_ids("prop_a");var initial_ok:=original_a.size()==1 and prop_ids("prop_b").is_empty()
	check(initial_ok,"initial geometry contains A but leaves distant B cold")
	if not initial_ok:await cleanup();quit(1);return
	var watches:=resource_watches("prop_a");check(watches.size()==3,"capture only weak references to real mesh/material/texture")
	if watches.size()!=3:await cleanup();quit(1);return
	check(Assets.has_cached_scene(asset_path),"initial model has a prepared cache template")
	if not Assets.has_cached_scene(asset_path):await cleanup();quit(1);return
	var cached_id:int=Assets._scenes[asset_path].get_instance_id()
	await ray("prop_a",4)
	if not await settle(B,"first B"):await cleanup();quit(1);return
	check(prop_ids("prop_b").size()==1 and Assets.has_cached_scene(asset_path) and Assets._scenes[asset_path].get_instance_id()==cached_id,"second shared instance reuses the existing model template")
	var known_shape_count:int=host._map_data.shapes.size()
	Stream.pin_source(map_root,"test_origin",A);Stream.pin_source(map_root,"test_target",B)
	deferred.set_demand("test_origin",AABB(A-Vector3(40,1000,40),Vector3(80,2000,80)),-2)
	deferred.set_demand("test_target",AABB(B-Vector3(40,1000,40),Vector3(80,2000,80)),-2)
	await settle(B,"pinned origin and target")
	await poll_retirement()
	check(prop_ids("prop_a")==original_a and prop_ids("prop_b").size()==1 and residency.profile.retired_instances==0,"origin plus destination demand pins reject retirement across grace")
	deferred.release_demand("test_origin");deferred.release_demand("test_target")
	check(not Stream.can_retire_specs(map_root,original_a).ok,"render/physics origin pin alone refuses retirement")
	Stream.release_source(map_root,"test_origin");Stream.release_source(map_root,"test_target")
	await settle(B,"unpin at B");await poll_retirement()
	check(prop_ids("prop_a").is_empty() and not runtime_has("prop_a") and not navigation._spec_ids.has(original_a[0]),"far A drops stream specs, hydrated record and navigation identity")
	check(Assets.has_cached_scene(asset_path) and Assets._scenes[asset_path].get_instance_id()==cached_id and prop_ids("prop_b").size()==1,"shared model cache stays alive until B also leaves")
	check(deferred.pending.any(func(item):return item.record.uuid=="prop_a" and item.has("reference_entry") and not item.get("reference_prepared",false)),"retired A returns as a cold compact reference request")
	await ray("prop_b",516)
	if not await settle(C,"empty C"):await cleanup();quit(1);return
	await poll_retirement()
	check(prop_ids("prop_b").is_empty() and not runtime_has("prop_b") and not Assets.has_cached_scene(asset_path),"last instance releases hydrated record and shared model cache")
	await probe_released(watches,"A/B departure")
	var models_before:int=deferred.profile.models
	var hits_before:int=int(deferred.profile.get("compiled_hits",0));var misses_before:int=int(deferred.profile.get("compiled_misses",0))
	if not await settle(A,"revisit A"):await cleanup();quit(1);return
	check(prop_ids("prop_a")==original_a and runtime_has("prop_a") and int(deferred.profile.models)>models_before,"revisit performs verified worker preparation and restores the original UUID")
	check(int(deferred.profile.get("compiled_hits",0))>hits_before and int(deferred.profile.get("compiled_misses",0))==misses_before,"cold revisit reloads compiled resources on the worker without raw GLTF fallback")
	check(navigation.geometry_error.is_empty() and host._map_data.shapes.size()>=known_shape_count and host._map_data._seen_specs.has(original_a[0]),"revisit appends navigation and retains the once-only minimap projection")
	await ray("prop_a",4)
	var complete_shapes:int=host._map_data.shapes.size();var counts:Array=[]
	for cycle in 3:
		if not await settle(B,"loop B %d"%cycle):break
		await poll_retirement();counts.append(map_root.get_meta("stream_library").size())
		check(prop_ids("prop_a").is_empty() and prop_ids("prop_b").size()==1,"loop retires A while retaining B %d"%cycle)
		if not await settle(A,"loop A %d"%cycle):break
		await poll_retirement();counts.append(map_root.get_meta("stream_library").size())
		check(prop_ids("prop_b").is_empty() and prop_ids("prop_a")==original_a,"loop retires B and restores stable A %d"%cycle)
	check(counts.size()==6 and counts.min()==counts.max() and int(residency.profile.resident_instances)==1,"repeated travel returns to the same resident count instead of accumulating")
	check(host._map_data.shapes.size()==complete_shapes and deferred.error.is_empty() and navigation.geometry_error.is_empty(),"repeated travel keeps minimap shape count and error state stable")
	var final_author:Dictionary=map_root.get_meta("author_reference_extras",{})
	check(final_author==author_snapshot,"complete authored snapshot remains strictly unchanged throughout retirement")
	check(Directory._json_equal(final_author.get("rmmo_records"),fixture.compact,0,[2000000]),"final authored references retain exact writer JSON semantics")
	check(FileAccess.get_sha256(fixture.path)==source_sha,"map source bytes retain their original SHA throughout retirement")
	if final_author!=author_snapshot:print("ASSET_RESIDENCY_AUTHOR_MUTATION ",JSON.stringify(author_difference(final_author,author_snapshot)))
	print("ASSET_RESIDENCY_GPU_PROFILE ",JSON.stringify({"residency":residency.profile,"queue":deferred.profile,"resident_counts":counts,"map_shapes":host._map_data.shapes.size()}))
	await cleanup()
	print("ASSET_RESIDENCY_GPU_FINISHED passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
