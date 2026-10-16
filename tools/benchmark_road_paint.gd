extends "res://tools/test_road_default_paint.gd"
## Same immutable input, alternating OFF pairs; setup and checks not timed.
func median(values:Array)->float:
	var sorted:=values.duplicate();sorted.sort()
	return sorted[sorted.size()/2] if sorted.size()%2 else (sorted[sorted.size()/2-1]+sorted[sorted.size()/2])*.5

func observe(tool:RefCounted,context:Node3D,args:Dictionary,expected:PackedByteArray,input:PackedByteArray,label_:String,profiling:bool)->Dictionary:
	tool.profile_enabled=profiling
	var start:=Time.get_ticks_usec();var result:Dictionary=tool.prepare(args)
	var wall_ms:float=(Time.get_ticks_usec()-start)/1000.
	var encoded:=var_to_bytes(result);var profile:Dictionary=tool.last_profile.duplicate(true)
	check(result.get("ok",false) and encoded==expected,label_+" exact full return")
	check(input==var_to_bytes([Fixture.state(context),args]),label_+" unchanged state and arguments")
	check(not profile.is_empty() if profiling else profile.is_empty(),label_+" expected probe state")
	return {"label":label_,"wall_ms":wall_ms,"profiling_on":profiling,"profile":profile,"input_sha256":bytes_sha(input),"full_result_sha256":bytes_sha(encoded)}

func paired_case(fixture:Dictionary)->void:
	check(fixture.construction_error.is_empty(),fixture.name+" native fixture built",fixture.construction_error)
	if failures:return
	var context:=Fixture.context(fixture);var baseline:=Baseline.new();baseline.editor=context
	var current:=Roads.new();current.editor=context;var versions:={"baseline":baseline,"current":current}
	var input:=var_to_bytes([Fixture.state(context),fixture.args]);var expected:=var_to_bytes(baseline.prepare(fixture.args))
	check(input==var_to_bytes([Fixture.state(context),fixture.args]),fixture.name+" untimed baseline seed immutable")
	write_bytes(report_path.get_base_dir().path_join(fixture.name+"_input.bin"),var_to_bytes(fixture))
	write_bytes(report_path.get_base_dir().path_join(fixture.name+"_result.bin"),expected)
	var warmups:Array=[];var samples:Array=[];var pairs:Array=[];var raw:={"baseline":[],"current":[]};var deltas:Array=[];var ratios:Array=[]
	for version:String in versions:
		for index in 2:warmups.append(observe(versions[version],context,fixture.args,expected,input,version+" warmup "+str(index),false))
	for index in 10:
		var order:Array=["baseline","current"] if index%2==0 else ["current","baseline"]
		var pair:={"index":index,"order":order}
		for version:String in order:
			var sample:=observe(versions[version],context,fixture.args,expected,input,version+" pair "+str(index),false)
			sample.version=version;sample.pair=index;samples.append(sample);raw[version].append(sample.wall_ms);pair[version]=sample.wall_ms
		pair.delta_ms=pair.current-pair.baseline;pair.ratio=pair.current/pair.baseline
		deltas.append(pair.delta_ms);ratios.append(pair.ratio);pairs.append(pair)
	var profiles:={}
	for version:String in versions:profiles[version]=observe(versions[version],context,fixture.args,expected,input,version+" ON diagnostic",true)
	for path:String in fixture.dependencies:check(FileAccess.get_sha256(path)==fixture.dependencies[path],fixture.name+" unchanged external source "+path.get_file())
	var stats:={"raw_ms":raw,"median_ms":{"baseline":median(raw.baseline),"current":median(raw.current)},"paired_delta_median_ms":median(deltas),"paired_ratio_median":median(ratios),"current_slower_pairs":deltas.filter(func(value):return value>0.).size(),"n_pairs":pairs.size()}
	report.fixtures.append({"name":fixture.name,"source_records":fixture.records.size(),"input_sha256":bytes_sha(input),"fixture_sha256":value_sha(fixture),"full_result_sha256":bytes_sha(expected),"dependencies":fixture.dependencies,"warmups":warmups,"samples":samples,"pairs":pairs,"profiles":profiles,"statistics":stats})
	print("ROAD_PAINT_PAIRED ",fixture.name," ",JSON.stringify(stats))
	baseline.editor=null;current.editor=null;context._waterways.editor=null;context.free()

func run()->void:
	report_path=ROOT+"paired/result.json"
	if not initialize():finish();return
	report.fixtures=[]
	report.method={"reference":"Exact d2cd069 road_tools with frozen original road_surface and surface_materials; all other helpers shared and unchanged.",
		"order":"Untimed baseline result seed, two OFF warmups each, ten OFF pairs alternating order. One final ON diagnostic per version excluded from OFF statistics.",
		"timing":"Wall around prepare only; setup, serialization, hashes, checks and report I/O excluded. Full input/output bytes verified on every call.",
		"scope":"CPU fixtures, builtin materials; includes uneven heightfield and existing authored roads. Real PBR/UI/HTTP tested separately. Not UI latency, FPS, memory, significance or tail latency. Other sessions/system load unmanaged."}
	for name_:String in fixture_names():
		if selected.is_empty() or selected==name_:paired_case(build_fixture(name_))
	finish()
