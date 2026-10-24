extends "res://tools/test_deferred_typed_demand_scan.gd"
func compare(queue:Deferred,label:String)->Dictionary:
	Deferred.reuse_typed_demand_filter_enabled=false
	var expected:=super.compare(queue,label)
	Deferred.reuse_typed_demand_filter_enabled=true;queue._demand_revision+=1;queue._refresh_demanded()
	check(expected==snapshot(queue),"typed filter reuse: "+label)
	return expected

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	Deferred.demand_membership_cache_enabled=false;contract_test();mixed_test()
	Deferred.demand_membership_cache_enabled=true
	var q:=Deferred.new()
	for i:int in 2048:
		var row:=item("road%d"%i,i%100);row.reference_entry={"reason":"native_road"};q.pending.append(row)
	q.set_demand("roads",AABB(Vector3(-1000,-1,-1000),Vector3(2000,2,2000)),1,"road")
	q._refresh_demanded();var first:=snapshot(q)
	check(first.ids.size()==2048 and int(q.profile.get("demand_kind_tests",0))==0,"already partitioned 2048 roads receive no duplicate kind tests")
	q._demand_revision+=1;q._refresh_demanded()
	check(snapshot(q)==first,"first typed scan populates the subsequent cached membership")
	q.pending[0].published=true;q._demand_revision+=1;q._refresh_demanded()
	check(q._demanded_count()==2047 and not q._demanded_by_id.has("road0"),"cached membership still observes live publication")
	q.free();OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	print("TYPED_FILTER_REUSE failures=",failed);quit(1 if failed else 0)
