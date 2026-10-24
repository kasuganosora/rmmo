extends SceneTree
## Source identity and reference closure regression without GLTF/GPU imports.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Fixtures=preload("res://tools/test_map_dependency_index.gd")
class MutationToken extends RefCounted:
	var checks:=0
	var path:=""
	var bytes:=PackedByteArray()
	func is_cancelled()->bool:
		checks+=1
		if checks==2:
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
		return false
class Document extends RefCounted:
	var calls:=0
	func _asset(_record:Dictionary)->Node3D:
		calls+=1;return Node3D.new()
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if ok:passed+=1
	else:failures+=1
func worker_reuse(path:String,digest:String,root_:String,index:Dictionary={},map_path:String="",requests:Array=[],token:RefCounted=null)->Dictionary:
	var worker:=Thread.new()
	worker.start(Deferred._prepare_job.bind(path,digest,token,{},false,root_,index,map_path,requests,false,false))
	while worker.is_alive():await process_frame
	return worker.wait_to_finish()
func run()->void:
	# Explicit diagnostic SHA/mutation cases; normal mounted packages trust
	# their declared content identity while still checking template ownership.
	var policy=preload("res://scripts/world3d/runtime_package_policy.gd")
	var previous_policy:bool=policy.verify_packages;policy.verify_packages=true
	var helper:=Fixtures.new();helper.content_root=Paths.external_root();helper.folder=Paths.cache_directory("cached_source_test_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(helper.folder)
	var path:=helper.folder.path_join("model.glb");helper.created.append(path)
	var model_helper:=preload("res://tools/test_asset_bounds_manifest.gd").new()
	model_helper.write(path,model_helper.data());model_helper.free()
	var bytes:=FileAccess.get_file_as_bytes(path);var digest:=FileAccess.get_sha256(path)
	var original:=PackedScene.new();Assets.cache_packed(path,original,digest)
	check(Assets.has_cached_scene(path,digest) and not Assets.has_cached_scene(path,"0".repeat(64)),"cached template carries its verified content identity, not only its path")
	check(not Assets.cache_packed(path,original,"0".repeat(64)) and Assets._scenes[path]==original,"an existing template cannot be relabelled as another source digest")
	var record:Dictionary=helper.box("shared",20);record.kind="asset";record.asset_path=path;record.size=[1,1,1]
	var fixture:Dictionary=helper.fixture("map",[record]);var index:=Index.build(fixture.path,helper.content_root,[record])
	check(index.ok,"fixture has a real source-bound reference directory")
	var selection:=Index.select(index,[]);var requests:Array=selection.deferred_entries
	var prepared:Dictionary=await worker_reuse(path,digest,helper.content_root,index,fixture.path,requests)
	check(prepared.error.is_empty() and prepared.get("reused_model",false) and prepared.source_digest==digest and prepared.records.size()==1 and not prepared.has("scene"),"reuse verifies final full source SHA and the real demanded rmres closure without importing a scene")
	var changed:=bytes.duplicate();changed[-1]^=1;helper.write_bytes(path,changed)
	var rejected:Dictionary=await worker_reuse(path,digest,helper.content_root,index,fixture.path,requests)
	check(not rejected.error.is_empty() and not rejected.has("records"),"same-length binary-only GLB replacement is rejected even with a resident template")
	helper.write_bytes(path,bytes)
	var mutator:=MutationToken.new();mutator.path=path;mutator.bytes=changed
	rejected=await worker_reuse(path,digest,helper.content_root,{},"",[],mutator)
	check(mutator.checks>=3 and not rejected.error.is_empty(),"GLB mutation after preflight is rejected by final full source verification")
	helper.write_bytes(path,bytes)
	rejected=await worker_reuse(path,"",helper.content_root)
	check(not rejected.error.is_empty(),"an unversioned cache cannot grant source trust")
	var token:=Deferred.Drainer.CancelToken.new();token.cancel()
	rejected=await worker_reuse(path,digest,helper.content_root,{},"",[],token)
	check(rejected.get("cancelled",false),"cancelled reuse returns no scene or reference result")
	# A completed CPU result must not publish through a template replaced by
	# another loader after its final SHA. Keep dispatch closed to prove no
	# synchronous fallback import is attempted by acceptance or publication.
	policy.verify_packages=previous_policy
	var map:=Node3D.new();root.add_child(map)
	var stream_index:=preload("res://scripts/world3d/stream_index.gd").build([])
	for key:String in stream_index:map.set_meta(key,stream_index[key])
	map.set_meta("stream_library",[])
	var service:=Deferred.new();map.add_child(service);var document:=Document.new();service._doc=document
	service.activate(map);service.set_process(false)
	var pending:={"record":record,"path":path,"bounds":AABB(Vector3(20,0,0),Vector3.ONE),"digest":digest}
	service.pending=[pending];service.source_signatures[path]=digest;service._prepared_paths[path]=true
	service.set_demand("test",AABB(Vector3(19,-1,-1),Vector3(3,2,2)));service.set_process(false)
	service._admission.reserve(path,{"estimated_bytes":1,"exclusive":false})
	service._jobs[path]={"result":prepared,"accepted":false,"token":Deferred.Drainer.CancelToken.new(),"publication_ids":[record.uuid],"native":false}
	service._admission.worker_limit=0
	Assets.cache_packed(path,PackedScene.new(),"0".repeat(64));service._process(0)
	check(document.calls==0 and service._jobs.is_empty() and not service._prepared_paths.has(path) and service._admission.reserved_bytes==0,"template replacement after worker verification discards result and releases admission without importing or publishing on main")
	check(service.pending.size()==1 and not pending.get("model_verified",false),"rejected cache handoff keeps the instance queued for fresh worker preparation")
	map.free();Assets.evict_cached_scene(path)
	for created_path:String in helper.created:
		if FileAccess.file_exists(created_path):DirAccess.remove_absolute(created_path)
	helper.free()
	print("DEFERRED_CACHED_SOURCE passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
