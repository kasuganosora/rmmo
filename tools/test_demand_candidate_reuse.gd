extends "res://tools/test_support_promotion_dedup.gd"
func compare(queue:Deferred,label:String)->Dictionary:
	var expected:=super.compare(queue,label)
	Deferred.reuse_demand_candidate_rows_enabled=false;queue._demand_revision+=1;queue._refresh_demanded()
	var old:=snapshot(queue);var owners:Array=queue._demanded.duplicate()
	Deferred.reuse_demand_candidate_rows_enabled=true;queue._demand_revision+=1;queue._refresh_demanded()
	var same:=old==snapshot(queue)
	for i:int in owners.size():same=same and is_same(owners[i],queue._demanded[i])
	check(same,"reused candidate rows: "+label)
	return expected
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	Deferred.demand_membership_cache_enabled=false;contract_test();mixed_test();Deferred.demand_membership_cache_enabled=true
	var trials:Array=[]
	for reuse:bool in [false,true,true,false]:
		Deferred.reuse_demand_candidate_rows_enabled=reuse
		var q:=make_queue();q._refresh_demanded();var before:int=q.profile.demand_candidate_rows_created;var began:=Time.get_ticks_usec()
		for i:int in 24:q._priority=Vector3(i*4,0,i*2);q._demand_revision+=1;q._refresh_demanded()
		trials.append({"reuse":reuse,"us":Time.get_ticks_usec()-began,"created":int(q.profile.demand_candidate_rows_created)-before,"result_sha":var_to_str(snapshot(q)).sha256_text()})
		if reuse:
			var removed:Dictionary=q._demanded.front();q._remove_published_demand([removed])
			check(not q._demand_candidate_rows.has(removed.record.uuid),"publication immediately releases its score-row owner")
			q._demands.clear();q._demand_revision+=1;q._refresh_demanded()
			check(q._demand_candidate_rows.is_empty(),"withdrawn demand retains no stale score rows")
		q.free()
	check(trials[1].created==0 and trials[0].created==57600,"same membership refresh allocates zero additional score arrays")
	for trial:Dictionary in trials:check(trial.result_sha==trials[0].result_sha,"exact scheduling snapshot across ABBA trials")
	Deferred.reuse_demand_candidate_rows_enabled=true
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	print("DEMAND_CANDIDATE_REUSE ",JSON.stringify({"trials":trials,"failures":failed}));quit(1 if failed else 0)
