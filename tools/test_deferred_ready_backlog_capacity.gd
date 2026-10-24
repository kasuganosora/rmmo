extends "res://tools/test_deferred_backpressure.gd"
## Characterise independent execution/byte admission versus complete-result cap.
## Real production dispatch + tiny CPU results; no model, texture or map reads.
## This test deliberately keeps the production ready cap intact for the A/B.
func backlog_fixture(ready:int=6,bytes:int=200,limit:int=6,exclusive:bool=false)->Dictionary:
	var rows:Array=[]
	for i:int in ready:rows.append(item("ready%d"%i,float(i),10))
	for i:int in 8:rows.append(item("next%d"%i,float(ready+i),10))
	var f:=fixture(rows);var queue:Queue=f.queue
	queue.paused=true;queue._admission.worker_limit=6;queue._admission.byte_limit=bytes;queue.ready_job_limit=limit
	for i:int in ready:
		var path:="reference:ready%d"%i;var uuid:="ready%d"%i
		check(queue._admission.reserve(path,{"estimated_bytes":10,"exclusive":exclusive}),"fixture reserves result bytes before parking "+uuid)
		queue._admission.set_stage(path,"ready");queue._admission.park(path)
		queue._jobs[path]={"accepted":true,"native":true,"result":{},"token":Deferred.Drainer.CancelToken.new(),"publication_ids":[uuid]}
		queue._prepared_paths[path]=true
	return f
func dispatch_bounded(queue:Queue)->void:
	# Thread creation itself may consume one short dispatch slice. Repeat only
	# its saved cursor; never join or publish in this capacity observation.
	for slice:int in 16:queue._dispatch_jobs(self)
func release_fixture(f:Dictionary)->void:
	await f.queue.quiesce()
	check(f.queue._jobs.is_empty() and f.queue._admission.reserved_bytes==0,"fixture shutdown joins every real worker and releases every retained lease")
	f.map.free();await process_frame
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var old_yield:=Deferred.ready_worker_yield_enabled;Deferred.ready_worker_yield_enabled=true
	var f:=backlog_fixture();var queue:Queue=f.queue
	var estimate:={"estimated_bytes":10,"exclusive":false}
	check(queue._jobs.size()==6 and queue._admission.active_workers()==0 and queue._admission.reserved_bytes==60,"six accepted results occupy complete-job slots but zero execution slots")
	check(queue._admission.can_admit("reference:next0",estimate),"the untouched execution and byte ledger allows the next lightweight job")
	dispatch_bounded(queue)
	check(queue.started.is_empty() and queue.requests==0 and queue._jobs.size()==6,"current complete-result cap stops dispatch before requesting or estimating the next job")
	check(int(queue.profile.get("priority_retirements",0))==0 and not queue._job_consumed(queue._jobs["reference:ready0"]),"equally demanded accepted closures are neither consumed nor cancelled to fake capacity")
	# Same code, same six workers, same 200-byte budget: isolate ready backlog.
	queue.ready_job_limit=16;dispatch_bounded(queue)
	check(queue.started.size()==6 and queue._admission.active_workers()==6,"raising only the result cap allows all six unchanged execution slots to prepare work")
	check(queue._jobs.size()==12 and queue._admission.reserved_bytes==120 and queue._admission.worker_limit==6 and queue._admission.byte_limit==200,"new work and parked results retain their full original byte charges")
	check(queue.started.all(func(path):return path.begins_with("reference:next")),"accepted model paths are not prepared a second time")
	await release_fixture(f)
	# Spare result slots do not authorize exceeding retained-result bytes.
	f=backlog_fixture(6,64,16);queue=f.queue
	check(queue._admission.blocking_reason("reference:next0",estimate)=="byte_limit","insufficient remaining bytes are distinguished from result backlog")
	dispatch_bounded(queue)
	check(queue.started.is_empty() and queue._admission.reserved_bytes==60 and queue._jobs.size()==6,"larger result cap preserves byte-budget refusal and every existing owner")
	await release_fixture(f)
	# Deliberately paused publication must still reach a finite complete cap.
	f=backlog_fixture(16,1000,16);queue=f.queue
	check(queue._admission.active_workers()==0 and queue._admission.can_admit("reference:next0",estimate),"full explicit ready cap can coexist with idle workers and spare bytes")
	dispatch_bounded(queue)
	check(queue.started.is_empty() and queue._jobs.size()==16 and queue._admission.reserved_bytes==160,"explicit complete-result ceiling remains finite without releasing parked bytes")
	await release_fixture(f)
	# A joined exclusive result remains exclusive until actual consumption.
	f=backlog_fixture(1,200,16,true);queue=f.queue
	check(queue._admission.active_workers()==0 and queue._admission.blocking_reason("reference:next0",estimate)=="active_exclusive","parking an exclusive result never releases its exclusivity")
	dispatch_bounded(queue)
	check(queue.started.is_empty() and queue._jobs.size()==1 and queue._admission.reserved_bytes==10,"exclusive ready ownership blocks successors despite both numeric caps allowing them")
	await release_fixture(f)
	Deferred.ready_worker_yield_enabled=old_yield
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEFERRED_READY_BACKLOG_CAPACITY passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
