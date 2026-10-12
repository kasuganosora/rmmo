extends SceneTree
## CPU-only production queue tests. Semaphores control completion, not sleeps.
const Queue=preload("res://scripts/world_editor/load_preparation_queue.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var passed:=0
var failures:=0
var _gates:Array=[]

class Gate extends RefCounted:
	var entered:=Semaphore.new()
	var leave:=Semaphore.new()
	func run(value:String)->Dictionary:
		entered.post();leave.wait()
		return {"error":OK,"value":value}

class LeaseProbe extends RefCounted:
	var owner:RefCounted
	var observations:Array
	func _init(ledger:RefCounted,results:Array)->void:owner=ledger;observations=results
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			observations.append({"main":OS.get_thread_caller_id()==OS.get_main_thread_id(),"bytes":owner.reserved_bytes})

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	if value:passed+=1;print("PASS ",label)
	else:failures+=1;push_error("FAIL "+label)
static func packet(value:String)->Dictionary:return {"error":OK,"value":value}
static func owned_packet(owner:RefCounted,observations:Array)->Dictionary:
	return {"error":OK,"retained_resources":[LeaseProbe.new(owner,observations)]}
func estimate(bytes:int,exclusive:bool=false)->Dictionary:return {"estimated_bytes":bytes,"exclusive":exclusive,"cpu_only":true}
func gate()->Gate:
	var result:=Gate.new();_gates.append(result);return result
func make_queue(lanes:bool=true,bytes:int=100)->Node:
	var queue:=Queue.new();queue.lanes_enabled=lanes;queue.diagnostics_enabled=true;queue.byte_limit=bytes
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
	# Release even unexpected starts after an assertion failure before shutdown.
	for item:Gate in _gates:
		for _i in 4:item.leave.post()
	_gates.clear()
	queue.free()
	var drainer:=Drainer.for_tree(self);var deadline:=Time.get_ticks_msec()+3000
	while not drainer.jobs.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(drainer.jobs.is_empty(),"queue workers retire before next fixture")

func fifo_and_cross_lane()->void:
	for enabled:bool in [false,true]:
		var queue:=make_queue(enabled)
		check(not queue.enqueue("bad_lane",packet.bind("bad"),estimate(10),"image"),"unknown lane rejected without a queue row")
		check(queue.enqueue("neutral",packet.bind("neutral"),estimate(1)),"legacy three-argument enqueue remains valid")
		await until_ready(queue,"neutral");queue.release("neutral")
		check(queue.rows.neutral.lane=="neutral","empty lane normalizes to bounded neutral category")
		queue.enqueue("texture_1",packet.bind("one"),estimate(20),"texture")
		queue.enqueue("texture_2",packet.bind("two"),estimate(20),"texture")
		await until_ready(queue,"texture_1");await until_ready(queue,"texture_2")
		var held:Dictionary=queue.acquire("texture_1");var ready_alias:Dictionary=queue.rows.texture_2.packet
		var large:=gate();var cheap:=gate();var model:=gate()
		queue.enqueue("texture_large",large.run.bind("large"),estimate(80),"texture")
		queue.enqueue("texture_cheap",cheap.run.bind("cheap"),estimate(1),"texture")
		queue.enqueue("model_1",model.run.bind("model"),estimate(10),"model")
		step(queue)
		check(queue.rows.texture_large.state=="pending" and queue.rows.texture_cheap.state=="pending","same-lane cheap tail never passes byte-blocked head")
		check(queue.rows.model_1.state==("running" if enabled else "pending"),"only enabled lanes bypass another category's blocked head")
		check(held.get("value")=="one" and ready_alias.get("value")=="two" and queue.snapshot().preempted==0,"speculation preserves held and ready owners without preemption")
		check(queue.ledger.reserved_bytes==(50 if enabled else 40),"shared byte ledger matches retained plus active lane work")
		await close_queue(queue)

func shares_and_idle_borrow()->void:
	var queue:=make_queue();var signals:Dictionary={}
	for key:String in ["t1","t2","t3","m1","m2","m3"]:
		var item:=gate();signals[key]=item
		queue.enqueue(key,item.run.bind(key),estimate(10),"texture" if key.begins_with("t") else "model")
	step(queue)
	check(queue.rows.t1.state=="running" and queue.rows.t2.state=="running" and queue.ledger.active_workers()==2,"two workers are the unchanged global dispatch cap")
	signals.t1.leave.post();signals.t2.leave.post()
	await until_ready(queue,"t1");await until_ready(queue,"t2")
	step(queue)
	check(queue.rows.t3.state=="pending" and queue.rows.m1.state=="running" and queue.rows.m2.state=="running","two texture results leave capacity for two model workers")
	signals.m1.leave.post();signals.m2.leave.post()
	await until_ready(queue,"m1");await until_ready(queue,"m2")
	var held:Dictionary=queue.acquire("t1");step(queue)
	check(queue.ledger.count()==4 and queue.rows.t3.state=="pending" and queue.rows.m3.state=="pending","running ready and held all occupy the global window")
	check(queue.snapshot().lane_admitted=={"model":2,"texture":2,"neutral":0},"contending categories stay within their two-result shares")
	queue.release("t2");step(queue)
	check(queue.rows.t3.state=="running" and held.get("value")=="t1" and queue.rows.m3.state=="pending","returned texture capacity advances its own earliest pending task")
	await close_queue(queue)

	queue=make_queue();signals={}
	for key:String in ["m1","m2","m3","m4","m5"]:
		var item:=gate();signals[key]=item;queue.enqueue(key,item.run.bind(key),estimate(10),"model")
	step(queue);signals.m1.leave.post();signals.m2.leave.post()
	await until_ready(queue,"m1");await until_ready(queue,"m2")
	step(queue)
	check(queue.rows.m3.state=="running" and queue.rows.m4.state=="running","single pending category borrows idle shares up to the original four slots")
	signals.m3.leave.post();signals.m4.leave.post()
	await until_ready(queue,"m3");await until_ready(queue,"m4");step(queue)
	check(queue.ledger.count()==4 and queue.rows.m5.state=="pending" and queue.snapshot().lane_admitted.model==4,"idle borrowing never expands the global ready limit")
	await close_queue(queue)

func demand_borrows_held_share()->void:
	var queue:=make_queue()
	for key:String in ["t1","t2"]:queue.enqueue(key,packet.bind(key),estimate(10),"texture")
	await until_ready(queue,"t1");await until_ready(queue,"t2")
	var held1:Dictionary=queue.acquire("t1");var held2:Dictionary=queue.acquire("t2")
	var required:=gate();var model:=gate()
	queue.enqueue("needed",required.run.bind("needed"),estimate(10),"texture")
	queue.enqueue("model",model.run.bind("model"),estimate(10),"model")
	queue.demand("needed");step(queue)
	check(queue.rows.needed.state=="running" and queue.snapshot().lane_admitted.texture==3,"actual demand may be a third same-lane result when global capacity permits")
	check(held1.get("value")=="t1" and held2.get("value")=="t2" and queue.rows.t1.state=="held" and queue.rows.t2.state=="held","share borrowing never steals held packet identities")
	check(queue.snapshot().preempted==0 and queue.ledger.count()==4 and queue.ledger.reserved_bytes==40,"idle demand borrowing neither discards results nor discounts their leases")
	await close_queue(queue)

func minimal_demand_retirement()->void:
	var queue:=make_queue();queue.enqueue("keep",packet.bind("keep"),estimate(10),"texture")
	await until_ready(queue,"keep");var keep:Dictionary=queue.rows.keep.packet
	var a:=gate();var b:=gate();var required:=gate()
	queue.enqueue("a",a.run.bind("a"),estimate(40),"model")
	queue.enqueue("b",b.run.bind("b"),estimate(40),"model")
	step(queue)
	queue.enqueue("needed",required.run.bind("needed"),estimate(80),"texture")
	queue.demand("needed");step(queue)
	check(queue.rows.needed.state=="pending" and queue.snapshot().preempted==0 and keep.get("value")=="keep","worker pressure never triggers futile ready destruction")
	a.leave.post();b.leave.post()
	var deadline:=Time.get_ticks_msec()+3000
	while queue.rows.needed.state!="running" and Time.get_ticks_msec()<deadline:step(queue);await process_frame
	check(queue.rows.needed.state=="running" and queue.rows.a.state=="pending" and queue.rows.b.state=="pending","byte-constrained demand retires exactly the two large joined results")
	check(keep.get("value")=="keep" and queue.snapshot().preempted==2 and queue.ledger.reserved_bytes==90,"minimum byte retirement preserves the useful smaller ready result")
	check(queue.snapshot().preempted_by_lane.get("model",0)==2 and queue.snapshot().preempted_worker_elapsed_us>0,"discarded work reports its lane and cumulative worker wall time")
	await close_queue(queue)

	# Equal-byte count pressure chooses the last-used ready packet, not held.
	queue=make_queue();queue.ready_limit=2
	for key:String in ["earlier","later"]:queue.enqueue(key,packet.bind(key),estimate(10),"model")
	await until_ready(queue,"earlier");await until_ready(queue,"later")
	var earlier:Dictionary=queue.rows.earlier.packet;var later:Dictionary=queue.rows.later.packet
	required=gate();queue.enqueue("needed",required.run.bind("needed"),estimate(10),"texture");queue.demand("needed");step(queue)
	check(earlier.get("value")=="earlier" and later.is_empty() and queue.snapshot().preempted==1,"global slot demand removes only the latest ready result")
	await close_queue(queue)

func exclusive_fences()->void:
	var queue:=make_queue();queue.enqueue("anchor",packet.bind("anchor"),estimate(20),"texture")
	await until_ready(queue,"anchor");var anchor:Dictionary=queue.acquire("anchor")
	var exclusive:=gate();var needed:=gate();var speculative:=gate()
	queue.enqueue("exclusive",exclusive.run.bind("exclusive"),estimate(200,true),"model")
	queue.enqueue("needed",needed.run.bind("needed"),estimate(10),"texture")
	queue.enqueue("speculative",speculative.run.bind("speculative"),estimate(10),"texture")
	step(queue)
	check(queue.rows.exclusive.state=="pending" and queue.rows.needed.state=="pending","speculative exclusive head stops replenishment while existing owners drain")
	queue.demand("needed");step(queue)
	check(queue.rows.needed.state=="running" and queue.rows.exclusive.state=="pending" and queue.rows.speculative.state=="pending","actual texture demand outranks a later speculative exclusive fence")
	check(anchor.get("value")=="anchor" and queue.ledger.reserved_bytes==30,"exclusive fence cannot destroy an earlier held owner")
	needed.leave.post();await until_ready(queue,"needed");queue.acquire("needed");queue.release("needed");queue.release("anchor");step(queue)
	check(queue.rows.exclusive.state=="running" and queue.ledger.count()==1 and queue.ledger.reserved_bytes==200,"drained oversized exclusive retains the pre-existing one-job admission exception")
	check(queue.rows.speculative.state=="pending","new ordinary work cannot coexist with an active exclusive")
	await close_queue(queue)

	queue=make_queue()
	queue.enqueue("held",packet.bind("held"),estimate(10),"texture")
	queue.enqueue("ready",packet.bind("ready"),estimate(10),"model")
	await until_ready(queue,"held");await until_ready(queue,"ready");queue.acquire("held")
	var ready_alias:Dictionary=queue.rows.ready.packet
	exclusive=gate();queue.enqueue("needed",exclusive.run.bind("needed"),estimate(200,true),"model");queue.demand("needed");step(queue)
	check(queue.rows.needed.state=="pending" and ready_alias.get("value")=="ready" and queue.snapshot().preempted==0,"held pressure makes exclusive ready eviction futile and therefore forbidden")
	queue.release("held");step(queue)
	check(queue.rows.needed.state=="running" and ready_alias.is_empty() and queue.snapshot().preempted==1,"exclusive demand retires remaining ready ownership only when it can proceed")
	await close_queue(queue)

func retry_cancel_and_ownership()->void:
	var queue:=make_queue();var observed:Array=[]
	queue.enqueue("native",owned_packet.bind(queue.ledger,observed),{"estimated_bytes":10,"exclusive":false,"stage":"compiled_read"},"model")
	await until_ready(queue,"native");var native:Dictionary=queue.acquire("native");var before:Array=queue.order.duplicate()
	var raw:=gate()
	check(queue.retry_as_raw("native",raw.run.bind("raw"),{"estimated_bytes":90,"exclusive":false}),"lane scheduler accepts the existing joined native-to-raw transition")
	check(queue.rows.native.lane=="model" and queue.order==before and queue.demand_key=="native","raw retry preserves its lane first-use position and real demand")
	check(native.is_empty() and observed.size()==1 and observed[0].main and observed[0].bytes==10 and queue.ledger.count()==0,"native ownership is destroyed on main before old lease return")
	step(queue);await until_entered(raw.entered)
	check(queue.rows.native.state=="running" and queue.ledger.reserved_bytes==90,"retry takes the full fresh raw envelope")
	var owner:RefCounted=queue.ledger;var drainer:=Drainer.for_tree(self);var drained:int=drainer.drained
	queue.free()
	check(owner.reserved_bytes==90 and owner.count()==1,"detached cancellation keeps the live raw lease")
	raw.leave.post();_gates.clear()
	var deadline:=Time.get_ticks_msec()+3000
	while drainer.drained==drained and Time.get_ticks_msec()<deadline:await process_frame
	check(drainer.drained>drained and owner.count()==0,"detached drainer joins and disposes before returning the raw budget")

	queue=make_queue();queue.thread_starter=func(_worker:Thread,_task:Callable)->int:return ERR_CANT_CREATE
	queue.enqueue("failed",packet.bind("must_not_run"),estimate(10),"model");step(queue)
	var failed:Dictionary=queue.acquire("failed")
	check(failed.get("start_failed",false) and not failed.has("value") and queue.ledger.reserved_bytes==10,"launch failure does not execute work on main and retains its lease")
	queue.release("failed")
	check(failed.is_empty() and queue.ledger.count()==0 and queue.snapshot().diagnostics.tasks.failed.first_start_us==0,"failed launch has no fabricated successful start timestamp")
	await close_queue(queue)

func bounded_diagnostics()->void:
	var queue:=make_queue();queue.enqueue("one",packet.bind("one"),estimate(10),"model")
	await until_ready(queue,"one");queue.acquire("one");queue.release("one")
	var stats:Dictionary=queue.snapshot();var timing:Dictionary=stats.diagnostics.tasks.one
	check(timing.enqueued_us<=timing.first_start_us and timing.first_start_us<=timing.last_join_us and timing.last_join_us<=timing.last_acquire_us and timing.last_acquire_us<=timing.last_release_us,"task lifecycle timestamps preserve enqueue dispatch join acquire release order")
	check(stats.first_start_us==timing.first_start_us and stats.first_start_by_lane.model==timing.first_start_us,"queue and lane first-start summaries refer to real successful dispatch")
	var kinds:Array=[]
	for item:Dictionary in queue.diagnostic_events():kinds.append(item.event)
	check(kinds==["enqueue","start","join","acquire","release"],"event history contains the real production ownership lifecycle")
	check(not stats.diagnostics.has("events"),"ordinary snapshots do not copy event history")
	await close_queue(queue)

	queue=make_queue()
	for i in 600:queue.enqueue("pending_%d"%i,packet.bind("unused"),estimate(1),"neutral")
	queue.cancel();stats=queue.snapshot()
	check(stats.diagnostics.tasks.size()==Queue.MAX_DIAGNOSTIC_TASKS and stats.diagnostics.tasks_dropped==600-Queue.MAX_DIAGNOSTIC_TASKS,"per-task diagnostic storage has a fixed cap and visible overflow")
	check(queue.diagnostic_events().size()==Queue.MAX_DIAGNOSTIC_EVENTS and stats.diagnostics.events_dropped==1200-Queue.MAX_DIAGNOSTIC_EVENTS,"event ring has a fixed cap and visible overwritten count")
	var last:=0;var ordered:=true
	for item:Dictionary in queue.diagnostic_events():
		ordered=ordered and item.time_us>=last;last=item.time_us
	check(ordered and queue.ledger.count()==0,"wrapped event history remains chronological without creating leases")
	await close_queue(queue)

	queue=make_queue();queue.diagnostics_enabled=false
	queue.enqueue("off",packet.bind("off"),estimate(1),"model");await until_ready(queue,"off");queue.release("off")
	check(queue.diagnostic_events().is_empty() and queue.snapshot().diagnostics=={"enabled":false},"diagnostics can be disabled without retaining task or event history")
	await close_queue(queue)

func run()->void:
	Engine.max_fps=240;create_timer(45).timeout.connect(func():quit(2))
	await fifo_and_cross_lane()
	await shares_and_idle_borrow()
	await demand_borrows_held_share()
	await minimal_demand_retirement()
	await exclusive_fences()
	await retry_cancel_and_ownership()
	await bounded_diagnostics()
	print("EDITOR_PREPARATION_LANES passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
