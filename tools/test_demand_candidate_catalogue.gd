extends "res://tools/test_demand_candidate_reuse.gd"
## Reuse the score catalogue's slots, not just its nested score arrays.
func compare(queue:Deferred,label:String)->Dictionary:
	var expected:=super.compare(queue,label)
	Deferred.reuse_demand_candidate_catalogue_enabled=false;Deferred.reuse_demand_dispatch_catalogue_enabled=false;queue._demand_revision+=1;queue._refresh_demanded()
	var old:=snapshot(queue);var owners:Array=queue._demanded.duplicate()
	Deferred.reuse_demand_candidate_catalogue_enabled=true;Deferred.reuse_demand_dispatch_catalogue_enabled=true;queue._demand_revision+=1;queue._refresh_demanded()
	var same:=old==snapshot(queue) and owners.size()==queue._demanded_count()
	for i:int in owners.size():same=same and is_same(owners[i],queue._demanded[i])
	check(same,"candidate catalogue preserves exact order, paths, heads, ranks, priorities and owners: "+label)
	return expected

func trial(reuse:bool,data:Dictionary)->Dictionary:
	Deferred.reuse_demand_candidate_catalogue_enabled=reuse
	Deferred.reuse_demand_dispatch_catalogue_enabled=reuse
	var q:Deferred=make_queue() if data.is_empty() else preload("res://tools/profile_demand_snapshot.gd").make_snapshot_queue(data)
	q._refresh_demanded()
	var before:Dictionary=q.profile.duplicate();var catalogue:Dictionary=q._demand_candidate_rows
	var stable:=true;var spans:Array=[];var origin:Vector3=q._priority
	for i:int in 24:
		q._priority=origin+Vector3((i%6)*4,0,(i%4)*2);q._demand_revision+=1
		var began:=Time.get_ticks_usec();q._refresh_demanded();spans.append(Time.get_ticks_usec()-began)
		stable=stable and is_same(catalogue,q._demand_candidate_rows)
	check(stable==reuse,"stable catalogue allocation only in reuse mode "+str(reuse))
	var delta:Dictionary={}
	for key:String in ["demand_candidate_catalogue_inserts","demand_candidate_catalogue_erased","demand_candidate_catalogue_scan_rows","demand_dispatch_catalogue_rows_written","demand_dispatch_catalogue_rows_reused","demand_dispatch_catalogue_guard_rows","demand_input_rows","demand_distance_evaluations","support_candidate_visits","support_array_key_queries"]:delta[key]=int(q.profile.get(key,0))-int(before.get(key,0))
	check(delta.demand_candidate_catalogue_inserts==(0 if reuse else 24*q._demanded_count()),"exact stable-membership hash-slot insert work "+str(reuse))
	check(delta.demand_candidate_catalogue_scan_rows==0,"unchanged membership does not add a retirement scan")
	var state:Dictionary=snapshot(q)
	var result:={"reuse":reuse,"items":q._demanded_count(),"spans_us":spans,"work":delta,"state_sha":var_to_str(state).sha256_text()}
	q.free();return result

func retirement_cases()->void:
	Deferred.reuse_demand_candidate_catalogue_enabled=true
	Deferred.reuse_demand_dispatch_catalogue_enabled=true
	var q:=make_queue();q._refresh_demanded()
	var first_path:String=q._demanded_by_path.keys()[0];var siblings:Array=q._demanded_by_path[first_path]
	q._demand_revision+=1;q._refresh_demanded()
	check(is_same(siblings,q._demanded_by_path[first_path]),"identical owner/order refresh preserves the existing dispatch path array")
	var old:Dictionary=q._demand_candidate_rows
	var removed:Dictionary=q._demanded.front();q._remove_published_demand([removed])
	check(not old.has(removed.record.uuid),"publication immediately drops the cached score owner")
	var scans:int=q.profile.get("demand_candidate_catalogue_scan_rows",0)
	q._demands.clear();q._demand_revision+=1;q._refresh_demanded()
	check(old.is_empty() and q._demanded_count()==0,"withdrawal releases every unseen cached score row")
	check(int(q.profile.get("demand_candidate_catalogue_scan_rows",0))==scans,"complete withdrawal adds no script epoch scan")
	q.free()
	q=Deferred.new();q.pending=[item("old",0)];q.set_demand("test",AABB(Vector3(-2,-1,-2),Vector3(4,2,4)));q._refresh_demanded()
	old=q._demand_candidate_rows
	var replacement:=item("new",0);q.pending=[replacement];q._indexed=false;q._demand_revision+=1;q._refresh_demanded()
	check(is_same(old,q._demand_candidate_rows) and old.size()==1 and old.has("new") and not old.has("old"),"equal-count replacement erases unseen UUIDs and preserves the catalogue")
	var same_id:=item("new",1);q.pending=[same_id];q._indexed=false;q._demand_revision+=1;q._refresh_demanded()
	check(is_same(q._demand_candidate_rows.new[2],same_id) and is_same(q._demanded_by_id.new,same_id),"same-UUID replacement updates the exact live owner")
	var old_path:String=same_id.path;same_id.path="replacement_path";q._demand_revision+=1;q._refresh_demanded()
	check(not q._demanded_by_path.has(old_path) and is_same(q._demanded_by_path.replacement_path[0],same_id),"in-place path change rebuilds dispatch grouping")
	q.instance_errors["new"]="fixture";q._demand_revision+=1;q._refresh_demanded()
	check(not q._path_first.has("replacement_path"),"new instance error removes the dispatch head")
	q.instance_errors.clear();q._demand_revision+=1;q._refresh_demanded()
	check(is_same(q._path_first.replacement_path,same_id),"clearing the last error restores the dispatch head")
	q._demands.test.priority=-3;q._demand_revision+=1;q._refresh_demanded()
	check(q._demanded_priority.new==-3,"priority change cannot reuse old dispatch metadata")
	var aggregate:Array=q._demanded;var path_rows:Array=q._demanded_by_path.replacement_path
	q._publication_queues.replacement_path={"cursor":99};q._dispatch_capacity=[1]
	q._demand_revision+=1;q._refresh_demanded()
	check(is_same(q._demanded,aggregate) and is_same(q._demanded_by_path.replacement_path,path_rows),"unchanged aggregate and path views remain valid without copying")
	check(q._publication_queues.is_empty() and q._dispatch_capacity.is_empty(),"unchanged catalogues still restart publication/dispatch retry cursors")
	compare(q,"same UUID replacement");q.free()
	q=Deferred.new()
	var bad:=item("bad",0,1,"shared");var tail:=item("tail",1,1,"shared")
	q.pending=[bad,tail];var clip:=AABB(Vector3(-2,-1,-2),Vector3(4,2,4));q.set_demand("test",clip);q._refresh_demanded()
	q._instance_failed("bad","fixture");tail.published=true;q._remove_published_demand([tail])
	check(not q._path_first.has("shared"),"publication skips a failed surviving path head before refresh")
	q.retry_failed(clip);q._refresh_demanded()
	check(q.instance_errors.is_empty() and q._path_first.has("shared") and is_same(q._path_first.shared,bad),"retry repairs a head changed by publication even without an intervening error refresh")
	q.free()

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var data:Dictionary={};var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):data=bytes_to_var(FileAccess.get_file_as_bytes(arg.trim_prefix("--snapshot=")))
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	Deferred.demand_membership_cache_enabled=false;contract_test();mixed_test();Deferred.demand_membership_cache_enabled=true
	retirement_cases()
	var groups:Array=[]
	for input:Dictionary in ([{},data] if not data.is_empty() else [{}]):
		var trials:Array=[]
		for reuse:bool in [false,true,true,false]:trials.append(trial(reuse,input))
		for row:Dictionary in trials:
			check(row.state_sha==trials[0].state_sha,"ABBA exact scheduling state")
			for key:String in ["demand_input_rows","demand_distance_evaluations","support_candidate_visits"]:check(row.work[key]==trials[0].work[key],"ABBA retains "+key)
		groups.append({"source":"synthetic" if input.is_empty() else "real_cpu_snapshot","trials":trials})
	Deferred.reuse_demand_candidate_catalogue_enabled=true
	Deferred.reuse_demand_dispatch_catalogue_enabled=true
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	var report:={"groups":groups,"passed":passed,"failures":failed,"errors":logger.errors}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("DEMAND_CANDIDATE_CATALOGUE ",JSON.stringify(report))
	quit(1 if failed else 0)
