extends "res://tools/test_deferred_backpressure.gd"
## Compare exact scheduling results with the retained full-scan control. The
## oracle includes ordering, path heads and ranks, not just set membership.
func snapshot(queue:Deferred)->Dictionary:
	var paths:Dictionary={};var first:Dictionary={};var ids:Array=[]
	for row:Dictionary in queue._demanded:ids.append(row.record.uuid)
	for path:String in queue._demanded_by_path:
		paths[path]=[]
		for row:Dictionary in queue._demanded_by_path[path]:paths[path].append(row.record.uuid)
	for path:String in queue._path_first:first[path]=queue._path_first[path].record.uuid
	return {"ids":ids,"paths":paths,"first":first,"rank":queue._demanded_rank.duplicate(),"priority":queue._demanded_priority.duplicate(),"dispatch":queue._dispatch_paths.duplicate()}

func compare(queue:Deferred,label:String)->Dictionary:
	Deferred.typed_demand_scan_enabled=false;queue._demand_revision+=1;queue._refresh_demanded()
	var expected:=snapshot(queue);var owners:Array=queue._demanded.duplicate()
	Deferred.typed_demand_scan_enabled=true;queue._demand_revision+=1;queue._refresh_demanded()
	var same:=expected==snapshot(queue)
	for i:int in mini(owners.size(),queue._demanded.size()):same=same and is_same(owners[i],queue._demanded[i])
	check(same,label)
	return expected

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var saved:=Deferred.typed_demand_scan_enabled
	contract_test();mixed_test()
	Deferred.typed_demand_scan_enabled=saved
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEFERRED_TYPED_DEMAND_SCAN passed=",passed," failures=",failed);quit(0 if failed==0 else 1)

func contract_test()->void:
	var queue:=Deferred.new()
	var building:=item("building",0);building.group_id="building:one"
	var road:=item("road",5);road.reference_entry={"reason":"native_road"}
	var hybrid:=item("hybrid",10);hybrid.reference_entry={"reason":"native_bridge"}
	var support:=item("support",8000)
	var hidden:=item("published",2);hidden.group_id="building:two";hidden.published=true
	var ordinary:=item("ordinary",3)
	queue.pending=[ordinary,building,road,hybrid,support,hidden]
	queue.register_runtime_building("hybrid",hybrid.bounds,{"support":true})
	queue._demands={"buildings":{"kind":"building","priority":2,"clip":AABB(Vector3(-100,-1,-100),Vector3(200,2,200))}}
	var state:=compare(queue,"building ticket preserves learned kind and out-of-clip support closure")
	check(state.ids==["support","building","hybrid"],"building kind excludes ordinary/road/published and promotes support priority")
	queue._demands={"roads":{"kind":"road","priority":2,"clip":AABB(Vector3(-100,-1,-100),Vector3(200,2,200))}}
	state=compare(queue,"road ticket keeps only its exact kind")
	check(state.ids==["road"],"road-only expected membership")
	queue._demands={"structures":{"kind":"structure","priority":2,"clip":AABB(Vector3(-100,-1,-100),Vector3(200,2,200))}}
	state=compare(queue,"a learned building can also satisfy its original structure kind")
	check(state.ids==["support","hybrid"],"hybrid kind retains the same support closure")
	queue._demands.group={"kind":"all","priority":-2,"group_id":"building:one","clip":AABB()}
	queue._demand_scope={"group":true}
	state=compare(queue,"group-scoped publication ignores unrelated typed tickets")
	check(state.ids==["building"],"group selection does not broaden its scope")
	queue._demand_scope={};queue._demands.structures.clip=AABB(Vector3(10,0,0),Vector3.ZERO)
	compare(queue,"zero-size inclusive boundary uses the existing local spatial query")
	queue.free()

func mixed_test()->void:
	var queue:=Deferred.new();var rng:=RandomNumberGenerator.new();rng.seed=981237
	for i:int in 2400:
		var row:=item("mixed%d"%i,rng.randf_range(-3000,3000),1,"path%d"%(i%23))
		row.bounds=AABB(Vector3(row.bounds.position.x,0,rng.randf_range(-3000,3000)),Vector3(400 if i%37==0 else 10,1,400 if i%37==0 else 10))
		if i%11==0:row.group_id="building:%d"%(i%5)
		row.reference_entry={"reason":["native_road","native_bridge","native_fortification","ordinary"][i%4]}
		if i%17==0:row.published=true
		queue.pending.append(row)
	queue._index_pending()
	# Same UUID in the large list and pending is normal. Also stress distinct
	# records sharing a UUID: spatial filtering must still precede deduplication.
	var duplicate:=item("mixed1",10000);duplicate.reference_entry={"reason":"native_road"}
	queue._large_pending.append(duplicate)
	for iteration:int in 48:
		var center:=Vector3(rng.randf_range(-1000,1000),0,rng.randf_range(-1000,1000))
		queue._priority=center
		queue._demands={}
		for kind:String in ["building","road","structure","all"]:
			var radius:float=32. if iteration%4==0 else 2200.
			queue._demands[kind]={"kind":kind,"priority":iteration%3,"clip":AABB(center-Vector3(radius,1,radius),Vector3(radius*2,2,radius*2))}
		queue._demands["group"]={"kind":"all","priority":-1,"group_id":"building:1","clip":AABB()}
		queue._demand_scope={"road":true,"structure":true} if iteration%3==0 else {}
		queue._runtime_building_records["mixed%d"%(iteration+1)]=AABB()
		queue._runtime_building_supports["mixed%d"%(iteration+1)]={"mixed2399":true}
		queue.pending[iteration+1].published=iteration%2==0
		queue.instance_errors={"mixed7":"test failure"}
		compare(queue,"mixed large/local/scoped/tied/late-kind/published path ordering %d"%iteration)
	check(int(queue.profile.get("typed_full_scan_tickets",0))>0,"mixed cases exercise the typed full-scan path")
	check(int(queue.profile.get("typed_full_scan_candidates",0))<int(queue.profile.get("typed_full_scan_unfiltered",0)),"typed tickets test fewer bounds than the original full scans")
	queue.free()
