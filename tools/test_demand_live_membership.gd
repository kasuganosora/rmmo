extends "res://tools/test_support_promotion_dedup.gd"
func cached_rows(q:Deferred)->Array:
	var rows:Array=[]
	for ticket:Dictionary in q._demand_membership.values():
		var members:Variant=ticket.items
		rows.append_array(members.values() if members is Dictionary else members)
	return rows
func compare_live(q:Deferred,label:String)->void:
	q._demand_revision+=1;q._refresh_demanded()
	var actual:=snapshot(q);var owners:Array=q._demanded.duplicate();var cached:Dictionary=q._demand_membership
	Deferred.demand_membership_cache_enabled=false;q._demand_revision+=1;q._refresh_demanded()
	var same:bool=actual==snapshot(q)
	for i:int in mini(owners.size(),q._demanded.size()):same=same and is_same(owners[i],q._demanded[i])
	check(same,label)
	Deferred.demand_membership_cache_enabled=true;q._demand_membership=cached
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var q:=make_queue();q._refresh_demanded()
	var before:=cached_rows(q).size();var published:Array=q.pending.slice(0,1800)
	var began:=Time.get_ticks_usec()
	for row:Dictionary in published:row.published=true
	q._remove_published_demand(published)
	var publication_us:=Time.get_ticks_usec()-began
	var stale:=0
	for row:Dictionary in cached_rows(q):
		if row.get("published",false):stale+=1
	check(stale==0,"publication removes completed owners from cached scheduling memberships")
	var trials:Array=[]
	for trial:int in 4:
		began=Time.get_ticks_usec()
		for i:int in 32:q._priority=Vector3(i*4,0,i*2);q._demand_revision+=1;q._refresh_demanded()
		trials.append(Time.get_ticks_usec()-began)
	for i:int in 16:
		q._priority=Vector3(i*4,0,i*2)
		q._demand_scope={"ticket3":true,"ticket0":true} if i%3==0 else {}
		q.instance_errors={"row2300":"fixture"} if i%2==0 else {}
		compare_live(q,"published prefix with moving ranks/scope/errors/supports "+str(i))
	q._demand_scope={};q.instance_errors={}
	# Requeue uses this same catalogue invalidation before a returning owner is ranked.
	var returning:Dictionary=published.front();returning.published=false
	q.pending.append(returning);q._indexed=false;q._demand_revision+=1;q._refresh_demanded()
	check(q._demanded_by_id.has(returning.record.uuid),"catalogue invalidation restores returning ownership")
	compare_live(q,"returning owner preserves full-scan path order and support closure")
	q.release_demand("ticket3");check(not q._demand_membership.has("ticket3"),"released ticket drops borrowed members")
	var after:=cached_rows(q).size();q.free()
	# Diagnostic/noncanonical spatial owners must retain their original identity.
	q=Deferred.new();var owner:=item("alias",0);q.pending=[owner];q._index_pending()
	var alias:=item("alias",-500);q._large_pending.append(alias)
	q.set_demand("alias_ticket",AABB(Vector3(-501,-1,-1),Vector3(3,3,3)),0)
	q._refresh_demanded();check(is_same(q._demanded.front(),alias),"alias fixture selects a distinct spatial owner")
	owner.published=true;q._remove_published_demand([owner])
	compare_live(q,"publishing a different owner cannot prune the alias membership")
	check(q._demanded.size()==1 and is_same(q._demanded.front(),alias),"noncanonical owner remains a live candidate")
	q.free();OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	print("DEMAND_LIVE_MEMBERSHIP ",JSON.stringify({"cached_before":before,"stale_after_publication":stale,"publication_us":publication_us,"refresh32_trials_us":trials,"cached_after_return":after,"failures":failed}))
	quit(1 if failed else 0)
