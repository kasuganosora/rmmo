extends "res://tools/test_support_promotion_dedup.gd"
func compare(queue:Deferred,label:String)->Dictionary:
	Deferred.reuse_demand_metadata_enabled=false;queue._demand_revision+=1;queue._refresh_demanded()
	var expected:=snapshot(queue);var owners:=queue._demanded.duplicate()
	Deferred.reuse_demand_metadata_enabled=true;queue._demand_revision+=1;queue._refresh_demanded()
	var same:=expected==snapshot(queue)
	for i:int in owners.size():same=same and is_same(owners[i],queue._demanded[i])
	check(same,label)
	return expected
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	contract_test();mixed_test()
	var reports:Array=[]
	for reuse:bool in [false,true,true,false]:
		var q:=make_queue();Deferred.reuse_demand_metadata_enabled=reuse
		q._refresh_demanded();q.profile.erase("demand_metadata_created");q.profile.erase("demand_metadata_erased")
		var began:=Time.get_ticks_usec()
		for i:int in 24:q._priority=Vector3(i*4,0,i*2);q._demand_revision+=1;q._refresh_demanded()
		reports.append({"reuse":reuse,"us":Time.get_ticks_usec()-began,"created":q.profile.get("demand_metadata_created",0),"erased":q.profile.get("demand_metadata_erased",0)})
		# Publication uses the ordered item dictionary. Reusing numeric maps may
		# not accidentally preserve the old order in that separate catalog.
		var removed:Array=q._demanded.slice(0,41);var survivors:Array=q._demanded.slice(41)
		q._remove_published_demand(removed)
		check(q._demanded==survivors,"publication preserves current sorted order after refresh")
		for row:Dictionary in removed:check(not q._demanded_rank.has(row.record.uuid) and not q._demanded_priority.has(row.record.uuid),"publication removes both numeric entries")
		q._demands.clear();q._demand_revision+=1;q._refresh_demanded()
		check(q._demanded_rank.is_empty() and q._demanded_priority.is_empty(),"removed demand leaves no stale numeric entries")
		q.free()
	check(reports[0].created==115200 and reports[1].created==0 and reports[1].erased==0,"24 stable refreshes eliminate 115200 dictionary entry creations and removals")
	Deferred.reuse_demand_metadata_enabled=true;OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero engine/script errors")
	print("DEMAND_METADATA_REUSE ",JSON.stringify({"trials":reports,"failures":failed}));quit(1 if failed else 0)
