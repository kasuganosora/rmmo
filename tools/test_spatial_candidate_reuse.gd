extends "res://tools/test_deferred_typed_demand_scan.gd"
func same_rows(a:Array,b:Array)->bool:
	if a.size()!=b.size():return false
	for i:int in a.size():
		if not is_same(a[i],b[i]):return false
	return true
func run()->void:
	var q:=Deferred.new()
	for i:int in 4600:
		var row:=item("row%d"%i,0)
		row.bounds=AABB(Vector3((i%80)*16,0,(i/80)*16),Vector3(160,1,160));q.pending.append(row)
	q._index_pending()
	# Same UUID, different spatial owner. A successful lookup must not suppress
	# a later distinct alias, nor let an out-of-range alias replace that owner.
	var alias:=item("row0",0);q._large_pending.append(alias)
	var far_alias:=item("row1",9000);q._large_pending.append(far_alias)
	var clips:Array=[AABB(Vector3(128,0,128),Vector3(128,1,128)),AABB(Vector3.ZERO,Vector3(12,1,12)),AABB(Vector3.ZERO,Vector3(2000,1,2000)),AABB(Vector3(9000,0,0),Vector3.ZERO)]
	for clip:AABB in clips:
		Deferred.spatial_candidate_reuse_enabled=false;var old:=q._in_clip(clip)
		Deferred.spatial_candidate_reuse_enabled=true
		check(same_rows(old,q._in_clip(clip)),"exact owner/order for repeated cells, full scan and distinct duplicate UUIDs")
	q.pending[0].published=true
	Deferred.spatial_candidate_reuse_enabled=false;var old:=q._in_clip(clips[1])
	Deferred.spatial_candidate_reuse_enabled=true;check(same_rows(old,q._in_clip(clips[1])),"publication is read fresh on the next query")
	var trials:Array=[]
	for fast:bool in [false,true,true,false]:
		Deferred.spatial_candidate_reuse_enabled=fast;var prior:=int(q.profile.spatial_candidate_tests);var began:=Time.get_ticks_usec();var count:=0
		for i:int in 64:count+=q._in_clip(AABB(Vector3(i*8,0,i*5),Vector3(128,1,128))).size()
		trials.append({"reuse":fast,"elapsed_us":Time.get_ticks_usec()-began,"candidate_tests":q.profile.spatial_candidate_tests-prior,"matches":count})
	Deferred.spatial_candidate_reuse_enabled=true;q.free()
	print("SPATIAL_CANDIDATE_REUSE ",JSON.stringify(trials)," failures=",failed);quit(1 if failed else 0)
