extends "res://tools/test_deferred_typed_demand_scan.gd"
## Same live rows, exact ranks/owners/path heads; cache is never a readiness proof.
func compare_cache(queue:Deferred,label:String)->void:
	Deferred.demand_membership_cache_enabled=false;queue._demand_revision+=1;queue._refresh_demanded()
	var expected:=snapshot(queue);var owners:=queue._demanded.duplicate()
	Deferred.demand_membership_cache_enabled=true;queue._demand_revision+=1;queue._refresh_demanded()
	var same:=snapshot(queue)==expected
	for i:int in mini(owners.size(),queue._demanded.size()):same=same and is_same(owners[i],queue._demanded[i])
	check(same,label)
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var queue:=Deferred.new();var rng:=RandomNumberGenerator.new();rng.seed=17917
	for i:int in 4600:
		var row:=item("row%d"%i,rng.randf_range(-1800,1800),1,"path%d"%(i%31))
		row.bounds.position.z=rng.randf_range(-1800,1800)
		row.reference_entry={"reason":["native_road","native_bridge","ordinary"][i%3]}
		if i%7==0:row.group_id="building:%d"%(i%17)
		queue.pending.append(row)
	for kind:String in ["all","building","road","structure"]:queue.set_demand(kind,AABB(Vector3(-2000,-1,-2000),Vector3(4000,2,4000)),2,kind,true)
	for i:int in 48:
		queue._priority=Vector3(i*4,0,i*3)
		if i%6==0:queue.pending[i].published=true
		if i%8==0:queue.register_runtime_building("row%d"%(i+1),AABB(),{"row4599":true})
		queue.instance_errors={"row31":"test"} if i%2==0 else {}
		queue._demand_scope={"all":true} if i%5==0 else {}
		compare_cache(queue,"stable envelope with moving ranks, live publication/errors/supports/scope %d"%i)
	queue._demand_scope={};queue.set_demand("all",AABB(Vector3.ZERO,Vector3(16,2,16)),-2,"all",true)
	compare_cache(queue,"changed envelope/priority replaces its candidates")
	var published:Dictionary=queue.pending[0];published.published=false
	# Requeue invalidates the same spatial layout epoch before allowing reload.
	queue._indexed=false;queue._pending_index.clear();queue._large_pending.clear()
	compare_cache(queue,"requeue rebuilds membership including previously published sources")
	queue.release_demand("all");check(not queue._demand_membership.has("all"),"released ticket drops cached candidate ownership immediately")
	compare_cache(queue,"release cannot leave scheduling membership")
	var elapsed:Dictionary={};var misses:=int(queue.profile.get("demand_membership_misses",0))
	for enabled:bool in [false,true]:
		Deferred.demand_membership_cache_enabled=enabled;var began:=Time.get_ticks_usec()
		for i:int in 100:
			queue._priority=Vector3(i*4,0,i*3);queue._demand_revision+=1;queue._refresh_demanded()
		elapsed[str(enabled)]=Time.get_ticks_usec()-began
	check(int(queue.profile.demand_membership_misses)==misses,"100 rerankings perform no new spatial membership scans")
	check(queue._demand_membership.size()<=queue._demands.size(),"candidate owners remain bounded by live tickets")
	print("DEMAND_MEMBERSHIP_STRESS ",JSON.stringify({"rows":4600,"refreshes":100,"elapsed_us":elapsed,"profile":queue.profile}))
	queue.shutdown();check(queue._demand_membership.is_empty(),"shutdown drops every cached ticket")
	queue.free();OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEMAND_MEMBERSHIP passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
