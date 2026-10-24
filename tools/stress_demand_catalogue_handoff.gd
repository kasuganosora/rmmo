extends "res://tools/test_demand_live_membership.gd"
## Reproduce the query Dictionary -> Array -> Dictionary copy before integration.
func compare_handoff(q:Deferred,label:String)->void:
	Deferred.reuse_spatial_membership_catalogue_enabled=false;q._demand_membership.clear();q._demand_revision+=1;q._refresh_demanded()
	var expected_state:=snapshot(q);var owners:Array=q._demanded.duplicate()
	Deferred.reuse_spatial_membership_catalogue_enabled=true;q._demand_membership.clear();q._demand_revision+=1;q._refresh_demanded()
	var same:bool=expected_state==snapshot(q)
	for i:int in owners.size():same=same and is_same(owners[i],q._demanded[i])
	check(same,label)
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var q:=make_queue();q._index_pending()
	var query:Dictionary=q._pending_by_record_id.duplicate();var expected:Array=query.values();var trials:Array=[]
	for fast:bool in [false,true,true,false]:
		var began:=Time.get_ticks_usec();var selected:Variant;var count:=0
		for i:int in 128:
			selected=query if fast else q._cache_demand_items(query.values())
			count+=selected.size()
		trials.append({"reuse":fast,"us":Time.get_ticks_usec()-began,"rows":count})
		check(selected.values()==expected,"handoff preserves query order and exact owners")
	# The existing prune already checks owner identity; authoritative UUID ownership
	# is not required for a deduplicated query catalogue to be safely cached.
	var alias:Dictionary=expected[3].duplicate(true)
	query[alias.record.uuid]=alias
	q._demand_membership={"probe":{"items":query}}
	var published:Array=[expected[2],expected[3]]
	for row:Dictionary in published:row.published=true
	q._remove_published_demand(published)
	check(not query.has(expected[2].record.uuid) and is_same(query[alias.record.uuid],alias),"pruning removes exact completed owner and retains a distinct alias")
	q.free();q=make_queue()
	for i:int in 20:
		q._priority=Vector3(i*4,0,i*8);q.pending[2301].published=i%2==0
		q._demand_scope={"ticket3":true,"ticket0":true} if i%3==0 else {}
		q.instance_errors={"row2300":"fixture"} if i%2==0 else {}
		Deferred.filtered_demand_membership_enabled=i%4!=0
		compare_handoff(q,"exact ranks/path heads/order, scope, supports and filtered/unfiltered membership "+str(i))
	q._demand_scope={};Deferred.filtered_demand_membership_enabled=true
	var alias_row:Dictionary=q.pending[2300].duplicate(true);alias_row.bounds.position=Vector3(-500,0,-500)
	# A cloned indexed row carries its old projected rectangle. This fixture is
	# a newly located owner, so keep its immutable 3D and scheduling bounds equal.
	alias_row.demand_rect=Rect2(Vector2(-500,-500),Vector2.ONE)
	q._large_pending.append(alias_row)
	compare_handoff(q,"noncanonical spatial UUID alias")
	var original:Dictionary=q.pending[2300]
	q.set_demand("alias",AABB(Vector3(-501,0,-501),Vector3(4,1,4)),-3);q._refresh_demanded()
	original.published=true;q._remove_published_demand([original])
	compare_live(q,"published authoritative owner does not erase cached foreign alias")
	q.free();q=make_queue();q._index_pending();var refresh_trials:Array=[]
	for fast:bool in [false,true,true,false]:
		Deferred.reuse_spatial_membership_catalogue_enabled=fast
		var before:int=q.profile.get("demand_catalogue_rows_reused",0);var began:=Time.get_ticks_usec()
		for i:int in 32:q._demand_membership.clear();q._priority=Vector3(i*4,0,i*2);q._demand_revision+=1;q._refresh_demanded()
		refresh_trials.append({"reuse":fast,"us":Time.get_ticks_usec()-began,"reused_rows":int(q.profile.get("demand_catalogue_rows_reused",0))-before})
	Deferred.reuse_spatial_membership_catalogue_enabled=true;q.free();OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	print("DEMAND_CATALOGUE_HANDOFF ",JSON.stringify({"trials":trials,"refresh_trials":refresh_trials,"failures":failed}));quit(1 if failed else 0)
