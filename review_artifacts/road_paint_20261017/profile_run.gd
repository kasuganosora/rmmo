extends "res://tools/benchmark_road_prepare.gd"
const Probe=preload("res://review_artifacts/road_paint_20261017/profile_paint.gd")
const Baseline=preload("res://review_artifacts/road_paint_20261017/road_tools_ref.gd")
func run()->void:
	report_path="res://review_artifacts/road_paint_20261017/profile.json"
	report={"fixtures":[],"method":"Diagnostic breakdown of exact baseline paint_default; warm prepare three times, all substage markers ON. No OFF or end-to-end speed claim."}
	for name_:String in Fixture.names():
		var fixture:=Fixture.build(name_);var context:=Fixture.context(fixture)
		var baseline:=Baseline.new();baseline.editor=context
		var expected:=var_to_bytes(baseline.prepare(fixture.args));var before:=var_to_bytes([Fixture.state(context),fixture.args])
		var probe:=Probe.new();probe.editor=context;probe.profile_enabled=true
		var rounds:Array=[]
		for round_ in 3:
			probe.paint_samples=[];var result:=probe.prepare(fixture.args)
			check(result.get("ok",false) and var_to_bytes(result)==expected,name_+" exact instrumented result "+str(round_))
			check(before==var_to_bytes([Fixture.state(context),fixture.args]),name_+" unchanged inputs "+str(round_))
			var totals:Dictionary={}
			for sample in probe.paint_samples:
				for key:String in sample:
					if key.ends_with("_ms"):totals[key]=totals.get(key,0.)+sample[key]
			rounds.append({"total_ms":probe.last_profile.total_ms,"stages_ms":probe.last_profile.stages_ms,"paint_totals_ms":totals,"paint_samples":probe.paint_samples.duplicate(true)})
			print("PAINT_PROFILE ",name_," ",round_," ",JSON.stringify(totals))
		report.fixtures.append({"name":name_,"input_sha256":bytes_sha(before),"result_sha256":bytes_sha(expected),"rounds":rounds})
		baseline.editor=null;probe.editor=null;context._waterways.editor=null;context.free()
	finish()
