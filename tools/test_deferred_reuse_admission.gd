extends SceneTree
## Headless: real reuse workers/hash/acceptance; the independent model worker is
## a held CPU task, not a renderer import. No author map or resource is changed.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const StreamIndex=preload("res://scripts/world3d/stream_index.gd")
const CachedFixture=preload("res://tools/test_deferred_cached_source.gd")
const MIB:=1024*1024
class Document extends RefCounted:
	var calls:=0
	func _asset(_record:Dictionary)->Node3D:
		calls+=1;return Node3D.new()
class HeldTask extends RefCounted:
	var gate:=Semaphore.new()
	func run()->Dictionary:
		gate.wait();return {"error":"","records":[],"dependencies":{},"read_profile":{}}
class CancelAfterFirstHash extends RefCounted:
	var checks:=0
	func is_cancelled()->bool:
		checks+=1;return checks>=2
var passed:=0
var failures:=0
var folder:=""
var created:Array[String]=[]

func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->void:
	print("PASS: " if value else "FAIL: ",label_)
	if value:passed+=1
	else:failures+=1
func write(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
	if path not in created:created.append(path)
func item(path:String,digest:String,id:String,x:float)->Dictionary:
	return {"path":path,"digest":digest,"record":{"uuid":id,"kind":"asset","asset_path":path,"collision":"none"},"bounds":AABB(Vector3(x,0,0),Vector3.ONE),"memory":{"estimated_bytes":6*1024*MIB,"exclusive":true,"known":true}}
func fixture()->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	for key:String in StreamIndex.build([]):map.set_meta(key,StreamIndex.build([])[key])
	map.set_meta("stream_library",[])
	var service:=Deferred.new();map.add_child(service);var document:=Document.new();service._doc=document
	service.activate(map);service.set_process(false);service._admission.byte_limit=96*MIB;service._admission.worker_limit=2
	return {"map":map,"service":service,"document":document}
func prepare(path:String,digest:String,token:RefCounted=null)->Dictionary:
	return Deferred._prepare_job(path,digest,token,{},false,Paths.external_root(),{},"",[],false,false)

func run()->void:
	folder=Paths.cache_directory("reuse_admission_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("shared.glb")
	for size in [0,17,Deferred.REUSE_HASH_BLOCK_BYTES,2*Deferred.REUSE_HASH_BLOCK_BYTES+29]:
		var bytes:=PackedByteArray();bytes.resize(size);bytes.fill(53)
		if size>0:bytes[-1]=91
		if size>Deferred.REUSE_HASH_BLOCK_BYTES:bytes[Deferred.REUSE_HASH_BLOCK_BYTES]=149
		write(path,bytes)
		check(Deferred._bounded_source_sha(path)==FileAccess.get_sha256(path),"streaming SHA matches engine for %d bytes (empty/exact/multi-block/short tail)"%size)
	check(Deferred._bounded_source_sha(folder.path_join("missing.glb")).is_empty(),"missing file cannot produce a source digest")
	var source:=FileAccess.get_file_as_bytes(path);var digest:=FileAccess.get_sha256(path)
	var original:=PackedScene.new();Assets.cache_packed(path,original,digest)
	var live_owner:=RefCounted.new();live_owner.set_meta("resident_template",original)
	var service:=Deferred.new();var value:=item(path,digest,"shared",0)
	var requests:Array=[{"memory_bytes":3*MIB},{"memory_bytes":5*MIB}]
	var full:Dictionary=service._estimate_job(value,requests,true);var reuse:Dictionary=service._estimate_job(value,requests,false)
	check(full.estimated_bytes==6*1024*MIB+8*MIB and full.exclusive,"new model keeps complete decode estimate plus reference outputs")
	check(reuse.estimated_bytes==8*MIB+Deferred.REUSE_HASH_RESERVATION_BYTES and not reuse.exclusive and reuse.stage=="reuse_reference","resident reuse reserves references plus bounded SHA scratch only")
	check(reuse.shared_model_estimate_bytes==6*1024*MIB and value.memory.estimated_bytes==6*1024*MIB,"reuse records shared resident ownership without modifying its original model estimate")
	var native:=value.duplicate(true);native.native_reference=true
	check(service._estimate_job(native,requests,false).estimated_bytes==8*MIB,"native reference route is unaffected by the imported-model reuse branch")
	service.free()
	var reused:=prepare(path,digest)
	check(reused.error.is_empty() and reused.get("reused_model",false) and not reused.has("scene") and reused.source_digest==digest,"reuse returns only verified CPU result and never a replacement scene")
	var cancelled:=Deferred.Drainer.CancelToken.new();cancelled.cancel()
	var result:=prepare(path,digest,cancelled)
	check(result.get("cancelled",false) and not result.has("scene"),"pre-cancelled small-budget reuse cannot import or publish")
	var between:=CancelAfterFirstHash.new();result=prepare(path,digest,between)
	check(result.get("cancelled",false) and not result.has("scene"),"cancellation after source preflight stops before any fallback")
	var changed:=source.duplicate();changed[-1]^=1;write(path,changed)
	result=prepare(path,digest)
	check(not result.error.is_empty() and not result.has("scene") and not result.get("reused_model",false),"same-length source replacement rejects without small-budget fallback")
	write(path,source)
	var mutator:=CachedFixture.MutationToken.new();mutator.path=path;mutator.bytes=changed
	result=prepare(path,digest,mutator)
	check(mutator.checks>=3 and not result.error.is_empty() and not result.has("scene"),"mutation between full SHA observations fails the frozen reuse route")
	write(path,source)
	result=prepare(folder.path_join("missing.glb"),digest)
	check(not result.error.is_empty() and not result.has("scene"),"missing source rejects rather than loading a different model")
	# Hold an independently admitted 70 MiB model worker. The real dispatch loop
	# must start the 16 MiB reuse worker without waiting for that worker to exit.
	var f:=fixture();service=f.service
	var other_path:=folder.path_join("other.glb");var other:=item(other_path,digest,"other",5)
	service.pending=[value,other];service.source_signatures[path]=digest;service._prepared_paths[path]=true
	service.set_demand("test",AABB(Vector3(-1,-1,-1),Vector3(10,3,3)));service.set_process(false)
	var held:=HeldTask.new();var worker:=Thread.new();check(worker.start(held.run)==OK,"independent CPU model task starts")
	service._admission.reserve(other_path,{"estimated_bytes":70*MIB,"exclusive":false})
	service._jobs[other_path]={"worker":worker,"token":Deferred.Drainer.CancelToken.new(),"publication_ids":["other"],"native":false}
	service._process(0)
	check(service._jobs.has(path) and service._jobs.has(other_path) and worker.is_alive() and service._admission.count()==2,"large resident model reuse dispatches while an independent model task remains active")
	check(service._admission.reserved_bytes==70*MIB+Deferred.REUSE_HASH_RESERVATION_BYTES+65536 and service._admission.reserved_bytes<=service._admission.byte_limit,"parallel reuse charges bounded scratch, not another 6 GiB decode peak")
	var deadline:=Time.get_ticks_msec()+3000
	while service._jobs.has(path) and Time.get_ticks_msec()<deadline:
		service._process(0);await process_frame
	check(not service._jobs.has(path) and service._jobs.has(other_path) and service._admission.reserved_bytes==70*MIB,"consumed reuse result releases its own reservation while sibling ownership remains charged")
	check(Assets.has_cached_scene(path,digest) and Assets._scenes[path]==original and live_owner.get_meta("resident_template")==original,"finishing reuse never releases or replaces the resident template")
	held.gate.post();await service.quiesce()
	check(service._admission.reserved_bytes==0 and service._jobs.is_empty(),"quiescence joins sibling and releases every task reservation")
	f.map.free()
	# Evict after worker verification but before result acceptance. Disable new
	# dispatch to prove neither acceptance nor publication tries a synchronous
	# model import under the reduced reservation.
	f=fixture();service=f.service;value=item(path,digest,"evicted",0)
	service.pending=[value];service.source_signatures[path]=digest;service._prepared_paths[path]=true
	service.set_demand("test",AABB(Vector3(-1,-1,-1),Vector3(3,3,3)));service.set_process(false)
	service._admission.reserve(path,reuse)
	service._jobs[path]={"result":reused,"accepted":false,"token":Deferred.Drainer.CancelToken.new(),"publication_ids":["evicted"],"native":false}
	service._admission.worker_limit=0;Assets.evict_cached_scene(path);service._process(0)
	check(f.document.calls==0 and service._jobs.is_empty() and service._admission.reserved_bytes==0 and not service._prepared_paths.has(path),"evicted template discards verified CPU result with no import/publication under small budget")
	check(service.pending.size()==1 and not value.get("model_verified",false) and service._estimate_job(value,[],not service._prepared_paths.has(path)).estimated_bytes==6*1024*MIB,"eviction retains pending work which must reacquire the full model reservation")
	check(live_owner.get_meta("resident_template")==original,"cache eviction does not destroy a separately held resident owner")
	f.map.free();Assets.evict_cached_scene(path);live_owner=null;original=null
	for created_path:String in created:
		if FileAccess.file_exists(created_path):DirAccess.remove_absolute(created_path)
	DirAccess.remove_absolute(folder)
	print("DEFERRED_REUSE_ADMISSION passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
