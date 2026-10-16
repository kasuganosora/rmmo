extends "res://tools/test_road_projection_reuse.gd"
const Counted=preload("res://review_artifacts/road_projection_20261017/road_tools_counted.gd")
const Counters=preload("res://review_artifacts/road_projection_20261017/terrain_projection_counted.gd")

func compare_projection(name_:String,record:Dictionary,terrains:Array,expected_ok:Variant=null,adaptive_limit:=-1)->void:
	super.compare_projection(name_,record,terrains,expected_ok,adaptive_limit)
	if name_=="kerb_cache_limit_exact_fallback":
		Counters.trace={}
		var result:Dictionary=Counters.fit(record,terrains)
		check(var_to_bytes(result)==var_to_bytes(BaselineFit.fit(record,terrains)),"counted cap fallback preserves all author bytes")
		check(Counters.trace.get("cache_peak",0)==4096 and Counters.trace.get("uncached_after_cap",0)>0,"actual cache reaches 4096 then recomputes excess coordinates")
		report.cache_limit=Counters.trace.duplicate(true)

func run()->void:
	report_path=EVIDENCE+"counts.json"
	if not initialize():finish();return
	for name_:String in fixture_names():
		var fixture:=build_fixture(name_);var context:=Fixture.context(fixture)
		var baseline:=Baseline.new();baseline.editor=context
		var current:=Counted.new();current.editor=context;Counters.trace={}
		var expected:Dictionary=baseline.prepare(fixture.args);var actual:Dictionary=current.prepare(fixture.args)
		check(var_to_bytes(actual)==var_to_bytes(expected),name_+" counted chain preserves exact full result")
		report.fixtures.append({"name":name_,"counts":Counters.trace.duplicate(true)})
		baseline.editor=null;current.editor=null;context._waterways.editor=null;context.free()
	reuse_matrix()
	for path:String in ["res://tools/profile_road_projection_counts.gd",ARCHIVE+"terrain_projection_counted.gd",ARCHIVE+"road_terrain_fit_counted.gd",ARCHIVE+"road_tools_counted.gd"]:report.script_sha256[path]=FileAccess.get_sha256(path)
	report.method="Diagnostic-only exact candidate copy, counters only. Baseline counts from profile.json; no timing claims from this run."
	finish()
