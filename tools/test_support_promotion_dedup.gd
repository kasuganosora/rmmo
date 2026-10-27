extends "res://tools/test_deferred_typed_demand_scan.gd"
func make_queue()->Deferred:
	var q:=Deferred.new()
	for i:int in 2400:
		var row:=item("row%d"%i,float(i%80)*8.,1,"path%d"%(i%37));row.bounds.position.z=float(i/80)*8.
		if i<100:row.group_id="building:%d"%i
		if i%3==0:row.reference_entry={"reason":"native_road"}
		q.pending.append(row)
	var supports:Dictionary={"missing":true}
	for i:int in 64:supports["row%d"%(2300+i)]=true
	for i:int in 100:q._runtime_building_supports["row%d"%i]=supports.duplicate()
	for i:int in 5:q.set_demand("ticket%d"%i,AABB(Vector3(-1,-1,-1),Vector3(2000,3,2000)),4-i,"building" if i%2==0 else "all",i%3!=0)
	return q
func compare_modes(q:Deferred,label:String)->void:
	Deferred.support_promotion_dedup_enabled=false;q._demand_revision+=1;q._refresh_demanded()
	var old:=snapshot(q);var owners:Array=q._demanded.duplicate()
	Deferred.support_promotion_dedup_enabled=true;q._demand_revision+=1;q._refresh_demanded()
	var same:=old==snapshot(q)
	for i:int in owners.size():same=same and is_same(owners[i],q._demanded[i])
	check(same,label)

func support_order_contract()->void:
	var q:=Deferred.new()
	var building:=item("building",0);var empty:=item("empty",1);var support:=item("support",1000)
	q.pending=[building,empty,support]
	q._runtime_building_supports={"building":{"support":true},"empty":{}}
	var bounds:=AABB(Vector3(-2,-1,-2),Vector3(10,3,10))
	q._demands={"weak":{"kind":"all","priority":6,"clip":bounds},"strong":{"kind":"all","priority":2,"clip":bounds}}
	q._demand_revision+=1;q._refresh_demanded()
	check(q._demanded_priority.get("support")==1 and q._demanded_priority.get("building")==2,"stronger overlapping ticket promotes the shared support before its building")
	check(q._demanded_by_id.has("empty") and is_same(q._demanded_by_id.empty,empty),"registered empty support set keeps its original demanded owner")
	var ids:Array=[]
	for row:Dictionary in q._demanded:ids.append(row.record.uuid)
	check(ids==["support","empty","building"],"support promotion preserves exact priority and distance-based output order")
	q._demands.strong.priority=7;q._demand_revision+=1;q._refresh_demanded()
	check(q._demanded_priority.get("support")==5 and q._demanded_priority.get("building")==6,"weaker later ticket does not demote the earlier shared support")
	support.published=true;q._demand_revision+=1;q._refresh_demanded()
	check(not q._demanded_by_id.has("support") and q._demanded_by_id.has("building"),"published support is not rescheduled while its parent remains demanded")
	q.free()

func run()->void:
	var q:=make_queue();var logger:=Errors.new();OS.add_logger(logger)
	support_order_contract()
	q._runtime_building_supports["row150"]={}
	for i:int in 16:
		q._priority=Vector3(i*4,0,i*8);q.pending[2301].published=i%2==0
		q._demands.ticket0.priority=(i%5)-2;q._demands.ticket1.priority=2-(i%5)
		q._demand_scope={"ticket3":true,"ticket0":true} if i%3==0 else {}
		q.instance_errors={"row2300":"fixture"} if i%2==0 else {}
		compare_modes(q,"exact owner/order/path/rank with overlapping supports and changing priority/scope/publication %d"%i)
	# The support owner differs from an explicit spatial winner with the same UUID.
	var alias:Dictionary=q.pending[2300].duplicate(true);alias.bounds.position=Vector3(-500,0,-500)
	q._large_pending.append(alias);q._demand_membership.clear()
	compare_modes(q,"same UUID with different owners retains the original score winner")
	q._demand_scope={};q.pending[2301].published=false;q._demand_membership.clear()
	var reports:Array=[]
	for fast:bool in [false,true,true,false]:
		Deferred.support_promotion_dedup_enabled=fast
		var before_visits:int=q.profile.get("support_candidate_visits",0);var before_promotions:int=q.profile.get("support_promotions",0)
		var started:=Time.get_ticks_usec()
		for i:int in 24:q._priority=Vector3(i*4,0,i*2);q._demand_revision+=1;q._refresh_demanded()
		reports.append({"deduplicated":fast,"us":Time.get_ticks_usec()-started,"visits":int(q.profile.support_candidate_visits)-before_visits,"promotions":int(q.profile.support_promotions)-before_promotions})
	check(reports[0].visits==reports[1].visits and reports[1].promotions<reports[0].promotions/50,"same support closure visits, at least fifty times fewer owner/score promotions")
	Deferred.support_promotion_dedup_enabled=true;q.free();OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero script/engine errors")
	print("SUPPORT_PROMOTION_DEDUP ",JSON.stringify({"trials":reports,"failures":failed}));quit(1 if failed else 0)
