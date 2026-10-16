extends "res://tools/publish_axel_market_realism_20261016.gd"
## Validator fixtures only. No acceptance file is written, no asset is approved,
## and no publication/import/catalog operation is invoked by these CPU tests.
var accepted_fixture:Dictionary={}
var cases:Array=[]

func read_json(path:String)->Dictionary:
	if path==REVIEW.path_join("__validator_fixture__/acceptance.json"):return accepted_fixture
	return super.read_json(path)

func check(ok:bool,label:String)->bool:
	report.checks.append({"check":label,"pass":ok})
	if not ok:report.failures.append(label)
	return ok

func fixture()->Dictionary:
	var result:Dictionary={"version":1,"visual_accepted":true,"intentional_visual_change":true,"assets":{}}
	for asset:String in ["pottery","scroll","potion","ore"]:
		var folder:=REVIEW.path_join("gpu_realism_v3_01").path_join(asset)
		var candidate:=super.read_json(folder.path_join("candidate.json"))
		result.assets[asset]={"candidate_sha256":candidate.original_sha,"compare_sha256":FileAccess.get_sha256(folder.path_join("compare.json")),"visual_accepted":true,"viewed_image_sha256":candidate.screenshots.map(func(shot):return shot.file_sha256),"evidence":{"take":"gpu_realism_v3_01","plan_version":"v3","plan_sha256":FileAccess.get_sha256(ART.path_join("v3/review_plan.json")),"baseline_report_sha256":FileAccess.get_sha256(folder.path_join("baseline.json")),"candidate_report_sha256":FileAccess.get_sha256(folder.path_join("candidate.json"))}}
	result.assets.potion.optics_review={"bright_background_visible":true,"dark_background_visible":true,"liquid_surface_visible":true,"no_plastic_or_emissive_panel_appearance":true}
	return result

func run_case(label:String,mutation:String,expected_pass:bool)->void:
	rows=super.read_json(ART.path_join("v3/review_plan.json")).rows.duplicate(true)
	accepted_fixture=fixture();report={"checks":[],"failures":[]};review_take="__validator_fixture__";plan_version="v4"
	if mutation=="changed_bytes":rows[0].candidate_sha256="0".repeat(64)
	elif mutation=="wrong_report":accepted_fixture.assets.pottery.evidence.candidate_report_sha256="0".repeat(64)
	elif mutation=="traversal":accepted_fixture.assets.pottery.evidence.take="../gpu_realism_v3_01"
	elif mutation=="stale_plan":accepted_fixture.assets.pottery.evidence.plan_sha256="0".repeat(64)
	var actual:=validate_acceptance()
	cases.append({"name":label,"passed":actual==expected_pass,"expected_validator_result":expected_pass,"actual_validator_result":actual,"checks":report.checks.size(),"caught_failures":report.failures,"reused_count":report.get("acceptance_asset_evidence",[]).filter(func(row):return row.reused_prior_version).size()})

func run()->void:
	run_case("unchanged SHA-bound v3 bytes can use per-asset historical evidence in a v4 publication plan","none",true)
	run_case("changed candidate bytes cannot inherit older GPU evidence","changed_bytes",false)
	run_case("different native-render report SHA is rejected","wrong_report",false)
	run_case("review take path traversal is rejected before file access","traversal",false)
	run_case("stale evidence-plan SHA is rejected","stale_plan",false)
	var passed:bool=cases.all(func(row):return row.passed)
	var output:=REVIEW.path_join("pipeline/evidence_reuse_cpu_regression.json")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir());var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"cases":cases,"scope":"Pure headless validator fixtures. Synthetic review booleans exist only in memory; no acceptance artifact, asset approval, GPU rendering, import, publication, catalog or map write occurred. Positive fixture tests integrity gates only; actual visual acceptance remains root-owned.","publisher_sha256":FileAccess.get_sha256("res://tools/publish_axel_market_realism_20261016.gd"),"script_sha256":FileAccess.get_sha256("res://tools/test_axel_market_evidence_reuse.gd")},"  ",true,true));file.close()
	print("MARKET_EVIDENCE_REUSE_CPU ",JSON.stringify({"passed":passed,"cases":cases.size(),"report":output}));quit(0 if passed else 1)
