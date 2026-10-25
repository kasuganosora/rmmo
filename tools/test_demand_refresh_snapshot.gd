extends "res://tools/test_support_promotion_dedup.gd"
## Full demand-refresh API fixture. All resources/rows are synthetic; no worker,
## filesystem model or GPU preparation runs. --legacy-refresh-snapshot retains
## the old eager control and should fail exactly the four WORK assertions.
class PrefetchQueue extends "res://scripts/world3d/deferred_asset_loader.gd":
	var required_seen:Dictionary={}
	var poll_calls:=0
	func _poll_jobs(required:Dictionary)->void:
		required_seen=required.duplicate();poll_calls+=1
	func _resume_pixel_jobs(_tree:SceneTree)->void:pass
	func _dispatch_jobs(_tree:SceneTree,_prefetch_only:bool=false)->void:pass

var legacy_control:=false
var work_report:Dictionary={}

func _initialize()->void:
	create_timer(30.0).timeout.connect(func():push_error("DEMAND_REFRESH_SNAPSHOT watchdog timeout");quit(124))
	run.call_deferred()

func full_snapshots(q:Deferred)->int:
	return int(q.profile.get("demand_snapshot_refresh_materializations",0))+int(q.profile.get("demand_snapshot_materializations",0))

func full_snapshot_rows(q:Deferred)->int:
	return int(q.profile.get("demand_snapshot_refresh_materialized_rows",0))+int(q.profile.get("demand_snapshot_materialized_rows",0))

func exact_owners(a:Array,b:Array)->bool:
	if a.size()!=b.size():return false
	for at:int in a.size():
		if not is_same(a[at],b[at]):return false
	return true

func dense_live_ranks(q:Deferred)->bool:
	var rank:=0
	for uuid:String in q._demanded_by_id:
		if int(q._demanded_rank.get(uuid,-1))!=rank:return false
		rank+=1
	return q._demanded_rank.size()==rank and q._demanded_priority.size()==rank

func compare(q:Deferred,label:String)->Dictionary:
	Deferred.lazy_demand_snapshot_enabled=false;q._demand_revision+=1;q._refresh_demanded()
	var expected:Dictionary=snapshot(q);var owners:Array=q._demanded.duplicate()
	Deferred.lazy_demand_snapshot_enabled=true;q._demand_revision+=1;q._refresh_demanded()
	var before:int=q.profile.get("demand_snapshot_materializations",0)
	var needs_snapshot:bool=q._demanded_snapshot_dirty
	var state:Dictionary=snapshot(q);var actual:Array=q._demanded
	check(state==expected and exact_owners(owners,actual) and dense_live_ranks(q),"exact eager/lazy owners, order, path heads, dispatch, ranks and priority: "+label)
	check(int(q.profile.get("demand_snapshot_materializations",0))-before==int(needs_snapshot),"explicit snapshot materializes once only when its current view is dirty: "+label)
	Deferred.lazy_demand_snapshot_enabled=not legacy_control
	return state

func work_and_publication()->void:
	var q:=make_queue()
	for at:int in 24:
		q._priority=Vector3(at*4,0,at*2);q._demand_revision+=1;q._refresh_demanded()
		check(q._demanded_count()==2400 and not q.is_idle() and dense_live_ranks(q),"count and exact dense ranks without reading aggregate "+str(at))
	var builds_before:=full_snapshots(q);var rows_before:=full_snapshot_rows(q)
	check(builds_before==0,"WORK count-only rank refreshes build zero full snapshots")
	check(rows_before==0,"WORK count-only rank refreshes copy zero snapshot rows")
	check(q._demanded_snapshot_dirty and q._demanded_snapshot.is_empty(),"WORK refresh retains only the live ordered catalogue until traversal")
	var held:Array=q._demanded;var previous:Array=held.duplicate()
	check(full_snapshots(q)==1 and full_snapshot_rows(q)==2400,"WORK first traversal builds only one aggregate after 24 refreshes")
	var builds_after:=full_snapshots(q);var rows_after:=full_snapshot_rows(q)
	check(exact_owners(held,q._demanded_by_id.values()) and dense_live_ranks(q),"first aggregate has exact catalogue owners and ranks")
	check(is_same(held,q._demanded) and full_snapshots(q)==builds_after and full_snapshot_rows(q)==rows_after,"second aggregate read reuses the same Array without extra work")
	work_report={"legacy":legacy_control,"refreshes":24,"count_only_full_snapshots":builds_before,"count_only_rows":rows_before,"after_first_read_full_snapshots":builds_after,"after_first_read_rows":rows_after,"items":held.size()}
	q._priority=Vector3(-50,0,70);q._demand_revision+=1;q._refresh_demanded()
	check(exact_owners(held,previous),"refresh leaves the previously borrowed Array intact")
	var ordered:Array=q._demanded;var borrowed:Array=ordered.duplicate();var removed:Array=ordered.slice(0,41)
	for row:Dictionary in removed:row.published=true
	q._remove_published_demand(removed)
	check(q._demanded_snapshot_dirty and q._demanded_snapshot.is_empty() and q._demanded_count()==2359,"publication drops its aggregate and keeps an exact dirty survivor count")
	check(exact_owners(ordered,borrowed) and exact_owners(held,previous),"publication preserves both previously borrowed generations")
	var lazy_before:int=q.profile.get("demand_snapshot_materializations",0)
	var survivors:Array=q._demanded
	check(exact_owners(survivors,ordered.slice(41)) and int(q.profile.get("demand_snapshot_materializations",0))==lazy_before+1,"first post-publication read materializes exact stable survivors once")
	compare(q,"refresh after publication preserves sparse-to-dense rank rebuilding")
	q._demands.clear();q._demand_revision+=1;q._refresh_demanded()
	var empty_before:int=q.profile.get("demand_snapshot_materializations",0)
	check(q._demanded_count()==0 and q.is_idle() and q._demanded.is_empty() and not q._demanded_snapshot_dirty,"empty refresh completes without a dirty empty snapshot")
	check(int(q.profile.get("demand_snapshot_materializations",0))==empty_before,"empty aggregate read creates no full snapshot")
	q.free()

func scope_error_support()->void:
	var q:=Deferred.new()
	var building:Dictionary=item("building",0,1,"reference:shared");building.group_id="building:one"
	var sibling:Dictionary=item("sibling",2,1,"reference:shared")
	var support:Dictionary=item("support",500)
	var far:Dictionary=item("far",1000)
	q.pending=[building,sibling,support,far]
	q._runtime_building_supports.building={"support":true}
	var near_clip:=AABB(Vector3(-1,-1,-1),Vector3(4,3,3))
	q.set_demand("near",near_clip,-1);q.set_demand("far",AABB(Vector3(999,-1,-1),Vector3(3,3,3)),10)
	q.set_demand_scope(["near"])
	var state:Dictionary=compare(q,"near scope retains out-of-clip support and excludes far ticket")
	check(state.ids==["support","building","sibling"] and q._demanded_priority.support==-2,"support promotion remains live and stable")
	q._instance_failed("building","fixture instance failure");q._path_failed("reference:shared","fixture path failure")
	state=compare(q,"instance/path errors remain live")
	check(q._path_first["reference:shared"].record.uuid=="sibling" and q.path_errors.has("reference:shared"),"errored first instance cannot become the dispatch head")
	q.retry_failed(near_clip);state=compare(q,"retry restores current head without stale error metadata")
	check(q._path_first["reference:shared"].record.uuid=="building" and q.instance_errors.is_empty() and q.path_errors.is_empty(),"retry restores the exact eligible owner")
	q.set_demand_scope(["far"]);state=compare(q,"far-only scope removes near and inherited support")
	check(state.ids==["far"],"scope does not retain support from an excluded parent")
	q.set_demand_scope([]);compare(q,"unrestricted scope recomputes all live tickets")
	q.free()
	q=Deferred.new();var owner:Dictionary=item("alias",0);q.pending=[owner];q._index_pending()
	var alias:Dictionary=item("alias",-500);q._large_pending.append(alias)
	q.set_demand("alias_ticket",AABB(Vector3(-501,-1,-1),Vector3(3,3,3)),0)
	compare(q,"different bounds owners sharing UUID")
	check(q._demanded.size()==1 and is_same(q._demanded[0],alias),"lazy materialization preserves exact noncanonical spatial owner")
	q.free()

func prefetch_traversal()->void:
	var q:=PrefetchQueue.new()
	q.pending=[item("a",0,1,"reference:shared"),item("b",2,1,"reference:shared"),item("c",4,1,"reference:other")]
	q.set_demand("entry_safety",AABB(Vector3(-6,-1,-1),Vector3(12,3,3)),-3)
	q._lifetime_tree=self;q._entry_prefetch={"core_model_paths":{}}
	q.pump_entry_prefetch()
	var held:Array=q._demanded;var before:=full_snapshots(q)
	check(q.poll_calls==1 and q.required_seen.keys()==["reference:shared","reference:other"],"real prefetch pump traverses the complete aggregate into exact required paths")
	check(held.size()==3 and before==1 and full_snapshot_rows(q)==3 and not q._demanded_snapshot_dirty,"prefetch explicit traversal materializes one exact three-row snapshot")
	q.pump_entry_prefetch()
	check(q.poll_calls==2 and full_snapshots(q)==before and is_same(held,q._demanded),"unchanged second prefetch pump reuses its aggregate")
	q._entry_prefetch.clear();q.free()

func run()->void:
	legacy_control=OS.get_cmdline_user_args().has("--legacy-refresh-snapshot")
	var saved:bool=Deferred.lazy_demand_snapshot_enabled
	Deferred.lazy_demand_snapshot_enabled=not legacy_control
	var logger:=Errors.new();OS.add_logger(logger)
	contract_test();mixed_test();work_and_publication();scope_error_support();prefetch_traversal()
	Deferred.lazy_demand_snapshot_enabled=saved
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEMAND_REFRESH_SNAPSHOT ",JSON.stringify({"passed":passed,"failures":failed,"work":work_report}))
	quit(1 if failed else 0)
