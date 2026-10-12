extends SceneTree
## Pure file/CPU tests; temporary exact files only, with no model/GPU imports.
const Hashes=preload("res://scripts/world3d/model_source_hashes.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
class CaptureHashes extends Hashes:
	var requested:Array=[]
	var requested_limit:=0
	func run(paths:Array,_content_root:String,worker_limit:int=4,_thread_starter:Callable=Callable(),_hash_reader:Callable=Callable())->Dictionary:
		requested=paths.duplicate();requested_limit=worker_limit
		return {"error":ERR_SKIP,"reason":"reject remaining non-model identity","error_path":"","elapsed_us":1,"signatures":{}}
class CaptureModels extends "res://scripts/world3d/model_parse_preparation.gd":
	var requested:Array=[]
	func run(paths:Array,_parser:Callable=Callable(),_worker_limit:int=2,_thread_starter:Callable=Callable(),_content_root:String="",_verified_sources:Dictionary={})->Dictionary:
		requested=paths.duplicate()
		return {"error":OK,"elapsed_us":1,"entries":paths.map(func(path):return {"path":path,"source_digest":FileAccess.get_sha256(path),"error":OK,"elapsed_us":1})}
class Probe extends RefCounted:
	var mutex:=Mutex.new()
	var calls:Array=[]
	var finished:Array=[]
	var active:=0
	var peak:=0
	var malformed:Dictionary={}
	var block:=false
	var gate:=Semaphore.new()
	func read(path:String)->Variant:
		mutex.lock();active+=1;peak=maxi(peak,active);calls.append(path);mutex.unlock()
		if block:gate.wait()
		else:OS.delay_msec(65 if path.get_file()=="slow.bin" else 5)
		var digest:Variant=malformed[path] if malformed.has(path) else FileAccess.get_sha256(path)
		mutex.lock();active-=1;finished.append(path);mutex.unlock()
		return digest
	func count()->int:
		mutex.lock();var value:=calls.size();mutex.unlock();return value
var passed:=0
var failures:=0
var folder:=""
var created:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if ok:passed+=1
	else:failures+=1
func write(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
	if not created.has(path):created.append(path)
func run()->void:
	folder=Paths.cache_directory("source_hash_test_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var slow:=folder.path_join("slow.bin");var fast:=folder.path_join("fast.bin");var last:=folder.path_join("last.bin")
	write(slow,"abc".to_utf8_buffer());write(fast,"fast bytes".to_utf8_buffer());write(last,"last bytes".to_utf8_buffer())
	var expected:="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	var result:Dictionary=Hashes.new().run([slow,fast,slow,last],folder)
	check(result.error==OK and result.entries.map(func(entry):return entry.path)==[slow,fast,last],"deduplicate source paths while preserving first appearance order")
	check(result.unique_count==3 and result.hash_calls==3 and result.signatures[slow]==expected,"default streaming reader computes the complete known SHA-256 vector once")
	check(result.signatures[fast]==FileAccess.get_sha256(fast) and result.signatures[last]==FileAccess.get_sha256(last),"every returned identity matches the entire independent source file")
	check(result.threads_started==3 and result.threads_joined==3 and result.active_at_return==0 and result.peak_active<=4,"all started hash workers are joined within four-worker capacity")
	check(result.elapsed_us>0 and result.preflight_us>0 and result.hash_us>0,"preflight, summed hashing and wall-time diagnostics are available")
	var probe:=Probe.new()
	result=Hashes.new().run([slow,fast,last],folder,2,Callable(),probe.read)
	check(result.error==OK and probe.finished[0]==fast and probe.finished.find(last)<probe.finished.find(slow),"finished hash slot is refilled before a slower first file completes")
	check(result.entries.map(func(entry):return entry.path)==[slow,fast,last] and probe.peak==2 and result.peak_active==2,"out-of-order completion keeps input-ordered results and an exact active peak")
	var paths:Array=[slow,fast,last]
	for i in 4:
		var path:=folder.path_join("extra_%d.bin"%i);write(path,("file_%d"%i).to_utf8_buffer());paths.append(path)
	probe=Probe.new();result=Hashes.new().run(paths,folder,99,Callable(),probe.read)
	check(result.error==OK and result.worker_limit==4 and probe.peak<=4 and result.threads_started==paths.size() and result.threads_started==result.threads_joined,"requested concurrency above four is clamped and every unique source is joined")
	probe=Probe.new();result=Hashes.new().run([fast,last],folder,0,Callable(),probe.read)
	check(result.error==OK and result.worker_limit==1 and probe.peak==1,"zero requested capacity safely selects one worker")
	var changed:="abd".to_utf8_buffer();write(slow,changed)
	var replacement:Dictionary=Hashes.new().run([slow],folder)
	check(replacement.error==OK and replacement.signatures[slow]!=expected and replacement.signatures[slow]==FileAccess.get_sha256(slow),"same-length source replacement changes identity even without a size shortcut")
	write(slow,"abc".to_utf8_buffer())
	probe=Probe.new();result=Hashes.new().run([slow,42],folder,4,Callable(),probe.read)
	check(result.error==ERR_INVALID_PARAMETER and probe.count()==0 and result.signatures.is_empty() and result.threads_started==0,"invalid tail item fails before hashing any earlier valid path")
	probe=Probe.new();var missing:=folder.path_join("missing.bin")
	result=Hashes.new().run([slow,missing],folder,4,Callable(),probe.read)
	check(result.error==ERR_FILE_NOT_FOUND and result.error_path==missing and probe.count()==0 and result.entries.is_empty(),"missing tail source fails whole-input preflight without partial work")
	var outside:=folder+"_outside.bin";write(outside,"outside".to_utf8_buffer())
	probe=Probe.new();result=Hashes.new().run([slow,outside],folder,4,Callable(),probe.read)
	check(result.error==ERR_INVALID_PARAMETER and result.error_path==outside and probe.count()==0,"existing sibling with the same directory prefix remains outside the allowed root")
	probe=Probe.new();result=Hashes.new().run([slow,"res://project.godot"],folder,4,Callable(),probe.read)
	check(result.error==ERR_INVALID_PARAMETER and probe.count()==0,"project URI cannot bypass the external source root")
	probe=Probe.new();result=Hashes.new().run([slow],"",4,Callable(),probe.read)
	check(result.error==ERR_INVALID_PARAMETER and probe.count()==0,"worker hashing requires an explicit snapshotted root rather than reading an autoload")
	probe=Probe.new();result=Hashes.new().run([slow,fast,last],folder,4,func(_worker:Thread,_task:Callable):return ERR_CANT_CREATE,probe.read)
	check(result.error==OK and result.fallback_count==3 and result.threads_started==0 and result.threads_joined==0 and probe.peak==1,"failed thread launches execute the same full hash synchronously without unstarted-thread joins")
	probe=Probe.new();var launches:=[0]
	result=Hashes.new().run([slow,fast,last],folder,2,func(worker:Thread,task:Callable):
		launches[0]+=1;return worker.start(task) if launches[0]!=2 else ERR_CANT_CREATE,probe.read)
	check(result.error==OK and result.fallback_count==1 and result.threads_started==result.threads_joined and probe.peak<=2 and probe.active==0,"mixed real workers and coordinator fallback retain the total concurrency bound")
	probe=Probe.new();probe.malformed[slow]=""
	result=Hashes.new().run([slow,fast],folder,2,func(_worker:Thread,_task:Callable):return ERR_CANT_CREATE,probe.read)
	check(result.error==ERR_FILE_CANT_READ and probe.count()==1 and result.signatures.is_empty(),"synchronous hash failure stops later work and publishes no partial identity dictionary")
	probe=Probe.new();probe.malformed[slow]="";probe.malformed[fast]=17
	result=Hashes.new().run([slow,fast,last],folder,2,Callable(),probe.read)
	check(result.error==ERR_FILE_CANT_READ and result.error_path==slow and probe.finished[0]==fast and probe.count()==2,"racing failures report the earliest input source deterministically and do not schedule the tail")
	check(result.threads_started==result.threads_joined and result.active_at_return==0 and result.signatures.is_empty(),"failed operation joins all siblings and cannot expose a trusted partial result")
	result=Hashes.new().run([slow],folder,4,Callable(),func(_path:String):return "g".repeat(64))
	check(result.error==ERR_FILE_CANT_READ and result.signatures.is_empty(),"malformed SHA output cannot become a source identity")
	var job:=Hashes.new();probe=Probe.new();probe.block=true
	var coordinator:=Thread.new();coordinator.start(job.run.bind([slow,fast,last],folder,2,Callable(),probe.read))
	var deadline:=Time.get_ticks_msec()+2000
	while probe.count()<2 and Time.get_ticks_msec()<deadline:OS.delay_msec(1)
	check(probe.count()==2 and job.run([slow],folder).error==ERR_BUSY,"concurrent caller cannot alter the running hash coordinator")
	job.cancel();probe.gate.post();probe.gate.post();result=coordinator.wait_to_finish()
	check(result.cancelled and result.error==ERR_SKIP and probe.count()==2 and probe.active==0,"cancellation stops the unscheduled source and joins both active file hashes")
	check(result.threads_started==result.threads_joined and result.signatures.is_empty() and result.active_at_return==0,"cancelled hash set has no publishable signatures or lingering workers")
	probe=Probe.new();result=job.run([last],folder,4,Callable(),probe.read)
	check(result.cancelled and probe.count()==0,"cancel is sticky across accidental reuse of an old transaction")
	job=Hashes.new();job.cancel();probe=Probe.new();result=job.run([slow],folder,4,Callable(),probe.read)
	check(result.error==ERR_SKIP and result.entries.is_empty() and result.threads_started==0,"cancel before run performs no source hashing")
	result=Hashes.new().run([last],folder,4,Callable(),func(path:String):
		var digest:=FileAccess.get_sha256(path);DirAccess.remove_absolute(path);return digest)
	check(result.error==ERR_FILE_NOT_FOUND and result.signatures.is_empty(),"source disappearing during the operation cannot publish its old identity")
	write(last,"last bytes".to_utf8_buffer())
	result=Hashes.new().run([],folder)
	check(result.error==OK and result.entries.is_empty() and result.signatures.is_empty() and result.threads_started==0,"no required model sources completes without workers")
	var loader:=Loader.new();var capture:=CaptureHashes.new();var models:=CaptureModels.new();loader._source_hash_preparation=capture;loader._model_preparation=models;loader._content_root=folder
	loader._record_meta={"rmmo_records":[{"uuid":"asset_a","kind":"asset","asset_path":slow},{"uuid":"fort","kind":"box","fortification_art":{"asset_path":fast}},{"uuid":"asset_b","kind":"asset","asset_path":slow},{"uuid":"frozen","kind":"asset","asset_path":outside,"house_prefab":{}}]}
	loader._prepare_record_assets_inner()
	check(models.requested==[slow] and capture.requested==[fast] and capture.requested_limit==4,"MapLoader takes ordinary source identity from one prepared result and hashes only remaining fortification sources, excluding frozen prefabs")
	check(loader._error==ERR_SKIP and loader._asset_states.is_empty() and loader._model_signatures.is_empty(),"failed remaining dependency verification rejects all prepared model results and cook identities")
	check(loader._profile.has("source_scan_us") and loader._profile.source_hash_us==1 and loader._profile.has("source_hash_profile"),"MapLoader exposes source scanning and hashing as separate measured stages")
	loader._exit_tree();loader.free()
	loader=Loader.new();loader._content_root=folder;loader._record_meta={"rmmo_records":[{"uuid":"missing","kind":"asset","asset_path":missing}]}
	loader._prepare_record_assets_inner()
	check(loader._error==ERR_FILE_NOT_FOUND and not loader._failure_reason.is_empty() and loader._terrain_thread==null,"MapLoader propagates missing required source before any geometry cache decision")
	loader.free()
	loader=Loader.new();loader._content_root=folder;loader._record_meta={"rmmo_records":[{"uuid":"cancelled","kind":"asset","asset_path":slow}]};loader.cancel()
	loader._prepare_record_assets_inner()
	check(loader._source_hash_preparation.is_cancelled() and loader._model_preparation.is_cancelled() and loader._error==ERR_SKIP and loader._terrain_thread==null and loader._asset_states.is_empty(),"MapLoader cancellation stops before speculative terrain or model preparation starts")
	loader.free()
	for path:String in created:
		if Paths.allowed(path,Paths.external_root()) and FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	print("MODEL_SOURCE_HASHES passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
