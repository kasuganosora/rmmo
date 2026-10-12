extends SceneTree
const Prepare = preload("res://scripts/world3d/chunk_reference_preparation.gd")
const Index = preload("res://scripts/world3d/map_dependency_index.gd")
const Store = preload("res://scripts/world3d/map_resource_store.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Fixtures = preload("res://tools/test_map_dependency_index.gd")
var failures := 0
var passed := 0
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
		if checks == 5:
			var file := FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
		return false
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS: " if value else "FAIL: ", label)
	if value: passed += 1
	else: failures += 1
func entries(index: Dictionary, positions: Array) -> Array:
	var result: Array = []
	for at in positions:
		var row: Dictionary = index.rows[at]
		result.append({"record_index":at,"compact_record":index.extras.rmmo_records[at],"bounds":index.groups[row.group_id].bounds if not row.group_id.is_empty() else row.bounds,"group_id":row.group_id,"asset_path":row.asset_path})
	return result
func run() -> void:
	var helper := Fixtures.new(); helper.content_root=Paths.external_root(); helper.folder=Paths.cache_directory("chunk_reference_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(helper.folder)
	var records: Array=[helper.box("a",0),helper.box("b",100),helper.box("c",200)]
	var fixture: Dictionary=helper.fixture("map",records);var path:String=fixture.path
	var index:=Index.build(path,helper.content_root,records)
	check(index.ok,"fixture directory builds")
	if not index.ok:print(index);quit(1);return
	var prepared:=Prepare.prepare(index,entries(index,[2,0]),path,helper.content_root)
	check(prepared.error.is_empty() and prepared.record_indices==[0,2] and prepared.records[0].uuid=="a" and prepared.records[1].uuid=="c", "demand request hydrates only selected records in original map order")
	check(prepared.dependencies.size()==1 and prepared.read_profile.unique_resources==1 and prepared.read_profile.worker_limit==1,"shared dependency decoded once; outer scheduler owns parallelism")
	check(prepared.selected_closure_verified and not prepared.closure_complete,"selected closure verified without claiming all-map integrity")
	var worker:=Thread.new();worker.start(Prepare.prepare.bind(index,entries(index,[1]),path,helper.content_root))
	var threaded:Dictionary=worker.wait_to_finish()
	check(threaded.error.is_empty() and threaded.records[0].uuid=="b","pure CPU reference preparation succeeds on independent worker")
	var token:=Token.new()
	check(Prepare.prepare(index,entries(index,[0]),path,helper.content_root,token).cancelled,"cancel before IO produces no records")
	token=Token.new();token.after=3
	var cancelled:=Prepare.prepare(index,entries(index,[0]),path,helper.content_root,token)
	check(cancelled.cancelled and cancelled.records.is_empty(),"cancellation after bounded resource read discards result")
	check(not Prepare.prepare(index,[],path,helper.content_root).error.is_empty(),"empty demand rejected")
	var duplicate:=entries(index,[0,0])
	check(not Prepare.prepare(index,duplicate,path,helper.content_root).error.is_empty(),"duplicate requested record rejected")
	var wrong_entry:=entries(index,[0]);wrong_entry[0].compact_record=wrong_entry[0].compact_record.duplicate(true);wrong_entry[0].compact_record.position[0]=999
	check(not Prepare.prepare(index,wrong_entry,path,helper.content_root).error.is_empty(),"request cannot change original compact pose")
	wrong_entry=entries(index,[0]);wrong_entry[0].bounds=AABB(Vector3.ZERO,Vector3.ONE)
	check(not Prepare.prepare(index,wrong_entry,path,helper.content_root).error.is_empty(),"request cannot replace directory bounds")
	var smaller:=index.duplicate(true);smaller.rows[0].bounds=AABB(Vector3.ZERO,Vector3(.01,.01,.01))
	check(not Prepare.prepare(smaller,entries(smaller,[0]),path,helper.content_root).error.is_empty(),"recomputed real definition bounds reject an invented smaller directory box")
	var original:=FileAccess.get_file_as_bytes(path);helper.write_bytes(path,original+" ".to_utf8_buffer())
	check(not Prepare.prepare(index,entries(index,[0]),path,helper.content_root).error.is_empty(),"full source SHA rechecked before demanded definition IO")
	helper.write_bytes(path,original)
	var resource:String=helper.folder.path_join(index.rows[0].reference.uri);var original_resource:=FileAccess.get_file_as_bytes(resource);var broken:=original_resource.duplicate();broken[-1]^=1;helper.write_bytes(resource,broken)
	check(not Prepare.prepare(index,entries(index,[0]),path,helper.content_root).error.is_empty(),"corrupt demanded definition rejected")
	helper.write_bytes(resource,original_resource)
	var mutator:=MutationToken.new();mutator.path=resource;mutator.bytes=broken
	check(not Prepare.prepare(index,entries(index,[0]),path,helper.content_root,mutator).error.is_empty() and mutator.checks>=5,"resource replacement after validation is caught by final full SHA")
	helper.write_bytes(resource,original_resource)
	var model_helper:=preload("res://tools/test_asset_bounds_manifest.gd").new();var model_path:=helper.folder.path_join("model.glb");helper.created.append(model_path)
	model_helper.write(model_path,model_helper.data())
	var asset:Dictionary=helper.box("model",400);asset.kind="asset";asset.size=[1,1,1];asset.asset_path=model_path;asset.label="display name only"
	var asset_fixture:Dictionary=helper.fixture("asset",[asset]);var asset_index:=Index.build(asset_fixture.path,helper.content_root,[asset])
	var asset_prepared:=Prepare.prepare(asset_index,entries(asset_index,[0]),asset_fixture.path,helper.content_root)
	check(asset_prepared.error.is_empty() and asset_prepared.records[0].asset_path==model_path,"ordinary GLB reference validation reads bounds without constructing a scene")
	var changed_model:Dictionary=model_helper.data();changed_model.nodes[0].translation[0]=500;model_helper.write(model_path,changed_model)
	check(not Prepare.prepare(asset_index,entries(asset_index,[0]),asset_fixture.path,helper.content_root).error.is_empty(),"changed model header cannot use the previously accepted spatial bounds")
	model_helper.free()
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-2,0,-2),Vector3(2,0,-2),Vector3(0,3,2)])
	var data:={"materials":[{"null":true}],"meshes":[{"bounds":AABB(Vector3(-2,0,-2),Vector3(4,3,4)),"box_size":Vector3.ZERO,"surfaces":[arrays],"materials":[0]}],"entries":[[[0],[0,0]]],"specs":[]}
	var bytes:=var_to_bytes(data);var prefab:Dictionary=helper.box("shell",300)
	prefab.house_prefab={"version":1,"sha256":Store._sha(bytes),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))};prefab.prefab_locked=true;prefab.prefab_materials=[]
	prefab.building={"id":"house","part":"shell","role":"shell","floor":0,"floor_y":0}
	var roof:=prefab.duplicate(true);roof.uuid="roof";roof.position=[300,5,0];roof.building.part="roof";roof.building.role="roof_tiles"
	var meta:={"building_instances":{"house":{"version":Index.Blueprint.VERSION,"parameters":Index.Blueprint.defaults(),"position":[300,0,0],"yaw":0,"parts":{"shell":"shell","roof":"roof"},"signatures":{"shell":"s","roof":"r"},"baked":true}}}
	var building:Dictionary=helper.fixture("building",[prefab,roof],meta);var building_index:=Index.build(building.path,helper.content_root,[prefab,roof])
	check(building_index.ok,"complete native prefab group directory builds")
	var group:=Prepare.prepare(building_index,entries(building_index,[1,0]),building.path,helper.content_root)
	check(group.error.is_empty() and group.records.size()==2 and group.read_profile.prefab_instances==2,"complete group CPU decoding validates real bounds and original ownership")
	check(group.prefab_cpu.size()==1 and group.prefab_cpu[prefab.house_prefab.sha256].collision_faces[0]==arrays[Mesh.ARRAY_VERTEX] and group.prefab_cpu[prefab.house_prefab.sha256].geometry_keys.size()==1,"worker handoff deduplicates immutable prefab arrays and expands real collision faces")
	Prepare.Prefab._decode_mutex.lock();Prepare.Prefab._decoded.clear();Prepare.Prefab._decoded_bytes=0;Prepare.Prefab._decode_mutex.unlock()
	check(group.prefab_cpu[prefab.house_prefab.sha256].data.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX]==arrays[Mesh.ARRAY_VERTEX],"admitted CPU packet retains its arrays after global decoded-cache eviction")
	check(not Prepare.prepare(building_index,entries(building_index,[0]),building.path,helper.content_root).error.is_empty(),"partial group rejected before resource reads")
	var forged:=building_index.duplicate(true);forged.rows[0].bounds=AABB(Vector3(300,1,0),Vector3.ONE*.01);forged.groups=Index._groups(forged.rows)
	check(not Prepare.prepare(forged,entries(forged,[0,1]),building.path,helper.content_root).error.is_empty(),"group table rebuilt around fabricated geometry still fails real prefab vertex comparison")
	check(FileAccess.get_sha256(path)==index.source_sha256 and FileAccess.get_sha256(building.path)==building_index.source_sha256,"preparation never edits author files")
	for created_path in helper.created:
		if Paths.allowed(created_path,helper.content_root) and FileAccess.file_exists(created_path):DirAccess.remove_absolute(created_path)
	for name in ["map","building","asset"]:DirAccess.remove_absolute(helper.folder.path_join(name+".gltf.resources"))
	DirAccess.remove_absolute(helper.folder);helper.free()
	print("CHUNK_REFERENCE_PREPARATION passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
