extends RefCounted
## Pure, synchronous readers. The main thread retains the transaction until
## every reader joins, including failed slices. No Mesh getters or callbacks.
static var workers:=4
static func _slice(values:Array,snapshots:Array,owners:Array,by_id:Variant,first:int,last:int)->bool:
	var _scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.spec_snapshot_validation.slice") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if values.slice(first,last)!=snapshots.slice(first,last):return false
	for i:int in range(first,last):
		if not is_same(values[i],owners[i]):return false
		if by_id!=null and not is_same(by_id.get(owners[i].uuid),owners[i]):return false
	return true
static func matches(values:Array,snapshots:Array,owners:Array,by_id:Variant=null)->bool:
	if values.size()!=snapshots.size() or values.size()!=owners.size():return false
	var limit:=mini(4,mini(workers,OS.get_processor_count())) if values.size()>=1024 else 0
	if limit<=1:return _slice(values,snapshots,owners,by_id,0,values.size())
	var jobs:Array=[];var width:=ceili(float(values.size())/limit)
	for first:int in range(0,values.size(),width):
		var task:=_slice.bind(values,snapshots,owners,by_id,first,mini(first+width,values.size()))
		var worker:=Thread.new()
		if worker.start(task)==OK:jobs.append({"thread":worker})
		else:jobs.append({"result":task.call()})
	var result:=true
	for job:Dictionary in jobs:
		var valid:bool=job.thread.wait_to_finish() if job.has("thread") else job.result
		result=result and valid
	return result
