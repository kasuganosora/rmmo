extends "res://tools/test_demand_return_refresh.gd"
## Headless synthetic ABBA. Includes the full guard, requeue and refresh cost;
## no claims about map loading, GPU, or actual player frames.
const BENCH_KEYS:Array[String]=["demand_refreshes","demand_membership_misses","demand_membership_hits","demand_input_rows","demand_distance_evaluations","support_candidate_visits","support_promotions","typed_full_scan_prefilter_tests","typed_partition_builds","pending_snapshot_materializations","pending_snapshot_materialized_rows","requeue_direct_pending_items","requeue_memberships_preserved"]

func trial(enabled:bool)->Dictionary:
	Deferred.dirty_requeue_index_enabled=enabled
	Deferred.selective_requeue_membership_enabled=enabled
	var f:=return_fixture();var q:Deferred=f.queue
	var expected:=snapshot(q);var owners:Array=q._demanded.duplicate()
	var before:Dictionary=q.profile.duplicate();var requeue_us:=0;var refresh_us:=0;var whole_us:=0
	var valid:=true
	for step:int in STEPS:
		var uuid:="outside_%d"%step;var old:Dictionary=q._pending_by_record_id[uuid]
		old.published=true;q._remove_published_demand([old])
		var began:=Time.get_ticks_usec()
		var admitted:int=q.requeue_references([f.entries[uuid]])
		var middle:=Time.get_ticks_usec();q._refresh_demanded();var ended:=Time.get_ticks_usec()
		requeue_us+=middle-began;refresh_us+=ended-middle;whole_us+=ended-began
		valid=valid and admitted==1
	var state:=snapshot(q)
	valid=valid and state==expected and q._demanded.size()==owners.size()
	for i:int in mini(owners.size(),q._demanded.size()):valid=valid and is_same(owners[i],q._demanded[i])
	var work:Dictionary={}
	for key:String in BENCH_KEYS:work[key]=int(q.profile.get(key,0))-int(before.get(key,0))
	var result:={"enabled":enabled,"requeue_us":requeue_us,"refresh_us":refresh_us,"whole_us":whole_us,"work":work,"state_sha":var_to_str(state).sha256_text(),"valid":valid}
	q.free();f.map.free();return result

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var trials:Array=[]
	for enabled:bool in [false,true,true,false]:trials.append(trial(enabled))
	for row:Dictionary in trials:check(row.valid and row.state_sha==trials[0].state_sha,"identical owner and complete scheduling state across ABBA")
	Deferred.dirty_requeue_index_enabled=true;Deferred.selective_requeue_membership_enabled=true
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	print("REQUEUE_MEMBERSHIP_ABBA ",JSON.stringify({"trials":trials,"errors":logger.errors,"failures":failed,"scope":"Synthetic 24 requeues; guard and complete requeue/refresh wall time included. Excludes publication and map/GPU/IO."}))
	quit(1 if failed else 0)
