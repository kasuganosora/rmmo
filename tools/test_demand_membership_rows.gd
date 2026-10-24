extends "res://tools/test_support_promotion_dedup.gd"
func compare(queue:Deferred,label:String)->Dictionary:
	Deferred.reuse_demand_membership_rows_enabled=false;queue._demand_revision+=1;queue._refresh_demanded()
	var expected:=snapshot(queue);var owners:Array=queue._demanded.duplicate()
	Deferred.reuse_demand_membership_rows_enabled=true;queue._demand_revision+=1;queue._refresh_demanded()
	var same:=expected==snapshot(queue) and owners.size()==queue._demanded.size()
	for at:int in mini(owners.size(),queue._demanded.size()):same=same and is_same(owners[at],queue._demanded[at])
	check(same,label)
	return expected
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	contract_test();mixed_test()
	var trials:Array=[]
	for reuse:bool in [false,true,true,false]:
		Deferred.reuse_demand_membership_rows_enabled=reuse
		var q:=make_queue();q._refresh_demanded();q._demand_revision+=1;q._refresh_demanded()
		var previous:int=q.profile.get("demand_membership_rows_created",0)
		var began:=Time.get_ticks_usec()
		for at:int in 24:q._priority=Vector3(at*4,0,at*2);q._demand_revision+=1;q._refresh_demanded()
		trials.append({"reuse":reuse,"us":Time.get_ticks_usec()-began,"created_rows":int(q.profile.get("demand_membership_rows_created",0))-previous,"snapshot":var_to_str(snapshot(q)).sha256_text()})
		var cached:Dictionary=q._demand_membership.ticket1
		var borrowed:Array=q._demand_membership_rows(cached)
		var before:Array=borrowed.duplicate();var removed:Dictionary=borrowed[0]
		q._remove_published_demand([removed])
		check(not cached.has("rows") and not cached.items.has(removed.record.uuid),"publication drops its snapshot owner and exact member immediately")
		check(borrowed==before,"publication never clears an outstanding borrowed snapshot")
		var after:Array=q._demand_membership_rows(cached)
		check(after==cached.items.values() and not after.has(removed),"next read materializes exact surviving membership")
		q._demands.clear();q._demand_revision+=1;q._refresh_demanded()
		check(q._demand_membership.is_empty(),"withdrawn tickets release cached arrays")
		q.free()
	check(trials[0].created_rows>0 and trials[1].created_rows==0,"rank-only refresh creates zero membership arrays after first traversal")
	for trial:Dictionary in trials:check(trial.snapshot==trials[0].snapshot,"ABBA exact ordering, path heads, ranks and priorities")
	Deferred.reuse_demand_membership_rows_enabled=true;OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero engine/script errors")
	print("DEMAND_MEMBERSHIP_ROWS ",JSON.stringify({"trials":trials,"failures":failed}));quit(1 if failed else 0)
