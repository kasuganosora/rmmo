extends "res://tools/test_support_promotion_dedup.gd"
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var q:=make_queue();q._refresh_demanded()
	var held:Array=q._demanded;var previous:Dictionary=snapshot(q)
	var materializations_before:int=q.profile.get("demand_snapshot_materializations",0)
	var published:Array=q.pending.slice(0,600);var began:=Time.get_ticks_usec()
	for row:Dictionary in published:
		row.published=true;q._remove_published_demand([row])
	var elapsed:=Time.get_ticks_usec()-began
	var unfinished:=true
	for i:int in 64:unfinished=unfinished and not q.is_idle()
	check(unfinished,"count-only readiness retains unfinished work")
	check(held.size()==2400 and previous.ids.size()==2400,"publication leaves an already borrowed ordered snapshot intact")
	check(int(q.profile.get("demand_snapshot_rows_deferred",0))>1000000,"publication defers rebuilding repeated full demand arrays")
	check(int(q.profile.get("demand_snapshot_materializations",0))==materializations_before,"publication and count-only queries do not materialize demand arrays")
	var remaining:Array=q._demanded
	check(remaining.size()==1800 and remaining==q._demanded_by_id.values(),"first traversal materializes exact stable survivors")
	check(int(q.profile.get("demand_snapshot_materializations",0))==materializations_before+1,"one consumer materializes once after many publications")
	q._priority=Vector3(-50,0,70);q._demand_revision+=1;q._refresh_demanded()
	var after:Dictionary=snapshot(q);var again:Array=q._demanded.duplicate()
	q._demand_membership.clear();q._demand_revision+=1;q._refresh_demanded()
	check(after==snapshot(q) and again==q._demanded,"reranking after publication matches a fresh membership rebuild")
	for row:Dictionary in again:row.published=true
	q._remove_published_demand(again)
	check(q.is_idle() and q._demanded.is_empty(),"last publication completes readiness without retaining stale survivors")
	q.free();OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	print("DEMAND_PUBLICATION_SNAPSHOT ",JSON.stringify({"publications":600,"elapsed_us":elapsed,"remaining":remaining.size(),"failures":failed}))
	quit(1 if failed else 0)
