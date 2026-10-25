extends "res://tools/test_deferred_typed_demand_scan.gd"
const Trace=preload("res://scripts/world3d/load_trace.gd")
static func make_snapshot_queue(data:Dictionary)->Deferred:
	var q:=Deferred.new()
	q.pending=data.pending.duplicate(true);q._demands=data.demands.duplicate(true);q._demand_scope=data.scope.duplicate()
	q._priority=data.priority;q.instance_errors=data.instance_errors.duplicate();q.path_errors=data.path_errors.duplicate()
	# Rebuild through production registration, including shared support IDs.
	# Assigning these dictionaries directly forced the old Array-key fallback
	# and measured hashing work that the live scheduler no longer performs.
	for uuid:String in data.buildings:q.register_runtime_building(uuid,data.buildings[uuid],data.supports.get(uuid,{}))
	if data.reference_index_present:q._reference_index={"snapshot":true}
	q._index_pending();q._refresh_demanded()
	return q
func run()->void:
	var input:="";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--input="):input=arg.trim_prefix("--input=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if input.is_empty() or output.is_empty():quit(2);return
	var data:Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(input))
	var report:Dictionary={"input":input,"input_sha":FileAccess.get_sha256(input),"map_sha":data.map_sha,"pending":data.pending.size(),"scope":"Synchronous CPU scheduling replay of real return inputs; GPU, IO, publication and actual movement excluded. Trace spans are instrumented; selected stage spans below do not overlap.","trials":[]}
	var logger:=Errors.new();OS.add_logger(logger)
	for mode:String in ["rank_only","chunk_changes"]:
		var q:=make_snapshot_queue(data)
		Trace.minimum_event_us=0;Trace.start();var samples:Array=[]
		for step:int in 24:
			var position:Vector3=data.priority+Vector3((step%6)*(4 if mode=="rank_only" else 32),0,0)
			if mode=="rank_only":q._priority=position;q._demand_revision+=1
			else:
				q.prioritize(position);q.ensure_geometry(AABB(position-Vector3(2,1,2),Vector3(4,2,4)),"player_collision")
			var began:=Time.get_ticks_usec();q._refresh_demanded();samples.append(Time.get_ticks_usec()-began)
		var capture:=Trace.stop();var stages:Dictionary={}
		for event:Dictionary in capture.events:
			if event.label not in ["demand.membership_setup","demand.collect_candidates","demand.sort_candidates","demand.rebuild_dispatch_catalog"]:continue
			if not stages.has(event.label):stages[event.label]={"us":0,"max_us":0,"calls":0}
			var row:Dictionary=stages[event.label];row.us+=event.duration_us;row.max_us=maxi(row.max_us,event.duration_us);row.calls+=1
		var measured:Dictionary={"mode":mode,"samples_us":samples,"stages":stages,"profile":q.profile.duplicate(true),"demanded":q._demanded.size()}
		var expected:=snapshot(q);var owners:Array=q._demanded.duplicate()
		Deferred.typed_demand_scan_enabled=false;Deferred.demand_membership_cache_enabled=false;q._demand_revision+=1;q._refresh_demanded()
		var same:=expected==snapshot(q)
		for i:int in owners.size():same=same and is_same(owners[i],q._demanded[i])
		check(same,"real replay equals full-scan ownership/order/path contract: "+mode)
		Deferred.typed_demand_scan_enabled=true;Deferred.demand_membership_cache_enabled=true
		report.trials.append(measured);q.free()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	report.failures=failed;report.engine_errors=logger.errors
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("DEMAND_SNAPSHOT_REPLAY ",output," failures=",failed);quit(1 if failed else 0)
