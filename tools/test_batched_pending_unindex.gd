extends "res://tools/test_deferred_typed_demand_scan.gd"
func queue_fixture()->Deferred:
	var q:=Deferred.new()
	for i:int in 512:
		var row:=item("row%d"%i,0,1,"path%d"%(i%37))
		row.bounds=AABB(Vector3.ZERO,Vector3(320 if i>=507 else 160,1,320 if i>=507 else 160));q.pending.append(row)
	q.set_demand("all",AABB(Vector3(-1,-1,-1),Vector3(1000,4,1000)),1);q._refresh_demanded();return q
func ids(rows:Array)->Array:
	var result:Array=[]
	for row:Dictionary in rows:result.append(row.record.uuid)
	return result
func publish(q:Deferred,batched:bool,duplicate_request:bool=false)->Dictionary:
	var rows:Array=[]
	for i:int in 50:rows.append(q.pending[27+i*7])
	rows.append(q.pending[-1])
	var cell:Vector2i=q._pending_index.keys()[0];var bucket:Array=q._pending_index[cell]
	var alias:Dictionary=rows[0].duplicate(true);alias.test_alias=true;bucket.push_front(alias)
	# A borrowed occurrence in a different bucket is not an ownership edge
	# selected by that member's own bounds (this member lives in large_pending).
	var foreign:Dictionary=rows[-1];bucket.insert(1,foreign)
	bucket.append(rows[0]);bucket.append(rows[0])
	var owner:Dictionary=rows[0]
	if duplicate_request:rows.append(owner)
	for row:Dictionary in rows:row.published=true
	Deferred.batched_pending_unindex_enabled=batched
	var began:=Time.get_ticks_usec();q._remove_published_demand(rows);var elapsed:=Time.get_ticks_usec()-began
	check(is_same(bucket,q._pending_index[cell]) and is_same(bucket[0],alias),"bucket container and distinct duplicate-UUID owner survive")
	check(is_same(bucket[1],foreign),"a foreign borrowed owner outside its indexed bucket selection survives")
	var expected:=1 if duplicate_request else 2;var copies:=0
	for row:Dictionary in bucket:
		if is_same(row,owner):copies+=1
	check(copies==expected,"only the requested number of exact object aliases is erased")
	return {"batched":batched,"elapsed_us":elapsed,"filtered_rows":q.profile.get("pending_bucket_filter_rows",0),"filter_calls":q.profile.get("pending_bucket_filters",0),"native_tail_rows":q.profile.get("pending_bucket_tail_rows",0)}
func same_index(a:Deferred,b:Deferred)->bool:
	if a._pending_index.keys()!=b._pending_index.keys() or ids(a._large_pending)!=ids(b._large_pending):return false
	for key:Vector2i in a._pending_index:
		if a._pending_index[key]!=b._pending_index[key]:return false
	return a._pending_by_record_id.keys()==b._pending_by_record_id.keys() and ids(a.pending)==ids(b.pending) and snapshot(a)==snapshot(b)
func run()->void:
	var trials:Array=[]
	for order:Array in [[false,true],[true,false]]:
		var a:=queue_fixture();var b:=queue_fixture()
		trials.append(publish(a,order[0]));trials.append(publish(b,order[1]))
		check(same_index(a,b),"bulk publication keeps every spatial bucket, owner, demand rank and path head identical")
		check(a.pending.size()==461 and b.pending.size()==461,"all 51 ordinary/large members leave the queue")
		a.free();b.free()
	var a:=queue_fixture();var b:=queue_fixture();publish(a,false,true);publish(b,true,true)
	check(same_index(a,b),"duplicate requests retain the original per-object removal semantics")
	a.free();b.free();a=queue_fixture();b=queue_fixture()
	a._pending_by_record_id.erase("row0");b._pending_by_record_id.erase("row0")
	publish(a,false);publish(b,true)
	check(same_index(a,b),"incomplete private catalog safely uses original removal")
	a.free();b.free();Deferred.batched_pending_unindex_enabled=true
	print("BATCHED_PENDING_UNINDEX ",JSON.stringify(trials)," failures=",failed);quit(1 if failed else 0)
