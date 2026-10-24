extends "res://tools/test_support_promotion_dedup.gd"
## Preserve borrowed cursors and external mutation detection while publishing
## hundreds of small groups from one large pending catalogue.
func run()->void:
	var baseline:=OS.get_cmdline_user_args().has("--baseline")
	var logger:=Errors.new();OS.add_logger(logger)
	var q:=make_queue();q._refresh_demanded();q._invalidate_collision_queries()
	var held:Array=q.pending;var published:Array=held.slice(0,600)
	var copied:=0;var began:=Time.get_ticks_usec()
	for row:Dictionary in published:
		row.published=true;q._remove_published_demand([row])
		if baseline:copied+=q.pending.size()
		q.is_complete();q.pending_record_catalogue();q._collision_query_slot("count_only")
	var elapsed:=Time.get_ticks_usec()-began
	check(held.size()==2400,"publication preserves the borrowed pre-publication array")
	if not baseline:
		check(int(q.profile.get("pending_snapshot_materializations",0))==0,"publication, readiness, catalogue and collision slots never copy survivors")
		check(int(q.profile.get("pending_snapshot_rows_deferred",0))==1259700,"600 publications defer exactly 1,259,700 repeated survivor copies")
	var expected:Array=held.slice(600)
	var remaining:Array=q.pending
	check(remaining==expected and remaining==q._pending_by_record_id.values(),"first traversal materializes exact ordered survivor identities")
	if not baseline:check(int(q.profile.get("pending_snapshot_materializations",0))==1,"many publications cause only one actual array materialization")
	# Merely materializing the snapshot must not invalidate maintained buckets.
	q._collision_query_slot("count_only")
	check(q._indexed,"materialization retains the live spatial catalogue")
	var added:=item("external_added",-10,1,"external")
	remaining.append(added);q._collision_query_slot("external")
	check(not q._indexed,"mutation through a borrowed array invalidates spatial membership")
	q._index_pending();q._invalidate_collision_queries()
	check(is_same(q.pending_record_catalogue()["external_added"],added),"external append is indexed with the exact owner")
	q.pending=remaining.duplicate();q._collision_query_slot("replacement")
	check(not q._indexed,"same-length external replacement is still detected")
	q._index_pending();q._invalidate_collision_queries()
	q._remove_published_demand([added])
	# Re-indexing and shutdown must materialize before dropping catalogue owners.
	q._indexed=false;q._index_pending()
	check(q.pending==expected,"explicit reindex preserves a deferred survivor snapshot")
	for row:Dictionary in expected:row.published=true
	q._remove_published_demand(expected)
	check(q.is_complete() and q.pending.is_empty(),"last publication completes without stale pending owners")
	var report:Dictionary=q.profile.duplicate();q.free()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	print("PENDING_PUBLICATION_SNAPSHOT ",JSON.stringify({"baseline":baseline,"publications":600,"elapsed_us":elapsed,"eager_copied_rows":copied,"profile":report,"failures":failed}))
	quit(1 if failed else 0)
