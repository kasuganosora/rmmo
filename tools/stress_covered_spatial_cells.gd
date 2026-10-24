extends "res://tools/test_native_spatial_union.gd"
## Prototype first: keep encounter order, but use contained cells as a bounds proof.
const Stream=preload("res://scripts/world3d/world_stream.gd")
var contained_rows:=0
func select(q:Deferred,clip:AABB)->Array:
	q._index_pending()
	var low:=Stream.chunk_key(clip.position);var high:=Stream.chunk_key(clip.end)
	if q._pending_by_record_id.size()!=q.pending_count() or q._large_native_pending.size()!=q._large_pending.size() or (high.x-low.x+1)*(high.y-low.y+1)>q._pending_index.size():return q._in_clip(clip)
	var flat:=Rect2(Vector2(clip.position.x,clip.position.z),Vector2(clip.size.x,clip.size.z))
	var unique:Dictionary=q._large_native_pending.duplicate();var inside:Dictionary={}
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var cell:=Vector2i(x,z)
			if not q._pending_index.has(cell):continue
			var bucket:Dictionary=q._pending_native_index.get(cell,{})
			if bucket.size()!=q._pending_index[cell].size():return q._in_clip(clip)
			unique.merge(bucket,true)
			if float(x)*Stream.CHUNK_M>=flat.position.x and float(x+1)*Stream.CHUNK_M<=flat.end.x and float(z)*Stream.CHUNK_M>=flat.position.y and float(z+1)*Stream.CHUNK_M<=flat.end.y:inside.merge(bucket,true)
	var result:Array=[]
	for uuid:String in unique:
		var row:Dictionary=unique[uuid]
		if row.get("published",false):continue
		if inside.has(uuid):result.append(row);contained_rows+=1
		elif flat.intersects(row.demand_rect,true):result.append(row)
	return result
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var q:=Deferred.new()
	for i:int in 4600:
		var row:=item("row%d"%i,0,1,"path%d"%(i%37))
		var size_:float=[1.,16.,160.,400.][i%4]
		row.bounds=AABB(Vector3((i%80)*16-512,0,(i/80)*16-512),Vector3(size_,1,size_));q.pending.append(row)
	q._index_pending();var clips:Array=[]
	for i:int in 128:clips.append(AABB(Vector3(i*8-700,0,i*5-600),Vector3(384,1,384)))
	clips.append_array([AABB(Vector3.ZERO,Vector3.ZERO),AABB(Vector3(-32,0,-32),Vector3(32,1,32)),AABB(Vector3.ZERO,Vector3(3000,1,3000))])
	for clip:AABB in clips:check(same_rows(q._in_clip(clip),select(q,clip)),"covered cell preserves owner and order at "+str(clip.position))
	var trials:Array=[]
	for fast:bool in [false,true,true,false]:
		contained_rows=0;var began:=Time.get_ticks_usec();var count:=0
		for clip:AABB in clips:count+=(select(q,clip) if fast else q._in_clip(clip)).size()
		trials.append({"covered":fast,"us":Time.get_ticks_usec()-began,"matches":count,"covered_rows":contained_rows})
	check(trials[0].matches==trials[1].matches and trials[1].covered_rows>0,"same requested matches with fewer bounds tests")
	for i:int in 600:q.pending[i].published=true
	q._remove_published_demand(q.pending.slice(0,600))
	for clip:AABB in clips:check(same_rows(q._in_clip(clip),select(q,clip)),"publication remains live")
	var alias:=item("row900",9000);q._large_pending.append(alias)
	check(same_rows(q._in_clip(clips[64]),select(q,clips[64])),"noncanonical owner retains fallback")
	q.free();OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	print("COVERED_SPATIAL_STRESS ",JSON.stringify({"trials":trials,"failures":failed}));quit(1 if failed else 0)
