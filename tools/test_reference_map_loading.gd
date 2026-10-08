extends SceneTree
## CPU-only: no map scenes or GPU meshes are generated. All files are temporary.
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Format=preload("res://scripts/world3d/world_location.gd")
const Cache=preload("res://scripts/world3d/map_metadata_cache.gd")
class PrefetchProbe extends "res://scripts/world3d/map_loader.gd":
	var texture_started_before_assets:=false
	func _prepare_record_assets()->void:
		texture_started_before_assets=_texture_thread!=null
var failures:=0
var passed:=0
var folder:=""
var root_path:=""
var cache_files:Array=[]

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if value:passed+=1
	else:failures+=1
func records(count_:int=12)->Array:
	var result:Array=[]
	for i in count_:result.append({"uuid":"obj_%d"%[i+1],"kind":"box","surface_id":"block","size":[1,1,1],"position":[i,1,0],"rotation":[0,0,0],"color":[.4,.5,.6]})
	return result
func write_json(path:String,data:Dictionary)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
func write_bytes(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func reference_file(name_:String,full:Array)->Dictionary:
	var path:=folder.path_join(name_+".gltf")
	var stored:=Store.write_records(full,path,root_path)
	if not stored.ok:check(false,"fixture resources written: "+str(stored.reason));return {}
	var data:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"rmmo_world","extras":{"rmmo_format":Format.FORMAT,"rmmo_version":Format.FORMAT_VERSION,"rmmo_unit":"m","rmmo_storage":Format.STORAGE,"rmmo_records":stored.records,"rmmo_resource_dependencies":stored.dependencies,"test_label":"preserved"}}]}
	write_json(path,data)
	return {"path":path,"data":JSON.parse_string(JSON.stringify(data)),"resources":stored}
func drain(cursor:RefCounted)->void:
	var deadline:=Time.get_ticks_msec()+15000
	while not cursor.done and Time.get_ticks_msec()<deadline:
		cursor.advance(1000)
		if not cursor.done:await process_frame
	check(cursor.done,"cursor terminates within timeout")
func parse_runtime(path:String)->Node:
	var loader:=Loader.new();loader._path=path;loader._content_root=root_path
	loader._parse()
	return loader
func dispose_runtime(loader:Node)->void:
	# CPU parser fixtures never enter a SceneTree; explicitly realize workers.
	loader._exit_tree();loader.free()

func run()->void:
	create_timer(60).timeout.connect(func():print("REFERENCE_MAP_LOADING_TIMEOUT");quit(1))
	root_path=Paths.external_root()
	folder=Paths.cache_directory("reference_loading_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var source:=records()
	var fixture:=reference_file("map",source)
	if fixture.is_empty():quit(1);return
	var path:String=fixture.path
	var raw:=Snapshot.read_file(path)
	var original_json:=JSON.stringify(raw._data)
	var original_sha:String=FileAccess.get_sha256(path)
	var cursor:=Cursor.new();cursor.begin_snapshot(raw,true)
	await drain(cursor)
	check(cursor.document!=null and cursor.document.records.size()==12 and cursor.document.records[0].kind=="box", "sliced cursor hydrates definitions before record validators")
	if cursor.document==null:print(cursor.error);quit(1);return
	check(cursor.metrics.common_records==12 and cursor.metrics.document_records==12, "hydrated authoritative records validate once")
	check(JSON.stringify(raw._data)==original_json and not raw._data.nodes[0].extras.rmmo_records[0].has("kind"), "original compact JSON remains immutable")
	check(cursor.document._disk_signature==original_sha and cursor.document._disk_path==path, "published document retains original map SHA and path")
	var meta:Dictionary=cursor.document.map_meta
	check(meta.get("test_label")=="preserved" and not meta.has("rmmo_storage") and not meta.has("rmmo_resource_dependencies") and not meta.has("rmmo_format") and not meta.has("rmmo_version") and not meta.has("rmmo_unit"), "format and storage identity do not leak into user metadata")
	var synchronous=Doc.open_file(path)
	check(synchronous!=null and synchronous.records==cursor.document.records and synchronous.map_meta==meta, "synchronous and sliced reference documents agree")
	cursor.document.records[0].color[0]=.9
	check(synchronous.records[0].color[0]==.4, "hydrated documents do not alias definition records")
	var runtime:=parse_runtime(path)
	check(runtime._error==OK and runtime._record_meta.rmmo_records.size()==12 and runtime._record_meta.rmmo_records[0].surface_id=="block", "runtime parser receives full visual and collision records")
	check(not runtime._profile.get("metadata_cache_hit",true) and runtime._profile.get("metadata_cache_bypassed")=="reference_integrity", "runtime bypasses metadata-only trust")
	check(runtime._reference_integrity(), "runtime map and definition integrity observation succeeds")
	check(runtime._profile.get("paint_identity_count")==source.size(), "runtime derives paint identities only from fully verified references")
	check(not runtime._valid_records(runtime._record_meta,["0".repeat(64)]), "paint identity count mismatch rejects before validation")
	dispose_runtime(runtime)
	var states:=records(2);states[0]["editor_hidden"]=true;states[1]["editor_locked"]=true
	states[1].rotation=[0,90,0];states[1].size=[2,3,4]
	var state_fixture:=reference_file("different_states",states)
	runtime=parse_runtime(state_fixture.path)
	check(state_fixture.data.nodes[0].extras.rmmo_records[0].rmmo_ref.sha256==state_fixture.data.nodes[0].extras.rmmo_records[1].rmmo_ref.sha256 and runtime._error==OK and preload("res://scripts/world3d/pose_save.gd").same(runtime._record_meta.rmmo_records,states), "same definition with different state and pose restores exact records")
	var invalid_pose:Dictionary=runtime._record_meta.duplicate(true);invalid_pose.rmmo_records[1].rotation[0]=NAN
	var shared_id:String=state_fixture.data.nodes[0].extras.rmmo_records[0].rmmo_ref.sha256
	check(not runtime._valid_records(invalid_pose,[shared_id,shared_id]), "shared definition identity does not bypass per-instance pose constraints")
	dispose_runtime(runtime)
	var png:=folder.path_join("paint.png");var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE);image.save_png(png)
	var textured:=records(1);textured[0]["surface_paint"]=[{"mesh":"","geometry":"test","surface":0,"face":0,"scale":[1,1],"offset":[0,0],"rotation":0,"mapping":"uv","material":{"name":"cpu paint","color":[1,1,1,1],"roughness":.8,"texture_path":png}}]
	cache_files.append(preload("res://scripts/world3d/runtime_texture_cache.gd").cache_path(png,false))
	var texture_fixture:=reference_file("prefetch",textured)
	var probe:=PrefetchProbe.new();probe._path=texture_fixture.path;probe._content_root=root_path;probe._parse()
	check(probe._error==OK and probe.texture_started_before_assets, "validated texture prefetch starts before asset and terrain preparation")
	probe.cancel();probe._exit_tree()
	check(probe._texture_thread!=null and not probe._texture_thread.is_alive(), "cancelled prefetch worker is joined before loader destruction")
	probe.free()
	var descriptor:Dictionary=fixture.data.nodes[0].extras.rmmo_records[0].rmmo_ref
	var resource_path:=path.get_base_dir().path_join(descriptor.uri)
	var resource_bytes:=FileAccess.get_file_as_bytes(resource_path)
	var changed:=resource_bytes.duplicate();changed[-1]=changed[-1]^1
	Cache.write(path,original_sha,{"rmmo_format":Format.FORMAT,"rmmo_version":Format.FORMAT_VERSION,"rmmo_storage":Format.STORAGE,"rmmo_records":source},[])
	cache_files.append(Cache.cache_path(path))
	write_bytes(resource_path,changed)
	check(Doc.open_file(path)==null, "corrupt definition is rejected even with unchanged map SHA")
	runtime=parse_runtime(path)
	check(runtime._error!=OK and runtime._record_meta.is_empty(), "runtime metadata cache cannot bypass definition corruption")
	check(not runtime._profile.has("paint_identity_count") and runtime._texture_thread==null, "same declared SHA with changed payload never grants identity or starts prefetch")
	dispose_runtime(runtime);write_bytes(resource_path,resource_bytes)
	var invalid:Dictionary=fixture.data.duplicate(true)
	invalid.nodes[0].extras.rmmo_resource_dependencies={}
	write_json(path,invalid)
	check(Doc.open_file(path)==null, "missing resource closure declaration rejects")
	invalid=fixture.data.duplicate(true)
	invalid.nodes[0].extras.rmmo_resource_dependencies["extra.rmres"]="0".repeat(64)
	write_json(path,invalid)
	check(Doc.open_file(path)==null, "extra undeclared resource closure rejects")
	invalid=fixture.data.duplicate(true)
	invalid.nodes[0].extras.rmmo_records[0].rmmo_ref.uri="../outside.rmres"
	write_json(path,invalid)
	check(Doc.open_file(path)==null, "traversal descriptor fails before publication")
	write_json(path,fixture.data)
	var late:=Cursor.new();late.begin_snapshot(Snapshot.read_file(path),true)
	while not late.done and late._phase!="signature":late.advance(1);await process_frame
	write_bytes(resource_path,changed)
	await drain(late)
	check(late.document==null and "changed" in late.error, "late definition mutation fails final publication guard")
	write_bytes(resource_path,resource_bytes)
	late=Cursor.new();late.begin_snapshot(Snapshot.read_file(path),true)
	while not late.done and late._phase!="signature":late.advance(1);await process_frame
	var file:=FileAccess.open(path,FileAccess.READ_WRITE);file.seek_end();file.store_string(" ");file.close()
	await drain(late)
	check(late.document==null and "changed" in late.error, "late map mutation retains source-signature failure semantics")
	write_json(path,fixture.data)
	var callbacks:Array=[]
	late=Cursor.new();late.begin_snapshot(Snapshot.read_file(path),true,func(_phase,_done,_total):callbacks.append(true))
	while not late.done and late._phase!="signature":late.advance(1);await process_frame
	var count_:int=callbacks.size();await drain(late)
	check(late.document!=null and callbacks.size()==count_, "no callbacks after final dependency and map verification")
	var old:Dictionary=fixture.data.duplicate(true)
	old.nodes[0].extras.rmmo_version=1;old.nodes[0].extras.rmmo_records=source
	old.nodes[0].extras.erase("rmmo_storage");old.nodes[0].extras.erase("rmmo_resource_dependencies")
	var legacy:=folder.path_join("legacy.gltf");write_json(legacy,old)
	check(Cursor.native_root(old)<0 and Cursor.native_root(old,true)==0 and Doc.open_file(legacy)==null, "version 1 cannot enter normal native document path")
	var migration=Doc.open_file(legacy,{},Callable(),true)
	check(migration!=null and migration.records.size()==12 and not migration.map_meta.has("rmmo_version"), "explicit version 1 migration preserves records with clean metadata")
	runtime=parse_runtime(legacy)
	check(runtime._error!=OK and "迁移" in runtime._failure_reason, "runtime rejects legacy RMMO before glTF fallback")
	dispose_runtime(runtime)
	var bad_records:=records(1);bad_records[0]["wind_response"]={"profile":"invalid"}
	bad_records=JSON.parse_string(JSON.stringify(bad_records))
	var bad_fixture:=reference_file("invalid_business",bad_records)
	check(not bad_fixture.is_empty() and Doc.open_file(bad_fixture.path)==null, "hydrated definitions still pass complete business validation")
	runtime=parse_runtime(bad_fixture.path)
	check(runtime._error!=OK and runtime._texture_thread==null, "invalid business record cannot start texture prefetch")
	dispose_runtime(runtime)
	var empty:=reference_file("empty",[])
	check(Doc.open_file(empty.path)!=null, "empty reference document has a valid empty dependency closure")
	var building_records:=records(3)
	var roles:= ["door","window","roof"]
	var parts:Dictionary={};var signatures:Dictionary={}
	for i in building_records.size():
		building_records[i]["building"]={"id":"house_a","part":roles[i],"role":roles[i],"floor":1,"floor_y":4.0}
		building_records[i]["position"]=[float(i),4.0,2.0]
		building_records[i]["collision"]="block" if i<2 else "walk"
		if i<2:building_records[i]["fixture"]={"id":roles[i]+"_a","kind":roles[i],"pivot":[-.5,0,0],"angle":90.0,"open":.7}
		parts[roles[i]]=building_records[i].uuid;signatures[roles[i]]="fixture_signature"
	building_records=JSON.parse_string(JSON.stringify(building_records))
	var house:=reference_file("house",building_records)
	var blueprint=load("res://scripts/world3d/building_blueprint.gd")
	house.data.nodes[0].extras["building_instances"]={"house_a":{"version":blueprint.VERSION,"parameters":blueprint.defaults(),"position":[0,0,0],"yaw":0,"parts":parts,"signatures":signatures}}
	write_json(house.path,house.data)
	var house_doc=Doc.open_file(house.path)
	check(house_doc!=null and house_doc.records[0].building.floor==1 and house_doc.records[2].building.role=="roof" and house_doc.records[1].fixture.kind=="window", "reference hydration preserves floor roof door and window semantics")
	if house_doc!=null:
		var fixtures=load("res://scripts/world3d/building_fixtures.gd")
		check(fixtures.transform(house_doc.records[0]).is_equal_approx(fixtures.transform(building_records[0])) and house_doc.records[0].collision=="block", "hydrated hinge pose and authored collision match original records")
	runtime=parse_runtime(house.path)
	check(runtime._error==OK and runtime._record_meta.rmmo_records[0].fixture.open==.7 and runtime._record_meta.building_instances.house_a.parts.window=="obj_2", "runtime receives complete building ownership and active fixture state")
	dispose_runtime(runtime)
	invalid=fixture.data.duplicate(true);invalid.scene=.5
	check(Cursor.native_root(invalid)<0, "fractional scene index cannot choose a native root")
	invalid=fixture.data.duplicate(true);invalid.nodes[0].extras.erase("rmmo_storage")
	write_json(path,invalid)
	check(Doc.open_file(path)==null, "version 2 without reference storage marker is rejected")
	for cache_path:String in cache_files:DirAccess.remove_absolute(cache_path)
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(folder)
	print("REFERENCE_MAP_LOADING_FINISHED passed=%d failures=%d"%[passed,failures])
	quit(0 if failures==0 else 1)
