extends SceneTree
## Default: CPU parser regression. --gpu: actual loader/stream/physics; run only
## through tools/run_godot_background.py on the independent desktop.
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Helper=preload("res://tools/test_map_dependency_index.gd")
class Host extends Node3D:
	var _ready_for_play:=true
var failures:=0
var passed:=0
var folder:=""
var content_root:=""
var created:Array=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if value:passed+=1
	else:failures+=1
func cube_data(size:Vector3)->Dictionary:
	var corners:Array=[]
	for z in [-1,1]:
		for y in [-1,1]:
			for x in [-1,1]:corners.append(Vector3(x,y,z)*size*.5)
	var vertices:=PackedVector3Array()
	# Godot's front faces are clockwise. Inward fixture triangles let the ray
	# skip the floor top and hit its bottom, coincident with the global ground.
	for i in [0,3,2,0,1,3,4,7,5,4,6,7,0,6,4,0,2,6,1,7,3,1,5,7,2,7,6,2,3,7,0,5,1,0,4,5]:vertices.append(corners[i])
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
	return {"materials":[{"values":{"albedo_color":Color(.55,.5,.42,1),"roughness":.9}}],"meshes":[{"bounds":AABB(-size*.5,size),"box_size":Vector3.ZERO,"surfaces":[arrays],"materials":[0]}],"entries":[[[0],[0,0]]],"specs":[]}
func prefab(size:Vector3)->Dictionary:
	var bytes:=var_to_bytes(cube_data(size))
	return {"version":1,"sha256":Store._sha(bytes),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
func append_house(records:Array,metadata:Dictionary,id:String,x:float,bad_unique:bool=false)->void:
	var parts:={};var signatures:={}
	for part in ["floor","door"]:
		var size:=Vector3(8,.5,8) if part=="floor" else Vector3(1.2,2.5,.2)
		var position:=[x,0,0] if part=="floor" else [x,1.25,-3.5]
		var uuid:String=id+"_"+str(part)
		var record:={"uuid":uuid,"kind":"box","surface_id":"ground" if part=="floor" else "block","collision":"walk" if part=="floor" else "block","position":position,"rotation":[0,0,0],"size":[size.x,size.y,size.z],"house_prefab":prefab(size),"prefab_locked":true,"prefab_materials":[],"building":{"id":id,"part":part,"role":part,"floor":0,"floor_y":0}}
		if part=="door":record.fixture={"id":"entrance","kind":"door","pivot":[-.6,0,0],"angle":95,"open":0.0}
		if bad_unique and part=="floor":record.color=[.9,.1,.1]
		records.append(record);parts[part]=uuid;signatures[part]="fixture_"+uuid
	metadata.building_instances[id]={"version":Index.Blueprint.VERSION,"parameters":Index.Blueprint.defaults(),"position":[x,0,0],"yaw":0,"parts":parts,"signatures":signatures,"baked":true}
func make_fixture(name_:String,extra_far:int=0)->Dictionary:
	var helper:=Helper.new();helper.folder=folder;helper.content_root=content_root
	var ground:Dictionary=helper.box("ground",0,2048);ground.position=[0,-.75,0];ground.size=[2048,1,2048];ground.surface_id="ground";ground.collision="walk"
	var records:Array=[ground];var metadata:={"building_instances":{}}
	append_house(records,metadata,"near",0);append_house(records,metadata,"far",500);append_house(records,metadata,"bad",700,true);append_house(records,metadata,"outside",3000)
	for i in extra_far:append_house(records,metadata,"extension_%d"%i,5000+i*40)
	var model_path:=folder.path_join(name_+".glb")
	var model_fixture:=preload("res://tools/test_asset_bounds_manifest.gd").new();model_fixture.write(model_path,model_fixture.data());model_fixture.free();created.append(model_path)
	records.append({"uuid":"decor","kind":"asset","asset_path":model_path,"position":[500,0,0],"rotation":[0,0,0],"size":[1,1,1],"surface_id":"model","collision":"none","label":"far decorative model"})
	var result:Dictionary=helper.fixture(name_,records,metadata);created.append_array(helper.created);helper.free()
	var hydrated:Dictionary=preload("res://scripts/world3d/document_open_cursor.gd").hydrate_references(result.extras,result.path,content_root)
	result.records=hydrated.extras.rmmo_records;result.model_path=model_path
	result.index=Index.build(result.path,content_root,result.records)
	return result
func parse(path:String)->Node:
	var loader:=Loader.new();loader.near_first=true;loader._path=path;loader._content_root=content_root;loader._entry_origin=Vector3(0,.9,0);loader._parse()
	return loader
func dispose(loader:Node)->void:loader._exit_tree();loader.free()
func run()->void:
	create_timer(150).timeout.connect(func():print("REFERENCE_CHUNK_LOADING_TIMEOUT");quit(2))
	content_root=Paths.external_root();folder=Paths.cache_directory("reference_chunk_loading_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var base:=make_fixture("base");var expanded:=make_fixture("expanded",12)
	check(base.index.ok and expanded.index.ok,"temporary native reference directories build")
	if not base.index.ok or not expanded.index.ok:
		print("INDEX_FAILURE ",base.index," ",expanded.index);quit(1);return
	var initial:=parse(base.path);var larger:=parse(expanded.path)
	check(initial._error==OK and initial._profile.get("reference_index_hit",false),"real MapLoader parser selects a verified dependency directory")
	check(initial._record_meta.rmmo_records.size()==3 and initial._deferred_assets.size()==7,"initial closure contains ground and complete near house only")
	check(larger._record_meta.rmmo_records.size()==3 and larger._profile.paint_identity_count==initial._profile.paint_identity_count,"adding view-distance-external houses does not increase hydrated/validated initial records")
	check(initial._author_reference_meta.rmmo_records.size()==base.records.size() and initial._author_reference_meta.building_instances.size()==4,"complete authored compact records and all owner metadata remain available")
	check(initial._mesh_cache_data.is_empty() and initial._profile.get("mesh_cache_scope")=="selected_reference_closure" and not initial._mesh_cache_selection.is_empty() and initial._profile.get("mesh_cache_path")!=Cook.cache_path(base.path),"selected map uses a separate exact-closure cache instead of the whole-map UUID closure")
	check(initial._record_order.far_floor==3 and initial._record_order.outside_door==8,"deferred records preserve original author draw order")
	dispose(initial);dispose(larger)
	var cache:String=Index.cache_path(base.path,content_root);var cache_bytes:=FileAccess.get_file_as_bytes(cache);var corrupted:=cache_bytes.duplicate();corrupted[-1]^=1
	var saved_cold_rebuild:bool=Loader.cold_index_rebuild_enabled;Loader.cold_index_rebuild_enabled=false
	write_bytes(cache,corrupted);var fallback:=parse(base.path)
	Loader.cold_index_rebuild_enabled=saved_cold_rebuild
	check(fallback._error==OK and not fallback._profile.reference_index_hit and fallback._record_meta.rmmo_records.size()==base.records.size(),"bad index with cold rebuild disabled falls back to complete strict author hydration")
	dispose(fallback);write_bytes(cache,cache_bytes)
	var bad_reference:Dictionary=base.extras.rmmo_records[5].rmmo_ref;var bad_path:String=folder.path_join(bad_reference.uri);var bad_bytes:=FileAccess.get_file_as_bytes(bad_path);corrupted=bad_bytes.duplicate();corrupted[-1]^=1;write_bytes(bad_path,corrupted)
	var local:=parse(base.path)
	check(local._error==OK and local._record_meta.rmmo_records.size()==3,"corrupt undemanded far component does not block safe initial closure")
	dispose(local)
	if "--gpu" in OS.get_cmdline_user_args():await gpu_case(base)
	write_bytes(bad_path,bad_bytes)
	for path in created:
		if Paths.allowed(path,content_root) and FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	for name_ in ["base","expanded"]:DirAccess.remove_absolute(folder.path_join(name_+".gltf.resources"))
	DirAccess.remove_absolute(folder)
	print("REFERENCE_CHUNK_LOADING passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
func write_bytes(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func gpu_case(fixture:Dictionary)->void:
	var host:=Host.new();root.add_child(host)
	var loader:=Loader.new();loader.near_first=true;host.add_child(loader);var result:={"done":false}
	loader.finished.connect(func(scene:Node,_path:String,error:String):result.done=true;result.scene=scene;result.error=error)
	loader.start(fixture.path,Vector3(0,.9,0));var deadline:=Time.get_ticks_msec()+60000
	while not result.done and Time.get_ticks_msec()<deadline:await process_frame
	check(result.done and result.get("scene")!=null and result.get("error","").is_empty(),"actual MapLoader produces a ready local scene")
	if not result.get("scene") is Node:host.free();return
	var map:Node=result.scene;host.add_child(map)
	var deferred:=map.get_node("DeferredAssets");deferred.activate(host);deferred.prioritize(Vector3(0,.9,0))
	check(map.get_meta("runtime_record_subset") and map.get_meta("author_reference_extras").rmmo_records.size()==fixture.records.size(),"live map distinguishes complete author refs from hydrated runtime subset")
	deadline=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		Stream.sync(map,host,Vector3(0,.9,0),Stream.LOAD_BUDGET)
		if map.get_meta("stream_by_id",{}).has("far_door") and not deferred.error_for_clip(AABB(Vector3(695,-10,-5),Vector3(10,20,10))).is_empty():break
		await process_frame
	check(map.get_meta("stream_by_id",{}).has("far_floor") and map.get_meta("stream_by_id",{}).has("far_door"),"low-priority 1km render demand prepares complete distant floor and door")
	check(not preload("res://scripts/world_editor/asset_library.gd")._scenes.has(fixture.model_path) and not map.get_meta("stream_by_id",{}).has("outside_floor"),"building render demand does not load far decorations or beyond-view buildings")
	check(not map.get_meta("stream_bodies",{}).has("far_floor"),"distant render preparation does not create distant physics bodies")
	check(deferred.error.is_empty() and deferred.error_for_clip(AABB(Vector3(-5,-10,-5),Vector3(10,20,10))).is_empty() and not deferred.error_for_clip(AABB(Vector3(695,-10,-5),Vector3(10,20,10))).is_empty(),"corrupt group failure is local and leaves healthy origin usable")
	var destination:=Vector3(500,.9,0);var clip:=AABB(destination-Vector3(40,100000,40),Vector3(80,200000,80));deadline=Time.get_ticks_msec()+30000
	while not deferred.ensure_geometry(clip,"test_target") and Time.get_ticks_msec()<deadline:await process_frame
	check(deferred.ensure_geometry(clip,"test_target") and preload("res://scripts/world_editor/asset_library.gd")._scenes.has(fixture.model_path),"target demand hydrates and prepares its decorative GLB before local geometry readiness")
	for i in 1200:
		Stream.sync(map,host,destination,Stream.LOAD_BUDGET)
		if Stream.nearby_collision_ready(map,destination):break
		await process_frame
	await physics_frame;await physics_frame;await process_frame
	var query:=PhysicsRayQueryParameters3D.create(Vector3(498,5,0),Vector3(498,-3,0),1);var hit:=host.get_world_3d().direct_space_state.intersect_ray(query)
	var floor_body:Variant=map.get_meta("stream_bodies",{}).get("far_floor")
	query.hit_back_faces=true;var back_hit:=host.get_world_3d().direct_space_state.intersect_ray(query)
	print("REFERENCE_COLLISION_DIAGNOSTICS ",{"hit_uuid":"" if hit.is_empty() else str(hit.collider.get_meta("uuid","")),"hit_position":hit.get("position"),"back_hit_uuid":"" if back_hit.is_empty() else str(back_hit.collider.get_meta("uuid","")),"back_hit_position":back_hit.get("position"),"floor_body_exists":is_instance_valid(floor_body),"floor_body_transform":floor_body.global_transform if is_instance_valid(floor_body) else null,"floor_body_children":floor_body.get_child_count() if is_instance_valid(floor_body) else 0,"collision_ready":Stream.nearby_collision_ready(map,destination)})
	check(not hit.is_empty() and str(hit.collider.get_meta("uuid",""))=="far_floor","demanded native floor has real collision under original UUID")
	var fixture_state:Dictionary=preload("res://scripts/world3d/building_fixtures.gd").set_runtime(map,"far","entrance",1.0,0.0)
	check(fixture_state.ok and map.get_meta("stream_by_id")["far_door"].extras.fixture.open==1.0,"deferred door retains functional fixture ownership and opening semantics")
	check(deferred.profile.peak_jobs<=2 and deferred.profile.reference_records>0,"native and GLB preparation share the bounded task ledger")
	await deferred.quiesce();host.free();await process_frame
