extends SceneTree
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failures:=0
class GateTask extends RefCounted:
	var entered:=Semaphore.new()
	var gate:=Semaphore.new()
	func work()->Dictionary:
		entered.post();gate.wait();return {"error":""}
	func header(_key:String,_source:Array,_root:String)->Dictionary:
		entered.post();gate.wait();return {}
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func plan()->Dictionary:
	return {"rows":{"test":{"path":"fixture.png","width":1024,"height":1024,"source_bytes":1,"output_bytes":4*1024*1024,"extension":"dds"}}}
func setup_pool(queue:Node,path:String)->void:
	var ledger:RefCounted=queue._admission;var pool:RefCounted=queue._shared_images;pool.admission=ledger
	var offer:Dictionary=pool.offer(plan())
	check(ledger.reserve_bundle(path,{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained),"pool producer admitted: "+path)
	pool.commit(path,offer)
	var image:=Image.create_empty(1024,1024,false,Image.FORMAT_RGBA8);image.fill(Color.RED)
	check(pool.publish(path,"test","digest",image),"pool image published: "+path)
func prepare_live_job(queue:Node,path:String,task:GateTask)->Thread:
	setup_pool(queue,path)
	var worker:=Thread.new();check(worker.start(task.work)==OK,"real loader worker started: "+path)
	task.entered.wait()
	var token:=Drainer.CancelToken.new();token.cancel_callback=queue._shared_images.cancel.bind(path)
	token.set_meta("prefab_shared_owner",queue._shared_images);token.set_meta("prefab_shared_release",queue._shared_images.release.bind(path))
	token.set_meta("admission_owner",queue._admission);token.set_meta("admission_release",queue._admission.release.bind(path))
	queue._drainer=Drainer.for_tree(self);queue._drainer.watch(worker,token)
	queue._jobs[path]={"worker":worker,"token":token,"result":{}}
	return worker
func wait_pixel(ledger:RefCounted)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while ledger.retiring_pixel_outputs>0 and ledger.active_workers()==0 and Time.get_ticks_msec()<deadline:await process_frame
func visibility_case()->void:
	var pixel_gate:=Semaphore.new();Retirement.pixel_retirement_test_gate=pixel_gate
	var queue:=Deferred.new();root.add_child(queue)
	var ledger:RefCounted=queue._admission;ledger.worker_limit=4;ledger.byte_limit=128*1024*1024
	setup_pool(queue,"pixel");ledger.park("pixel");queue._shared_images.release("pixel");ledger.release("pixel")
	await wait_pixel(ledger)
	check(ledger.retiring_pixel_outputs==1 and ledger.active_workers()==1,"pixel retirement worker actually holds one ledger slot")
	check(queue.active_workers()==1,"queue reports blocked pixel retirement worker")
	queue._candidates_revision=queue._demand_revision
	check(queue.is_idle(),"pixel worker count leaves product demand idle unchanged")
	var reader:=GateTask.new();queue._texture_plan_catalog.header_reader=reader.header
	var root_path:String=Paths.external_root();var source:String=root_path.path_join("visibility_header.png")
	var key:String=Paint.texture_key(source,false,false)
	check(not queue._texture_plan_catalog.prepare_async({key:[source,false,false]},root_path,ledger,self),"header dispatched through same admission")
	reader.entered.wait()
	var task:=GateTask.new();var worker:=Thread.new()
	check(ledger.reserve("job",{"estimated_bytes":1,"exclusive":false}) and worker.start(task.work)==OK,"ordinary loader job starts with its own ledger slot")
	task.entered.wait();queue._jobs["job"]={"worker":worker}
	check(ledger.reserve("external",{"estimated_bytes":1,"exclusive":false,"stage":"speculative_cpu"}),"external prefetch lease uses shared ledger")
	check(ledger.active_workers()==4 and queue.active_workers()==3,"pixel plus loader plus header counted once; unrelated prefetch preserves old public semantics")
	reader.gate.post();var deadline:=Time.get_ticks_msec()+5000
	while queue._texture_plan_catalog.pending_count()>0 and Time.get_ticks_msec()<deadline:queue._texture_plan_catalog.poll();await process_frame
	check(queue.active_workers()==2,"completed header removes only its own count")
	task.gate.post()
	while worker.is_alive():await process_frame
	worker.wait_to_finish();queue._jobs.erase("job");ledger.park("job");ledger.release("job")
	ledger.park("external");ledger.release("external")
	check(queue.active_workers()==1,"job and external lease removal leaves only pixel worker")
	pixel_gate.post();deadline=Time.get_ticks_msec()+5000
	while ledger.retiring_pixel_outputs>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(queue.active_workers()==0 and ledger.reserved_bytes==0,"completed retirement removes public count and lease")
	Retirement.pixel_retirement_test_gate=null;queue.free()
func detached_reopen_case()->void:
	var pixel_gate:=Semaphore.new();Retirement.pixel_retirement_test_gate=pixel_gate
	var old_queue:=Deferred.new();root.add_child(old_queue)
	var old_ledger:RefCounted=old_queue._admission;old_ledger.worker_limit=1;old_ledger.byte_limit=64*1024*1024
	var old_task:=GateTask.new();prepare_live_job(old_queue,"old",old_task)
	var drainer:Node=old_queue._drainer;var weak:WeakRef=weakref(old_queue)
	# Removing the map from the SceneTree triggers the real _exit_tree transfer;
	# calling free directly invokes the separate synchronous PREDELETE shutdown.
	root.remove_child(old_queue);old_queue.free()
	check(weak.get_ref()==null and drainer.jobs.size()>0 and old_ledger.active_workers()==1 and old_ledger.reserved_bytes>0,"forced old queue exit transfers live worker and charged ledger to drainer")
	check(not old_ledger.reserve("old-extra",{"estimated_bytes":1,"exclusive":false}),"old detached ledger still enforces its own worker cap")
	var new_queue:=Deferred.new();root.add_child(new_queue)
	var new_ledger:RefCounted=new_queue._admission;new_ledger.worker_limit=1;new_ledger.byte_limit=64*1024*1024
	var new_task:=GateTask.new();prepare_live_job(new_queue,"old",new_task)
	check(not is_same(old_ledger,new_ledger) and old_ledger.active_workers()==1 and new_ledger.active_workers()==1,"new queue uses independent bounded ledger while old worker drains")
	check(not new_ledger.reserve("new-extra",{"estimated_bytes":1,"exclusive":false}),"new ledger independently enforces its own worker cap")
	old_task.gate.post();var deadline:=Time.get_ticks_msec()+5000
	while old_ledger.retiring_pixel_outputs==0 and Time.get_ticks_msec()<deadline:await process_frame
	await wait_pixel(old_ledger)
	check(old_ledger.retiring_pixel_outputs==1 and old_ledger.active_workers()==1 and new_ledger.active_workers()==1,"old drainer transfers charge to pixel worker without touching new ledger")
	check(not old_ledger.reserve("old-extra",{"estimated_bytes":1,"exclusive":false}) and not new_ledger.reserve("new-extra",{"estimated_bytes":1,"exclusive":false}),"both independent limits remain enforced during overlapping retire and load")
	pixel_gate.post();deadline=Time.get_ticks_msec()+5000
	while old_ledger.reserved_bytes>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(old_ledger.reserved_bytes==0 and new_ledger.reserved_bytes>0,"old completion releases only old ledger")
	Retirement.pixel_retirement_test_gate=null;new_task.gate.post();new_queue.shutdown();new_queue.free()
	deadline=Time.get_ticks_msec()+5000
	while drainer.jobs.size()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(old_ledger.reserved_bytes==0 and new_ledger.reserved_bytes==0 and drainer.jobs.is_empty(),"both real queues and drainer finish without residual leases")
func run()->void:
	Retirement._service()
	await visibility_case()
	await detached_reopen_case()
	print("PIXEL_WORKER_VISIBILITY failures=",failures);quit(0 if failures==0 else 1)
