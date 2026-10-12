extends SceneTree
## CPU ownership/scheduling checks. No native renderer resource claims here.
const Queue=preload("res://scripts/world_editor/load_preparation_queue.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var passed:=0
var failures:=0
var _gates:Array=[]

class LeaseProbe extends RefCounted:
	var owner:RefCounted
	var key:String
	var observations:Array
	func _init(ledger:RefCounted,key_:String,results:Array)->void:owner=ledger;key=key_;observations=results
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			observations.append({"key":key,"main":OS.get_thread_caller_id()==OS.get_main_thread_id(),"owned":owner._entries.has(key),"bytes":owner.reserved_bytes})

class Gate extends RefCounted:
	var entered:=Semaphore.new()
	var leave:=Semaphore.new()
	func run(value:String)->Dictionary:
		entered.post();leave.wait()
		return {"error":OK,"value":value,"fixed_native":true}
	func owned(owner:RefCounted,key:String,observations:Array)->Dictionary:
		var result:Dictionary={"error":OK,"value":key,"fixed_native":true,"retained_resources":[LeaseProbe.new(owner,key,observations)]}
		entered.post();leave.wait()
		return result

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	if value:passed+=1;print("PASS ",label)
	else:failures+=1;push_error("FAIL "+label)
static func packet(value:String,native:bool=true)->Dictionary:return {"error":OK,"value":value,"fixed_native":native}
static func owned_packet(owner:RefCounted,key:String,observations:Array)->Dictionary:
	return {"error":OK,"value":key,"fixed_native":true,"retained_resources":[LeaseProbe.new(owner,key,observations)]}
func estimate(bytes:int,exclusive:bool=false)->Dictionary:return {"estimated_bytes":bytes,"exclusive":exclusive,"stage":"compiled_read"}
func gate()->Gate:
	var result:=Gate.new();_gates.append(result);return result
func make_queue(bytes:int=1000)->Node:
	var queue:=Queue.new();queue.resident_enabled=true;queue.lanes_enabled=true;queue.diagnostics_enabled=true;queue.byte_limit=bytes
	queue.resident_eligible=func(key:String,result:Dictionary)->bool:
		return queue.rows[key].lane=="model" and queue.rows[key].estimate.get("stage")=="compiled_read" and result.get("error",FAILED)==OK and result.get("fixed_native",false) and not result.get("fallback_required",false)
	root.add_child(queue);queue.set_process(false);return queue
func step(queue:Node)->void:queue._pump(Time.get_ticks_usec()+50000)
func until_ready(queue:Node,key:String)->void:
	var deadline:=Time.get_ticks_msec()+3000
	while not queue.is_ready(key) and Time.get_ticks_msec()<deadline:
		step(queue)
		if not queue.is_ready(key):await process_frame
	check(queue.is_ready(key),"joined completion: "+key)
func until_entered(signal_:Semaphore)->void:
	var deadline:=Time.get_ticks_msec()+3000;var entered:=false
	while Time.get_ticks_msec()<deadline:
		if signal_.try_wait():entered=true;break
		await process_frame
	check(entered,"worker entered semaphore gate")
func close_queue(queue:Node)->void:
	for item:Gate in _gates:
		for _i in 4:item.leave.post()
	_gates.clear();queue.resident_eligible=Callable();queue.free()
	var drainer:=Drainer.for_tree(self);var deadline:=Time.get_ticks_msec()+3000
	while not drainer.jobs.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(drainer.jobs.is_empty(),"fixture leaves no drainer worker")

func disabled_control()->void:
	for lanes:bool in [false,true]:
		var queue:=make_queue();queue.resident_enabled=false;queue.lanes_enabled=lanes
		var called:Array=[];queue.resident_eligible=func(_key:String,_packet:Dictionary)->bool:called.append(true);return true
		for index in 5:queue.enqueue("m%d"%index,packet.bind("m%d"%index),estimate(10),"model")
		for index in 4:await until_ready(queue,"m%d"%index)
		step(queue)
		check(queue.rows.m4.state=="pending" and queue.ledger.count()==4,"disabled residency preserves the original four-result window")
		check(called.is_empty() and queue.snapshot().peak_resident==0,"disabled residency never calls the ownership gate")
		check(queue.snapshot().peak_inflight==4 and queue.snapshot().peak_unconsumed==4,"disabled count diagnostics retain original meaning")
		await close_queue(queue)

func bounded_private_window()->void:
	var queue:=make_queue()
	for index in 13:queue.enqueue("m%d"%index,packet.bind("m%d"%index),estimate(10),"model")
	for index in 12:await until_ready(queue,"m%d"%index)
	step(queue)
	var stats:Dictionary=queue.snapshot()
	check(stats.resident_current==8 and stats.inflight_current==4 and queue.rows.m12.state=="pending","eight private residents plus four in-flight results is the hard count boundary")
	check(stats.peak_unconsumed==12 and stats.peak_inflight==4 and stats.peak_resident==8 and stats.peak_private_bytes==120,"all private leases remain visible separately from the two count windows")
	check(queue.ledger.reserved_bytes==120 and queue.ledger.active_workers()==0 and stats.ledger.peak_workers<=2,"resident promotion keeps the full byte charge and unchanged worker limit")
	check(stats.lane_admitted.model==4,"single pending lane borrows four in-flight slots without counting resident models")
	var held:Dictionary=queue.acquire("m0");var original:Dictionary=queue.rows.m0.packet
	check(is_same(held,original) and queue.rows.m0.held_origin=="resident","acquire returns the original packet and preserves resident ownership category")
	check(queue.snapshot().resident_current==8 and queue.snapshot().inflight_current==4,"resident-held does not silently move into the in-flight window")
	queue.release("m0");await until_ready(queue,"m12")
	check(held.is_empty() and queue.snapshot().resident_current==8 and queue.snapshot().inflight_current==4,"released resident capacity promotes joined work and permits one further preparation")
	check(queue.snapshot().resident_entered==9 and queue.snapshot().resident_exited==1,"resident transitions are counted once across acquire and release")
	var events:Array=queue.diagnostic_events();var joined_at:=-1;var resident_at:=-1
	for index in events.size():
		if events[index].key=="m0" and events[index].event=="join":joined_at=index
		if events[index].key=="m0" and events[index].event=="resident_enter":resident_at=index
	check(joined_at>=0 and resident_at>joined_at,"residency diagnostic follows real worker join")
	await close_queue(queue)

func gate_and_cross_lane()->void:
	var queue:=make_queue();queue.lanes_enabled=false # Residency itself requires the safe cross-lane scheduler.
	var observed:Array=[]
	queue.resident_eligible=func(key:String,result:Dictionary)->bool:
		observed.append({"main":OS.get_thread_caller_id()==OS.get_main_thread_id(),"joined":not queue.rows[key].has("worker"),"worker_slot":queue.ledger._entries[key].occupies_worker})
		return key=="native" and result.get("error",FAILED)==OK
	queue.enqueue("native",packet.bind("native"),estimate(10),"model")
	queue.enqueue("image",packet.bind("image",false),estimate(10),"texture")
	await until_ready(queue,"native");await until_ready(queue,"image")
	check(queue.rows.native.state=="resident" and queue.rows.image.state=="ready","only an explicitly accepted packet becomes resident")
	var safe:=true
	for item:Dictionary in observed:safe=safe and item.main and item.joined and not item.worker_slot
	check(safe and not observed.is_empty(),"ownership gate runs only on main after CPU join and worker slot park")
	queue.enqueue("bad",func()->Dictionary:return {"error":ERR_INVALID_DATA,"fixed_native":true},estimate(10),"model")
	await until_ready(queue,"bad")
	check(queue.rows.bad.state=="ready","rejected/error packet keeps the existing ready ownership route")
	await close_queue(queue)

	queue=make_queue(100)
	queue.enqueue("model",packet.bind("model"),estimate(10),"model");await until_ready(queue,"model")
	queue.enqueue("image",packet.bind("image",false),estimate(80),"texture");await until_ready(queue,"image")
	var large:=gate();var model:=gate()
	queue.enqueue("large_image",large.run.bind("large"),estimate(30),"texture")
	queue.enqueue("next_model",model.run.bind("next"),estimate(10),"model")
	step(queue)
	check(queue.rows.large_image.state=="pending" and queue.rows.next_model.state=="running","byte-blocked texture lane does not prevent a model that fits the same full ledger")
	check(queue.ledger.reserved_bytes==100 and queue.snapshot().resident_current==1,"cross-lane progress never borrows unpaid resident bytes")
	await close_queue(queue)

func demand_minimal_retirement()->void:
	var queue:=make_queue(100);var observed:Array=[]
	queue.enqueue("resident",owned_packet.bind(queue.ledger,"resident",observed),estimate(60),"model")
	await until_ready(queue,"resident");var alias:Dictionary=queue.rows.resident.packet
	queue.enqueue("ready",packet.bind("ready",false),estimate(10),"texture");await until_ready(queue,"ready")
	var required:=gate();queue.enqueue("needed",required.run.bind("needed"),estimate(50),"texture");queue.demand("needed");step(queue)
	check(queue.rows.needed.state=="running" and queue.rows.resident.state=="pending" and queue.rows.ready.state=="ready","byte demand retires the one sufficiently large resident, preserving useful ready work")
	check(alias.is_empty() and observed.size()==1 and observed[0].main and observed[0].owned and observed[0].bytes==70,"resident aliases are destroyed on main while their exact lease is still charged")
	check(queue.snapshot().preempted==1 and queue.snapshot().resident_exited==1 and queue.ledger.reserved_bytes==60,"retirement returns full resident credit exactly once")
	await close_queue(queue)

	queue=make_queue(100)
	queue.enqueue("held",packet.bind("held"),estimate(60),"model");await until_ready(queue,"held");var held:Dictionary=queue.acquire("held")
	queue.enqueue("ready",packet.bind("ready",false),estimate(10),"texture");await until_ready(queue,"ready")
	required=gate();queue.enqueue("needed",required.run.bind("needed"),estimate(50),"texture");queue.demand("needed");step(queue)
	check(queue.rows.needed.state=="pending" and queue.snapshot().preempted==0 and held.get("value")=="held","held resident pressure prevents futile destruction of a ready packet")
	queue.release("held");step(queue)
	check(queue.rows.needed.state=="running" and queue.rows.ready.state=="ready" and queue.snapshot().preempted==0,"actual held release allows demand without any unnecessary eviction")
	await close_queue(queue)

	queue=make_queue();queue.ready_limit=2
	queue.enqueue("large_resident",packet.bind("resident"),estimate(500),"model");await until_ready(queue,"large_resident")
	for key:String in ["early","late"]:queue.enqueue(key,packet.bind(key,false),estimate(10),"texture");await until_ready(queue,key)
	var retained:Dictionary=queue.rows.large_resident.packet
	required=gate();queue.enqueue("needed",required.run.bind("needed"),estimate(10),"texture");queue.demand("needed");step(queue)
	check(queue.rows.needed.state=="running" and queue.rows.late.state=="pending" and queue.rows.early.state=="ready","in-flight pressure retires exactly the latest in-flight result")
	check(retained.get("value")=="resident" and queue.snapshot().preempted==1,"resident eviction cannot be used to pretend an in-flight slot was freed")
	await close_queue(queue)

func exclusive_and_worker_fences()->void:
	var queue:=make_queue(100)
	queue.enqueue("resident",packet.bind("resident"),estimate(20),"model");await until_ready(queue,"resident")
	var exclusive:=gate();queue.enqueue("exclusive",exclusive.run.bind("exclusive"),estimate(200,true),"model");step(queue)
	check(queue.rows.exclusive.state=="pending" and queue.ledger.count()==1 and queue.snapshot().inflight_current==0,"resident-only ledger is not empty for an exclusive drain fence")
	queue.demand("exclusive");step(queue)
	check(queue.rows.exclusive.state=="running" and queue.rows.resident.state=="pending" and queue.ledger.reserved_bytes==200,"exclusive actual demand can retire joined resident then use the existing oversized singleton exception")
	exclusive.leave.post();await until_ready(queue,"exclusive")
	check(queue.rows.exclusive.state=="resident" and queue.ledger.snapshot().exclusive_keys==["exclusive"],"promoted exclusive keeps its exclusive ledger ownership")
	queue.enqueue("ordinary",packet.bind("ordinary",false),estimate(1),"texture");step(queue)
	check(queue.rows.ordinary.state=="pending","zero in-flight count never bypasses a resident exclusive")
	await close_queue(queue)

	queue=make_queue(100)
	queue.enqueue("resident",packet.bind("resident"),estimate(60),"model");await until_ready(queue,"resident")
	var a:=gate();var b:=gate()
	queue.enqueue("a",a.run.bind("a"),estimate(10),"texture");queue.enqueue("b",b.run.bind("b"),estimate(10),"texture");step(queue)
	await until_entered(a.entered);await until_entered(b.entered)
	var required:=gate();queue.enqueue("needed",required.run.bind("needed"),estimate(50),"texture");queue.demand("needed");step(queue)
	check(queue.rows.needed.state=="pending" and queue.rows.resident.state=="resident" and queue.snapshot().preempted==0,"both live workers block demand without wasting a resident packet")
	await close_queue(queue)

func raw_retry_and_start_failure()->void:
	var queue:=make_queue();var observed:Array=[]
	queue.enqueue("native",owned_packet.bind(queue.ledger,"native",observed),estimate(10),"model");await until_ready(queue,"native")
	var held:Dictionary=queue.acquire("native");var raw:=gate()
	check(queue.retry_as_raw("native",raw.run.bind("raw"),{"estimated_bytes":90,"exclusive":false}),"resident-held native result can take the existing raw retry route")
	check(held.is_empty() and observed.size()==1 and observed[0].main and observed[0].owned and queue.ledger.count()==0,"native resident is synchronously disposed before fresh raw admission")
	check(queue.rows.native.state=="pending" and not queue.rows.native.has("held_origin") and queue.rows.native.lane=="model" and queue.demand_key=="native","raw retry resets residency while preserving first-use lane and demand")
	step(queue);await until_entered(raw.entered)
	check(queue.ledger.reserved_bytes==90 and queue.snapshot().inflight_current==1 and queue.snapshot().resident_current==0,"raw retry reserves full new bytes in the in-flight window")
	raw.leave.post();await until_ready(queue,"native")
	check(queue.rows.native.state=="ready","raw success does not inherit native residency eligibility")
	await close_queue(queue)

	queue=make_queue();queue.thread_starter=func(_worker:Thread,_task:Callable)->int:return ERR_CANT_CREATE
	queue.enqueue("failed",packet.bind("must_not_run"),estimate(10),"model");step(queue);step(queue)
	check(queue.rows.failed.state=="ready" and queue.rows.failed.packet.get("start_failed",false) and queue.snapshot().resident_current==0,"start failure stays ready and cannot promote as native success")
	queue.release("failed")
	check(queue.ledger.count()==0 and queue.snapshot().diagnostics.tasks.failed.first_start_us==0,"failed launch releases its lease with no fabricated worker start")
	await close_queue(queue)

func exact_mixed_cancel()->void:
	var queue:=make_queue();var observed:Array=[]
	for key:String in ["resident","resident_held"]:
		queue.enqueue(key,owned_packet.bind(queue.ledger,key,observed),estimate(10),"model");await until_ready(queue,key)
	var resident_alias:Dictionary=queue.rows.resident.packet;var resident_held:Dictionary=queue.acquire("resident_held")
	for key:String in ["ready","ready_held"]:
		queue.enqueue(key,owned_packet.bind(queue.ledger,key,observed),estimate(10),"texture");await until_ready(queue,key)
	var ready_alias:Dictionary=queue.rows.ready.packet;var ready_held:Dictionary=queue.acquire("ready_held")
	var live:=gate();queue.enqueue("running",live.owned.bind(queue.ledger,"running",observed),estimate(30),"model");step(queue);await until_entered(live.entered)
	queue.enqueue("pending",packet.bind("not_run"),estimate(1000),"model")
	check(queue.rows.resident.state=="resident" and queue.rows.resident_held.state=="held" and queue.rows.ready.state=="ready" and queue.rows.ready_held.state=="held" and queue.rows.running.state=="running" and queue.rows.pending.state=="pending","cancel fixture simultaneously owns actual resident resident-held ready ready-held running and pending rows")
	var owner:RefCounted=queue.ledger;var drainer:=Drainer.for_tree(self);var before:int=drainer.drained
	queue.cancel()
	check(resident_alias.is_empty() and resident_held.is_empty() and ready_alias.is_empty() and ready_held.is_empty(),"mixed cancellation clears all joined packet aliases including held residents")
	check(owner.reserved_bytes==30 and owner.count()==1 and owner._entries.has("running"),"mixed cancellation retains exactly the semaphore-blocked worker lease")
	check(observed.size()==4 and queue.snapshot().resident_exited==2,"joined resources are destroyed before worker completion and residency exits exactly once")
	var safe:=true
	for item:Dictionary in observed:safe=safe and item.main and item.owned
	check(safe,"each joined destructor sees its own live lease on main")
	queue.cancel();check(owner.reserved_bytes==30 and observed.size()==4,"repeated cancel is idempotent while worker remains gated")
	queue.resident_eligible=Callable();queue.free()
	live.leave.post();_gates.clear()
	var deadline:=Time.get_ticks_msec()+3000
	while drainer.drained==before and Time.get_ticks_msec()<deadline:await process_frame
	check(drainer.drained==before+1 and owner.count()==0 and owner.reserved_bytes==0,"detached drainer joins gated worker and returns its exact remaining credit")
	check(observed.size()==5 and observed[4].key=="running" and observed[4].main and observed[4].owned,"live worker output is destroyed on main before its own lease disappears")
	check(drainer.jobs.is_empty(),"mixed cancel leaves no live or abandoned worker")

func run()->void:
	Engine.max_fps=240;create_timer(45).timeout.connect(func():quit(2))
	await disabled_control()
	await bounded_private_window()
	await gate_and_cross_lane()
	await demand_minimal_retirement()
	await exclusive_and_worker_fences()
	await raw_retry_and_start_failure()
	await exact_mixed_cancel()
	print("EDITOR_PREPARATION_RESIDENCY passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
