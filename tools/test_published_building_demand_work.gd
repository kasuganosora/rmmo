extends "res://tools/test_deferred_typed_demand_scan.gd"
## Registering already resident geometry must not rebuild the pending scheduler.
func run()->void:
	var q:=Deferred.new()
	for i:int in 2400:
		var row:=item("row%d"%i,float(i%80)*8.,1,"path%d"%(i%37));row.bounds.position.z=float(i/80)*8.
		if i<100:row.group_id="building:%d"%i
		q.pending.append(row)
	q.set_demand("visible",AABB(Vector3(-1,-1,-1),Vector3(2000,3,2000)),1)
	q._refresh_demanded();var began:=Time.get_ticks_usec()
	for i:int in 100:
		var row:Dictionary=q._pending_by_record_id["row%d"%i]
		row.published=true;q._remove_published_demand([row])
		q.register_runtime_building(row.record.uuid,row.bounds,{"row2399":true})
		q._refresh_demanded()
	var elapsed:=Time.get_ticks_usec()-began
	check(q._runtime_building_records.size()==100 and q._runtime_building_supports.row0.has("row2399"),"resident bounds and support identity remain available for return loading")
	check(int(q.profile.demand_refreshes)==1,"one hundred completed buildings do not invalidate pending demand ranks")
	var before:=snapshot(q)
	q._demand_revision+=1;q._refresh_demanded();var rebuilt:=snapshot(q)
	for key:String in ["ids","paths","first","priority","dispatch"]:check(before[key]==rebuilt[key],"incremental publication matches full refresh: "+key)
	print("PUBLISHED_BUILDING_DEMAND elapsed_us=",elapsed," refreshes=",int(q.profile.demand_refreshes)-1)
	# Live pending learning still changes both kind eligibility and support order.
	q._demands.clear();q._demand_membership.clear()
	q.set_demand("buildings",AABB(Vector3(-1,-1,-1),Vector3(2000,3,2000)),1,"building")
	q._refresh_demanded();check(q._demanded.is_empty(),"all authored building components are already resident")
	var pending:Dictionary=q._pending_by_record_id.row100
	q.register_runtime_building("row100",pending.bounds,{"row2399":true});q._refresh_demanded()
	check(q._demanded.map(func(row):return row.record.uuid)==["row2399","row100"],"newly learned pending building promotes its exact support before itself")
	q.register_runtime_building("row100",pending.bounds,{"row2398":true});q._refresh_demanded()
	check(q._demanded.map(func(row):return row.record.uuid)==["row2398","row100"],"changed support on a pending building invalidates even with unchanged building count")
	q.free()
	print("PUBLISHED_BUILDING_DEMAND failures=",failed);quit(1 if failed else 0)
