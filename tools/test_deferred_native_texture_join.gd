extends SceneTree
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const InitialFixture=preload("res://tools/test_initial_native_texture_join.gd")
const Ready=preload("res://scripts/world3d/model_texture_readiness.gd")
class Queue extends Deferred:
	var fixture:SceneTree
	var geometries:=0
	var count_mutex:=Mutex.new()
	var copies:Dictionary={}
	var bad_binding:=false
	var hold_binding:=false
	var binding_blocked:=false
	var binding_gate:=Semaphore.new()
	func _candidate_for_job(_path:String,_root:String,_digest:String)->Dictionary:return fixture.candidate
	func _make_prepare_task(path:String,_digest:String,token:RefCounted,_item:Dictionary,_faces:bool,root_:String,_requests:Array,_native:bool,_need_model:bool)->Callable:
		var job:Dictionary=_jobs[path]
		return _geometry.bind(path,token,root_,job.get("estimate",{}).get("prefab_texture_plan",{}),job.get("shared_pixels",{}),job.get("parallel_pixels",false),job.has("native_model_plan"))
	func _geometry(path:String,token:RefCounted,root_:String,plan:Dictionary,shared:Dictionary,parallel:bool,split:bool)->Dictionary:
		count_mutex.lock();geometries+=1;count_mutex.unlock()
		var packed:PackedScene=copies[path];var scene:=packed.instantiate()
		if bad_binding:scene.set_meta(Ready.TABLE_META,"c".repeat(64))
		var result:Dictionary={"error":"","scene":scene,"compiled":true,"source_digest":fixture.candidate.source_sha,"records":[],"dependencies":{},"read_profile":{},"native_packet":{"error":OK,"packed":packed,"private_preparation":{"scene":scene}}}
		if split and not parallel and not plan.get("rows",{}).is_empty():
			result.prefab_texture_packet=fixture.fake_pixels({"plan":plan},root_,token,shared)
			result.waiting_pixels=result.prefab_texture_packet.get("waiting_pixels",false)
			result.error=result.prefab_texture_packet.error
		return result
	func _make_pixel_prepare_task(plan:Dictionary,root_:String,token:RefCounted,shared:Dictionary)->Callable:
		return fixture.fake_pixels.bind({"plan":plan},root_,token,shared)
	func _make_native_pixel_prepare_task(plan:Dictionary,_requested:Dictionary,root_:String,token:RefCounted,shared:Dictionary)->Callable:
		return fixture.fake_pixels.bind({"plan":plan},root_,token,shared)
	func _make_native_binding_task(result:Dictionary,plan:Dictionary,token:RefCounted)->Callable:
		var task:=super(result,plan,token)
		if hold_binding and not binding_blocked:binding_blocked=true;return _held_binding.bind(task)
		return task
	func _held_binding(task:Callable)->Dictionary:
		binding_gate.wait();return task.call()
	func geometry_count()->int:
		count_mutex.lock();var count:=geometries;count_mutex.unlock();return count
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func run()->void:
	for label:String in ["shared","serial","serial_no_yield","direct_split","empty","cancel","detach","missing","bad_binding","held_binding"]:await run_case(label)
	print("DEFERRED_NATIVE_TEXTURE_JOIN ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
func run_case(label:String)->void:
	print("CASE ",label)
	Deferred.ready_worker_yield_enabled=label!="serial_no_yield"
	Deferred.full_native_template_reuse_enabled=label=="direct_split"
	var fixture:=InitialFixture.new();fixture.make_fixture(label=="empty")
	if label=="direct_split":fixture.candidate.direct_template_reuse_safe=true
	fixture.material.resource_local_to_scene=true
	# An explicit override guarantees that PackedScene creates a distinct
	# private material; binding only the source template cannot pass this case.
	var model:=fixture.packed.instantiate();model.get_child(0).material_override=fixture.material
	model.get_child(0).mesh.surface_set_material(0,null)
	fixture.packed=PackedScene.new();fixture.packed.pack(model);model.free()
	var queue:=Queue.new();queue.fixture=fixture;queue.require_native_products=true;queue.loading_worker_limit=2
	queue.bad_binding=label=="bad_binding";queue.hold_binding=label=="held_binding"
	var pool:=InitialFixture.ControlledPool.new();pool.hold=label in ["shared","cancel","detach"];pool.fail=label=="missing";queue._shared_images=pool
	var bounds:=AABB(Vector3.ZERO,Vector3.ONE)
	for i:int in 2:
		var path:String=fixture.content_root.path_join("deferred_%d.glb"%i)
		queue.copies[path]=fixture.packed.duplicate(true)
		queue.pending.append({"record":{"uuid":"native_%d"%i,"collision":"none"},"path":path,"bounds":bounds,"digest":fixture.candidate.source_sha,"memory":{"estimated_bytes":4096,"exclusive":false,"known":true}})
	queue._reference_root=fixture.content_root
	check(queue.begin_entry_prefetch(self,bounds.grow(1),{}),"real deferred queue starts two-worker native transaction")
	queue._admission.worker_limit=1 if label.begins_with("serial") else 2
	var deadline:=Time.get_ticks_msec()+5000
	if pool.hold:
		while queue.geometry_count()<2 and Time.get_ticks_msec()<deadline:queue.pump_entry_prefetch();await process_frame
		check(queue.geometry_count()==2,"held native pixel producer permits both geometries to finish")
		check(pool.is_entered(),"native model pixels enter the common shared pool")
	var ledger:RefCounted=queue._admission;var catalog:RefCounted=queue._texture_plan_catalog
	if label in ["cancel","detach"]:
		check(ledger.reserved_bytes>0 and catalog.snapshot().native_consumers==2,"cancellation begins with live pixel and metadata owners")
		if label=="detach":
			root.add_child(queue);root.remove_child(queue);queue.copies.clear();queue.free();queue=null
			check(ledger.reserved_bytes>0 and catalog.native_metadata_reserved_bytes>0,"detachment preserves held worker and metadata charges")
			pool.gate.post()
			while ledger.reserved_bytes>0 and Time.get_ticks_msec()<deadline:await process_frame
		else:
			post_next_frame(pool.gate);await queue.quiesce();queue.copies.clear();queue.shutdown();queue.free();queue=null
		check(ledger.reserved_bytes==0 and pool.snapshot().outputs==0 and catalog.native_metadata_reserved_bytes==0,"cancel/detach drains every worker resource and metadata pin")
		fixture.packed=null;fixture.material=null;fixture.free();return
	if pool.hold:pool.gate.post()
	deadline=Time.get_ticks_msec()+5000
	var binding_released:=not queue.hold_binding
	while Time.get_ticks_msec()<deadline:
		queue.pump_entry_prefetch()
		if queue.binding_blocked and not binding_released:
			var completed:=0
			for job:Dictionary in queue._jobs.values():
				if not job.get("native_binding_pending",true):completed+=1
			if completed>0:check(true,"a blocked native binding leaves the other model free to complete");queue.binding_gate.post();binding_released=true
		if label in ["missing","bad_binding"] and (not queue.path_errors.is_empty() or not queue.instance_errors.is_empty()):break
		if complete(queue):break
		await process_frame
	if not binding_released:check(false,"binding sibling completed without head-of-line wait");queue.binding_gate.post()
	if label in ["missing","bad_binding"]:
		check(not queue.path_errors.is_empty() or not queue.instance_errors.is_empty(),"pixel/binding failure is rejected before publication")
		await queue.quiesce();queue.copies.clear();queue.shutdown();queue.free()
		check(pool.snapshot().outputs==0 and ledger.reserved_bytes==0 and catalog.native_metadata_reserved_bytes==0,"failed preparation releases all resource and metadata reservations")
		fixture.packed=null;fixture.material=null;fixture.free();return
	check(complete(queue),"native geometry and bindings finish without occupying a waiting worker")
	var bound:=0;var private_materials:=true
	for job:Dictionary in queue._jobs.values():
		if label=="direct_split":check(job.get("direct_template_reuse",false) and not job.get("direct_material_plan",true) and int(job.estimate.get("texture_plan_workspace_bytes",0))==0,"split-native direct reuse skips the empty embedded-texture scan and workspace")
		var result:Dictionary=job.get("result",{})
		if is_instance_valid(result.get("scene")):
			var material:StandardMaterial3D=result.scene.get_child(0).material_override
			if (material.albedo_texture==null if label=="empty" else material.albedo_texture!=null) and Ready.scene_ready(result.scene):bound+=1
			private_materials=private_materials and material!=fixture.material
	check(bound==2 and private_materials,"actual private local-to-scene materials bind before publication")
	check(pool.snapshot().get("streamed_loads",0)==(0 if label=="empty" else 1),"native pixel load count matches unique table rows")
	check(queue._admission.peak_workers<=(1 if label.begins_with("serial") else 2),"geometry pixel binding and metadata jobs share the worker cap")
	check(catalog.snapshot().native_async_reads==1 and catalog.snapshot().native_consumers==2,"two consumers share one native table read and keep independent pins")
	await queue.quiesce();queue.copies.clear();queue.shutdown();queue.free()
	check(pool.snapshot().outputs==0 and ledger.reserved_bytes==0 and catalog.native_metadata_reserved_bytes==0,"normal shutdown retires pixels and both metadata pins")
	fixture.packed=null;fixture.material=null;fixture.free()
func post_next_frame(gate:Semaphore)->void:
	await process_frame;gate.post()
func complete(queue:Queue)->bool:
	if queue._jobs.size()!=2:return false
	for job:Dictionary in queue._jobs.values():
		if job.has("worker") or not job.has("result") or job.result.get("waiting_pixels",false) or job.get("native_binding_pending",false) or not str(job.result.get("error","missing")).is_empty():return false
	return true
