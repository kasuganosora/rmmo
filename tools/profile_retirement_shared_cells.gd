extends "res://tools/test_stream_index_retire.gd"
const CONTROL:="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/stream_index_before_bucket_dedup.gd"
func run()->void:
	var old:Script=load(CONTROL)
	var library:Array=[];var ids:Array=[]
	for i:int in 2151:
		var record:Dictionary={"kind":"asset","building":{"id":"group%d"%(i%156)}}
		var item:=spec("guild__part%d"%i,Vector2i(12,8),Vector2i(12,8),record)
		library.append(item);ids.append(item.uuid)
	for i:int in 2500:library.append(spec("keep%d"%i,Vector2i(30+i%32,30),Vector2i(30+i%32,30),{"kind":"asset"}))
	var data:=Index.build(library);var before:=data.duplicate(true)
	var timings:Dictionary={"before":[],"after":[]}
	for round_:int in 12:
		for label:String in (["before","after"] if round_%2==0 else ["after","before"]):
			var began:=Time.get_ticks_usec()
			var result:Dictionary=old.validate_owned_retire(data,library,ids) if label=="before" else Index.validate_owned_retire(data,library,ids)
			timings[label].append((Time.get_ticks_usec()-began)/1000.)
			check(result.ok and result.removed==2151,label+": complete shared-cell namespace remains valid")
	check(data==before,"all complete validations preserve every caller-owned index")
	var cell:=Vector2i(12,8)
	for field:String in ["stream_index","stream_prop_index","stream_collision_index"]:
		var bucket:Variant=data[field].get(cell)
		data[field][cell]=false
		check(not old.validate_owned_retire(data,library,ids).ok and not Index.validate_owned_retire(data,library,ids).ok,"new transaction rechecks corrupted "+field+" despite an earlier successful call")
		if bucket==null:data[field].erase(cell)
		else:data[field][cell]=bucket
	var grouped:Variant=data.stream_append_state.group_cells[cell]
	data.stream_append_state.group_cells[cell]=false
	check(not Index.validate_owned_retire(data,library,ids).ok,"shared group cells retain complete bucket validation")
	data.stream_append_state.group_cells[cell]=grouped
	for label:String in timings:
		var values:Array=timings[label];values.sort();var total:=0.
		for value:float in values:total+=value
		print("SHARED_CELL_VALIDATION ",label," mean_ms=",total/values.size()," p50_ms=",values[values.size()/2]," min_ms=",values[0]," max_ms=",values[-1])
	print("SHARED_CELL_BUCKET_CHECKS spatial=",ids.size()*3,"->3 group=156->1; full_spec_checks=",library.size()," unchanged")
	print("RETIREMENT_SHARED_CELLS checks=",checks," failures=",failures);quit(1 if failures else 0)
