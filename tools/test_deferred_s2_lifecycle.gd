extends SceneTree
## CPU-only scheduler proof: shared frame gating, exact group demands, and
## detached continuation owners stay charged until main-thread disposal.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
class Probe extends Deferred:
	var accepts:=0
	var publication_budget:=0
	var demand_scans:=0
	func _refresh_demanded()->void:
		demand_scans+=1
		super._refresh_demanded()
	func _main_thread_budget_usec()->int:return COVERED_LOADING_BUDGET_US
	func _dispatch_jobs(_tree:SceneTree,_prefetch_only:bool=false)->void:pass
	func _accept_prepared_records(_result:Dictionary)->void:accepts+=1
	func _publish_ready(_began:int,budget:int=INTERACTIVE_BUDGET_US)->Dictionary:
		publication_budget=budget;return {"units":0,"unit_us":0,"max_unit_us":0,"scan_us":0}
var passed:=0
var failed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failed+=1
func item(uuid:String,group:String,position:Vector3=Vector3.ZERO)->Dictionary:
	return {"record":{"uuid":uuid},"path":"reference:"+group,"group_id":group,"native_reference":true,"bounds":AABB(position,Vector3.ONE)}
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	group_test();priority_test();frame_test();failure_retirement_test();await detached_continuation_test()
	Budget.enabled=false;Budget._shared=null
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEFERRED_S2_LIFECYCLE passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
func group_test()->void:
	var queue:=Deferred.new();queue._reference_index={"groups":{"building:a":{"bounds":AABB(Vector3.ZERO,Vector3(96,10,10)),"members":[0,1]}}}
	queue.pending=[item("a0","building:a"),item("a1","building:a",Vector3(64,0,0)),item("b","building:b")]
	queue.set_demand_scope(["existing"])
	check(not queue.set_group_demand("","building:a") and not queue.set_group_demand("g","building:missing"),"unknown group and empty ticket fail without changing demand")
	check(queue.set_group_demand("g","building:a") and queue.get_demand_scope()==["existing"],"exact group demand never widens an existing transaction scope")
	queue._refresh_demanded();check(queue._demanded.is_empty(),"out-of-scope group remains unscheduled")
	queue.allow_demand_in_scope("g");queue._refresh_demanded()
	check(queue._demanded.size()==2 and queue._demanded_by_id.has("a0") and queue._demanded_by_id.has("a1") and not queue._demanded_by_id.has("b"),"group demand includes all chunks without unrelated overlapping objects")
	check(not queue.group_is_published("building:a") and not queue.group_is_published("building:missing"),"pending members and unknown groups are not published")
	queue.pending[0].published=true;check(not queue.group_is_published("building:a"),"one member never completes the whole group")
	queue.pending[1].published=true;check(queue.group_is_published("building:a"),"publication endpoint completes only after the whole group")
	queue.release_demand("g");queue._refresh_demanded();check(queue._demanded.is_empty(),"ordinary release cancels the exact group ticket")
	queue.free()
func priority_test()->void:
	var queue:=Deferred.new();queue.prioritize(Vector3(1,0,1))
	var revision:int=queue._demand_revision
	check(not queue.is_idle() and queue._candidates_revision==-1,"idle observer cannot refresh a dirty demand snapshot outside the scheduler")
	for step in 20:queue.prioritize(Vector3(1+step*.1,0,1))
	check(queue._demand_revision==revision,"centimetre motion does not rebuild town-wide ranking or texture plans every frame")
	queue.prioritize(Vector3(6,0,1))
	check(queue._demand_revision>revision,"four metre motion refreshes near-first ordering")
	queue.prioritize(Vector3(31.9,0,1));revision=queue._demand_revision
	queue.prioritize(Vector3(32.1,0,1))
	check(queue._demand_revision>revision and queue._demands.player.clip.get_center().x==48.,"chunk boundary immediately changes membership despite the ranking threshold")
	queue._active=true;queue.set_process(false);queue.prioritize(Vector3(38,0,1))
	check(queue.is_processing(),"rank revision wakes a completed scheduler so idle cannot remain stale")
	queue.set_process(false);queue.release_demand("player")
	check(queue.is_processing(),"ticket release wakes the owner to refresh idle and retire obsolete work")
	queue.free()
func frame_test()->void:
	Budget.enabled=true;Budget._shared=Budget.new()
	var queue:=Probe.new();root.add_child(queue);queue._active=true;queue.set_process(false)
	queue.pending=[item("a","a")];queue.set_demand("a",AABB(Vector3(-1,-1,-1),Vector3(3,3,3)))
	queue._admission.reserve("reference:a",{"estimated_bytes":32,"exclusive":false})
	queue._jobs["reference:a"]={"result":{},"native":true,"token":Drainer.CancelToken.new(),"publication_ids":["a"]}
	queue._admission.reserve("obsolete",{"estimated_bytes":32,"exclusive":false})
	var cancelled:=Drainer.CancelToken.new();queue._jobs.obsolete={"result":{},"native":true,"token":cancelled,"publication_ids":[]}
	Budget.shared().record(Engine.get_process_frames(),"publication",24000)
	queue._process(0)
	check(queue.accepts==0 and queue.demand_scans==0 and queue._admission.reserved_bytes==64 and not cancelled.is_cancelled(),"zero publication allowance performs no demand scan, publication or cancellation based on stale demand")
	Budget._shared=Budget.new();queue.loading_worker_limit=4;queue._process(0)
	check(queue.accepts==1 and queue.publication_budget==7000,"covered queue receives the shared seven millisecond publication lane")
	check(cancelled.is_cancelled() and not queue._jobs.has("obsolete"),"first admitted demand refresh cancels and retires obsolete work")
	check(queue.profile.main_thread_budget_mode=="covered_loading" and queue.profile.worker_capacity.mode=="covered_loading" and queue.profile.worker_capacity.effective_limit==4,"reduced frame allowance does not change covered worker capacity or diagnostic mode")
	check(Budget.report().lanes.get("publication",{}).get("calls",0)==1,"all non-await queue work charges one shared frame segment")
	queue.free();Budget.enabled=false;Budget._shared=null
class SlowRetirement extends Deferred:
	var retired:=0
	func _discard_job(path:String)->void:
		OS.delay_usec(3000)
		retired+=1
		super._discard_job(path)
func failure_retirement_test()->void:
	Budget.enabled=true;Budget._shared=Budget.new()
	var queue:=SlowRetirement.new();root.add_child(queue);queue.set_process(false);queue._active=true;queue.error="fixture failure"
	var tokens:Array=[]
	for path:String in ["one","two","three"]:
		var token:=Drainer.CancelToken.new();tokens.append(token)
		queue._admission.reserve(path,{"estimated_bytes":32,"exclusive":false})
		queue._admission.park(path)
		queue._jobs[path]={"result":{},"native":true,"token":token}
	Budget.shared().record(Engine.get_process_frames(),"retire",1000)
	queue._process(0)
	check(tokens.all(func(token):return token.is_cancelled()) and queue.retired==0 and queue._admission.reserved_bytes==96,"failure cancels immediately but denied retirement retains every result and charge")
	Budget._shared=Budget.new();queue._process(0)
	check(queue.retired==1 and queue._jobs.size()==2 and queue._admission.reserved_bytes==64,"one indivisible slow failure disposal cannot drain the entire queue in one frame")
	check(Budget.report().lanes.retire.elapsed_us>1000,"failure retirement reports actual overshoot")
	Budget.enabled=false;queue._process(0)
	check(queue._jobs.is_empty() and queue._admission.reserved_bytes==0,"remaining cancelled results eventually retire without lost reservations")
	queue.free();Budget._shared=null
static func continuation_wait(gate:Semaphore)->Dictionary:
	gate.wait();return {"error":"cancelled","cancelled":true,"images":{}}
func detached_continuation_test()->void:
	var queue:=Deferred.new();root.add_child(queue);queue.set_process(false)
	var ledger:RefCounted=queue._admission;ledger.byte_limit=1024
	var pool:RefCounted=queue._shared_images;pool.admission=ledger
	var plan:Dictionary={"rows":{"small":{"path":"small","width":1,"height":1,"source_bytes":4,"output_bytes":4,"cache_limit":4}}}
	var offer:Dictionary=pool.offer(plan)
	check(ledger.reserve_bundle("reference:continuation",{"estimated_bytes":64,"exclusive":false},offer.retained),"continuation fixture reserves original packet and unique image output")
	pool.commit("consumer",offer)
	var image:=Image.create(1,1,false,Image.FORMAT_RGBA8)
	check(pool.publish("consumer","small","a".repeat(64),image),"original worker produced its immutable CPU image")
	var weak:WeakRef=weakref(image);var packet:Dictionary={"prefab_texture_packet":{"images":{"small":image}},"records":[]};image=null
	var token:=Drainer.CancelToken.new();token.set_meta("prefab_continuation_result",packet)
	token.set_meta("prefab_shared_owner",pool);token.set_meta("prefab_shared_release",pool.release.bind("consumer"));token.cancel_callback=pool.cancel.bind("consumer")
	token.set_meta("admission_owner",ledger);token.set_meta("admission_release",ledger.release.bind("reference:continuation"))
	var gate:=Semaphore.new();var worker:=Thread.new();worker.start(continuation_wait.bind(gate))
	var drainer:=Drainer.for_tree(self);drainer.set_process(false);drainer.watch(worker,token);drainer.set_process(false)
	queue._drainer=drainer;queue._jobs["reference:continuation"]={"worker":worker,"token":token,"result":packet,"pixel_continuation":true,"pixel_consumer":"consumer"}
	# Removal exercises the ordinary map exit path. Direct free() delivers
	# PREDELETE first and deliberately uses the synchronous shutdown fallback.
	root.remove_child(queue);queue.free();drainer.set_process(false)
	check(token.is_cancelled() and weak.get_ref()!=null and ledger.reserved_bytes==72,"scene exit keeps original continuation image and complete ledger until worker termination")
	gate.post()
	while worker.is_alive():await process_frame
	drainer.set_process(false)
	Budget.enabled=true;Budget._shared=Budget.new();Budget.shared().record(Engine.get_process_frames(),"retire",1000)
	drainer._process(0)
	check(not packet.is_empty() and ledger.reserved_bytes==72,"exhausted retire lane does not dispose resources or release their charge")
	Budget._shared=Budget.new();drainer._process(0)
	check(packet.is_empty() and weak.get_ref()==null and ledger.reserved_bytes==0 and pool.snapshot().outputs==0,"main retirement clears all original packet aliases and shared owners before freeing bytes")
	check(Budget.report().lanes.get("retire",{}).get("calls",0)==1,"completed abandonment charges the shared retire lane")
	Budget.enabled=false;Budget._shared=null
