extends "res://tools/test_demand_refresh_snapshot.gd"
## Synthetic scheduler ABBA; no models/workers/GPU. Each trial has its own call
## frame, so locals from a previous trial cannot be released in a timed getter.
func measure_trial(lazy:bool)->Dictionary:
	# Compare eager/lazy aggregate construction after real refresh commits;
	# unchanged-dispatch reuse has its own independent benchmark.
	var dispatch_reuse:bool=Deferred.reuse_demand_dispatch_catalogue_enabled
	Deferred.reuse_demand_dispatch_catalogue_enabled=false
	var q:=make_queue()
	# Same eager warm catalogue for every trial; cold membership allocation is
	# outside the hot refresh comparison. No borrowed aggregate is retained.
	Deferred.lazy_demand_snapshot_enabled=false
	q._priority=Vector3.ZERO;q._demand_revision+=1;q._refresh_demanded()
	Deferred.lazy_demand_snapshot_enabled=lazy
	var before_builds:=full_snapshots(q);var before_rows:=full_snapshot_rows(q)
	var before_refreshes:int=q.profile.get("demand_refreshes",0)
	var before_us:int=q.profile.get("demand_refresh_us",0)
	var before_inputs:int=q.profile.get("demand_input_rows",0)
	var before_distances:int=q.profile.get("demand_distance_evaluations",0)
	var began:=Time.get_ticks_usec()
	for at:int in 24:
		q._priority=Vector3(at*4,0,at*2);q._demand_revision+=1;q._refresh_demanded()
	var refresh_us:=Time.get_ticks_usec()-began
	var refresh_builds:=full_snapshots(q)-before_builds
	var refresh_rows:=full_snapshot_rows(q)-before_rows
	var row:Dictionary={"lazy":lazy,"refreshes":int(q.profile.get("demand_refreshes",0))-before_refreshes,"wall_refresh_us":refresh_us,"profile_refresh_us":int(q.profile.get("demand_refresh_us",0))-before_us,"refresh_aggregate_builds":refresh_builds,"refresh_aggregate_rows":refresh_rows,"demand_input_rows":int(q.profile.get("demand_input_rows",0))-before_inputs,"distance_evaluations":int(q.profile.get("demand_distance_evaluations",0))-before_distances,"items":q._demanded_count(),"dirty_before_read":q._demanded_snapshot_dirty}
	check(row.refreshes==24 and row.items==2400,"trial has exactly2400 rows and24 real refreshes")
	check(refresh_builds==(0 if lazy else 24) and refresh_rows==(0 if lazy else 57600),"refresh aggregate counter matches actual eager/lazy work")
	var traversal_started:=Time.get_ticks_usec()
	var aggregate:Array=q._demanded
	row.first_aggregate_read_us=Time.get_ticks_usec()-traversal_started
	row.refresh_plus_first_read_us=refresh_us+int(row.first_aggregate_read_us)
	row.aggregate_builds_after_read=full_snapshots(q)-before_builds
	row.aggregate_rows_after_read=full_snapshot_rows(q)-before_rows
	check(row.aggregate_builds_after_read==(1 if lazy else 24) and row.aggregate_rows_after_read==(2400 if lazy else 57600),"first traversal has exact aggregate total work")
	check(aggregate.size()==2400 and exact_owners(aggregate,q._demanded_by_id.values()) and dense_live_ranks(q),"exact owner/order/rank after timed refreshes")
	var state:Dictionary=snapshot(q)
	aggregate=[] # Drop borrowed owners before freeing q, outside every measured span.
	q.free()
	Deferred.reuse_demand_dispatch_catalogue_enabled=dispatch_reuse
	return {"report":row,"state":state}

func run()->void:
	var saved:bool=Deferred.lazy_demand_snapshot_enabled
	var logger:=Errors.new();OS.add_logger(logger)
	var reports:Array=[];var expected:Dictionary={}
	for lazy:bool in [false,true,true,false]:
		var result:Dictionary=measure_trial(lazy)
		var row:Dictionary=result.report;var state:Dictionary=result.state
		if expected.is_empty():expected=state
		else:check(state==expected,"ABBA scheduling outputs match the eager oracle")
		if not reports.is_empty():check(row.demand_input_rows==reports[0].demand_input_rows and row.distance_evaluations==reports[0].distance_evaluations,"same candidate visits and distance work across modes")
		reports.append(row)
	Deferred.lazy_demand_snapshot_enabled=saved
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEMAND_REFRESH_SNAPSHOT_ABBA ",JSON.stringify({"passed":passed,"failures":failed,"trials":reports,"scope":"2400 synthetic rows x24 warm-catalogue refreshes; isolated trial call frames; false/true/true/false; first aggregate read separate, no real-map speed claim"}))
	quit(1 if failed else 0)
