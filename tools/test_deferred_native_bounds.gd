extends "res://tools/test_deferred_typed_demand_scan.gd"
func same_rows(a:Array,b:Array)->bool:
	if a.size()!=b.size():return false
	for i:int in a.size():
		if not is_same(a[i],b[i]):return false
	return true
func run()->void:
	var queue:=Deferred.new();var rng:=RandomNumberGenerator.new();rng.seed=98131
	Deferred.demand_membership_cache_enabled=false
	for i:int in 4600:
		var value:=item("flat%d"%i,rng.randf_range(-1600,1600))
		value.bounds=AABB(Vector3(value.bounds.position.x,-20,rng.randf_range(-1600,1600)),Vector3(320 if i%29==0 else 12,100,320 if i%29==0 else 12))
		value.reference_entry={"reason":["native_road","native_bridge","ordinary"][i%3]}
		if i%9==0:value.group_id="building:flat"
		queue.pending.append(value)
	queue._index_pending()
	var duplicate:=item("flat1",10000);queue._large_pending.append(duplicate)
	var boundary:=item("boundary",0);boundary.bounds=AABB(Vector3.ZERO,Vector3(10,1,10))
	queue._large_pending.append(boundary)
	for i:int in 32:
		var center:=Vector3(rng.randf_range(-800,800),0,rng.randf_range(-800,800))
		var radius:float=[0.,16.,128.,2000.][i%4]
		var clip:=AABB(center-Vector3(radius,10000,radius),Vector3(radius*2,20000,radius*2))
		if i==0:clip=AABB(Vector3(10,1000,10),Vector3.ZERO)
		queue.pending[i].published=i%2==0
		Deferred.native_demand_bounds_enabled=false;var old:=queue._in_clip(clip);var was_pending:=queue._has_pending_in_clip(clip)
		Deferred.native_demand_bounds_enabled=true
		check(same_rows(old,queue._in_clip(clip)) and was_pending==queue._has_pending_in_clip(clip),"flat native bounds preserve inclusive X/Z edges, exact owner/order and live publication %d"%i)
		queue.set_demand("road",clip,2,"road");queue.set_demand("building",clip,2,"building")
		Deferred.native_demand_bounds_enabled=false;queue._demand_revision+=1;queue._refresh_demanded();var control:=snapshot(queue)
		Deferred.native_demand_bounds_enabled=true;queue._demand_revision+=1;queue._refresh_demanded()
		check(snapshot(queue)==control,"typed and spatial scheduling have the same exact native/legacy result %d"%i)
	var trials:Array=[]
	for enabled:bool in [false,true,true,false]:
		Deferred.native_demand_bounds_enabled=enabled;var began:=Time.get_ticks_usec();var rows:=0
		for i:int in 160:rows+=queue._in_clip(AABB(Vector3(i*8-640,-1,i*6-480),Vector3(256,2,256))).size()
		trials.append({"native":enabled,"queries":160,"rows":rows,"elapsed_us":Time.get_ticks_usec()-began})
	print("DEFERRED_NATIVE_BOUNDS ",JSON.stringify({"sources":4600,"trials":trials}))
	queue.free();print("DEFERRED_NATIVE_BOUNDS passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
