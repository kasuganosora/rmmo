extends "res://tools/test_demand_return_refresh.gd"
## Draft red test; copy to an isolated project before execution.
## Baseline must fail the membership-hit assertion. No timings are asserted.

func _support_requeue_case()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var id:="source_960";var old:Dictionary=q._pending_by_record_id[id]
	check(q._demanded_by_id.has(id),"initial shared landscape support is demanded")
	old.published=true;q._remove_published_demand([old])
	var previous_revision:int=q._demand_revision
	check(q.requeue_references([f.entries[id]])==1 and q._demand_revision==previous_revision+1,"out-of-clip support requeue still advances the real revision")
	q._refresh_demanded()
	check(q._demanded_by_id.has(id) and is_same(q._demanded_by_id[id],q._pending_by_record_id[id]),"live support closure picks up the exact newly requeued owner")
	check(q._demanded_priority.get(id)==-1,"live player support retains its promoted priority")
	exact_full_scan_oracle(q,"requeued shared support")
	q.free();f.map.free()

func _mixed_batch_case()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var id0:="outside_0";var id1:="outside_1"
	for id:String in [id0,id1]:
		var old:Dictionary=q._pending_by_record_id[id];old.published=true;q._remove_published_demand([old])
	# The compact entry stays far away; the learned bounds apply to the live item.
	q._runtime_building_records[id0]=AABB(Vector3(4,0,4),Vector3.ONE)
	var before:int=q._demand_revision
	check(q.requeue_references([f.entries[id0],f.entries[id1]])==2 and q._demand_revision==before+1,"mixed accepted batch retains one revision")
	q._refresh_demanded()
	check(q._demanded_by_id.has(id0) and is_same(q._demanded_by_id[id0],q._pending_by_record_id[id0]),"learned live bounds override the far compact bounds")
	check(not q._demanded_by_id.has(id1),"unrelated member remains undemanded")
	exact_full_scan_oracle(q,"mixed relevant and unrelated requeue")
	q.free();f.map.free()

func _published_owner_case()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	q.set_demand_scope(["road_render"])
	var id:="source_500";var row:Dictionary=q._pending_by_record_id[id]
	row.published=true;q._demand_membership.clear();q._demand_revision+=1;q._refresh_demanded()
	check(not q._demanded_by_id.has(id),"published owner is excluded when the typed membership is built")
	row.published=false
	var old:Dictionary=q._pending_by_record_id.outside_0;old.published=true;q._remove_published_demand([old])
	q.requeue_references([f.entries.outside_0]);q._refresh_demanded()
	check(q._demanded_by_id.has(id) and is_same(q._demanded_by_id[id],row),"unrelated requeue rediscovers an owner that was published during membership construction")
	exact_full_scan_oracle(q,"published owner returns")
	q.free();f.map.free()

func _scope_and_group_cases()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	check(q._demand_membership.has("road_render"),"road ticket has a cached membership before scoping")
	q.set_demand_scope(["player"])
	var old:Dictionary=q._pending_by_record_id.outside_0;old.published=true;q._remove_published_demand([old])
	var entry:Dictionary=f.entries.outside_0;entry.bounds=AABB(Vector3(150,0,0),Vector3.ONE)
	check(Deferred._intersects(q._demands.road_render.clip,entry.bounds) and not Deferred._intersects(q._demands.player.clip,entry.bounds),"scope fixture reaches road but not player")
	q.requeue_references([entry]);q.set_demand_scope([]);q._refresh_demanded()
	check(q._demanded_by_id.has("outside_0") and is_same(q._demanded_by_id.outside_0,q._pending_by_record_id.outside_0),"a cached scope-excluded ticket sees requeued owners after scope widening")
	exact_full_scan_oracle(q,"scope widening")
	q.free();f.map.free()
	f=return_fixture();q=f.queue
	q._demands.away_group={"clip":AABB(),"kind":"all","priority":-2,"group_id":"building:away"}
	q._demand_revision+=1;q._refresh_demanded()
	old=q._pending_by_record_id.outside_1;old.published=true;q._remove_published_demand([old])
	entry=f.entries.outside_1;entry.group_id="building:away"
	q.requeue_references([entry]);q._refresh_demanded()
	check(q._demanded_by_id.has("outside_1") and q._demanded_priority.outside_1==-2,"outside-clip requeue matches group ticket")
	exact_full_scan_oracle(q,"outside group")
	q.free();f.map.free()

func _strategy_threshold_case()->void:
	var q:=Deferred.new();var map:=Node3D.new();var entries:Dictionary={}
	q._map=map;q._reference_index={"models":{}};map.set_meta("extras",{"rmmo_records":[]})
	# Nine ticket cells, eight existing occupied buckets: this starts on typed
	# full-scan. The two matching roads have tied bounds and priority.
	append_source(q,entries,"tie_a",0,Vector3(1,0,1),"native_road")
	append_source(q,entries,"tie_b",1,Vector3(1,0,1),"native_road")
	for i:int in 7:append_source(q,entries,"far_%d"%i,2+i,Vector3(1000+i*64,0,0),"ordinary")
	q.set_demand("roads",AABB(Vector3.ZERO,Vector3(64,1,64)),0,"road")
	q._refresh_demanded()
	check(q._pending_index.size()==8 and q._demand_membership.has("roads"),"typed ticket starts with eight buckets and nine query cells")
	var before:=snapshot(q);var source:=item("far_new",2000)
	var entry:Dictionary={"compact_record":source.record,"record_index":99,"bounds":source.bounds,"asset_path":"","group_id":"","reason":"ordinary"}
	q.requeue_references([entry])
	check(q._pending_index.size()==9 and not q._demand_membership.has("roads"),"crossing the bucket threshold drops old typed membership")
	q._refresh_demanded();check(snapshot(q)==before,"equal-score road order survives a typed-to-spatial strategy switch")
	exact_full_scan_oracle(q,"bucket threshold")
	q.free();map.free()

func _ownership_and_retry_case()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var token:=RefCounted.new();q._jobs.held={"token":token,"publication_ids":[]}
	check(q._admission.reserve("held",{"estimated_bytes":128,"exclusive":false}),"lease fixture reserves one live worker slot")
	var reserved:int=q._admission.reserved_bytes
	q._dispatch_capacity=["prior"];q._dispatch_fence="held";q._publication_queues.held={"cursor":7}
	q.instance_errors["source_3"]="fixture"
	var old:Dictionary=q._pending_by_record_id.outside_2;old.published=true;q._remove_published_demand([old])
	q.requeue_references([f.entries.outside_2]);q._refresh_demanded()
	check(is_same(q._jobs.held.token,token) and q._admission.reserved_bytes==reserved,"requeue preserves a live job token and its byte lease")
	check(q._publication_queues.is_empty() and q._dispatch_capacity.is_empty() and q.instance_errors.has("source_3"),"requeue keeps retry reset and instance-error behavior")
	q._jobs.clear();q._admission.release("held");q.free();f.map.free()

func _registration_case()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var id:="source_0";var previous:Dictionary=q._runtime_building_supports[id].duplicate()
	var epoch:int=q._membership_registration_epoch
	q.register_runtime_building(id,q._runtime_building_records[id],previous)
	check(q._membership_registration_epoch==epoch,"unchanged support registration retains its epoch")
	previous["outside_0"]=true
	q.register_runtime_building(id,q._runtime_building_records[id],previous)
	check(q._membership_registration_epoch==epoch+1,"changed support registration advances its epoch even at equal building count")
	var old:Dictionary=q._pending_by_record_id.outside_0;old.published=true;q._remove_published_demand([old])
	q.requeue_references([f.entries.outside_0])
	check(not q._demand_membership.has("road_render"),"registration changes discard older typed membership")
	q._refresh_demanded()
	check(q._demanded_by_id.has("outside_0"),"same-count support registration change is observed on unrelated requeue")
	exact_full_scan_oracle(q,"changed support registration")
	q.free();f.map.free()

func _alias_and_current_position_cases()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var alias:Dictionary=q.pending[0].duplicate(true);alias.bounds.position=Vector3(-500,0,-500)
	q._large_pending.append(alias) # Deliberately breaks canonical large-owner identity.
	var old:Dictionary=q._pending_by_record_id.outside_3;old.published=true;q._remove_published_demand([old])
	q.requeue_references([f.entries.outside_3])
	check(q._demand_membership.is_empty(),"noncanonical alias falls back to clearing all cached memberships")
	q._refresh_demanded();exact_full_scan_oracle(q,"alias fallback")
	q.free();f.map.free()
	f=return_fixture();q=f.queue
	q.prioritize(Vector3(4,0,4)) # Within the anchor; current position changes.
	old=q._pending_by_record_id.outside_4;old.published=true;q._remove_published_demand([old])
	q.requeue_references([f.entries.outside_4]);q._refresh_demanded()
	check(q._priority==Vector3(4,0,4) and q._priority_rank_anchor==Vector3.ZERO,"unrelated requeue keeps current position distinct from the retained anchor")
	exact_full_scan_oracle(q,"current position after unrelated requeue")
	q.free();f.map.free()

func _dirty_snapshot_case()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var borrowed:Array=q.pending;var borrowed_copy:Array=borrowed.duplicate()
	var old:Dictionary=q._pending_by_record_id.outside_5;old.published=true;q._remove_published_demand([old])
	check(q._pending_snapshot_dirty,"publication makes UUID index authoritative before requeue")
	var materializations:int=q.profile.get("pending_snapshot_materializations",0)
	q.requeue_references([f.entries.outside_5])
	check(q._pending_snapshot_dirty and int(q.profile.get("pending_snapshot_materializations",0))==materializations,"dirty indexed requeue avoids a full pending snapshot materialization")
	check(borrowed==borrowed_copy and is_same(borrowed[0],borrowed_copy[0]),"previously borrowed pending snapshot remains unchanged")
	var current:Array=q.pending
	check(current.back().record.uuid=="outside_5" and is_same(current.back(),q._pending_by_record_id.outside_5),"later getter materializes correct order and current owner")
	q._collision_query_slot("snapshot_test")
	check(q._indexed,"getter and collision observation retain the valid incremental index")
	q._refresh_demanded();exact_full_scan_oracle(q,"dirty snapshot return")
	q.free();f.map.free()

func _fallback_case()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var old:Dictionary=q._pending_by_record_id.outside_6;old.published=true;q._remove_published_demand([old])
	Deferred.incremental_pending_index_enabled=false
	check(q.requeue_references([f.entries.outside_6])==1,"nonincremental fallback still accepts the returned owner")
	check(not q._indexed and q._demand_membership.is_empty(),"nonincremental fallback retains clear-all and rebuild semantics")
	Deferred.incremental_pending_index_enabled=true;q._refresh_demanded()
	check(q._pending_by_record_id.has("outside_6"),"fallback reindexes returned owner")
	exact_full_scan_oracle(q,"nonincremental fallback")
	q.free();f.map.free()

func _flags_and_borrowed_mutation_case()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var old:Dictionary=q._pending_by_record_id.outside_7;old.published=true;q._remove_published_demand([old])
	Deferred.native_demand_bounds_enabled=false
	q.requeue_references([f.entries.outside_7])
	check(not q._demand_membership.has("road_render"),"changed bounds predicate falls back to rebuilding cached membership")
	Deferred.native_demand_bounds_enabled=true;q._refresh_demanded();exact_full_scan_oracle(q,"bounds predicate reset")
	q.free();f.map.free()
	f=return_fixture();q=f.queue
	var exposed:Array=q.pending;exposed[0]=exposed[0].duplicate(true)
	var entry:Dictionary={"compact_record":{"uuid":"fresh_outside"},"record_index":5000,"bounds":AABB(Vector3(30000,0,0),Vector3.ONE),"asset_path":"","group_id":"","reason":"native_road"}
	q.requeue_references([entry])
	check(q._demand_membership.is_empty(),"same-count mutation of a live borrowed pending array takes the conservative fallback")
	q.free();f.map.free()

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var result:=unrelated_requeue_trial(false)
	check(int(result.work.demand_refreshes)==STEPS,"all unrelated requeues keep the original revision/refresh behavior")
	check(int(result.work.demand_membership_misses)<STEPS*5,"unrelated requeues avoid at least one typed membership rebuild")
	_support_requeue_case();_mixed_batch_case();_published_owner_case();_scope_and_group_cases()
	_strategy_threshold_case();_ownership_and_retry_case();_registration_case();_alias_and_current_position_cases();_dirty_snapshot_case();_fallback_case();_flags_and_borrowed_mutation_case()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	print("REQUEUE_MEMBERSHIP_DRAFT ",JSON.stringify({"passed":passed,"failures":failed,"work":result.work,"errors":logger.errors}))
	quit(1 if failed else 0)
