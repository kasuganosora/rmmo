extends "res://tools/test_parallel_retirement_schema.gd"
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Preparation=preload("res://scripts/world3d/retirement_schema_preparation.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
func setup()->Dictionary:
	var f:=fixture();var private_mesh:=BoxMesh.new()
	for i:int in 2200:f.library[i].mesh=private_mesh
	f.watch=weakref(private_mesh)
	f.data=Index.build(f.library)
	var map:=Node3D.new();root.add_child(map)
	for key:String in f.data:map.set_meta(key,f.data[key])
	map.set_meta("stream_library",f.library);map.set_meta("stream_chunk",Vector2i.ZERO)
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new();map.add_child(nav)
	nav.configure_streaming_geometry(func(_clip:AABB):return {"ok":true,"error":""})
	nav.map=NavigationServer3D.map_create();nav.ready_for_queries=true;nav.set_process(false)
	check(nav.append_specs(f.library).ok,"navigation owns all 4600 source identities")
	f.map=map;f.nav=nav;return f
func prepare(f:Dictionary)->void:
	var result:=Stream.retire_specs(f.map,f.ids,true,f.nav,"native_retirement")
	check(not result.ok and result.error=="retirement_schema_pending","large runtime retirement schedules private preparation")
	check(f.library.size()==4600 and f.nav._specs.size()==4600,"pending preparation makes no index or navigation writes")
	var prep:RefCounted=f.map.get_meta("retirement_schema_preparation")
	var frames:=0
	while not prep.complete and prep.error.is_empty() and frames<1000:
		await process_frame;Stream.advance_retirement_preparation(f.map);frames+=1
	check(prep.complete and frames>1 and frames<1000,"preparation advances through shared frame-budget slices")
	check(f.library.size()==4600 and f.nav._specs.size()==4600,"all yielded preparation slices preserve resident ownership")
	await process_frame
func drain()->void:
	var service:Node=root.get_node_or_null(Retirement.NODE_NAME)
	if service==null:return
	service.set_process(false)
	var count:=0
	while not service.pending.is_empty() and count<10000:
		if service._advance(service.pending[0],1000):service._finish_front()
		count+=1
	check(service.pending.is_empty(),"all private snapshot retirement tickets drain")
func run()->void:
	var f:=setup();await prepare(f)
	var prep:RefCounted=f.map.get_meta("retirement_schema_preparation")
	Trace.start();var result:=Stream.retire_specs(f.map,f.ids,true,f.nav,"native_retirement");var trace:=Trace.stop()
	var scans:=0
	for row:Dictionary in trace.stats:
		if row.label=="stream.retirement_schema_slice":scans+=row.count
	check(result.ok and result.removed==2200 and scans==0,"fresh prepared commit performs no synchronous schema worker scan")
	check(f.library.size()==2400 and f.nav._spec_ids.size()==2400 and f.nav._specs.size()==2400,"atomic commit removes the same complete index and navigation sources")
	check(prep.valid_for(f.library,f.map.get_meta("stream_by_id")),"surviving proof stays reusable after the exact committed removal")
	drain();check(f.watch.get_ref()==null,"removed mesh is released while the surviving proof remains alive")
	# Ordinary retirement also removes private ownership, keeping valid survivors.
	f.map.set_meta("stream_chunk",Vector2i(-100,-100))
	result=Stream.retire_specs(f.map,["keep0"],false,f.nav)
	check(result.ok and prep.valid_for(f.library,f.map.get_meta("stream_by_id")) and not prep.seen.has("keep0"),"ordinary removal compacts the prepared owner and preserves the exact survivor proof")
	prep=null;f.map.free();f={};drain();await process_frame
	f=setup();await prepare(f)
	# A resumed player/source pin is checked again after every preparation yield.
	f.map.set_meta("stream_chunk",Vector2i(50,50))
	result=Stream.retire_specs(f.map,f.ids,true,f.nav,"native_retirement")
	check(not result.ok and result.error=="source_pinned" and f.library.size()==4600 and f.nav._specs.size()==4600,"returning into the prepared unit cancels retirement without losing any source")
	f.map.set_meta("stream_chunk",Vector2i.ZERO);await process_frame
	f.library[-1].extras=17
	result=Stream.retire_specs(f.map,f.ids,true,f.nav,"native_retirement")
	check(not result.ok and result.error=="retirement_schema_pending" and f.library.size()==4600,"late surviving mutation invalidates the fresh commit proof")
	prep=f.map.get_meta("retirement_schema_preparation")
	while not prep.advance(1000):pass
	await process_frame;result=Stream.retire_specs(f.map,f.ids,true,f.nav,"native_retirement")
	check(not result.ok and result.error=="library/index identity mismatch" and f.nav._specs.size()==4600,"revalidated malformed survivor rejects before navigation consent")
	prep=null;f.map.free();f={};drain();await process_frame
	f=setup();result=Stream.retire_specs(f.map,f.ids,true,f.nav,"native_retirement")
	check(not result.ok,"map exit starts with a pending private cursor")
	var watch:WeakRef=f.watch;f.map.free();f={};drain()
	check(watch.get_ref()==null,"map exit releases cancelled partial snapshot and source owners")
	await process_frame;f=setup()
	result=Stream.retire_specs(f.map,f.ids,true,f.nav,"native_retirement")
	prep=f.map.get_meta("retirement_schema_preparation")
	prep.advance(1);var cursor:int=prep.cursor
	f.map.set_meta("stream_chunk",Vector2i(-100,-100))
	result=Stream.retire_specs(f.map,["keep2399"],false,f.nav)
	check(result.ok and is_same(prep,f.map.get_meta("retirement_schema_preparation")) and prep.cursor==cursor,"small ordinary removal preserves the same pending native cursor")
	while not prep.advance(1000):pass
	check(prep.valid_for(f.library,f.map.get_meta("stream_by_id")) and prep.profile.rows==4599,"mixed ownership removal completes once without repeating validated work")
	prep=null;f.map.free();f={};drain()
	print("SLICED_NATIVE_RETIREMENT checks=",checks," failures=",failures);quit(1 if failures else 0)
