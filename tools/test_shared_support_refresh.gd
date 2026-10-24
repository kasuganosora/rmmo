extends "res://tools/test_support_promotion_dedup.gd"
func modes(fast:bool)->void:
	Deferred.shared_support_closure_enabled=fast;Deferred.filtered_demand_membership_enabled=fast
func compare_shared(q:Deferred,label:String)->void:
	var cached:Dictionary=q._demand_membership
	modes(false);q._demand_membership={};q._demand_revision+=1;q._refresh_demanded()
	var expected:=snapshot(q);var owners:=q._demanded.duplicate()
	modes(true);q._demand_membership=cached;q._demand_revision+=1;q._refresh_demanded()
	var same:bool=expected==snapshot(q)
	for i:int in owners.size():same=same and is_same(owners[i],q._demanded[i])
	check(same,label)
func run()->void:
	var q:=make_queue();var logger:=Errors.new();OS.add_logger(logger)
	for id:String in q._runtime_building_supports.keys():q.register_runtime_building(id,AABB(Vector3.ZERO,Vector3.ONE),q._runtime_building_supports[id])
	for i:int in 24:
		q._priority=Vector3(i*4,0,i*2);q.pending[2301].published=i%2==0
		q.pending[i%100].published=i%3==0
		q._demand_scope={"ticket3":true,"ticket0":true} if i%3==0 else {}
		q.instance_errors={"row2300":"fixture"} if i%2==0 else {}
		compare_shared(q,"same IDs, winners, order, path queues and ranks with live publication/scope/errors "+str(i))
	var reverse:Dictionary={};var keys:Array=q._runtime_building_supports.row1.keys();keys.reverse()
	for id:String in keys:reverse[id]=true
	q.register_runtime_building("row1",AABB(Vector3.ONE,Vector3.ONE),reverse)
	check(q._runtime_support_order.row1==keys,"registered support fixture actually has reversed insertion order")
	compare_shared(q,"same support members in different insertion order preserve score ties")
	reverse["row2399"]=true
	q.register_runtime_building("row1",AABB(Vector3.ZERO,Vector3.ONE),reverse)
	compare_shared(q,"changed supporting geometry replaces the frozen ordered set")
	q._demand_scope={};q.instance_errors={}
	var trials:Array=[]
	for fast:bool in [false,true,true,false]:
		modes(fast);q._demand_membership.clear()
		var before:int=q.profile.get("support_candidate_visits",0);var kinds:int=q.profile.get("demand_kind_tests",0);var began:=Time.get_ticks_usec()
		for i:int in 24:q._priority=Vector3(i*4,0,i*2);q._demand_revision+=1;q._refresh_demanded()
		trials.append({"fast":fast,"us":Time.get_ticks_usec()-began,"support_visits":int(q.profile.support_candidate_visits)-before,"kind_tests":int(q.profile.demand_kind_tests)-kinds})
	check(trials[1].support_visits<trials[0].support_visits/10 and trials[1].kind_tests<trials[0].kind_tests/10,"shared supports and static membership filters are traversed at least ten times less")
	q.free();modes(true);OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	print("SHARED_SUPPORT_REFRESH ",JSON.stringify({"trials":trials,"failures":failed}));quit(1 if failed else 0)
