extends RefCounted
## Capacity stays charged until a completed result is consumed or discarded.
## Single scheduler owner only; loading coordinators may own a separate ledger.
## Workers never mutate it. Stage labels are diagnostic and never release bytes.
var worker_limit:=2
var byte_limit:=4*1024*1024*1024
var reserved_bytes:=0
var peak_bytes:=0
var peak_jobs:=0
var peak_workers:=0
var _entries:Dictionary={}

func active_workers()->int:
	var count_:=0
	for entry:Dictionary in _entries.values():
		if entry.get("occupies_worker",true):count_+=int(entry.get("worker_slots",1))
	return count_

func has_capacity()->bool:
	if active_workers()>=worker_limit or reserved_bytes>=byte_limit:
		_preempt_background();return false
	for entry:Dictionary in _entries.values():
		if entry.exclusive:return false
	return true

func requires_exclusive(estimate:Dictionary)->bool:
	return bool(estimate.get("exclusive",true)) or maxi(1,int(estimate.get("estimated_bytes",byte_limit)))>byte_limit

func blocking_reason(key:String,estimate:Dictionary)->String:
	if _entries.has(key):return "already_reserved"
	if worker_limit<=0:return "disabled"
	var size:=maxi(1,int(estimate.get("estimated_bytes",byte_limit)))
	var exclusive:=requires_exclusive(estimate)
	# Report the drain requirement before generic capacity; it explains why an
	# empty sibling slot cannot safely be filled by a lower-priority request.
	if exclusive and not _entries.is_empty():
		_preempt_background();return "exclusive_drain"
	for entry:Dictionary in _entries.values():
		if entry.exclusive:return "active_exclusive"
	if active_workers()>=worker_limit:
		_preempt_background();return "worker_limit"
	if not exclusive and reserved_bytes+size>byte_limit:
		_preempt_background();return "byte_limit"
	return ""

func can_admit(key:String,estimate:Dictionary)->bool:
	return blocking_reason(key,estimate).is_empty()

func reserve(key:String,estimate:Dictionary)->bool:
	if not can_admit(key,estimate):return false
	var size:=maxi(1,int(estimate.get("estimated_bytes",byte_limit)))
	_entries[key]={"bytes":size,"exclusive":requires_exclusive(estimate),"stage":str(estimate.get("stage","preparing")),"occupies_worker":true}
	reserved_bytes+=size;peak_bytes=maxi(peak_bytes,reserved_bytes);peak_jobs=maxi(peak_jobs,_entries.size())
	peak_workers=maxi(peak_workers,active_workers())
	return true

func reserve_bundle(key:String,estimate:Dictionary,retained:Dictionary)->bool:
	# One main-thread transaction: a job's temporary workspace plus NEW unique
	# shared outputs. Existing outputs must already belong to another live lease.
	var combined:Dictionary=estimate.duplicate();var output_bytes:=0
	for output:String in retained:
		if output==key or _entries.has(output) or not retained[output] is int or retained[output]<=0:return false
		output_bytes+=int(retained[output])
	combined.estimated_bytes=maxi(1,int(estimate.get("estimated_bytes",byte_limit)))+output_bytes
	if not can_admit(key,combined):return false
	_entries[key]={"bytes":maxi(1,int(estimate.get("estimated_bytes",byte_limit))),"exclusive":requires_exclusive(combined),"stage":str(estimate.get("stage","preparing")),"occupies_worker":true}
	for output:String in retained:_entries[output]={"bytes":int(retained[output]),"exclusive":false,"stage":"shared_pixels","occupies_worker":false}
	reserved_bytes+=int(combined.estimated_bytes);peak_bytes=maxi(peak_bytes,reserved_bytes);peak_jobs=maxi(peak_jobs,_entries.size());peak_workers=maxi(peak_workers,active_workers())
	return true

func shrink_joined(key:String,retained_bytes:int)->bool:
	# Explicit caller proof: the worker is joined, its workspace aliases are gone,
	# and the remaining CPU result is covered by this retained bound. GPU/raw jobs
	# continue using park() alone; this API must never infer that a worker is done.
	if not _entries.has(key) or _entries[key].get("occupies_worker",true):return false
	var remaining:=maxi(1,retained_bytes)
	if remaining>int(_entries[key].bytes):return false
	reserved_bytes-=int(_entries[key].bytes)-remaining;_entries[key].bytes=remaining
	return true

func resume_worker(key:String)->bool:
	# No new allocation: a parked CPU continuation keeps its final-proof scratch
	# reserved, so a full ready queue cannot steal the bytes it needs to finish.
	if not _entries.has(key) or _entries[key].get("occupies_worker",true) or worker_limit<=0 or active_workers()>=worker_limit:return false
	for other:String in _entries:
		if other!=key and _entries[other].exclusive:return false
	_entries[key].occupies_worker=true;_entries[key].stage="pixel_continuation";peak_workers=maxi(peak_workers,active_workers());return true

func park(key:String)->bool:
	# The scheduler calls this only after joining a worker. Retained output still
	# owns all of its bytes and any exclusive lease until consume/discard.
	if not _entries.has(key):return false
	_entries[key].occupies_worker=false
	return true

func release(key:String)->void:
	if not _entries.has(key):return
	reserved_bytes-=int(_entries[key].bytes);_entries.erase(key)

func count()->int:return _entries.size()

func set_stage(key:String,stage:String)->bool:
	if not _entries.has(key):return false
	_entries[key].stage=stage
	return true

func snapshot()->Dictionary:
	var stages:Dictionary={};var exclusive:Array[String]=[]
	for key:String in _entries:
		var entry:Dictionary=_entries[key];var stage:String=entry.stage
		if not stages.has(stage):stages[stage]={"jobs":0,"reserved_bytes":0}
		stages[stage].jobs+=1;stages[stage].reserved_bytes+=int(entry.bytes)
		if entry.exclusive:exclusive.append(key)
	return {"jobs":_entries.size(),"worker_limit":worker_limit,"reserved_bytes":reserved_bytes,"byte_limit":byte_limit,
		"active_workers":active_workers(),"peak_workers":peak_workers,"peak_jobs":peak_jobs,"peak_bytes":peak_bytes,"stages":stages,"exclusive_keys":exclusive}

func inspect(key:String,estimate:Dictionary)->Dictionary:
	# Explicitly sampled, not allocated by every can_admit/reserve polling call.
	var result:=snapshot();result.reason=blocking_reason(key,estimate);result.allowed=result.reason.is_empty()
	result.requested_bytes=maxi(1,int(estimate.get("estimated_bytes",byte_limit)))
	result.requested_exclusive=requires_exclusive(estimate)
	return result

func reserve_background(key:String,size:int,cancel:Callable,worker_slots:int=1)->bool:
	if worker_slots<1 or active_workers()+worker_slots>worker_limit:return false
	# Speculation may use spare capacity only. Foreground reserve() retains its
	# exclusive oversize/preemption policy; a denied upgrade must not cancel
	# another useful speculative result (e.g. its own completed CPU target).
	if size<=0 or size>byte_limit or reserved_bytes+size>byte_limit:return false
	if not cancel.is_valid() or not reserve(key,{"estimated_bytes":size,"exclusive":false,"stage":"speculative_cpu"}):return false
	_entries[key].preempt=cancel
	_entries[key].worker_slots=worker_slots;peak_workers=maxi(peak_workers,active_workers())
	return true
func _preempt_background()->void:
	# Cancellation only requests retirement. The same byte lease remains held
	# until its worker joins and the owner/drainer discards the actual output.
	for entry:Dictionary in _entries.values():
		if entry.has("preempt"):
			var callback:Callable=entry.preempt
			if callback.is_valid():callback.call()
