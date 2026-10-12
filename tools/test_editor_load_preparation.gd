extends SceneTree
const Queue=preload("res://scripts/world_editor/load_preparation_queue.gd")
const Job=preload("res://scripts/world_editor/load_job.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var passed:=0
var failures:=0

class LeaseProbe extends RefCounted:
	var ledger:RefCounted
	var observations:Array
	func _init(owner:RefCounted,observed:Array)->void:
		ledger=owner;observations=observed
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			observations.append({"reserved_bytes":ledger.reserved_bytes,"main_thread":OS.get_thread_caller_id()==OS.get_main_thread_id()})

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	if value:passed+=1;print("PASS ",label)
	else:failures+=1;push_error("FAIL "+label)
static func packet(value:String,wait_msec:int=0)->Dictionary:
	OS.delay_msec(wait_msec)
	return {"error":OK,"value":value}
static func gated_packet(value:String,gate:Semaphore)->Dictionary:
	gate.wait()
	return {"error":OK,"value":value}
static func owned_native_packet(ledger:RefCounted,observations:Array)->Dictionary:
	return {"error":OK,"value":"native","retained_resources":[LeaseProbe.new(ledger,observations)]}
static func hold_raw_lock(entered:Semaphore,release_:Semaphore)->Dictionary:
	Job.ModelPreparation.RAW_IMPORT_MUTEX.lock();entered.post();release_.wait();Job.ModelPreparation.RAW_IMPORT_MUTEX.unlock()
	return {}
func collect_asset(job:Node,record:Dictionary,bucket:Dictionary)->void:
	bucket.result=await job._prepare_asset(record)
func until_ready(queue:Node,key:String)->void:
	var deadline:=Time.get_ticks_msec()+3000
	while not queue.is_ready(key) and Time.get_ticks_msec()<deadline:await process_frame
	check(queue.is_ready(key),"bounded completion: "+key)
func make_queue(bytes:int=100,workers:int=2,retained:int=4)->Node:
	var queue:=Queue.new();queue.byte_limit=bytes;queue.worker_limit=workers;queue.ready_limit=retained;root.add_child(queue);return queue

func native_result_cases()->void:
	# Empty PackedScenes exercise real Resource ownership/type checks without
	# creating meshes, textures, renderer objects or an imported scene.
	var packed:=PackedScene.new()
	var candidate:Dictionary={"source_sha":"a".repeat(64)}
	var fallback:Dictionary={"error":OK,"fallback_required":true,"cache_reason":"candidate_checksum","elapsed_us":1}
	check(Job._native_result_action(candidate,fallback)=="retry","resource-free fixed-native miss requests separate raw admission")
	for patch:Dictionary in [{"packed":packed},{"fallback_required":1},{"fallback_required":false},{"error":ERR_BUSY},{"cache_reason":1},{"scene":null},{"unknown_owner":packed},{"retained_resources":[]}]:
		var malformed:Dictionary=fallback.duplicate();malformed.merge(patch,true)
		check(Job._native_result_action(candidate,malformed)=="reject","fallback rejects invalid control or ownership field: "+str(patch.keys()[0]))
	var retry:Dictionary={"error":ERR_BUSY,"packed":packed,"compiled":true,"source_digest":candidate.source_sha,"compiled_payload_bytes":1,"native_source_retry":true,"cache_reason":"candidate_source_changed_after_read","elapsed_us":1}
	check(Job._native_result_action(candidate,retry)=="retry","typed source replacement retains its exact native identity before raw retry")
	for patch:Dictionary in [{"source_digest":"b".repeat(64)},{"native_source_retry":1},{"native_source_retry":false},{"error":ERR_INVALID_DATA},{"error":OK},{"compiled":1},{"compiled":false},{"packed":null},{"cache_reason":"other"},{"scene":null},{"private_preparation":{}},{"fallback_required":true},{"unknown_owner":packed},{"retained_resources":{}}]:
		var malformed:Dictionary=retry.duplicate();malformed.merge(patch,true)
		check(Job._native_result_action(candidate,malformed)=="reject","source retry rejects invalid identity, control or ownership field: "+str(patch.keys()[0]))
	check(Job._native_result_action({"source_sha":"invalid"},retry)=="reject","source retry rejects malformed candidate SHA")
	var success:Dictionary={"error":OK,"packed":packed,"compiled":true,"source_digest":candidate.source_sha}
	check(Job._native_result_action(candidate,success)=="ready","successful fixed-native result requires a PackedScene and matching verified source")
	for patch:Dictionary in [{"source_digest":"b".repeat(64)},{"compiled":false},{"packed":null},{"error":"0"}]:
		var malformed:Dictionary=success.duplicate();malformed.merge(patch,true)
		check(Job._native_result_action(candidate,malformed)=="reject","successful native result rejects invalid publication identity: "+str(patch.keys()[0]))
	check(Job._native_result_action(candidate,{"error":ERR_CANT_CREATE,"packed":packed})=="error","unmarked resource-bearing errors remain failures instead of retrying raw")
	check(retry.packed==packed and fallback.fallback_required and success.packed==packed,"native result classification never disposes or mutates its borrowed packets")

func native_retry_cases()->void:
	# These packets are private CPU stand-ins. Scheduling, joins, ownership,
	# admission, preemption and detached cancellation use the production queue.
	var native_estimate:Dictionary={"estimated_bytes":10,"exclusive":false,"stage":"compiled_read"}
	var queue:=make_queue()
	var observations:Array=[]
	queue.enqueue("native",owned_native_packet.bind(queue.ledger,observations),native_estimate)
	await until_ready(queue,"native")
	var native:Dictionary=queue.acquire("native")
	var original_order:Array=queue.order.duplicate()
	check(not queue.retry_as_raw("absent",packet.bind("raw"),{"estimated_bytes":90,"exclusive":false}),"retry rejects an unknown preparation key")
	check(not queue.retry_as_raw("native",packet.bind("raw"),{"estimated_bytes":0,"exclusive":false}),"invalid raw estimate cannot retire a native result")
	check(not queue.retry_as_raw("native",Callable(),{"estimated_bytes":90,"exclusive":false}),"invalid raw callable cannot retire a native result")
	check(not queue.retry_as_raw("native",packet.bind("raw"),{"estimated_bytes":90,"exclusive":false,"cpu_only":true}),"raw retry rejects a CPU-only disposal policy")
	check(native.get("value")=="native" and queue.rows.native.state=="held" and queue.ledger.reserved_bytes==10,"rejected retry preserves native aliases, state and lease")
	var gate:=Semaphore.new()
	check(queue.retry_as_raw("native",gated_packet.bind("raw",gate),{"estimated_bytes":90,"exclusive":false,"stage":"compiled_read"}),"joined held native result accepts separately admitted raw retry")
	check(native.is_empty() and queue.ledger.reserved_bytes==0 and queue.ledger.count()==0,"retry clears the consumer packet alias before returning native byte credit")
	check(observations.size()==1 and observations[0].main_thread and observations[0].reserved_bytes==10,"native ownership is destroyed on main while the original byte lease is still charged")
	check(queue.order==original_order and queue.rows.native.state=="pending" and queue.demand_key=="native","held retry preserves first-use position and restores its demand")
	check(queue.rows.native.estimate.estimated_bytes==90 and queue.rows.native.estimate.stage=="raw_import" and not queue.rows.native.estimate.get("cpu_only",false),"raw retry replaces the native estimate and cannot retain a compiled or CPU-only stage")
	queue.pump()
	check(queue.rows.native.state=="running" and queue.ledger.reserved_bytes==90,"raw worker starts only after acquiring its full fresh reservation")
	check(not queue.retry_as_raw("native",packet.bind("second_raw"),{"estimated_bytes":1,"exclusive":false}) and queue.ledger.reserved_bytes==90,"running raw work cannot re-enter retry or discount its reservation")
	gate.post();await until_ready(queue,"native")
	check(not queue.retry_as_raw("native",packet.bind("second_raw"),{"estimated_bytes":1,"exclusive":false}),"joined raw result cannot retry raw a second time")
	var raw:Dictionary=queue.acquire("native")
	check(raw.get("value")=="raw" and queue.ledger.reserved_bytes==90 and queue.snapshot().raw_retries==1,"raw completion stays charged through acquire and counts one stage transition")
	queue.release("native")
	check(raw.is_empty() and queue.ledger.count()==0,"raw publication clears its packet and returns the full retry lease")
	queue.free()

	queue=make_queue(100,4,4)
	queue.enqueue("native",packet.bind("native"),native_estimate)
	for key:String in ["later_a","later_b","later_c"]:queue.enqueue(key,packet.bind(key),{"estimated_bytes":10,"exclusive":false})
	for key:String in ["native","later_a","later_b","later_c"]:await until_ready(queue,key)
	check(queue.ledger.count()==4,"native retry fixture fills the complete ready window")
	var later_alias:Dictionary=queue.rows.later_a.packet
	native=queue.acquire("native")
	check(queue.retry_as_raw("native",packet.bind("exclusive_raw"),{"estimated_bytes":200,"exclusive":true}),"oversized raw retry retires its held native packet before exclusive admission")
	await until_ready(queue,"native")
	check(native.is_empty() and later_alias.is_empty() and queue.snapshot().preempted==3,"exclusive raw demand safely retires all joined lookahead aliases")
	check(queue.ledger.reserved_bytes==200 and queue.ledger.count()==1 and queue.rows.native.estimate.stage=="raw_import","exclusive retry owns its complete raw envelope without native or lookahead credits")
	queue.release("native")
	for key:String in ["later_a","later_b","later_c"]:
		await until_ready(queue,key);queue.release(key)
	check(queue.ledger.count()==0 and queue.snapshot().raw_retries==1,"preempted lookahead resumes after exclusive raw consumption without duplicate retry")
	queue.free()

	queue=make_queue();queue.enqueue("ready_native",packet.bind("native"),native_estimate)
	await until_ready(queue,"ready_native");queue.demand("ready_native")
	native=queue.rows.ready_native.packet
	check(queue.retry_as_raw("ready_native",packet.bind("never_started"),{"estimated_bytes":80,"exclusive":false}),"joined unacquired native result may transition to raw")
	check(native.is_empty() and queue.demand_key=="ready_native" and queue.ledger.count()==0,"ready retry retains existing demand and returns only the disposed native lease")
	queue.cancel()
	check(queue.ledger.count()==0 and queue.rows.ready_native.state=="cancelled" and not queue.retry_as_raw("ready_native",packet.bind("late"),{"estimated_bytes":80,"exclusive":false}),"cancellation between stages prevents raw dispatch and further retries")
	queue.free()

	# Keep each worker blocked deterministically while removing its owning Node.
	# The main thread never waits for that worker; the retained drainer ledger
	# must outlive the queue until the semaphore permits worker completion.
	for raw_stage:bool in [false,true]:
		queue=make_queue();gate=Semaphore.new()
		queue.enqueue("cancel_stage",packet.bind("native") if raw_stage else gated_packet.bind("native",gate),native_estimate)
		if raw_stage:
			await until_ready(queue,"cancel_stage");queue.acquire("cancel_stage")
			check(queue.retry_as_raw("cancel_stage",gated_packet.bind("raw",gate),{"estimated_bytes":90,"exclusive":false}),"raw cancellation fixture transitions through real native ownership")
		queue.pump()
		var charge:int=90 if raw_stage else 10
		check(queue.rows.cancel_stage.state=="running" and queue.ledger.reserved_bytes==charge,"cancellation fixture keeps its active stage charged")
		check(not queue.retry_as_raw("cancel_stage",packet.bind("illegal"),{"estimated_bytes":1,"exclusive":false}) and queue.ledger.reserved_bytes==charge,"running stage cannot be retired or re-admitted before join")
		var ledger:RefCounted=queue.ledger;var drainer:Node=Drainer.for_tree(self);var before:int=drainer.drained
		var began:=Time.get_ticks_usec();queue.free()
		check(Time.get_ticks_usec()-began<50000 and ledger.reserved_bytes==charge,"stage cancellation remains nonblocking and keeps its detached lease")
		gate.post()
		var deadline:=Time.get_ticks_msec()+3000
		while drainer.drained==before and Time.get_ticks_msec()<deadline:await process_frame
		check(drainer.drained>before and ledger.count()==0,"drainer joins and disposes the cancelled stage before returning its lease")

	queue=make_queue();queue.enqueue("start_failure",packet.bind("native"),native_estimate)
	await until_ready(queue,"start_failure");native=queue.acquire("start_failure")
	check(queue.retry_as_raw("start_failure",packet.bind("must_not_run"),{"estimated_bytes":200,"exclusive":true}),"raw start-failure fixture replaces the native reservation")
	queue.thread_starter=func(_worker:Thread,_task:Callable)->int:return ERR_CANT_CREATE
	queue.pump();var failed:Dictionary=queue.acquire("start_failure")
	check(native.is_empty() and failed.get("start_failed",false) and not failed.has("value"),"failed raw launch never executes heavyweight fallback on main")
	check(queue.ledger.reserved_bytes==200 and queue.ledger.active_workers()==0,"failed raw launch retains its complete parked lease until disposal")
	queue.release("start_failure")
	check(failed.is_empty() and queue.ledger.count()==0 and queue.snapshot().raw_retries==1,"failed raw launch clears aliases and releases the new envelope exactly once")
	queue.free()

func native_job_retry_case()->void:
	# An absent source exercises both real readers without GLTF import, native
	# scene construction or GPU work. The LoadJob consumer owns the transition.
	var filename:=Paths.cache_directory("editor_native_retry_cpu_%d"%Time.get_ticks_usec()).path_join("missing.glb")
	check(not FileAccess.file_exists(filename),"native LoadJob fixture begins with an absent source")
	var job:=Job.new();root.add_child(job);job._timings.build={"units":{}};job._begin_asset_lookahead([])
	var queue:Node=job._preparation;var key:="model:"+filename
	queue.enqueue(key,Job._parse_native_asset.bind(filename,Paths.external_root(),{}),{"estimated_bytes":10,"exclusive":false,"stage":"compiled_read"})
	var prepared:Dictionary=await job._prepare_asset({"kind":"asset","uuid":"missing_native_model","asset_path":filename})
	check(prepared.has("scene") and prepared.scene==null and not prepared.get("cancelled",false),"real native miss and raw missing-source error return a missing scene without GPU work")
	check(queue.snapshot().raw_retries==1 and job._timings.asset_lookahead.native_retries==1,"LoadJob itself performs exactly one native-to-raw transition")
	check(queue.rows[key].estimate.estimated_bytes==Job.MemoryEstimate.UNKNOWN_BYTES and queue.rows[key].estimate.exclusive and queue.rows[key].estimate.stage=="raw_import","LoadJob re-estimates the source and separately admits the complete unknown raw envelope")
	check(queue.rows[key].state=="done" and queue.ledger.count()==0 and queue.ledger.reserved_bytes==0,"LoadJob consumes and releases its raw failure without retaining either stage lease")
	check(job._timings.asset_lookahead.native_retry_reasons.get("candidate_disabled",0)==1,"LoadJob preserves the fixed-reader miss reason through fallback")
	check(not FileAccess.file_exists(filename),"two-stage preparation never creates or rewrites the missing source")
	job.free()

func run()->void:
	Engine.max_fps=240
	create_timer(30).timeout.connect(func():quit(2))
	var queue:=make_queue()
	check(not queue.enqueue("bad",packet.bind("bad"),{"estimated_bytes":0,"exclusive":false}),"invalid estimates rejected before dispatch")
	for key:String in ["a","b","c"]:queue.enqueue(key,packet.bind(key,40),{"estimated_bytes":40,"exclusive":false})
	check(not queue.enqueue("a",packet.bind("duplicate"),{"estimated_bytes":1,"exclusive":false}),"one task per immutable key")
	queue.pump();check(queue.ledger.peak_workers==2 and queue.ledger.reserved_bytes==80,"independent preparations overlap under one memory ledger")
	await until_ready(queue,"a");await until_ready(queue,"b")
	check(queue.rows.c.state=="pending" and queue.ledger.reserved_bytes==80,"joined but unconsumed output still blocks over-budget lookahead")
	var first:Dictionary=queue.acquire("a")
	check(first.value=="a" and queue.ledger.reserved_bytes==80,"acquiring a packet does not release its retained ownership")
	queue.release("a")
	check(first.is_empty() and queue.ledger.reserved_bytes==40,"release clears caller alias before returning byte credit")
	queue.release("b");await until_ready(queue,"c");queue.release("c")
	check(queue.ledger.count()==0 and queue.snapshot().consumed==3,"all consumed tasks return their leases")
	queue.free()

	queue=make_queue(100,2,2)
	for key:String in ["one","two","three"]:queue.enqueue(key,packet.bind(key,15),{"estimated_bytes":1,"exclusive":false})
	queue.pump();await until_ready(queue,"one");await until_ready(queue,"two")
	check(queue.rows.three.state=="pending" and queue.snapshot().peak_unconsumed==2,"ready-window cap applies even when bytes are plentiful")
	queue.free()

	queue=make_queue()
	queue.enqueue("later_a",packet.bind("later_a",15),{"estimated_bytes":30,"exclusive":false})
	queue.enqueue("later_b",packet.bind("later_b",15),{"estimated_bytes":30,"exclusive":false})
	queue.pump();await until_ready(queue,"later_a");await until_ready(queue,"later_b")
	queue.enqueue("repair",packet.bind("repair",10),{"estimated_bytes":200,"exclusive":true});queue.demand("repair")
	await until_ready(queue,"repair")
	check(queue.snapshot().preempted==2 and queue.ledger.count()==1,"new exclusive demand retires joined lookahead instead of deadlocking")
	queue.release("repair");await until_ready(queue,"later_a");queue.release("later_a");await until_ready(queue,"later_b");queue.release("later_b")
	check(queue.ledger.count()==0,"preempted work can be re-prepared without losing order or credit")
	queue.free()

	queue=make_queue(100,4,4)
	for key:String in ["slot_a","slot_b","slot_c","slot_d"]:queue.enqueue(key,packet.bind(key,10),{"estimated_bytes":1,"exclusive":false})
	for key:String in ["slot_a","slot_b","slot_c","slot_d"]:await until_ready(queue,key)
	check(queue.ledger.count()==4 and queue.ledger.reserved_bytes==4,"ready slots can fill before exhausting the byte limit")
	queue.enqueue("slot_repair",packet.bind("slot_repair"),{"estimated_bytes":1,"exclusive":false});queue.demand("slot_repair")
	await until_ready(queue,"slot_repair")
	check(queue.snapshot().preempted>=1 and queue.ledger.count()<=4,"required texture repair preempts a ready slot even when bytes are sufficient")
	queue.free()

	queue=make_queue();queue.thread_starter=func(_worker:Thread,_task:Callable)->int:return ERR_CANT_CREATE
	queue.enqueue("failure",packet.bind("must_not_run"),{"estimated_bytes":1,"exclusive":false});queue.pump()
	var failed:Dictionary=queue.acquire("failure")
	check(failed.get("start_failed",false) and not failed.has("value"),"thread failure never performs heavyweight work on main")
	queue.release("failure");check(queue.ledger.count()==0,"failed start keeps and releases normal result ownership")
	queue.free()

	queue=make_queue();var ledger:RefCounted=queue.ledger
	queue.enqueue("cancel",packet.bind("unpublished",100),{"estimated_bytes":90,"exclusive":false});queue.pump()
	var drainer:Node=Drainer.for_tree(self);var before:int=drainer.drained
	var began:=Time.get_ticks_usec();queue.free()
	check(Time.get_ticks_usec()-began<50000 and ledger.reserved_bytes==90,"owner exit is nonblocking and leaves live worker credit charged")
	var deadline:=Time.get_ticks_msec()+3000
	while drainer.drained==before and Time.get_ticks_msec()<deadline:await process_frame
	check(drainer.drained>before and ledger.count()==0,"tree-owned drainer joins then releases abandoned result and lease")

	queue=make_queue();queue.enqueue("budget",packet.bind("budget"),{"estimated_bytes":1,"exclusive":false})
	Budget.enabled=true;Budget.shared().record(Engine.get_process_frames(),"publication",7000);queue.pump()
	check(queue.rows.budget.state=="pending","spent frame budget postpones dispatch without changing readiness")
	queue.cancel();check(queue.cancelled and queue.ledger.count()==0,"budget denial cannot prevent cancellation")
	Budget.enabled=false;queue.free()
	native_result_cases()
	await native_retry_cases()
	await native_job_retry_case()

	var directory:=Paths.cache_directory("editor_preparation_cpu_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var filename:=directory.path_join("normal.png")
	var pixels:=Image.create(2,2,false,Image.FORMAT_RGBA8);pixels.fill(Color(.2,.25,1.));pixels.save_png(filename)
	var records:Array=[{"uuid":"terrain_a","terrain_mesh":{},"terrain_material":{"normal_path":filename,"normal_format":"directx"}},
		{"uuid":"terrain_b","terrain_mesh":{},"terrain_material":{"normal_path":filename,"normal_format":"directx"}}]
	var original:Array=records.duplicate(true)
	var job:=Job.new();root.add_child(job);job._timings.build={"units":{}}
	job._begin_asset_lookahead(records)
	check(job._preparation.order.size()==1 and job._texture_tasks.size()==1,"texture lookahead deduplicates repeated authored references")
	var prepared:Dictionary=await job._prepare_record_textures(records[0])
	var key:String=filename+"|flip_y"
	check(prepared.failed.is_empty() and prepared.images.has(key) and absf(prepared.images[key].get_pixel(0,0).g-.75)<.01,"bounded CPU preparation retains normal orientation and source pixels")
	check(prepared.images[key].get_meta("runtime_source_sha256")==FileAccess.get_sha256(filename),"prefetched image carries source SHA proof")
	job._preparation.release(prepared.queue_key)
	# Deliberately do not install an ImageTexture: equivalent to an LRU miss,
	# and keeps this fixture independent of GPU/RenderingServer textures.
	var repaired:Dictionary=await job._prepare_record_textures(records[1])
	check(repaired.images.has(key) and job._texture_retry==1,"a later cache miss is explicitly re-admitted instead of losing a texture")
	job._preparation.release(repaired.queue_key)
	check(records==original and not job.state().capabilities.metadata_ready and not job.state().capabilities.query_ready,"preparation never changes document records or grants editor capabilities")
	job.free()
	check(FileAccess.file_exists(filename),"derived preparation never rewrites or deletes source images")

	# Removing (not freeing) the loader lets suspended functions resume. Hold the
	# raw importer on another thread so cancellation happens after acquire but
	# before main-thread generate, where the queue clears the aliased packet.
	job=Job.new();root.add_child(job);job._timings.build={"units":{}};job._begin_asset_lookahead([])
	job._preparation.enqueue("model:"+filename,packet.bind("raw"),{"estimated_bytes":1,"exclusive":false,"cpu_only":true})
	await until_ready(job._preparation,"model:"+filename)
	var entered:=Semaphore.new();var release_:=Semaphore.new();var lock_worker:=Thread.new()
	lock_worker.start(hold_raw_lock.bind(entered,release_));entered.wait()
	var bucket:Dictionary={};collect_asset(job,{"kind":"asset","uuid":"cancelled","asset_path":filename},bucket)
	check(job._preparation.rows["model:"+filename].state=="held","raw generation can await its mutex after acquiring a charged packet")
	root.remove_child(job);release_.post()
	while lock_worker.is_alive():await process_frame
	lock_worker.wait_to_finish()
	for frame in 3:await process_frame
	check(bucket.get("result",{}).get("cancelled",false),"removed loader terminates suspended publication before touching a cleared packet")
	var unlocked:bool=Job.ModelPreparation.RAW_IMPORT_MUTEX.try_lock()
	check(unlocked,"cancellation does not leak the shared raw import mutex")
	if unlocked:Job.ModelPreparation.RAW_IMPORT_MUTEX.unlock()
	job.free()
	print("EDITOR_LOAD_PREPARATION passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
