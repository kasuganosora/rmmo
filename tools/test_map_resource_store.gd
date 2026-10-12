extends SceneTree
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
var failed:=0
var directory:String
var path:String
func _init()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if not value:failed+=1
func fixture()->Dictionary:
	return {"uuid":"stone_1","position":[1.,2.,3.],"rotation":[0.,45.,0.],"size":[1.,1.,1.],"kind":"box","building":{"id":"house","floor":1,"floor_y":2.},"house_prefab":{"version":1,"data":"original baked payload","collision":[[1,2,3]]},"collision":"walk","surface_paint":[{"face":2,"material":{"texture_path":"D:/not_read_or_exported/source.png","roughness":.7}}],"fixture":{"open":.3,"pivot":[-1.,0.,0.]},"cpu":{"vertices":PackedVector3Array([Vector3(1,2,3),Vector3(4,5,6)]),"bytes":PackedByteArray([0,255]),"basis":Basis.IDENTITY}}
func put_resource(definition:Variant)->Dictionary:
	var raw:=var_to_bytes(definition)
	var bytes:=Store.MAGIC.to_ascii_buffer();bytes.resize(16);bytes.encode_u64(8,raw.size());bytes.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return put_bytes(bytes)
func put_bytes(bytes:PackedByteArray)->Dictionary:
	var digest:=Store._sha(bytes);var uri:=path.get_file()+".resources/"+digest+".rmres"
	var file:=FileAccess.open(path.get_base_dir().path_join(uri),FileAccess.WRITE);file.store_buffer(bytes);file.close()
	var compact:=fixture()
	for key in compact.keys():
		if key not in Store.FIELDS:compact.erase(key)
	compact.rmmo_ref={"version":1,"uri":uri,"sha256":digest,"length":bytes.size()}
	compact.rmmo_state={}
	return compact
func make_link(link:String,target:String,kind:String)->bool:
	var output:Array=[]
	var command:="$ErrorActionPreference='Stop'; New-Item -ItemType %s -Path '%s' -Target '%s' | Out-Null"%[kind,link.replace("'","''"),target.replace("'","''")]
	var result:=OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-Command",command],output,true,false)
	if result!=0:print("LINK_FIXTURE_UNAVAILABLE ",kind," ",output)
	return result==0
func remove_directory_link(link:String)->void:
	var output:Array=[]
	OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-Command","[IO.Directory]::Delete('%s')"%link.replace("'","''")],output,true,false)
func test_path_links()->void:
	if OS.get_name()!="Windows":return
	var link_map:=directory.path_join("link_test.gltf")
	var link_folder:=link_map+".resources";var target:=directory.path_join("link_target")
	DirAccess.make_dir_recursive_absolute(link_folder);DirAccess.make_dir_recursive_absolute(target)
	var context:=Store._path_batch(link_map,Paths.external_root());var digest:="3".repeat(64)
	check(not Store._batch_location(context,link_map.get_file()+".resources/"+digest+".rmres",digest).is_empty(),"batch starts with an ordinary resource directory")
	DirAccess.remove_absolute(link_folder)
	if make_link(link_folder,target,"Junction"):
		check(Store._path_batch(link_map,Paths.external_root()).is_empty() and not Store._finish_paths(context),"resource directory junction is rejected initially and after cached batch creation")
		remove_directory_link(link_folder)
	else:check(false,"create directory junction security fixture")
	var ancestor:=directory.path_join("linked_ancestor")
	if make_link(ancestor,target,"Junction"):
		check(Store._path_batch(ancestor.path_join("nested/map.gltf"),Paths.external_root()).is_empty(),"junction in any resource ancestor is rejected")
		remove_directory_link(ancestor)
	else:check(false,"create ancestor junction security fixture")
	DirAccess.make_dir_recursive_absolute(link_folder)
	var file_target:=target.path_join("target.rmres")
	var file:=FileAccess.open(file_target,FileAccess.WRITE);file.store_string("link payload");file.close()
	var leaf:=digest+".rmres";var link_file:=link_folder.path_join(leaf)
	context=Store._path_batch(link_map,Paths.external_root())
	Store._batch_location(context,link_map.get_file()+".resources/"+leaf,digest)
	if make_link(link_file,file_target,"SymbolicLink"):
		var fresh:=Store._path_batch(link_map,Paths.external_root())
		check(Store._batch_location(fresh,link_map.get_file()+".resources/"+leaf,digest).is_empty() and not Store._finish_paths(context),"file symbolic link rejects before IO and after cached leaf validation")
		DirAccess.remove_absolute(link_file)
	else:print("SKIP: file symlink fixture unavailable on this Windows account")
func reset_encoding_caches(hot_only:bool=false)->void:
	Store._mutex.lock();Store._cache.clear();Store._cache_size=0
	if not hot_only:Store._identities.clear()
	Store._mutex.unlock()
func test_identity_cache()->void:
	reset_encoding_caches()
	var large_records:Array=[];var crypto:=Crypto.new()
	for index in 12:
		large_records.append({"uuid":"identity_%d"%index,"position":[0.,0.,0.],"rotation":[0.,0.,0.],"size":[1.,1.,1.],"kind":"cpu_fixture","payload":crypto.generate_random_bytes(4*1024*1024),"nested":{"value":index}})
	var identity_path:=directory.path_join("identity.gltf")
	var initial:=Store.write_records(large_records,identity_path,Paths.external_root())
	check(initial.ok and initial.resources_written==12 and initial.compression_count==12,"working set above hot cache budget publishes each initial resource once")
	large_records[0].position[0]=7.
	var moved:=Store.write_records(large_records,identity_path,Paths.external_root())
	check(moved.ok and moved.resources_written==0 and moved.compression_count==0 and moved.encoded_raw_bytes==0 and moved.identity_cache_hits>0 and moved.serialized_raw_bytes>0,"hot snapshot eviction still avoids every unchanged compression using current full raw SHA")
	var clone:Dictionary=large_records[0].duplicate(true);clone.uuid="identity_clone";large_records.append(clone);large_records.remove_at(1)
	var mixed:=Store.write_records(large_records,identity_path,Paths.external_root())
	check(mixed.ok and mixed.resources_written==0 and mixed.compression_count==0,"add existing definition plus delete bypasses unchanged compression")
	large_records[0].nested.value=3456
	var changed:=Store.write_records(large_records,identity_path,Paths.external_root())
	check(changed.ok and changed.resources_written==1 and changed.compression_count==1,"nested mutation compresses exactly one changed definition")
	reset_encoding_caches()
	var cold:=Store.read_records(changed.records,identity_path,Paths.external_root())
	check(cold.ok and cold.records==large_records,"cold resource read verifies and restores all current author data")
	var after_open:=Store.write_records(cold.records,identity_path,Paths.external_root())
	check(after_open.ok and after_open.compression_count==0 and after_open.identity_cache_hits==large_records.size(),"fully verified cold read seeds identities and first save performs zero compression")
	var save_as_path:=directory.path_join("identity_save_as.gltf")
	var saved_as:=Store.write_records(cold.records,save_as_path,Paths.external_root())
	check(saved_as.ok and saved_as.resources_written==changed.dependencies.size() and Store.read_records(saved_as.records,save_as_path,Paths.external_root()).records==large_records,"Save As materializes missing destinations and fully roundtrips without source-path trust")
	var first_file:=identity_path.get_base_dir().path_join(changed.records[0].rmmo_ref.uri)
	var original_bytes:=FileAccess.get_file_as_bytes(first_file)
	reset_encoding_caches(true);DirAccess.remove_absolute(first_file)
	var repaired:=Store.write_records(cold.records,identity_path,Paths.external_root())
	check(repaired.ok and repaired.resources_written==1 and repaired.compression_count==1 and FileAccess.get_file_as_bytes(first_file)==original_bytes,"missing resource rebuilds only that identity with exact old bytes")
	var corrupt:=original_bytes.duplicate();corrupt[corrupt.size()-1]^=1
	var file:=FileAccess.open(first_file,FileAccess.WRITE);file.store_buffer(corrupt);file.close()
	check(not Store.write_records(cold.records,identity_path,Paths.external_root()).ok and FileAccess.get_file_as_bytes(first_file)==corrupt,"identity cache cannot hide or overwrite tampered immutable file")
	file=FileAccess.open(first_file,FileAccess.WRITE);file.store_buffer(original_bytes);file.close()
	reset_encoding_caches(true)
	var changed_in_flight:=Store._definition(cold.records[0]).duplicate(true)
	var lazy:=Store._encode(changed_in_flight)
	changed_in_flight.nested.value=-1
	check(lazy.identity_hit and not Store._materialize(lazy).ok,"deferred materialization rejects nested input change after identity lookup")
	var wanted:={"kind":"collision_target","data":"different"}
	Store._cache[hash(wanted)]=[{"definition":{"kind":"unrelated"},"bytes":PackedByteArray([1]),"sha256":"bad"}]
	var collision_result:=Store._encode(wanted)
	check(collision_result.ok and not collision_result.cache_hit and collision_result.sha256!="bad","native Variant hash collision never bypasses actual definition equality")
	reset_encoding_caches()
	for index in Store.IDENTITY_CACHE_ENTRIES+1:
		Store._remember_identity("%064x"%index,1,"%064x"%(index+1),17)
	check(Store._identities.size()==Store.IDENTITY_CACHE_ENTRIES and Store._identity("%064x"%0,1).is_empty(),"metadata identity cache has a fixed entry bound and evicts old entries")
	var retained_payload:=false
	for identity:Dictionary in Store._identities.values():
		if identity.size()!=3 or identity.has("definition") or identity.has("bytes"):retained_payload=true
	check(not retained_payload,"bounded identity index retains no raw/compressed payload or author snapshot")
	reset_encoding_caches()
func run()->void:
	directory=Paths.cache_directory("resource_store_%d"%Time.get_ticks_usec());path=directory.path_join("map.gltf")
	DirAccess.make_dir_recursive_absolute(directory)
	if "--path-benchmark" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(path+".resources")
		var fake_sha:="1".repeat(64);var uri:=path.get_file()+".resources/"+fake_sha+".rmres"
		var start:=Time.get_ticks_usec();var accepted:=0
		for index in 4437:
			if not Store._location(uri,fake_sha,path,Paths.external_root()).is_empty():accepted+=1
		print("PATH_BENCHMARK ",JSON.stringify({"calls":4437,"accepted":accepted,"legacy_ms":(Time.get_ticks_usec()-start)/1000.0}))
		start=Time.get_ticks_usec();accepted=0
		var context:=Store._path_batch(path,Paths.external_root())
		for index in 4437:
			if not Store._batch_location(context,uri,fake_sha).is_empty():accepted+=1
		var final_safe:=Store._finish_paths(context)
		print("PATH_BATCH_BENCHMARK ",JSON.stringify({"calls":4437,"accepted":accepted,"unique_leaves":context.leaves.size(),"final_safe":final_safe,"batch_ms":(Time.get_ticks_usec()-start)/1000.0}))
		start=Time.get_ticks_usec();accepted=0;context=Store._path_batch(path,Paths.external_root())
		for index in 4437:
			var unique_sha:="%064x"%(index%1762)
			if not Store._batch_location(context,path.get_file()+".resources/"+unique_sha+".rmres",unique_sha).is_empty():accepted+=1
		final_safe=Store._finish_paths(context)
		print("PATH_UNIQUE_BATCH_BENCHMARK ",JSON.stringify({"calls":4437,"accepted":accepted,"unique_leaves":context.leaves.size(),"final_safe":final_safe,"batch_ms":(Time.get_ticks_usec()-start)/1000.0}))
		Io._remove_tree(directory);quit();return
	var invalid:=fixture();invalid.position=[1,2]
	check(not Store.write_records([fixture(),invalid],path,Paths.external_root()).ok and not DirAccess.dir_exists_absolute(path+".resources"),"all shapes preflight before any resource directory or file write")
	for unsupported in [Vector3.ONE,PackedByteArray([1]),Basis.IDENTITY,NodePath("path"),RefCounted.new(),Callable(self,"run"),9007199254740993,&"string_name_value",NAN]:
		invalid=fixture();invalid.event={"nested":[{"unsupported":unsupported}]}
		check(not Store.write_records([fixture(),invalid],path,Paths.external_root()).ok and not DirAccess.dir_exists_absolute(path+".resources"),"non-JSON instance state rejects without resource side effects: "+type_string(typeof(unsupported)))
	var state_cycle:Array=[];state_cycle.append(state_cycle);invalid=fixture();invalid.event={"cycle":state_cycle}
	check(not Store.write_records([invalid],path,Paths.external_root()).ok and not DirAccess.dir_exists_absolute(path+".resources"),"cyclic instance state rejects without resource side effects")
	state_cycle.clear();invalid.clear()
	invalid=fixture();invalid.bad=RefCounted.new()
	check(not Store.write_records([invalid],path,Paths.external_root()).ok,"Object in author data is rejected before serialization")
	invalid=fixture();invalid.bad=Callable(self,"run")
	check(not Store.write_records([invalid],path,Paths.external_root()).ok,"Callable in author data is rejected")
	var cycle:Array=[];cycle.append(cycle);invalid=fixture();invalid.bad=cycle
	check(not Store.write_records([invalid],path,Paths.external_root()).ok,"recursive container is rejected without unbounded traversal")
	cycle.clear();invalid.clear()
	var a:=fixture();var b:=fixture();b.uuid="stone_2";b.position=[8.,2.,3.];b.size=[2.,1.,1.]
	var output:=Store.write_records([a,b],path,Paths.external_root())
	check(output.ok and output.resources_written==1 and output.dependencies.size()==1,"pose-independent definitions deduplicate into one immutable resource")
	check(output.records[0].size()==6 and output.records[0].rmmo_ref==output.records[1].rmmo_ref and output.records[0].rmmo_state.building==a.building,"compact records contain four pose fields, reference and allowlisted state")
	var location:=directory.path_join(output.records[0].rmmo_ref.uri)
	var bytes:=FileAccess.get_file_as_bytes(location);var digest:=FileAccess.get_sha256(location)
	check(digest==output.records[0].rmmo_ref.sha256 and bytes.size()==output.records[0].rmmo_ref.length,"descriptor hashes exact stored resource bytes and length")
	var decoded:=Store.read_records(output.records,path,Paths.external_root())
	check(decoded.ok and decoded.records==[a,b] and decoded.dependencies==output.dependencies,"roundtrip preserves house prefab, collision, paint, building, fixture and packed CPU data")
	decoded.records[0].house_prefab.collision[0][0]=777
	check(decoded.records[1].house_prefab.collision[0][0]==1 and a.house_prefab.collision[0][0]==1,"hydrated instances are independently editable deep copies")
	check(Store.read_records(output.records,path,Paths.external_root()).records[0].house_prefab.collision[0][0]==1,"editing hydrated data cannot poison later reads")
	var untouched_time:=FileAccess.get_modified_time(location)
	a.position[0]+=10.;a.rotation[1]+=5.;a.size[2]=2.
	var moved:=Store.write_records([a,b],path,Paths.external_root())
	check(moved.ok and moved.resources_written==0 and moved.resources_reused==1 and moved.bytes_written==0,"moving/rotating/scaling instances reuses resource without a write")
	check(moved.encoding_cache_hits==2 and moved.encoding_cache_misses==0 and moved.encoded_raw_bytes==0 and moved.verified_bytes==bytes.size(),"reuse metrics distinguish encoding cache hits from mandatory disk SHA verification")
	check(FileAccess.get_modified_time(location)==untouched_time and FileAccess.get_file_as_bytes(location)==bytes,"reused resource bytes and modification time remain unchanged")
	a.building.id="new_building";a.building.floor_y=25.;a.editor_hidden=true;a.editor_locked=true;a.editor_group="clone_group"
	b.building.id="other_building";b.fixture.open=.8
	var state_changed:=Store.write_records([a,b],path,Paths.external_root())
	check(state_changed.ok and state_changed.resources_written==0 and state_changed.resources_reused==1 and state_changed.records[0].rmmo_ref==state_changed.records[1].rmmo_ref,"building id/floor height, visibility/lock, group and fixture changes share geometry without writes")
	var state_read:=Store.read_records(state_changed.records,path,Paths.external_root())
	check(state_read.ok and state_read.records==[a,b],"instance state is completely restored independently of geometry")
	state_read.records[0].building.id="mutated"
	check(state_read.records[1].building.id=="other_building" and a.building.id=="new_building","hydrated instance states are independent deep copies")
	var runtime:=fixture();runtime.wind={};runtime.wind.profile="breeze";runtime.house_prefab.extra={};runtime.house_prefab.extra.setting=1;runtime.building.extra={};runtime.building.extra.value=2
	var runtime_output:=Store.write_records([runtime],path,Paths.external_root())
	check(runtime_output.ok and Store.read_records(runtime_output.records,path,Paths.external_root()).records==[runtime],"runtime dot-assigned StringName keys preserve nested wind/prefab/building data without JSON conversion")
	check(typeof(runtime_output.records[0].rmmo_state.building.keys()[-1])==TYPE_STRING and typeof(runtime_output.records[0].rmmo_state.building.extra.keys()[0])==TYPE_STRING,"nested StringName instance keys normalize to JSON string keys")
	var runtime_json:Variant=JSON.parse_string(JSON.stringify(runtime_output.records,"",false,true))
	var runtime_read:=Store.read_records(runtime_json,path,Paths.external_root())
	# Godot JSON parses all numbers as float; compare numerical values, while
	# CPU resource data remains exact and never passes through JSON.
	check(runtime_read.ok and runtime_read.records[0].building.extra.value==2 and runtime_read.records[0].building.id==runtime.building.id and runtime_read.records[0].fixture.open==runtime.fixture.open and Store._definition(runtime_read.records[0])==Store._definition(runtime),"normalized instance state survives actual JSON serialization without stringify loss")
	a.house_prefab.collision[0][0]=99
	var changed:=Store.write_records([a,b],path,Paths.external_root())
	check(changed.ok and changed.resources_written==1 and changed.resources_reused==1 and changed.dependencies.size()==2,"nested authored mutation invalidates encoded cache and writes only changed definition")
	check(Store.read_records(changed.records,path,Paths.external_root()).records==[a,b],"nested mutation survives resource hydration")
	check(FileAccess.get_file_as_bytes(location)==bytes,"changed definition never rewrites previous content-addressed resource")
	check(Store.verify_dependencies(changed.dependencies,path,Paths.external_root()),"publication check verifies full resource SHA closure")
	for uri in ["../"+output.records[0].rmmo_ref.uri,"map.gltf.resources/../"+digest+".rmres","map.gltf.resources/%2e%2e/"+digest+".rmres","other.gltf.resources/"+digest+".rmres",location,"map.gltf.resources/"+digest.to_upper()+".rmres"]:
		var bad:Array=output.records.duplicate(true);bad[0].rmmo_ref.uri=uri
		check(not Store.read_records(bad,path,Paths.external_root()).ok,"reject invalid adjacent resource URI "+uri)
	var bad:Array=output.records.duplicate(true);bad[0].rmmo_ref.length+=1
	check(not Store.read_records(bad,path,Paths.external_root()).ok,"reject wrong reference byte length")
	bad=output.records.duplicate(true);bad[0].rmmo_ref.version=2
	check(not Store.read_records(bad,path,Paths.external_root()).ok,"reject unknown reference version")
	bad=output.records.duplicate(true);bad[0].extra_author_field=true
	check(not Store.read_records(bad,path,Paths.external_root()).ok,"reject unexpected author fields on compact instance")
	for field in ["uuid","position","house_prefab","rmmo_ref","kind"]:
		bad=output.records.duplicate(true);bad[0].rmmo_state[field]="override"
		check(not Store.read_records(bad,path,Paths.external_root()).ok,"instance state cannot override "+field)
	bad=output.records.duplicate(true);bad[0].rmmo_state={"event":Callable(self,"run")}
	check(not Store.read_records(bad,path,Paths.external_root()).ok,"unsafe instance state is rejected")
	bad=output.records.duplicate(true);bad[0].rmmo_state={"event":{"nested":Vector3.ONE}}
	check(not Store.read_records(bad,path,Paths.external_root()).ok,"compact reader rejects non-JSON instance state instead of silently stringify")
	check(not Store.write_records([a],"C:/outside/map.gltf",Paths.external_root()).ok,"resource writer enforces external content root")
	var malformed:=put_resource({"uuid":"override","kind":"box"})
	check(not Store.read_records([malformed],path,Paths.external_root()).ok,"decoded definition cannot override instance UUID")
	malformed=put_resource({"kind":"box","building":{"id":"hidden_state"}})
	check(not Store.read_records([malformed],path,Paths.external_root()).ok,"resource definition cannot smuggle instance state")
	malformed=put_resource({"bad":RID()})
	check(not Store.read_records([malformed],path,Paths.external_root()).ok,"unsafe RID variant decoded from externally supplied bytes is rejected")
	var oversized:=bytes.duplicate();oversized.encode_u64(8,Store.MAX_RAW_BYTES+1)
	malformed=put_bytes(oversized)
	check(not Store.read_records([malformed],path,Paths.external_root()).ok,"reject oversized decompression length before allocation")
	var corrupt:=bytes.duplicate();corrupt[corrupt.size()-1]^=1
	var file:=FileAccess.open(location,FileAccess.WRITE);file.store_buffer(corrupt);file.close()
	check(not Store.read_records(output.records,path,Paths.external_root()).ok and not Store.verify_dependencies(output.dependencies,path,Paths.external_root()),"cached resource cannot hide modified disk bytes from read or publication")
	var original:=fixture()
	check(not Store.write_records([original],path,Paths.external_root()).ok and FileAccess.get_file_as_bytes(location)==corrupt,"writer rejects corrupted existing digest filename and never overwrites it")
	DirAccess.remove_absolute(location)
	check(not Store.read_records(output.records,path,Paths.external_root()).ok,"missing resource fails explicitly instead of substituting a placeholder")
	# JSON encodes integer-looking values as floats; reference integer semantics
	# accept that representation without weakening length or version validation.
	var normal:=Store.write_records([fixture()],path,Paths.external_root())
	var json:Variant=JSON.parse_string(JSON.stringify(normal.records,"",false,true))
	check(Store.read_records(json,path,Paths.external_root()).ok,"compact reference survives JSON numeric representation")
	var contested:=fixture();contested.kind="contested_definition"
	var thread_a:=Thread.new();var thread_b:=Thread.new()
	check(thread_a.start(Store.write_records.bind([contested],path,Paths.external_root()))==OK and thread_b.start(Store.write_records.bind([contested],path,Paths.external_root()))==OK,"start two concurrent immutable writers")
	var first:Dictionary=thread_a.wait_to_finish();var second:Dictionary=thread_b.wait_to_finish()
	check(first.ok and second.ok and first.resources_written+second.resources_written==1 and first.resources_reused+second.resources_reused==1,"concurrent writers atomically publish exactly once without replacing the winner")
	check(first.dependencies==second.dependencies and Store.verify_dependencies(first.dependencies,path,Paths.external_root()),"concurrent immutable resource remains valid for both publications")
	var unicode_path:=directory.path_join("中文 空间'图.gltf")
	var unicode_output:=Store.write_records([fixture()],unicode_path,Paths.external_root())
	if not unicode_output.ok or unicode_output.resources_written!=1:print("UNICODE_RESOURCE_RESULT ",unicode_output)
	check(unicode_output.ok and unicode_output.resources_written==1 and Store.read_records(unicode_output.records,unicode_path,Paths.external_root()).ok,"Unicode spaces and quoted map filename publish without shell interpolation or encoding loss")
	var large:=fixture();large.house_prefab.data="A".repeat(17*1024*1024)
	var large_output:=Store.write_records([large],path,Paths.external_root())
	check(large_output.ok and Store.read_records(large_output.records,path,Paths.external_root()).records==[large],"legal prefab string above 16 MiB roundtrips under actual serialized size cap")
	test_path_links()
	test_identity_cache()
	if failed==0:Io._remove_tree(directory)
	else:print("RESOURCE_STORE_FAILED_FIXTURE ",directory)
	print("MAP_RESOURCE_STORE_FAILED=",failed);quit(0 if failed==0 else 1)
