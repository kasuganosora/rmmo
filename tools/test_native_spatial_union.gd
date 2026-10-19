extends "res://tools/test_spatial_candidate_reuse.gd"
func compare_union(q:Deferred,clip:AABB,label:String)->void:
	Deferred.native_spatial_union_enabled=false;var expected:=q._in_clip(clip)
	Deferred.native_spatial_union_enabled=true;check(same_rows(expected,q._in_clip(clip)),label)
func run()->void:
	var q:=Deferred.new()
	for i:int in 4600:
		var row:=item("row%d"%i,0,1,"path%d"%(i%37))
		row.bounds=AABB(Vector3((i%80)*16,0,(i/80)*16),Vector3(160,1,160));q.pending.append(row)
	q._index_pending();var clips:Array=[]
	for i:int in 64:clips.append(AABB(Vector3(i*8,0,i*5),Vector3(128,1,128)))
	for clip:AABB in clips:compare_union(q,clip,"native union retains exact cell encounter order and row identities")
	var trials:Array=[]
	for fast:bool in [false,true,true,false]:
		Deferred.native_spatial_union_enabled=fast
		var previous:int=q.profile.get("spatial_script_rows",0);var began:=Time.get_ticks_usec();var count:=0
		for clip:AABB in clips:count+=q._in_clip(clip).size()
		trials.append({"native":fast,"us":Time.get_ticks_usec()-began,"script_rows":int(q.profile.spatial_script_rows)-previous,"matches":count})
	check(trials[0].matches==trials[1].matches and trials[1].script_rows<trials[0].script_rows/5,"same spatial matches with at least five times fewer interpreted rows")
	q.set_demand("all",AABB(Vector3(-1,-1,-1),Vector3(3000,3,3000)));q._refresh_demanded()
	var retired:Array=q.pending.slice(0,51)
	for row:Dictionary in retired:row.published=true
	q._remove_published_demand(retired)
	compare_union(q,clips[0],"batch publication updates both spatial views")
	var row:Dictionary=q.pending[0];q._unindex_pending_item(row);q.pending.erase(row);q._index_pending_item(row);q.pending.append(row)
	compare_union(q,clips[0],"requeue preserves tail ordering in native buckets")
	var alias:=item("row52",9000);q._large_pending.append(alias)
	compare_union(q,clips[0],"foreign UUID alias uses original filter-before-deduplication semantics")
	q._large_pending.clear()
	var cell:Vector2i=q._pending_index.keys()[0];q._pending_index[cell].append(row)
	compare_union(q,AABB(Vector3.ZERO,Vector3(32,1,32)),"non-canonical borrowed bucket falls back safely")
	Deferred.native_spatial_union_enabled=true;q.free()
	print("NATIVE_SPATIAL_UNION ",JSON.stringify({"trials":trials,"failures":failed}));quit(1 if failed else 0)
