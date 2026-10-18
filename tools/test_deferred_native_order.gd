extends "res://tools/test_deferred_typed_demand_scan.gd"
func run()->void:
	var queue:=Deferred.new()
	for i:int in 4600:
		var value:=item("order%d"%i,float((i*37)%1700),1,"path%d"%(i%41))
		if i%11==0:value.group_id="building:test"
		queue.pending.append(value)
	queue.set_demand("player",AABB(Vector3(-1,-1,-1),Vector3(2000,3,3)),0)
	queue.set_demand("prefetch",AABB(Vector3(400,-1,-1),Vector3(500,3,3)),2,"building",true)
	queue.instance_errors={"order7":"intentional"}
	for turn:int in 12:
		queue._priority=Vector3(turn*8,0,0)
		Deferred.native_demand_order_enabled=false;queue._demand_revision+=1;queue._refresh_demanded()
		var control:=snapshot(queue);var owners:=queue._demanded.duplicate()
		Deferred.native_demand_order_enabled=true;queue._demand_revision+=1;queue._refresh_demanded()
		var same:=snapshot(queue)==control
		for i:int in owners.size():same=same and is_same(owners[i],queue._demanded[i])
		check(same,"native lexicographic ordering preserves precise float scores, stable ties and exact owners %d"%turn)
	var trials:Array=[]
	for enabled:bool in [false,true,true,false]:
		Deferred.native_demand_order_enabled=enabled;var began:=Time.get_ticks_usec()
		for turn:int in 20:queue._priority=Vector3(turn*8,0,0);queue._demand_revision+=1;queue._refresh_demanded()
		trials.append({"native":enabled,"refreshes":20,"elapsed_us":Time.get_ticks_usec()-began})
	print("DEFERRED_NATIVE_ORDER ",JSON.stringify({"rows":4600,"trials":trials}))
	queue.free();print("DEFERRED_NATIVE_ORDER passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
