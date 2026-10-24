extends "res://tools/test_support_promotion_dedup.gd"
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var q:=make_queue();q._refresh_demanded()
	var rows:Array=q.pending.slice(0,100)
	var before_partitions:=int(q.profile.get("typed_partition_builds",0))
	var before_misses:=int(q.profile.get("demand_membership_misses",0))
	var before_tests:=int(q.profile.get("typed_full_scan_prefilter_tests",0))
	var began:=Time.get_ticks_usec()
	for i:int in rows.size():
		var row:Dictionary=rows[i];row.published=true;q._remove_published_demand([row])
		q.register_runtime_building(row.record.uuid,row.bounds,{"row2399":true})
		q._priority=Vector3(i*4,0,i*2);q._demand_revision+=1;q._refresh_demanded()
	var elapsed:=Time.get_ticks_usec()-began
	var partitions:=int(q.profile.get("typed_partition_builds",0))-before_partitions
	var misses:=int(q.profile.get("demand_membership_misses",0))-before_misses
	var tests:=int(q.profile.get("typed_full_scan_prefilter_tests",0))-before_tests
	check(partitions==0 and tests==0,"learning already-published buildings does not repartition unchanged pending kinds")
	check(misses==0,"moving ranks keep existing building-ticket membership after publication learning")
	var expected:=snapshot(q);var owners:Array=q._demanded.duplicate()
	q._typed_pending.clear();q._typed_pending_buildings=-1;q._demand_membership.clear();q._demand_revision+=1;q._refresh_demanded()
	var same:=expected==snapshot(q)
	for i:int in owners.size():same=same and is_same(owners[i],q._demanded[i])
	check(same,"retained epochs produce exactly the fresh classification, order, owners and path heads")
	# This new knowledge affects a live pending member and MUST invalidate.
	q.set_demand_scope(["ticket0"])
	check(not q._demanded_by_id.has("row2000"),"ordinary pending row starts outside building-only scope")
	q.register_runtime_building("row2000",q._pending_by_record_id.row2000.bounds,{"row2399":true})
	q._refresh_demanded()
	check(q._demanded_by_id.has("row2000") and q._demanded_by_id.has("row2399"),"new pending building and its support enter the current scoped demand")
	# An unrelated old invalidation must not be accidentally blessed by learning.
	q._runtime_building_records.row2001=AABB();q.register_runtime_building("absent",AABB(),{})
	q._demand_revision+=1;q._refresh_demanded()
	check(q._demanded_by_id.has("row2001"),"already-stale cached epochs still rebuild after an absent registration")
	q.free();OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	print("PUBLISHED_KIND_EPOCH ",JSON.stringify({"publication_and_refresh_us":elapsed,"partition_rebuilds":partitions,"prefilter_rows":tests,"membership_misses":misses,"failures":failed}))
	quit(1 if failed else 0)
