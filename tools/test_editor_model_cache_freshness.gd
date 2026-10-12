extends SceneTree
## CPU source checks and empty PackedScenes. No author assets, GPU or HTTP.
const Job=preload("res://scripts/world_editor/load_job.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var passed:=0
var failures:=0

class ProbeJob extends "res://scripts/world_editor/load_job.gd":
	var retries:=0
	var fail_model:=false
	var replace_before_publication:Callable
	var raw_task_override:Callable
	var original_lease:=0
	func _retry_cached_asset(queue:Node,key:String,asset_path:String)->bool:
		retries+=1;original_lease=queue.ledger.reserved_bytes
		# Stand in only for the heavy model parser; source checking, queue route
		# replacement, publication and cache adoption are the production methods.
		return queue.retry_cached_model(key,raw_task_override if raw_task_override.is_valid() else _model.bind(asset_path,fail_model),{"estimated_bytes":2*1024*1024,"exclusive":false,"stage":"legacy_model"})
	static func _model(path:String,fail_:bool)->Dictionary:
		if fail_:return {"error":ERR_FILE_CORRUPT}
		var node:=Node3D.new();node.name="CurrentSource"
		var packed:=PackedScene.new();var err:=packed.pack(node);node.free()
		return {"error":err,"packed":packed,"source_digest":FileAccess.get_sha256(path),"compiled":true}
	func _publication_slot()->bool:
		await get_tree().process_frame
		if replace_before_publication.is_valid():
			var action:=replace_before_publication;replace_before_publication=Callable();action.call()
		return is_inside_tree()

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failures+=1

func source(path:String,value:String)->String:
	var bytes:=PackedFloat32Array([0,0,0]).to_byte_array()
	var json:=JSON.stringify({"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":value}],"buffers":[{"byteLength":bytes.size()}]}).to_utf8_buffer()
	while json.size()%4:json.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(12+8+json.size()+8+bytes.size())
	file.store_32(json.size());file.store_32(0x4e4f534a);file.store_buffer(json)
	file.store_32(bytes.size());file.store_32(0x004e4942);file.store_buffer(bytes);file.close()
	return FileAccess.get_sha256(path)

func packed(label:String)->PackedScene:
	var node:=Node3D.new();node.name=label
	var value:=PackedScene.new();value.pack(node);node.free();return value

func make_job(path:String)->ProbeJob:
	var job:=ProbeJob.new();root.add_child(job);job._timings.build={"units":{}}
	job._begin_asset_lookahead([{"kind":"asset","uuid":"one","asset_path":path},{"kind":"asset","uuid":"two","asset_path":path}])
	return job

func prepare(job:ProbeJob,path:String)->Dictionary:
	return await job._prepare_asset({"kind":"asset","uuid":"one","asset_path":path})

func finish(job:ProbeJob,path:String,result:Dictionary)->void:
	Drainer.dispose_result(result);job._clear_asset_lookahead();job.free();Library.evict_cached_scene(path)

func run()->void:
	create_timer(30).timeout.connect(func():push_error("cache freshness test timed out");quit(2))
	var folder:=Paths.cache_directory("editor_model_freshness_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("model.glb")
	var digest:=source(path,"cached source version")
	var original:=packed("CachedSource");Library.cache_packed(path,original,digest)
	var job:=make_job(path)
	check(job._asset_paths.size()==1 and job._preparation.order.size()==1,"duplicate instances schedule one freshness check per open")
	check(job._preparation.rows["model:"+path].estimate.stage=="cache_check" and job._preparation.rows["model:"+path].estimate.cpu_only,"cached template gets a bounded CPU lease instead of bypassing preparation")
	var result:=await prepare(job,path)
	check(not result.has("scene") and job.retries==0 and Library._scenes[path]==original,"matching source snapshot reuses the exact cached allocation without parsing")
	check(job._verified_asset_versions.get(path,{}).get("source_digest")==digest and job._preparation.ledger.count()==0,"successful check stamps operation identity and releases its CPU lease")
	var next:=await prepare(job,path)
	check(not next.has("scene") and job._preparation.metrics.started==1,"later instance reuses the verified version without another hash task")
	Library.cache_packed(path,packed("SameDigestForeignOwner"),digest)
	await process_frame
	var record:={"kind":"asset","uuid":"one","asset_path":path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
	var document:=Job.Doc.new()
	var visual:Node3D=document._asset(record,result)
	check(visual.get_child_count()==1 and visual.get_child(0).name=="CachedSource","actual document publication uses the checked template across later awaits and same-SHA replacement")
	Drainer.dispose_scene(visual)
	Drainer.dispose_result(next)
	next=await prepare(job,path)
	check(next.has("scene") and next.scene==null,"later instance rejects a changed allocation even with the same source SHA")
	Library.cache_packed(path,packed("ForeignVersion"),"b".repeat(64))
	next=await prepare(job,path)
	check(next.has("scene") and next.scene==null,"later instance never borrows a different source version from global cache")
	finish(job,path,result);original=null

	digest=source(path,"older contents");original=packed("OldSource");Library.cache_packed(path,original,digest)
	var changed:=source(path,"newer contents")
	job=make_job(path);result=await prepare(job,path)
	check(job.retries==1 and job.original_lease==Job.CACHE_CLOSURE_BYTES,"changed bytes require one explicit transition out of the charged closure/hash lease")
	check(result.get("scene") is Node3D and result.scene.name=="CurrentSource","stale cached template cannot override newly prepared scene")
	check(Library.has_cached_scene(path,changed) and Library._scenes[path]!=original,"new template is bound to the parsed source identity")
	check(job._preparation.rows["model:"+path].estimate.estimated_bytes==2*1024*1024 and job._preparation.metrics.cache_retries==1 and job._preparation.ledger.count()==0,"new model uses its full separate lease and retires it after publication")
	finish(job,path,result);original=null

	digest=source(path,"same bytes new owner");Library.cache_packed(path,packed("OriginalOwner"),digest)
	job=make_job(path)
	job.replace_before_publication=func():Library.cache_packed(path,packed("ConcurrentOwner"),digest)
	result=await prepare(job,path)
	check(job.retries==1,"cache replacement while awaiting publication invalidates the checked owner even with equal source SHA")
	check(Library.has_cached_scene(path,digest) and job._preparation.ledger.count()==0,"replacement recovery retains source binding and releases all leases")
	finish(job,path,result)

	var external:=folder.path_join("external.gltf")
	var file:=FileAccess.open(folder.path_join("external.bin"),FileAccess.WRITE);file.store_buffer(PackedFloat32Array([0,0,0]).to_byte_array());file.close()
	file=FileAccess.open(external,FileAccess.WRITE);file.store_string('{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"FreshExternal"}],"buffers":[{"uri":"external.bin","byteLength":12}]}');file.close()
	digest=FileAccess.get_sha256(external);original=packed("ExternalDependencies");Library.cache_packed(external,original,digest)
	job=make_job(external)
	job.raw_task_override=Job.ModelPreparation._parse_fallback.bind(external,Paths.external_root())
	result=await prepare(job,external)
	check(job.retries==1,"root-only SHA cannot authorize cached external glTF dependencies")
	check(result.get("scene") is Node3D and Library._scenes[external]!=original,"fresh raw dependencies are published even when the root-file SHA is unchanged")
	finish(job,external,result)
	original=null

	digest=source(path,"valid old version");Library.cache_packed(path,packed("OldFallback"),digest)
	source(path,"corrupt new version");job=make_job(path);job.fail_model=true;result=await prepare(job,path)
	check(result.has("scene") and result.scene==null and job._asset_failures.has(path),"failed new parser never silently succeeds using an old cached model")
	check(Library.has_cached_scene(path,digest) and job._preparation.ledger.count()==0,"failure leaves other live/cache owners intact while returning its task budget")
	finish(job,path,result)

	# Unknown legacy cache identity must take normal full preparation, not the
	# fast hash-only check. Use valid empty geometry if its worker starts first.
	source(path,"Unverified");Library.cache_packed(path,packed("Unversioned"))
	job=ProbeJob.new();root.add_child(job);job._timings.build={"units":{}}
	job._begin_asset_lookahead([{"kind":"asset","uuid":"one","asset_path":path}])
	check(job._preparation.rows["model:"+path].estimate.stage!="cache_check","unversioned template cannot gain a trusted source version from its path")
	job._clear_asset_lookahead();job.free();Library.evict_cached_scene(path)
	var drainer:Node=Drainer.for_tree(self);var deadline:=Time.get_ticks_msec()+3000
	while not drainer.jobs.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(drainer.jobs.is_empty(),"cancelled unversioned preparation is joined and retired")
	await retry_control_contract()
	print("EDITOR_MODEL_CACHE_FRESHNESS passed=",passed," failures=",failures)
	quit(1 if failures else 0)

static func control_packet()->Dictionary:
	return {"error":OK,"cache_checked":true,"source_digest":"a".repeat(64),"cache_closed":false}

func retry_control_contract()->void:
	var queue:=Job.PreparationQueue.new();root.add_child(queue)
	var estimate:={"estimated_bytes":4096,"exclusive":false,"stage":"legacy_model"}
	queue.enqueue("check",control_packet,{"estimated_bytes":1024,"exclusive":false,"stage":"cache_check","cpu_only":true},"model")
	queue.demand("check")
	while not queue.is_ready("check"):await process_frame
	var alias:Dictionary=queue.acquire("check")
	alias.retained_resources=[packed("UnexpectedOwner")]
	check(not queue.retry_cached_model("check",control_packet,estimate) and queue.ledger.reserved_bytes==1024 and alias.has("retained_resources"),"resource-bearing check packet cannot release credit through the CPU-only retry")
	alias.erase("retained_resources")
	alias.error=ERR_FILE_CANT_READ
	check(not queue.retry_cached_model("check",control_packet,estimate) and queue.rows.check.state=="held","failed source check cannot retry as a successful cache mismatch")
	alias.error=OK;alias.cache_checked=1
	check(not queue.retry_cached_model("check",control_packet,estimate),"numeric cache flag cannot impersonate the successful check contract")
	alias.cache_checked=true;alias.cache_closed=1
	check(not queue.retry_cached_model("check",control_packet,estimate),"unknown closure flag cannot authorize model re-admission")
	alias.cache_closed=false
	var invalid:=estimate.duplicate();invalid.cpu_only=true
	check(not queue.retry_cached_model("check",control_packet,invalid) and queue.ledger.reserved_bytes==1024,"heavy model cannot keep the CPU-only lease classification")
	check(queue.retry_cached_model("check",control_packet,estimate) and alias.is_empty() and queue.ledger.reserved_bytes==0 and queue.rows.check.state=="pending" and queue.demand_key=="check","valid transition clears aliases before returning credit and preserves actual demand")
	queue.cancel();queue.free()
