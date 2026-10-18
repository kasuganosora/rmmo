extends SceneTree
## CPU-only source observation and resident-template ownership regression.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Fixture=preload("res://tools/test_deferred_reuse_admission.gd")
class MutationToken extends RefCounted:
	var checks:=0
	var path:=""
	var bytes:=PackedByteArray()
	var remove:=false
	func is_cancelled()->bool:
		checks+=1
		if checks==2:
			if remove:DirAccess.remove_absolute(path)
			else:
				var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
		return false
class CancelToken extends RefCounted:
	var checks:=0
	var after:=1
	func is_cancelled()->bool:
		checks+=1;return checks>=after
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->void:
	print("PASS: " if value else "FAIL: ",label_)
	if value:passed+=1
	else:failures+=1
func write(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func prepare(path:String,digest:String,token:RefCounted=null,root_:String="")->Dictionary:
	return Deferred._prepare_job(path,digest,token,{},false,Paths.external_root() if root_.is_empty() else root_,{},"",[],false,false)
func sha_calls(trace:Dictionary)->int:
	var count:=0
	for row:Dictionary in trace.stats:
		if row.label=="deferred.reused_source_sha":count+=int(row.count)
	return count
func cache(path:String,digest:String)->WeakRef:
	var packed:=PackedScene.new();Assets.cache_packed(path,packed,digest)
	return weakref(packed)
func fixture()->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	var index:=preload("res://scripts/world3d/stream_index.gd").build([])
	for key:String in index:map.set_meta(key,index[key])
	map.set_meta("stream_library",[])
	var service:=Deferred.new();map.add_child(service);var document:=Fixture.Document.new();service._doc=document
	service.activate(map);service.set_process(false)
	service._admission.byte_limit=96*1024*1024;service._admission.worker_limit=2
	return {"map":map,"service":service,"document":document}
func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=true
	var folder:=Paths.cache_directory("reuse_final_verification_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("resident.glb")
	# Deliberately not a parseable GLB: the frozen reuse route must never import.
	var bytes:=PackedByteArray();bytes.resize(4097);bytes.fill(71);bytes[-1]=29
	write(path,bytes);var digest:=FileAccess.get_sha256(path)
	Trace.start();var prepared:=prepare(path,digest);var trace:=Trace.stop()
	check(prepared.error.is_empty() and prepared.get("reused_model",false) and prepared.source_digest==digest and not prepared.has("scene"),"resident reuse verifies bytes without decoding or constructing a model")
	check(sha_calls(trace)==1,"one complete final source SHA replaces the redundant before/after pair")
	var changed:=bytes.duplicate();changed[-1]^=1;write(path,changed)
	Trace.start();var rejected:=prepare(path,digest);trace=Trace.stop()
	check(not rejected.error.is_empty() and not rejected.has("scene") and not rejected.get("reused_model",false) and sha_calls(trace)==1,"same-size source replacement still fails the complete final observation without fallback")
	write(path,bytes)
	var mutator:=MutationToken.new();mutator.path=path;mutator.bytes=changed
	rejected=prepare(path,digest,mutator)
	check(mutator.checks>=3 and not rejected.error.is_empty() and not rejected.has("scene"),"replacement after cheap preflight is rejected by final SHA")
	write(path,bytes);mutator=MutationToken.new();mutator.path=path;mutator.remove=true
	rejected=prepare(path,digest,mutator)
	check(not rejected.error.is_empty() and not rejected.has("scene"),"source removed after preflight cannot publish a resident result")
	write(path,bytes)
	for boundary in [1,2,3,4]:
		var token:=CancelToken.new();token.after=boundary
		rejected=prepare(path,digest,token)
		check(rejected.get("cancelled",false) and not rejected.has("scene") and not rejected.get("reused_model",false),"cancellation boundary %d produces no reusable result or fallback"%boundary)
	Trace.start();rejected=prepare(path,"invalid");trace=Trace.stop()
	check(not rejected.error.is_empty() and sha_calls(trace)==0,"unverified digest rejected before reading source bytes")
	Trace.start();rejected=prepare(path,digest,null,folder.path_join("outside"));trace=Trace.stop()
	check(not rejected.error.is_empty() and sha_calls(trace)==0,"content-root escape rejected before reading source bytes")
	var helper:=Fixture.new()
	for replace_same_digest in [false,true]:
		var witness:=cache(path,digest)
		var f:=fixture();var service:Node=f.service
		var item:Dictionary=helper.item(path,digest,"replacement",0)
		service.pending=[item];service.source_signatures[path]=digest;service._prepared_paths[path]=true
		service.set_demand("test",AABB(Vector3(-1,-1,-1),Vector3(3,3,3)));service.set_process(false)
		service._process(0)
		check(service._jobs.has(path) and service._jobs[path].get("reuse_template_owner")==witness.get_ref(),"dispatch strongly leases the exact validated resident template")
		service._admission.worker_limit=0
		if replace_same_digest:cache(path,digest)
		else:Assets.evict_cached_scene(path)
		check(witness.get_ref()!=null,"cache removal/replacement cannot destroy a running job's template owner")
		var deadline:=Time.get_ticks_msec()+3000
		while service._jobs.has(path) and Time.get_ticks_msec()<deadline:
			service._process(0);await process_frame
		check(service._jobs.is_empty() and service._admission.reserved_bytes==0 and f.document.calls==0,"%s after dispatch discards the completed result without importing or publishing"%["same-digest template replacement" if replace_same_digest else "cache eviction"])
		check(witness.get_ref()==null,"discard releases the job's template lease after the worker has joined")
		check(service.pending.size()==1 and not item.get("model_verified",false) and not service._prepared_paths.has(path),"rejected template generation remains pending for full-budget preparation")
		f.map.free();Assets.evict_cached_scene(path)
	# Accepted work may wait a frame before publication. Same digest is not
	# permission to silently switch the template object behind its retained lease.
	var witness:=cache(path,digest);var f:=fixture();var service:Node=f.service
	var item:Dictionary=helper.item(path,digest,"accepted_replaced",0);item.model_verified=true
	service.pending=[item];service.source_signatures[path]=digest;service._prepared_paths[path]=true
	service.set_demand("test",AABB(Vector3(-1,-1,-1),Vector3(3,3,3)));service.set_process(false)
	service._admission.reserve(path,{"estimated_bytes":65536,"exclusive":false})
	service._jobs[path]={"result":prepared,"accepted":true,"token":Deferred.Drainer.CancelToken.new(),"publication_ids":[item.record.uuid],"native":false,"reuse_template_owner":witness.get_ref()}
	service._admission.worker_limit=0;cache(path,digest);service._process(0)
	check(f.document.calls==0 and service._jobs.is_empty() and not item.get("model_verified",false),"accepted result rechecks the exact template owner before publication on a later frame")
	check(witness.get_ref()==null and service._admission.reserved_bytes==0,"late template replacement releases the superseded lease and reservation")
	f.map.free();Assets.evict_cached_scene(path)
	# Map exit abandons an unjoined worker to the scene-tree drainer. Its token
	# must retain the lease after the map's own job dictionary has disappeared.
	witness=cache(path,digest);f=fixture();service=f.service
	item=helper.item(path,digest,"exiting",0)
	service.pending=[item];service.source_signatures[path]=digest;service._prepared_paths[path]=true
	service.set_demand("test",AABB(Vector3(-1,-1,-1),Vector3(3,3,3)));service.set_process(false)
	service._process(0)
	check(service._jobs.has(path) and service._jobs[path].token.get_meta("reuse_template_owner")==witness.get_ref(),"drainer-owned cancellation token retains the same resource lease")
	Assets.evict_cached_scene(path);f.map.free()
	check(witness.get_ref()!=null,"map exit preserves an unjoined worker's template owner until the drainer consumes it")
	var deadline:=Time.get_ticks_msec()+3000
	while witness.get_ref()!=null and Time.get_ticks_msec()<deadline:await process_frame
	check(witness.get_ref()==null,"drainer joins abandoned work before releasing its retained template")
	helper.free()
	DirAccess.remove_absolute(path);DirAccess.remove_absolute(folder)
	print("DEFERRED_REUSE_FINAL_VERIFICATION passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
