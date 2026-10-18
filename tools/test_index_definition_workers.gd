extends SceneTree
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Helper=preload("res://tools/test_map_dependency_index.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var helper:=Helper.new();helper.content_root=Paths.external_root();helper.folder=Paths.cache_directory("index_worker_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(helper.folder)
	var records:Array=[]
	for i:int in 24:
		var record:Dictionary=helper.box("part%d"%i,i*32)
		record.color=[i/24.,.5,.25,1.];records.append(record)
	var shared:Dictionary=records[0].duplicate(true);shared.uuid="shared";shared.position=[1000,1,0];records.append(shared)
	var fixture:Dictionary=helper.fixture("workers",records)
	var serial:Dictionary=Index.build(fixture.path,helper.content_root,records,"",1)
	var serial_bytes:=FileAccess.get_file_as_bytes(Index.cache_path(fixture.path,helper.content_root))
	var parallel:Dictionary=Index.build(fixture.path,helper.content_root,records,"",4)
	check(serial.ok and parallel.ok and serial.rows==parallel.rows and serial.models==parallel.models and serial.groups==parallel.groups,"serial and bounded workers produce identical ordered metadata and geometry bounds")
	check(serial_bytes==FileAccess.get_file_as_bytes(Index.cache_path(fixture.path,helper.content_root)),"directory payload and SHA remain byte identical across worker policies")
	var changed:Array=records.duplicate(true);changed[-1].color[0]=.99
	check(not Index.build(fixture.path,helper.content_root,changed,"",4).ok,"one changed duplicate cannot borrow an earlier canonical resource identity")
	changed=records.duplicate(true);changed[1].unsafe=RefCounted.new()
	check(not Index.build(fixture.path,helper.content_root,changed,"",4).ok,"unsafe definition is rejected before any classifier uses its contents")
	check(serial_bytes==FileAccess.get_file_as_bytes(Index.cache_path(fixture.path,helper.content_root)),"failed identity jobs cannot publish or replace the previous valid directory")
	var jobs:Array=[]
	for i:int in 24:
		var definition:Dictionary=Store._definition(records[i]);var encoded:Dictionary=Store._encode(definition)
		jobs.append({"definition":definition,"sha256":encoded.sha256,"length":encoded.length})
	var fallback:Dictionary=Store._read_many(jobs,false,4,Index._encode_index_definition,func(_worker,_task):return ERR_CANT_CREATE)
	check(fallback.ok and fallback.entries.size()==24 and fallback.read_profile.fallback_count==4 and fallback.read_profile.threads_started==0,"failed worker launch completes all exact canonical checks on the caller")
	for i:int in jobs.size():
		check(fallback.entries[i].sha256==jobs[i].sha256 and fallback.entries[i].length==jobs[i].length and fallback.entries[i].serialized_raw_bytes>0,"fallback preserves complete SHA, length and decoded-size accounting %d"%i)
	var invalid:Array=jobs.duplicate();invalid[0]={"definition":{"bad":RefCounted.new()}}
	var rejected:Dictionary=Store._read_many(invalid,false,4,Index._encode_index_definition)
	check(not rejected.ok and rejected.read_profile.threads_started==rejected.read_profile.workers_joined,"corrupt job always joins every started worker before returning failure")
	for path:String in helper.created:
		if Paths.allowed(path,helper.content_root) and FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(fixture.path+".resources");DirAccess.remove_absolute(helper.folder);helper.free()
	print("INDEX_DEFINITION_WORKERS checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
