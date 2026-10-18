extends "res://tools/test_stream_index_retire.gd"
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const CONTROL:="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/world_stream_before_pin_dedup.gd"
func traced(script:Script,map:Node,ids:Array)->Dictionary:
	Trace.methods_enabled=true
	Trace.method_labels={"method.world_stream._draws":true,"method.world_stream._overlaps":true}
	Trace.start()
	var result:Dictionary=script.can_retire_specs(map,ids,true)
	var trace:Dictionary=Trace.stop();Trace.methods_enabled=false;Trace.method_labels.clear()
	var counts:Dictionary={}
	for row:Dictionary in trace.stats:counts[row.label]=row.count
	return {"result":result,"counts":counts}
func run()->void:
	var control:Script=load(CONTROL) if FileAccess.file_exists(CONTROL) else Stream
	var library:Array=[];var ids:Array=[];var shared:=BoxMesh.new()
	for i:int in 2151:
		var item:=spec("guild__part%d"%i,Vector2i(100,100),Vector2i(100,100),{"kind":"asset","building":{"id":"group%d"%(i%156)}})
		item.mesh=shared;library.append(item);ids.append(item.uuid)
	for i:int in 2500:
		var item:=spec("keep%d"%i,Vector2i.ZERO,Vector2i.ZERO,{"kind":"asset"});item.mesh=shared;library.append(item)
	var data:=Index.build(library);var map:=Node3D.new();root.add_child(map)
	for key:String in data:map.set_meta(key,data[key])
	map.set_meta("stream_library",library);map.set_meta("stream_chunk",Vector2i.ZERO)
	var old:=traced(control,map,ids);var improved:=traced(Stream,map,ids)
	check(old.result==improved.result and improved.result.ok,"complete 2151-part namespace keeps the authoritative retirement decision")
	check(improved.counts.get("method.world_stream._draws")==156 and improved.counts.get("method.world_stream._overlaps")==157,"interleaved groups check 156 actual render owners and one collision envelope")
	print("RETIREMENT_PIN_WORK old=",old.counts," new=",improved.counts)
	var before:=data.duplicate(true);var original:=library.duplicate()
	var a:Dictionary=library[0];var b:Dictionary=library[156]
	var saved:Variant=b.render_bounds
	b.render_bounds={"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO}
	check(not Stream.can_retire_specs(map,ids,true).ok,"equal group label with a different mutable render owner cannot reuse an earlier answer")
	b.render_bounds=saved
	b.render_dependents=[{"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO}]
	check(not Stream.can_retire_specs(map,ids,true).ok,"same bounds with distinct dependent envelopes must be checked separately")
	b.erase("render_dependents")
	b.chunk_min=Vector2i.ZERO;b.chunk_max=Vector2i.ZERO
	check(not Stream.can_retire_specs(map,ids,true).ok,"collision envelope remains independently pinned even with a distant shared render owner")
	b.chunk_min=Vector2i(100,100);b.chunk_max=Vector2i(100,100)
	map.set_meta("stream_chunk",Vector2i(100,100))
	check(not Stream.can_retire_specs(map,ids,true).ok,"a later transaction always rechecks the current camera ring")
	map.set_meta("stream_chunk",Vector2i.ZERO)
	var saved_mesh:Mesh=a.mesh;a.mesh=null
	check(not Stream.can_retire_specs(map,ids,true).ok,"full source schema still rejects a malformed selected member")
	a.mesh=saved_mesh
	var keep:Dictionary=library[-1];keep.mesh=null
	check(not Stream.can_retire_specs(map,ids,true).ok,"full source schema still rejects a malformed surviving member")
	keep.mesh=shared
	check(data==before and library==original,"all pin checks and refusals leave the complete index and source identities unchanged")
	var times:Dictionary={"before":[],"after":[]}
	for round_:int in 12:
		for label:String in (["before","after"] if round_%2==0 else ["after","before"]):
			var started:=Time.get_ticks_usec()
			var result:Dictionary=control.can_retire_specs(map,ids,true) if label=="before" else Stream.can_retire_specs(map,ids,true)
			times[label].append((Time.get_ticks_usec()-started)/1000.)
			check(result.ok,label+" keeps complete validation in every independent transaction")
	for label:String in times:
		var values:Array=times[label];values.sort();var total:=0.
		for value:float in values:total+=value
		print("RETIREMENT_PIN_TIMING ",label," mean_ms=",total/values.size()," p50_ms=",values[values.size()/2]," max_ms=",values[-1])
	map.free();library.clear();data.clear()
	print("RETIREMENT_PIN_CHECKS checks=",checks," failures=",failures);quit(1 if failures else 0)
