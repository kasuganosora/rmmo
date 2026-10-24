extends "res://tools/test_support_promotion_dedup.gd"
func invalidate_requeue(q:Deferred)->void:
	q._demand_membership.clear();q._typed_pending.clear();q._typed_pending_buildings=-1;q._demand_revision+=1
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var q:=make_queue();q._refresh_demanded()
	var builds:=int(q.profile.get("typed_partition_builds",0));var scans:=int(q.profile.get("typed_full_scan_prefilter_tests",0))
	var began:=Time.get_ticks_usec()
	for i:int in 64:
		var row:=item("return%d"%i,float(i)*2,1,"returned");row.group_id="building:return";row.reference_entry={"reason":"native_road"}
		if i%4==0:row.bounds.size=Vector3(500,1,500)
		q.pending.append(row);q._index_pending_item(row);invalidate_requeue(q);q._refresh_demanded()
		check(q._demanded_by_id.has(row.record.uuid),"new pending owner is classified immediately "+str(i))
	var elapsed:=Time.get_ticks_usec()-began
	builds=int(q.profile.get("typed_partition_builds",0))-builds;scans=int(q.profile.get("typed_full_scan_prefilter_tests",0))-scans
	check(builds==0 and scans==0,"sparse requeue never repartitions the entire pending catalogue")
	var expected:=snapshot(q);var owners:Array=q._demanded.duplicate()
	# Compare against the retained general spatial/type path, including large-first order.
	Deferred.typed_demand_scan_enabled=false;q._demand_membership.clear();q._demand_revision+=1;q._refresh_demanded()
	var same:=expected==snapshot(q)
	for i:int in owners.size():same=same and is_same(owners[i],q._demanded[i])
	check(same,"large/small requeue keeps exact full-scan order, owners, ranks and paths")
	Deferred.typed_demand_scan_enabled=true
	var removed:Array=q.pending.slice(0,80)
	for row:Dictionary in removed:row.published=true
	q._remove_published_demand(removed);invalidate_requeue(q);q._refresh_demanded()
	for row:Dictionary in removed:check(not q._demanded_by_id.has(row.record.uuid),"published UUID is absent from typed candidates "+row.record.uuid)
	q.set_demand_scope(["ticket0"]);q.register_runtime_building("row2000",q._pending_by_record_id.row2000.bounds,{"row2399":true});q._refresh_demanded()
	check(q._demanded_by_id.has("row2000"),"late knowledge of a pending building updates its type")
	q.free();OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	print("INCREMENTAL_PENDING_KINDS ",JSON.stringify({"requeue64_us":elapsed,"partition_builds":builds,"prefilter_rows":scans,"failures":failed}))
	quit(1 if failed else 0)
