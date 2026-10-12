extends RefCounted
## Operation-local CPU warm hints. The hydration coordinator owns admission;
## persistent workers return only booleans, never canonical geometry aliases.
const House=preload("res://scripts/world3d/house_prefab.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const DefinitionPolicy=preload("res://scripts/world3d/definition_cache_policy.gd")
const DEFAULT_TOTAL_BYTES:=2*1024*1024*1024
const MAX_RAW_BYTES:=16777216
const MAX_ENCODED_CHARS:=24000000

class CancelToken extends RefCounted:
	var mutex:=Mutex.new()
	var stopped:=false
	func cancel()->void:
		mutex.lock();stopped=true;mutex.unlock()
	func is_cancelled()->bool:
		mutex.lock();var value:=stopped;mutex.unlock();return value

class Slot extends RefCounted:
	var thread:=Thread.new()
	var mutex:=Mutex.new()
	var wake:=Semaphore.new()
	var completed:Semaphore
	var token:RefCounted
	var body:Callable
	var value:Dictionary={}
	var output:Dictionary={}
	var stop:=false
	# Only the coordinator reads/writes the lease key.
	var key:=""
	func assign(next:Dictionary)->void:
		mutex.lock();value=next;mutex.unlock();wake.post()
	func take_output()->Dictionary:
		mutex.lock();var result:=output;output={};mutex.unlock();return result
	func request_stop()->void:
		mutex.lock();stop=true;mutex.unlock();wake.post()
	func run()->void:
		while true:
			wake.wait();mutex.lock()
			if stop:mutex.unlock();return
			var input:=value;value={};mutex.unlock()
			var began:=Time.get_ticks_usec();var cancelled:bool=token.is_cancelled()
			var decoded:bool=false if cancelled else bool(body.call(input))
			# Release the input alias before announcing completion/returning credit.
			input={}
			mutex.lock();output={"decoded":decoded,"cancelled":cancelled,"elapsed_us":Time.get_ticks_usec()-began};mutex.unlock()
			completed.post()

static func estimate(value:Dictionary)->Dictionary:
	# Conservative scheduling account, not measured RSS or source validation.
	# Raw bytes + expanded Variant containers, index-validation scratch, geometry
	# serialization/SHA and codec workspace. Unknown headers use the maximum;
	# House.warm still performs every eligibility/content check itself.
	var raw:=MAX_RAW_BYTES;var encoded:=MAX_ENCODED_CHARS
	var length:Variant=value.get("length")
	var known:bool=typeof(length) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(length)) and float(length)==floor(float(length)) and float(length)>0 and float(length)<=MAX_RAW_BYTES and value.get("data") is String and value.data.length()<=MAX_ENCODED_CHARS
	if known:raw=int(length);encoded=value.data.length()
	return {"estimated_bytes":raw*32+encoded*8+4*1024*1024,"exclusive":not known,"known":known,"stage":"prefab_warm"}

static func prepare(records:Array,options:Dictionary={},cancel:RefCounted=null,warmer:Callable=Callable(),thread_starter:Callable=Callable())->Dictionary:
	# Called after hydrate_references() has joined all resource readers. A sliced
	# cursor runs this coordinator off main; a 1-worker control stays inline in
	# that same coordinator, matching the old serial warm-up without child threads.
	var began:=Time.get_ticks_usec();var token:RefCounted=cancel if cancel!=null else CancelToken.new()
	var workers:=clampi(int(options.get("workers",1)),1,2)
	var retained:=House.DECODE_BUDGET+DefinitionPolicy.reserved_bytes()
	var total_bytes:=maxi(retained+1,int(options.get("total_budget_bytes",DEFAULT_TOTAL_BYTES)))
	var ledger:=Admission.new();ledger.worker_limit=workers;ledger.byte_limit=total_bytes-retained
	var stats:={"unique":0,"decoded":0,"attempted":0,"completed":0,"cancelled":false,"configured_workers":workers,"worker_limit":workers,"threads_started":0,"threads_joined":0,"start_failures":0,"worker_elapsed_us":0,"elapsed_ms":0.,"total_budget_bytes":total_bytes,"decode_cache_capacity_reserved_bytes":House.DECODE_BUDGET,"definition_cache_capacity_reserved_bytes":DefinitionPolicy.reserved_bytes(),"workspace_budget_bytes":ledger.byte_limit,"budget_scope":"workspace admission plus existing process cache capacities; excludes authored document residency; estimates, not RSS; oversized jobs use the existing exclusive admission rule","blocked":{}}
	var seen:Dictionary={};var jobs:Array=[]
	for record:Dictionary in records:
		var value:Variant=record.get("house_prefab")
		if not value is Dictionary or not value.get("sha256") is String or seen.has(value.sha256):continue
		seen[value.sha256]=true;jobs.append({"key":str(jobs.size()),"value":value,"estimate":estimate(value)})
	stats.unique=jobs.size()
	var body:Callable=warmer if warmer.is_valid() else House.warm
	var slots:Array=[];var completion:=Semaphore.new()
	if workers>1 and not token.is_cancelled() and not jobs.is_empty():
		for i in mini(workers,jobs.size()):
			var slot:=Slot.new();slot.completed=completion;slot.token=token;slot.body=body
			var status:int=thread_starter.call(slot.thread,slot.run) if thread_starter.is_valid() else slot.thread.start(slot.run,Thread.PRIORITY_LOW)
			if status==OK:slots.append(slot);stats.threads_started+=1
			else:stats.start_failures+=1
	ledger.worker_limit=maxi(1,slots.size()) if workers>1 else 1
	stats.worker_limit=ledger.worker_limit
	if slots.is_empty():
		for job:Dictionary in jobs:
			if token.is_cancelled():break
			if not ledger.reserve(job.key,job.estimate):break
			stats.attempted+=1
			var started:=Time.get_ticks_usec();var decoded:bool=bool(body.call(job.value))
			stats.worker_elapsed_us+=Time.get_ticks_usec()-started
			if decoded:stats.decoded+=1
			stats.completed+=1;ledger.release(job.key)
	else:
		var next:=0;var active:=0
		while next<jobs.size() or active>0:
			for slot:Slot in slots:
				if slot.key.is_empty():continue
				var result:=slot.take_output()
				if result.is_empty():continue
				stats.worker_elapsed_us+=int(result.elapsed_us);stats.completed+=1
				if result.decoded:stats.decoded+=1
				# The boolean result is consumed and the worker already discarded all
				# task aliases. No retained output lease or parked work remains.
				ledger.release(slot.key);slot.key="";active-=1
			if token.is_cancelled():next=jobs.size()
			for slot:Slot in slots:
				if not slot.key.is_empty() or next>=jobs.size():continue
				var job:Dictionary=jobs[next];var reason:=ledger.blocking_reason(job.key,job.estimate)
				if not reason.is_empty():stats.blocked[reason]=int(stats.blocked.get(reason,0))+1;break
				if not ledger.reserve(job.key,job.estimate):break
				slot.key=job.key;stats.attempted+=1;active+=1;next+=1;slot.assign(job.value)
			if active>0:completion.wait()
		for slot:Slot in slots:slot.request_stop()
		for slot:Slot in slots:slot.thread.wait_to_finish();stats.threads_joined+=1
	stats.cancelled=token.is_cancelled();stats.ledger=ledger.snapshot()
	stats.elapsed_ms=(Time.get_ticks_usec()-began)/1000.
	return stats
