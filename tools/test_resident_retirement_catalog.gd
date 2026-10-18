extends "res://tools/test_sliced_native_retirement.gd"
func run()->void:
	Stream.resident_retirement_catalog_enabled=true
	catalog_contract()
	var f:=setup()
	check(f.data.stream_append_state.namespace_sizes.guild==2200,"build records complete namespace count once")
	var rejected:=Index._owned_retire_plan(f.data,f.library,f.ids.slice(1),true,null,true)
	check(not rejected.ok and rejected.error=="split namespace" and f.library.size()==4600,"incremental count rejects incomplete unload without mutation")
	f.map.set_meta("stream_chunk",Vector2i(50,50))
	var result:=Stream.retire_specs(f.map,f.ids,true,f.nav,"native_retirement")
	check(not result.ok and result.error=="source_pinned" and f.nav._specs.size()==4600,"live render/collision protection remains authoritative")
	f.map.set_meta("stream_chunk",Vector2i.ZERO)
	var previous_frame:=Engine.get_process_frames()
	while Engine.get_process_frames()==previous_frame:await process_frame
	Trace.methods_enabled=true;Trace.method_labels={"method.spec_snapshot_validation.slice":true};Trace.start()
	var began:=Time.get_ticks_usec();result=Stream.retire_specs(f.map,f.ids,true,f.nav,"native_retirement");var elapsed:=Time.get_ticks_usec()-began
	var trace:=Trace.stop();Trace.methods_enabled=false;Trace.method_labels.clear()
	var scans:=0
	for row:Dictionary in trace.stats:
		if row.label in ["stream.retirement_schema_slice","method.spec_snapshot_validation.slice"]:scans+=row.count
	check(result.ok and result.removed==2200 and scans==0 and not f.map.has_meta("retirement_schema_preparation"),"runtime retires with zero whole-directory copies, schema scans or validation workers")
	check(f.library.size()==2400 and f.nav._spec_ids.size()==2400 and not f.map.get_meta("stream_append_state").namespace_sizes.has("guild"),"index, navigation and incremental counts commit together")
	check(f.watch.get_ref()!=null,"completed logical unload defers large source destruction to bounded disposal")
	drain();check(f.watch.get_ref()==null,"catalog counts retain no retired meshes")
	var additions:Array=[]
	for i:int in 2200:additions.append(spec("guild__part%d"%i,Vector2i(50,50),Vector2i(50,50),{"kind":"asset","building":{"id":"guild"}}))
	check(Stream.append_specs(f.map,additions).ok and f.nav.append_specs(additions).ok,"same namespace can return through ordinary append")
	check(f.map.get_meta("stream_append_state").namespace_sizes.guild==2200,"append restores exact catalog count")
	f.map.set_meta("stream_append_pending",[]);await process_frame
	result=Stream.retire_specs(f.map,f.ids,true,f.nav,"native_retirement")
	check(result.ok and f.library.size()==2400,"return/unload cycle uses the updated catalog without an old proof")
	print("RESIDENT_RETIREMENT_CATALOG ",JSON.stringify({"retired":2200,"survivors":2400,"elapsed_us":elapsed,"whole_library_scans":scans}))
	f.map.free();f={};drain()
	print("RESIDENT_RETIREMENT_CATALOG checks=",checks," failures=",failures);quit(1 if failures else 0)

func catalog_contract()->void:
	var helper:=preload("res://tools/test_owned_retirement_delta.gd").new()
	var original:Array=helper.world();helper.free()
	var library:=original.duplicate(true);var data:=Index.build(library)
	var cases:Array=[["house0_part0"],["ground0"],["missing"],["road","road"],["house0_part0","house0_part1","house0_part2"],["house0_part0","house0_part1","house0_part2","house1_part0","house1_part1","house1_part2","ground0"],["road"]]
	for ids:Array in cases:
		var before:=data.duplicate(true)
		var reference:=Index._owned_retire_plan(data,library,ids)
		var cached:=Index._owned_retire_plan(data,library,ids,true,null,true)
		check(reference.ok==cached.ok and data==before,"resident catalogue preserves complete-group/support decision and no-side-effect preflight "+str(ids))
		if not cached.ok:continue
		var retained:=library.duplicate(true);var other:=Index.build(retained)
		var result:=Index._commit_owned_retire(data,library,ids,cached)
		check(result.ok and Index.retire_owned(other,retained,ids).ok and library==retained,"catalogue commit preserves every survivor")
		check(same_contents(data,other),"catalogue cells, fixtures, reverse dependencies and scalar membership match full control")
		library=original.duplicate(true);data=Index.build(library)
	# Dynamic gameplay/native ownership never becomes a cached authorization.
	for kind:String in ["native_visual","event","seat"]:
		var selected:Dictionary=data.stream_by_id.road
		if kind=="native_visual":selected.native_visual=true
		else:selected.extras[kind]={}
		var before:=data.duplicate(true)
		check(not Index._owned_retire_plan(data,library,["road"],true,null,true).ok and data==before,"new live pin is checked: "+kind)
		selected.erase("native_visual");selected.extras.erase(kind)
