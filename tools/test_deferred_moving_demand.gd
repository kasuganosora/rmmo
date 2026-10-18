extends "res://tools/test_deferred_backpressure.gd"
## The production scheduler runs real CPU workers/publication while both exact
## safety callers move by centimetres. No Godot renderer or authored resources.
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var old_yield:=Deferred.ready_worker_yield_enabled;Deferred.ready_worker_yield_enabled=true
	await continuous_test();boundary_test();scope_test()
	Deferred.ready_worker_yield_enabled=old_yield
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEFERRED_MOVING_DEMAND passed=",passed," failures=",failed);quit(0 if failed==0 else 1)

func moving_clip(x:float,y:float=0,z:float=0)->AABB:
	return AABB(Vector3(x-2,y-1,z-2),Vector3(4,2,4))

func continuous_test()->void:
	var rows:Array=[]
	for i in 80:rows.append(item("moving%d"%i,float(i+20)))
	var f:=fixture(rows);var queue:Queue=f.queue
	queue.prioritize(Vector3(1,0,1))
	queue.ensure_geometry(moving_clip(1,0,1),"manual_traversal")
	queue.ensure_geometry(moving_clip(1,0,1),"player_collision")
	queue._refresh_demanded()
	var before:=int(queue.profile.demand_refreshes);var revision:=queue._demand_revision
	var exact:=true
	for frame in 180:
		var x:=1.+frame*.01;var y:=float(frame%11)*1.5
		var clip:=moving_clip(x,y,1)
		queue.prioritize(Vector3(x,y,1))
		for id:String in ["manual_traversal","player_collision"]:
			if queue.ensure_geometry(clip,id)!=queue._in_clip(clip).is_empty():exact=false
		await tick(queue)
	check(exact,"both moving callers keep exact current-footprint readiness during continuous motion")
	check(queue._demand_revision==revision and int(queue.profile.demand_refreshes)==before,"centimetre XZ steps and large height changes do not re-sort the entire demand set")
	check(not f.document.calls.is_empty() and queue.pending.size()<rows.size(),"continuous movement makes publication progress before the final drain")
	# Publication itself now has multiple bounded preparation slices. A fixed
	# 180 ticks cannot finish 80 objects when each needs at least four slices.
	# Keep the already-tested movement/ticket invariant, then bound the drain.
	for drain_frame:int in 600:
		if queue.is_complete():break
		await tick(queue)
	check(queue.started.size()==80 and queue.is_complete() and f.document.calls.size()==80,"small-step safety tickets leave sustained CPU preparation and publication progress")
	check(int(queue.profile.max_total_jobs)<=4 and queue._admission.reserved_bytes==0,"moving-demand reuse preserves backlog and byte limits")
	check(int(queue.profile.get("moving_demand_reuses",0))>=360,"reused movement envelopes are directly observable")
	f.map.free()

func boundary_test()->void:
	var queue:=Deferred.new()
	queue.pending=[item("prefetched",4.5),item("edge",7),item("negative",-8),item("diagonal",12)]
	queue.pending[3].bounds=AABB(Vector3(12,0,12),Vector3.ONE)
	var initial:=moving_clip(0)
	check(queue.ensure_geometry(initial,"manual_traversal"),"pending geometry outside the exact footprint does not block readiness merely because it is prefetched")
	queue._refresh_demanded()
	check(queue._demanded_by_id.has("prefetched") and not queue._demanded_by_id.has("edge"),"the preparation-only halo is bounded to four metres")
	var first:=queue._demand_revision;var envelope:AABB=queue._demands.manual_traversal.clip
	check(not queue.ensure_geometry(moving_clip(3),"manual_traversal") and queue._demand_revision==first,"newly encountered pending geometry inside a reused envelope still blocks exact readiness")
	queue.ensure_geometry(moving_clip(4,100),"manual_traversal")
	check(queue._demand_revision==first and queue._demands.manual_traversal.clip==envelope,"inclusive envelope edge and height changes reuse the same membership")
	check(not queue.ensure_geometry(moving_clip(5),"manual_traversal") and queue._demand_revision>first,"crossing the held edge renews immediately and detects the new boundary obstacle")
	queue._refresh_demanded();check(queue._demanded_by_id.has("edge"),"renewed membership includes the previously outside obstacle before it can report ready")
	first=queue._demand_revision
	check(not queue.ensure_geometry(moving_clip(-8),"manual_traversal") and queue._demand_revision>first,"backward relocation cannot inherit a stale positive-side envelope")
	queue.ensure_geometry(moving_clip(12,0,12),"manual_traversal");queue._refresh_demanded()
	check(queue._demanded_by_id.has("diagonal"),"diagonal and chunk-edge movement conservatively covers both XZ axes")
	queue.release_demand("manual_traversal");queue._refresh_demanded()
	check(queue.is_idle() and not queue._demands.has("manual_traversal"),"release removes the envelope and its scheduling interest")
	queue.free()

func scope_test()->void:
	var queue:=Deferred.new();queue.pending=[item("near",0),item("target",500)]
	var target:=moving_clip(500);queue.set_demand("transfer:9",target,-2)
	queue.set_demand_scope(["transfer:9"])
	queue.ensure_geometry(moving_clip(0),"player_collision");queue._refresh_demanded()
	check(queue._demanded_by_id.keys()==["target"] and queue._demands["transfer:9"].clip==target,"a moving safety envelope never widens a transfer scope or its exact destination ticket")
	queue.allow_demand_in_scope("player_collision");queue._refresh_demanded()
	check(queue._demanded_by_id.has("near") and queue._demanded_by_id.has("target"),"explicit scope authorization includes the complete conservative movement ticket")
	queue.release_demand("player_collision");queue._refresh_demanded()
	check(queue._demanded_by_id.keys()==["target"],"cancelling a movement ticket retains the independent transfer closure")
	var original:=moving_clip(20);queue.ensure_geometry(original,"navigation:exact")
	var revision:=queue._demand_revision;var next:=moving_clip(20.01)
	queue.ensure_geometry(next,"navigation:exact")
	check(queue._demand_revision>revision and queue._demands["navigation:exact"].clip==next,"navigation and other non-moving ticket IDs preserve exact update semantics")
	queue.free()
