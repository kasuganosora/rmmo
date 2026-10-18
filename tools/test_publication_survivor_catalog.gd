extends "res://tools/test_deferred_typed_demand_scan.gd"
func queue_fixture()->Deferred:
	var queue:=Deferred.new()
	for i:int in 4600:queue.pending.append(item("source%d"%i,(i%80)*16.,1,"model%d"%(i%37)))
	queue.set_demand("all",AABB(Vector3(-1,-1,-1),Vector3(2000,4,2000)),1)
	queue._refresh_demanded();return queue
func ids(rows:Array)->Array:
	var result:Array=[]
	for row:Dictionary in rows:result.append(row.record.uuid)
	return result
func publish(queue:Deferred,ordered:bool,round_:int)->int:
	Deferred.ordered_publication_removal_enabled=ordered
	var rows:Array=[]
	for i:int in 8:rows.append(queue.pending[(round_*13+i*197)%queue.pending.size()])
	for row:Dictionary in rows:row.published=true
	var began:=Time.get_ticks_usec();queue._remove_published_demand(rows)
	return Time.get_ticks_usec()-began
func run()->void:
	var trials:Array=[]
	for order:Array in [[false,true],[true,false]]:
		var queues:Array=[queue_fixture(),queue_fixture()];var times:Array=[0,0]
		var before:Array=queues[0].pending
		for round_:int in 64:
			for i:int in 2:times[i]+=publish(queues[i],order[i],round_)
			check(ids(queues[0].pending)==ids(queues[1].pending) and snapshot(queues[0])==snapshot(queues[1]),"exact survivor, demand, path-head and dispatch order round %d"%round_)
		check(before.size()==4600 and not is_same(before,queues[0].pending),"publication leaves outstanding array snapshots intact")
		for i:int in 2:
			var q:Deferred=queues[i]
			check(q.pending.size()==4088 and q._pending_by_record_id.size()==4088,"all 512 published members leave both catalogs")
			for row:Dictionary in q.pending:
				if not is_same(row,q._pending_by_record_id[row.record.uuid]):check(false,"survivor identity");break
			trials.append({"ordered":order[i],"elapsed_us":times[i],"scanned_rows":q.profile.publication_survivor_scan_rows})
			q.free()
	Deferred.ordered_publication_removal_enabled=true
	print("PUBLICATION_SURVIVOR_CATALOG ",JSON.stringify(trials)," failures=",failed);quit(1 if failed else 0)
