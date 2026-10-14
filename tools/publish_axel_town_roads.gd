extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014"
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const CANDIDATE="D:/code/rmmo_runtime/cache/world3d/axel_town_roads_20261014/map.gltf"
var report:Dictionary={"published":false,"checks":[]}
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	report.checks.append({"passed":ok,"name":label});print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok
func finish()->void:
	report.failures=failures
	var f:=FileAccess.open(OUT.path_join("publication.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	quit(1 if failures else 0)
func run()->void:
	var built:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("build.json")))
	var review:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("runtime/result.json")))
	var accepted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("visual_acceptance.json")))
	if not check(built.get("failures",-1)==0 and built.get("phase")=="candidate_complete","authoring and reopen passed"):finish();return
	if not check(review.get("failures",-1)==0 and review.get("phase","")=="complete" and review.get("status","")=="passed","outdoor runtime routes passed"):finish();return
	if not check(review.get("map_path","").replace("\\","/").to_lower()==CANDIDATE.to_lower() and review.get("map_sha256","")==FileAccess.get_sha256(CANDIDATE),"runtime evidence is pinned to the actual candidate"):finish();return
	if not check(accepted.get("passed",false) and accepted.get("candidate_sha256")==FileAccess.get_sha256(CANDIDATE),"visual acceptance is pinned to candidate"):finish();return
	if not check(FileAccess.get_sha256(FORMAL)==built.source_sha256,"formal source has no concurrent edits"):finish();return
	if not check(FileAccess.get_sha256(CANDIDATE)==built.candidate_sha256,"candidate unchanged since review"):finish();return
	var baseline=Doc.open_file(FORMAL);var next=Doc.open_file(CANDIDATE)
	if not check(baseline!=null and next!=null,"both documents open natively"):finish();return
	if not check(baseline._disk_signature==built.source_signature and next._disk_signature==built.candidate_sha256,"native open signatures match the reviewed revisions"):finish();return
	report.before_sha256=FileAccess.get_sha256(FORMAL);report.candidate_sha256=FileAccess.get_sha256(CANDIDATE)
	var records_token:=City.token(next.records);var meta_token:=City.token(next.map_meta)
	next.accept_save(FORMAL,built.source_signature)
	if not check(next.save(FORMAL)==OK,"native atomic conflict-aware publication"):finish();return
	report.published=true;report.formal_sha256=FileAccess.get_sha256(FORMAL)
	var reopened=Doc.open_file(FORMAL)
	check(reopened!=null and City.token(reopened.records)==records_token and City.token(reopened.map_meta)==meta_token,"formal reopen matches accepted content")
	check(ProjectSettings.get_setting("rmmo/world3d_start_map","")==FORMAL,"new map remains configured birth map")
	report.formal_path=FORMAL;report.catalog_name="axel_town";report.save_metrics=next.last_save_metrics
	finish()
