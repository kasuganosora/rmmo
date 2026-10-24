extends "res://tools/test_support_promotion_dedup.gd"
func compare_modes(q:Deferred,label:String)->void:
	Deferred.demand_score_pruning_enabled=false;q._demand_revision+=1;q._refresh_demanded()
	var old:=snapshot(q);var owners:=q._demanded.duplicate()
	Deferred.demand_score_pruning_enabled=true;q._demand_revision+=1;q._refresh_demanded()
	var same:bool=old==snapshot(q)
	for i:int in owners.size():same=same and is_same(owners[i],q._demanded[i])
	check(same,label)
func run()->void:
	var q:=make_queue()
	for i:int in 9:q.set_demand("overlap%d"%i,AABB(Vector3(-1,-1,-1),Vector3(2000,3,2000)),i,"all",true)
	for i:int in 24:
		q._priority=Vector3(i*4,0,i*8);q.pending[2301].published=i%2==0
		q._demand_scope={"ticket3":true,"overlap0":true,"overlap4":true} if i%3==0 else {}
		q.instance_errors={"row2300":"fixture"} if i%2==0 else {}
		compare_modes(q,"overlapping priorities/support/publication/scope/path errors "+str(i))
	var alias:Dictionary=q.pending[2300].duplicate(true);alias.bounds.position=Vector3(-500,0,-500)
	q._large_pending.append(alias);q._demand_membership.clear();compare_modes(q,"distinct owner sharing UUID")
	q._demand_scope={};q._demand_membership.clear()
	var reports:Array=[]
	for fast:bool in [false,true,true,false]:
		Deferred.demand_score_pruning_enabled=fast
		var count:int=q.profile.get("demand_distance_evaluations",0);var began:=Time.get_ticks_usec()
		for i:int in 12:q._priority=Vector3(i*4,0,i*2);q._demand_revision+=1;q._refresh_demanded()
		reports.append({"pruning":fast,"us":Time.get_ticks_usec()-began,"distance_evaluations":int(q.profile.demand_distance_evaluations)-count})
	check(reports[1].distance_evaluations<reports[0].distance_evaluations/2,"overlapping tickets eliminate more than half the exact distance computations")
	Deferred.demand_score_pruning_enabled=true;q.free()
	print("DEMAND_SCORE_PRUNING ",JSON.stringify({"trials":reports,"failures":failed}));quit(1 if failed else 0)
