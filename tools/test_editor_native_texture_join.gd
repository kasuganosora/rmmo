extends "res://tools/test_native_texture_preview.gd"
## CPU-only real LoadJob entry. Native geometry and tables are external fixtures;
## only the StreamedTexture2D upload is replaced by a counted Texture2D stub.
const Job=preload("res://scripts/world_editor/load_job.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Shared=preload("res://scripts/world3d/shared_prefab_images.gd")
const Frame=preload("res://scripts/world3d/frame_work_budget.gd")
var cases:Array=[]

class Host extends Node3D:
	var _shared_preparation_ledger=Admission.new()
class TextureStub extends Texture2D:
	var audit:RefCounted
	func _get_width()->int:return 4
	func _get_height()->int:return 4
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE and audit!=null:audit.record_release()
class Audit extends RefCounted:
	var mutex:=Mutex.new()
	var releases:Array=[]
	var created:=0
	func record_release()->void:
		mutex.lock();releases.append(OS.get_thread_caller_id());mutex.unlock()
class ControlledPool extends Shared:
	var gate:=Semaphore.new()
	var guard:=Mutex.new()
	var hold:=false
	var entered:=false
	var fail:=false
	var audit:=Audit.new()
	func _streamed_handoff_enabled()->bool:return true
	func _streamed_handoff_texture_valid(texture:Texture2D)->bool:return texture is TextureStub
	func _load_stream(_plan:Dictionary,_digest:String)->Texture2D:
		guard.lock();entered=true;var blocked:=hold;guard.unlock()
		if blocked:gate.wait()
		if fail:return null
		var texture:=TextureStub.new();texture.audit=audit
		audit.mutex.lock();audit.created+=1;audit.mutex.unlock()
		return texture
	func has_entered()->bool:
		guard.lock();var value:=entered;guard.unlock();return value

func pixels(plan:Dictionary,_root:String,token:RefCounted,shared:Dictionary)->Dictionary:
	var owners:Dictionary={};var waiting:=false
	for key:String in plan.plan.rows:
		if token.is_cancelled():return {"error":"cancelled","cancelled":true}
		var row:Dictionary=plan.plan.rows[key];var digest:String=row.path.sha256_text()
		if not shared.pool.remember_source_identity(shared.consumer,row.path,digest):return {"error":"identity"}
		if shared.leaders.has(key) and not shared.pool.load_stream(shared.consumer,key,digest,row):return {"error":"load"}
		var fetched:Dictionary=shared.pool.fetch(shared.consumer,key,digest,token)
		if not fetched.error.is_empty():return {"error":fetched.error}
		if fetched.get("pending",false):waiting=true;continue
		owners[key]=fetched.texture
	return {"error":"","images":{},"uploaded_textures":owners,"waiting_pixels":waiting}

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):
		printerr("This fixture requires an isolated review_artifacts content root");quit(2);return
	create_timer(45.0).timeout.connect(func():printerr("EDITOR_NATIVE_TEXTURE_JOIN watchdog timeout");quit(2))
	var first:=fixture("editor_first",true);var second:=fixture("editor_second",true)
	check(not FileAccess.file_exists(first.path) and not FileAccess.file_exists(second.path),"cold editor fixtures have no GLB sources")
	var host:=Host.new();root.add_child(host)
	var job:=Job.new();job.editor=host;host.add_child(job)
	job._timings.build={"units":{}}
	var pool:=ControlledPool.new()
	# Optional injection leaves the same test runnable against the old source.
	if "native_texture_pool" in job:job.native_texture_pool=pool
	if "native_texture_preparer" in job:job.native_texture_preparer=pixels
	var records:Array=[{"kind":"asset","uuid":"one","asset_path":first.path},{"kind":"asset","uuid":"two","asset_path":second.path}]
	job._begin_asset_lookahead(records)
	check(job._preparation.ledger==host._shared_preparation_ledger,"LoadJob uses the editor shared ledger")
	var scenes:Array=[];var owners:Array=[]
	for record:Dictionary in records:
		var result:Dictionary=await job._prepare_asset(record)
		var scene:Node=result.get("scene")
		check(scene!=null,"cold LoadJob prepares complete model "+record.uuid)
		if scene!=null:
			scenes.append(scene)
			var material:StandardMaterial3D=scene.get_child(0).mesh.surface_get_material(0)
			owners.append(material.albedo_texture)
			check(Ready.scene_ready(scene) and material.albedo_texture is TextureStub,"cold editor publishes only bound native model "+record.uuid)
	check(owners.size()==2 and owners[0]==owners[1],"different native models share the exact texture owner")
	check(int(pool.profile.produced)==1,"one unique texture is produced once")
	check(Assets._scenes.has(first.path) and Assets._scenes.has(second.path),"cold models enter the existing shared template cache")
	for scene:Node in scenes:Drainer.dispose_scene(scene)
	scenes.clear();owners.clear()
	Assets._scenes.erase(first.path);Assets._scenes.erase(second.path)
	job._clear_asset_lookahead()
	check(host._shared_preparation_ledger.reserved_bytes==0 and host._shared_preparation_ledger.count()==0,"completed operation releases every temporary lease")
	job.free();host.free()
	var probe:=Job.new();var extended:bool="native_texture_pool" in probe;probe.free()
	if extended:
		await contract_case("single",1,1,4*1024*1024*1024)
		await contract_case("oversize",1,1,1024)
		await contract_case("parallel_wait",2,4,4*1024*1024*1024)
		await contract_case("missing",2,1,4*1024*1024*1024)
		await contract_case("start_fail",1,1,4*1024*1024*1024)
		await contract_case("cancel_running",2,4,4*1024*1024*1024)
		await contract_case("cancel_ready",2,4,4*1024*1024*1024)
	print("EDITOR_NATIVE_TEXTURE_CASES ",JSON.stringify(cases))
	print("EDITOR_NATIVE_TEXTURE_JOIN checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func release_gate(job:Node,pool:ControlledPool,cancelled:bool)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while not pool.has_entered() and Time.get_ticks_msec()<deadline:await process_frame
	if not cancelled:
		while int(pool.snapshot().waits)==0 and Time.get_ticks_msec()<deadline:await process_frame
		check(int(pool.snapshot().waits)>0,"parallel_wait: follower yields while its leader is busy")
		check(job._preparation.ledger.active_workers()<=2,"parallel_wait: shared worker allowance includes both models")
	else:job._clear_asset_lookahead()
	pool.gate.post()

func contract_case(label:String,workers:int,ready_limit:int,bytes_:int)->void:
	var first:=fixture(label+"_first",true);var second:=fixture(label+"_second",true)
	var records:Array=[{"kind":"asset","uuid":"one","asset_path":first.path},{"kind":"asset","uuid":"two","asset_path":second.path}]
	var host:=Host.new();root.add_child(host)
	var job:=Job.new();job.editor=host;job._timings.build={"units":{}};host.add_child(job)
	var pool:=ControlledPool.new();pool.hold=label in ["parallel_wait","cancel_running"];pool.fail=label=="missing"
	job.native_texture_pool=pool;job.native_texture_preparer=pixels
	# Suppress only this synchronous setup pump, so the requested limits apply
	# before the first table/model worker is started. Normal frame pumping follows.
	var old_enabled:=Frame.enabled;var old_shared:RefCounted=Frame._shared
	Frame.enabled=true;Frame._shared=Frame.new();Frame._shared.covered_limits=Frame.COVERED.duplicate();Frame._shared.covered_limits.publication=0
	job._begin_asset_lookahead(records)
	var queue:Node=job._preparation;queue.worker_limit=workers;queue.ready_limit=ready_limit
	queue.ledger.worker_limit=workers;queue.byte_limit=bytes_;queue.ledger.byte_limit=bytes_
	if label=="start_fail":queue.thread_starter=func(_worker:Thread,_task:Callable)->int:return ERR_CANT_CREATE
	Frame.enabled=old_enabled;Frame._shared=old_shared
	var helper:RefCounted=job._native_textures
	if pool.hold:release_gate(job,pool,label=="cancel_running")
	var scenes:Array=[];var owners:Array=[]
	if label=="cancel_ready":
		var deadline:=Time.get_ticks_msec()+5000
		while not queue.is_ready("model:"+first.path) and Time.get_ticks_msec()<deadline:await process_frame
		check(queue.is_ready("model:"+first.path),label+": native result completes before cancellation")
		check(not Assets._scenes.has(first.path),label+": completed private result is not published early")
		job._clear_asset_lookahead()
	else:
		for record:Dictionary in records:
			var result:Dictionary=await job._prepare_asset(record)
			var scene:Node=result.get("scene")
			if label=="cancel_running":
				check(result.get("cancelled",false) and scene==null,label+": pending caller sees cancelled generation");break
			var expected:=label not in ["missing","start_fail"]
			check((scene!=null)==expected,label+": complete publication contract "+record.uuid)
			if scene!=null:
				scenes.append(scene)
				owners.append(scene.get_child(0).mesh.surface_get_material(0).albedo_texture)
				check(Ready.scene_ready(scene),label+": no unbound native READY "+record.uuid)
	if label in ["single","oversize","parallel_wait"]:
		check(owners.size()==2 and owners[0]==owners[1],label+": exact owner shared across models")
		check(int(pool.snapshot().produced)==1,label+": one unique native texture production")
		check(int(helper.catalog.native_async_reads)==1,label+": one table read for both models")
		check(host._shared_preparation_ledger.peak_workers<=workers,label+": no extra worker allowance")
	for scene:Node in scenes:Drainer.dispose_scene(scene)
	scenes.clear();owners.clear();Assets._scenes.erase(first.path);Assets._scenes.erase(second.path)
	job._clear_asset_lookahead()
	var deadline:=Time.get_ticks_msec()+5000
	while host._shared_preparation_ledger.count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(host._shared_preparation_ledger.reserved_bytes==0 and host._shared_preparation_ledger.count()==0,label+": exact temporary ledger zero after join")
	check(host._shared_preparation_ledger.byte_limit==bytes_ and helper.catalog.native_metadata_reserved_bytes==0,label+": metadata allowance restored")
	check(pool.snapshot().consumers==0 and pool.snapshot().outputs==0,label+": no pool consumer or output leak")
	check(pool.audit.releases.size()==pool.audit.created,label+": every created texture has a final release")
	check(pool.audit.releases.all(func(thread_id):return thread_id==OS.get_main_thread_id()),label+": final texture release stays on main")
	cases.append({"label":label,"profile":helper.snapshot(),"ledger":host._shared_preparation_ledger.snapshot(),"final_texture_releases":pool.audit.releases})
	job.free();host.free();await process_frame
