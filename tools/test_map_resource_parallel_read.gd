extends SceneTree
## Pure CPU/file fixtures. No rendering, editor scene or authored map writes.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
var failed:=0
var passed:=0
var directory:=""
var map_path:=""
var created_files:Array[String]=[]

class Probe extends RefCounted:
	var mutex:=Mutex.new()
	var calls:Array=[]
	var done:Array=[]
	var active:=0
	var peak:=0
	var failures:Dictionary={}
	func read(job:Dictionary,decode:bool)->Dictionary:
		mutex.lock();calls.append(job.id);active+=1;peak=maxi(peak,active);mutex.unlock()
		OS.delay_msec(80 if job.id==0 else 5)
		mutex.lock();done.append(job.id);active-=1;mutex.unlock()
		if failures.has(job.id):return {"ok":false,"error":ERR_FILE_CORRUPT,"reason":"bad:"+str(job.id)}
		return {"ok":true,"error":OK,"length":17,"definition":{"id":job.id},"decoded":decode}

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if value:passed+=1
	else:failed+=1

func requests(count:int)->Array:
	var result:Array=[]
	for i in count:result.append({"id":i})
	return result

func record(id:String,definition:Dictionary)->Dictionary:
	var bytes:=Store._compressed(var_to_bytes(definition))
	var digest:=Store._sha(bytes)
	var uri:="map.gltf.resources/"+digest+".rmres"
	var target:=directory.path_join(uri)
	var file:=FileAccess.open(target,FileAccess.WRITE);file.store_buffer(bytes);file.close()
	if not created_files.has(target):created_files.append(target)
	return {"uuid":id,"position":[0.,0.,0.],"rotation":[0.,0.,0.],"size":[1.,1.,1.],"rmmo_state":{"editor_name":id},"rmmo_ref":{"version":1,"uri":uri,"sha256":digest,"length":bytes.size()}}

func read_count(trace:Dictionary)->int:
	var count:=0
	for stat:Dictionary in trace.stats:
		if stat.label=="resource.read_sha":count+=stat.count
	return count

func rejects_before_io(records:Array,expected:Variant,label:String)->void:
	Store._mutex.lock();Store._identities.clear();Store._mutex.unlock()
	Trace.start()
	var result:=Store.read_records(records,map_path,Paths.external_root(),expected)
	var trace:=Trace.stop()
	check(not result.ok and read_count(trace)==0 and Store._identities.is_empty(),label)

func run()->void:
	var probe:=Probe.new()
	var result:=Store._read_many(requests(12),true,99,probe.read)
	check(result.ok and probe.peak==4 and result.read_profile.peak_active==4,"concurrent reads are capped at four workers")
	check(probe.done.find(11)<probe.done.find(0),"a completed worker takes another request without waiting for the slow first request")
	check(result.entries.map(func(entry):return entry.definition.id)==range(12),"out-of-order completion restores original request order")
	check(probe.active==0 and result.read_profile.workers_joined==result.read_profile.threads_started,"successful return joins every worker")
	probe=Probe.new();probe.failures={0:true,1:true}
	result=Store._read_many(requests(8),true,2,probe.read)
	check(not result.ok and result.reason=="bad:0" and probe.done[0]==1,"failure selection follows request order instead of completion order")
	check(probe.calls.size()==2 and probe.active==0 and result.read_profile.workers_joined==2,"failure stops new claims and drains all started siblings")
	probe=Probe.new()
	result=Store._read_many(requests(5),true,4,probe.read,func(_worker:Thread,_task:Callable):return ERR_CANT_CREATE)
	check(result.ok and probe.peak==1 and result.read_profile.fallback_count==4,"failed thread launches use the same reader synchronously")
	probe=Probe.new();var launches:=[0]
	result=Store._read_many(requests(8),true,4,probe.read,func(worker:Thread,task:Callable):
		launches[0]+=1
		return worker.start(task) if launches[0]%2==1 else ERR_CANT_CREATE)
	check(result.ok and probe.active==0 and probe.peak<=4 and result.read_profile.workers_joined==2 and result.read_profile.fallback_count==2,"mixed thread failure preserves concurrency bound and cleanup")
	result=Store._read_many(requests(5),true,4,func(_job:Dictionary,_decode:bool):return null)
	check(not result.ok and result.error==ERR_INVALID_DATA and result.read_profile.completed==result.read_profile.reads_started,"malformed worker result fails closed and every claimed request finishes")
	result=Store._read_many([])
	check(result.ok and result.read_profile.threads_started==0 and result.entries.is_empty(),"empty request set launches no workers")
	directory=Paths.cache_directory("parallel_resource_read_%d"%Time.get_ticks_usec());map_path=directory.path_join("map.gltf")
	DirAccess.make_dir_recursive_absolute(map_path+".resources")
	var records:Array=[]
	for i in 9:records.append(record("object_%d"%i,{"kind":"cpu_fixture","nested":{"items":[i,i+1]},"bytes":PackedByteArray([i,255])}))
	var clone:Dictionary=records[0].duplicate(true);clone.uuid="clone";clone.rmmo_state.editor_name="clone";records.insert(3,clone)
	var dependencies:Dictionary={}
	for item:Dictionary in records:dependencies[item.rmmo_ref.uri]=item.rmmo_ref.sha256
	Trace.start();result=Store.read_records(records,map_path,Paths.external_root(),dependencies)
	var trace:=Trace.stop()
	check(result.ok and result.read_profile.unique_resources==9 and read_count(trace)==9,"shared resource URI is decoded exactly once within a concurrent open")
	check(result.records.map(func(item):return item.uuid)==records.map(func(item):return item.uuid),"hydration retains authored UUID order and duplicate-resource instances")
	var serial:=Store.read_records(records,map_path,Paths.external_root(),dependencies,1)
	check(serial.ok and serial.records==result.records and serial.dependencies==result.dependencies,"serial and parallel readers produce identical authored content and closure")
	result.records[0].nested.items[0]=999;result.records[0].position[0]=8.;result.records[0].editor_name="changed"
	check(result.records[3].nested.items[0]==0 and result.records[3].position[0]==0. and records[0].rmmo_state.editor_name=="object_0","hydrated definitions, transforms and instance state retain independent deep copies")
	var bad:Array=records.duplicate(true);bad[-1].position=[1,2]
	rejects_before_io(bad,dependencies,"invalid trailing compact record performs no resource reads or identity publication")
	bad=records.duplicate(true);bad[-1].uuid=bad[0].uuid
	rejects_before_io(bad,dependencies,"trailing duplicate UUID fails before resource IO")
	bad=records.duplicate(true);bad[-1].rmmo_ref.uri="../escape.rmres"
	rejects_before_io(bad,dependencies,"trailing invalid resource path fails before resource IO")
	bad=records.duplicate(true);bad[3].rmmo_ref.length+=1
	rejects_before_io(bad,dependencies,"conflicting lengths on one shared URI fail before resource IO")
	var wrong:Dictionary=dependencies.duplicate();wrong.erase(wrong.keys()[-1])
	rejects_before_io(records,wrong,"missing dependency rejects the complete header before any reads")
	wrong=dependencies.duplicate();wrong[wrong.keys()[-1]]="0".repeat(64)
	rejects_before_io(records,wrong,"wrong dependency digest rejects the complete header before any reads")
	wrong=dependencies.duplicate();wrong["extra"]="0".repeat(64)
	rejects_before_io(records,wrong,"extra dependency rejects exact closure before any reads")
	check(Store.verify_dependencies(dependencies,map_path,Paths.external_root()),"parallel integrity verification accepts intact full closure")
	var corrupted_path:=directory.path_join(records[-1].rmmo_ref.uri)
	var bytes:=FileAccess.get_file_as_bytes(corrupted_path);bytes[-1]^=1
	var file:=FileAccess.open(corrupted_path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
	result=Store.read_records(records,map_path,Paths.external_root(),dependencies)
	check(not result.ok and result.reason=="Resource content SHA mismatch" and result.read_profile.workers_joined==result.read_profile.threads_started,"late corrupted resource fails and joins workers without publishing records")
	check(not Store.verify_dependencies(dependencies,map_path,Paths.external_root()),"final parallel verification still detects post-open content changes")
	wrong=dependencies.duplicate();wrong["../outside.rmres"]="0".repeat(64)
	Trace.start();var verified:=Store.verify_dependencies(wrong,map_path,Paths.external_root());trace=Trace.stop()
	check(not verified and read_count(trace)==0,"invalid trailing integrity path fails before any verification reads")
	# Exact fixture paths only; no recursive removal and never touch real maps.
	for target:String in created_files:DirAccess.remove_absolute(target)
	DirAccess.remove_absolute(map_path+".resources");DirAccess.remove_absolute(directory)
	print("MAP_RESOURCE_PARALLEL_READ passed=",passed," failures=",failed)
	quit(1 if failed else 0)
