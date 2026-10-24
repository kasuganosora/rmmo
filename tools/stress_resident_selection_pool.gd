extends "res://tools/stress_resident_selection_parallel.gd"
## Isolated scheduler comparison; immutable borrowed rows are joined before use.
class Part extends RefCounted:
	var result:Dictionary={}
	var task:Callable
	var ticket:=-1
	func execute()->void:result=task.call()
static func pooled(existing:Dictionary,ids:Array,workers:int)->Dictionary:
	var parts:Array=[];var stride:=ceili(float(ids.size())/workers)
	for i in workers:
		var part:=Part.new()
		part.task=Index.ResidentSelection.rows.bind(existing.stream_by_id,existing.stream_append_state.ground_order,ids.slice(i*stride,mini((i+1)*stride,ids.size())),Index.retirement_metadata_enabled)
		part.ticket=WorkerThreadPool.add_task(part.execute,false,"resident selection probe")
		if part.ticket<0:part.execute()
		parts.append(part)
	for part:Part in parts:
		if part.ticket>=0:WorkerThreadPool.wait_for_task_completion(part.ticket)
	var result:={"ok":true,"selected":{},"prefixes":{},"groups":{},"ground_ids":{},"removed_specs":[],"cleanup":{"fixtures":{},"digests":{},"model_paths":{}}}
	for part:Part in parts:
		var packet:Dictionary=part.result
		if not packet.get("ok",false):return packet
		result.selected.merge(packet.selected);result.ground_ids.merge(packet.ground_ids);result.removed_specs.append_array(packet.removed_specs)
		for field:String in ["prefixes","groups"]:
			for key:String in packet[field]:result[field][key]=int(result[field].get(key,0))+int(packet[field][key])
		for field:String in ["fixtures","digests","model_paths"]:result.cleanup[field].merge(packet.cleanup[field],true)
	if result.selected.size()!=ids.size():return Index.ResidentSelection.failure("invalid complete retirement identity")
	return result
func run()->void:
	var f:=setup();var expected:=row_plan(f.data,f.ids);var trials:Array=[]
	check(pooled(f.data,f.ids,8)==expected,"pool produces exact scalar cleanup, owners and stable selected order")
	for use_pool:bool in [false,true,true,false]:
		var began:=Time.get_ticks_usec();var result:Dictionary={}
		for iteration in 32:result=pooled(f.data,f.ids,8) if use_pool else parallel(f.data,f.ids,8)
		trials.append({"pool":use_pool,"rows":32*f.ids.size(),"us":Time.get_ticks_usec()-began})
		check(result==expected,"identical work and owning references after all children finish")
	var invalid:Array=f.ids.duplicate();invalid[1100]=invalid[0]
	check(not pooled(f.data,invalid,8).ok,"cross-part duplicate fails after all children stop")
	f.data.stream_by_id[f.ids[1500]].extras.event={}
	check(not pooled(f.data,f.ids,8).ok,"live gameplay pin remains authoritative")
	check(f.library.size()==4600 and f.nav._specs.size()==4600,"probe mutates no live index/navigation owners")
	print("RESIDENT_SELECTION_POOL ",JSON.stringify({"trials":trials,"failures":failures}))
	f.map.free();f={};drain();quit(1 if failures else 0)
