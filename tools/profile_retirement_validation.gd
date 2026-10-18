extends "res://tools/test_stream_index_retire.gd"
func run()->void:
	var old:Script=load("D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/stream_index_before_validation_alloc.gd")
	var library:Array=[];var ids:Array=[]
	for i:int in 6000:
		var record:Dictionary={"kind":"box"}
		if i<4800:record.building={"id":"house%d"%(i/12),"part":str(i),"role":"wall","floor":0}
		var item:=spec("source%d"%i,Vector2i(i/12,0),Vector2i(i/12,0),record)
		library.append(item)
		if i<12:ids.append(item.uuid)
	var data:=Index.build(library);var timings:Dictionary={"before":[],"after":[]}
	for round_:int in 20:
		for label:String in (["before","after"] if round_%2==0 else ["after","before"]):
			var start:=Time.get_ticks_usec()
			var result:Dictionary=old.validate_owned_retire(data,library,ids) if label=="before" else Index.validate_owned_retire(data,library,ids)
			timings[label].append((Time.get_ticks_usec()-start)/1000.)
			if not result.ok:push_error(str(result));quit(1);return
	for label:String in timings:
		var values:Array=timings[label];values.sort();var sum_:float=0
		for value:float in values:sum_+=value
		print("RETIREMENT_VALIDATION ",label," count=",values.size()," mean_ms=",sum_/values.size()," p50_ms=",values[values.size()/2]," min_ms=",values[0]," max_ms=",values[-1])
	quit(0)
