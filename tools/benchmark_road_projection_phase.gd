extends "res://tools/benchmark_road_projection.gd"
## Same native adaptive fit, including validation/splits, in isolation.
## Attribution supplement; does not replace full prepare/UI measurements.
func phase(tool:GDScript,records:Array,terrains:Array,expected:PackedByteArray,input:PackedByteArray)->float:
	var start:=Time.get_ticks_usec()
	var result:Dictionary=tool.fit(records,terrains,.025,128)
	var ms:float=(Time.get_ticks_usec()-start)/1000.
	check(result.ok and var_to_bytes(result)==expected,"isolated adaptive phase exact full result")
	check(var_to_bytes([records,terrains])==input,"isolated inputs unchanged")
	return ms

func run()->void:
	report_path=EVIDENCE+"phase.json"
	if not initialize():finish();return
	for name_:String in ["terrain64_local","terrain64_far_complex","terrain64_wavy","terrain64_kerbs","terrain64_far_kerbs"]:
		var fixture:=build_fixture(name_);var settings:Dictionary=Plan.defaults().merged(fixture.args,true)
		var built:=Plan.build(fixture.layout.roads,settings);var terrains:Array=fixture.records.filter(func(r):return r.has("terrain_mesh"))
		check(built.ok,name_+" native raw road fixture")
		var records:Array=built.records;var input:=var_to_bytes([records,terrains])
		var expected:=var_to_bytes(BaselineAdaptive.fit(records,terrains,.025,128))
		var versions:={"baseline":BaselineAdaptive,"current":Adaptive};var warmups:Array=[];var noise:Array=[];var pairs:Array=[]
		for version:String in versions:
			for i in 2:warmups.append({"version":version,"ms":phase(versions[version],records,terrains,expected,input)})
		for i in 12:noise.append([phase(BaselineAdaptive,records,terrains,expected,input),phase(BaselineAdaptive,records,terrains,expected,input)])
		for i in 40:
			var order:Array=["baseline","current"] if i%2==0 else ["current","baseline"]
			var pair:={"order":order}
			for version:String in order:pair[version]=phase(versions[version],records,terrains,expected,input)
			pairs.append(pair)
		report.fixtures.append({"name":name_,"input_sha256":bytes_sha(input),"result_sha256":bytes_sha(expected),"warmups":warmups,"aa":noise,"pairs":pairs})
	report.script_sha256["res://tools/benchmark_road_projection_phase.gd"]=FileAccess.get_sha256("res://tools/benchmark_road_projection_phase.gd")
	report.method="Diagnostic supplement: entire native road_terrain_fit.fit including 128-paint budget, splits and Surface.valid. Setup excluded, exact full output/input bytes checked outside timing. Two warmups per version, twelve A/A pairs and forty alternating A/B pairs. No inner probes; not full prepare, UI, rendering or memory. No source changes since final whole-prepare run."
	finish()
