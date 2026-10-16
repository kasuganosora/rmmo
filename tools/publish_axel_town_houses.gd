extends SceneTree
## Publication only. Run explicitly after the pinned outdoor and visual reviews.
## No editor/GPU launch, asset regeneration, configuration edits or map backups.
const Doc=preload("res://scripts/world3d/world_document.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Buildings=preload("res://scripts/world3d/building_blueprint.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const CANDIDATE="D:/code/rmmo_runtime/cache/world3d/axel_town_houses_20261014/map.gltf"
var report:Dictionary={"published":false,"checks":[],"formal_path":FORMAL,"candidate_path":CANDIDATE}
var failures:=0

func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	report.checks.append({"passed":ok,"name":label});print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok
func canonical(path:String)->String:return path.replace("\\","/").simplify_path().to_lower()
func read_report(name_:String)->Dictionary:
	var path:=OUT.path_join(name_)
	if not check(FileAccess.file_exists(path),"review exists: "+name_):return {}
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not check(value is Dictionary,"review is valid JSON object: "+name_):return {}
	return value
func finish()->void:
	report.failures=failures;report.status="passed" if failures==0 else "failed"
	var file:=FileAccess.open(OUT.path_join("publication.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	else:push_error("Cannot write publication report");failures+=1
	quit(1 if failures else 0)
func ids(rows:Array,key:String)->Array:
	var result:Array=[]
	for row:Dictionary in rows:result.append(str(row.get(key,"")))
	result.sort();return result
func run()->void:
	var built:=read_report("build.json")
	var runtime:=read_report("runtime/result.json")
	var visual:=read_report("visual_acceptance.json")
	var watercourse:=read_report("watercourse_acceptance.json")
	if failures:finish();return
	if not check(FileAccess.file_exists(FORMAL) and FileAccess.file_exists(CANDIDATE),"formal baseline and candidate both exist"):finish();return
	var candidate_sha:=FileAccess.get_sha256(CANDIDATE)
	var baseline_sha:=FileAccess.get_sha256(FORMAL)
	report.before_sha256=baseline_sha;report.candidate_sha256=candidate_sha
	report.evidence={"build_sha256":FileAccess.get_sha256(OUT.path_join("build.json")),"runtime_sha256":FileAccess.get_sha256(OUT.path_join("runtime/result.json")),"visual_sha256":FileAccess.get_sha256(OUT.path_join("visual_acceptance.json")),"watercourse_sha256":FileAccess.get_sha256(OUT.path_join("watercourse_acceptance.json"))}
	check(built.get("phase","")=="candidate_complete" and int(built.get("failures",-1))==0,"native candidate authoring and reopen completed without failure")
	check(canonical(str(built.get("candidate","")))==canonical(CANDIDATE) and built.get("candidate_sha256","")==candidate_sha,"build receipt pins the current candidate")
	check(runtime.get("phase","")=="complete" and runtime.get("status","")=="passed" and int(runtime.get("failures",-1))==0,"outdoor runtime review completed without failure")
	check(canonical(str(runtime.get("map_path","")))==canonical(CANDIDATE) and runtime.get("map_sha256","")==candidate_sha,"runtime review pins the same candidate")
	check(runtime.get("build_sha256","")==report.evidence.build_sha256,"runtime reviewed the current placement receipt")
	check(visual.get("passed",false)==true and visual.get("candidate_sha256","")==candidate_sha,"visual acceptance passes for the same candidate")
	check(watercourse.get("passed",false)==true and watercourse.get("candidate_sha256","")==candidate_sha,"continuous tributary and crossing acceptance pins the same candidate")
	check(watercourse.get("views",[]).all(func(v):return v.get("passed",false)) and ids(watercourse.get("views",[]),"id")==["s12_stream_confluence","s12_stream_crossing","s12_stream_rapid","s12_watercourse_overview","s12_watercourse_source"],"upstream, complete course, bridge, rapid and confluence were visually reviewed")
	for view:Dictionary in watercourse.get("views",[]):
		var image_path:String=view.get("path","")
		var receipt_path:=image_path+".review-image.json"
		var encoding:Variant=JSON.parse_string(FileAccess.get_file_as_string(receipt_path)) if FileAccess.file_exists(receipt_path) else {}
		check(image_path.get_extension()=="webp" and FileAccess.file_exists(image_path) and FileAccess.get_sha256(image_path)==view.get("sha256","") and encoding is Dictionary and encoding.get("sha256","")==view.get("sha256","") and encoding.get("quality",0)==90 and encoding.get("lossless",true)==false,"watercourse visual proof keeps reviewed quality-90 source "+str(view.get("id","")))
	check(built.get("watercourse",{}).get("continuous",false),"build includes the continuous tributary correction")
	check(runtime.get("bridges",[]).size()==1 and runtime.bridges[0].get("walks",[]).size()==2 and runtime.bridges[0].walks.all(func(w):return w.get("passed",false)) and runtime.bridges[0].get("parapets",[]).size()==2 and runtime.bridges[0].parapets.all(func(p):return p.get("passed",false)),"new stream bridge supports actual bidirectional crossings and both parapets")
	check(not built.get("houses",[]).is_empty() and ids(built.get("houses",[]),"id")==ids(runtime.get("houses",[]),"id"),"runtime covers every saved residential entrance")
	check(runtime.get("houses",[]).all(func(h):return h.get("walks",[]).size()==2 and h.walks.all(func(w):return w.get("passed",false))),"all homes have two successful outdoor approach walks")
	check(ids(runtime.get("routes",[]),"house")==["s10_front_home","s12_arch_home","s1_north_courtyard"],"three representative outdoor access routes were reviewed")
	check(runtime.get("routes",[]).all(func(r):return r.get("walks",[]).size()==r.get("points",[]).size()-1 and not r.get("walks",[]).is_empty() and r.walks.all(func(w):return w.get("passed",false))),"representative street and courtyard paths completed")
	var landmarks:Array=built.get("landmarks",{}).get("placements",[])
	if not landmarks.is_empty():
		check(ids(landmarks,"id")==ids(runtime.get("landmarks",[]),"id") and runtime.get("landmarks",[]).all(func(r):return r.get("walks",[]).size()==2 and r.walks.all(func(w):return w.get("passed",false))),"new landmarks retain clear bidirectional public approaches")
		check(visual.get("landmark_macro_layout_passed",false),"new landmark exterior placement visually accepted")
	check(built.get("source_sha256","")==baseline_sha and built.get("source_signature","")==baseline_sha,"formal baseline is unchanged from authoring")
	check(canonical(str(ProjectSettings.get_setting("rmmo/world3d_start_map","")))==canonical(FORMAL),"formal map remains configured as birth map")
	if failures:finish();return
	var baseline=Doc.open_file(FORMAL);var candidate=Doc.open_file(CANDIDATE)
	if not check(baseline!=null and candidate!=null,"both maps open through native document loading"):finish();return
	check(baseline._disk_signature==baseline_sha and candidate._disk_signature==candidate_sha,"native documents opened the reviewed disk revisions")
	check(Buildings.valid_ownership(candidate.map_meta,candidate.records),"candidate retains editable house floor roof and fixture ownership")
	check(preload("res://scripts/world3d/terrain_river_layer.gd").valid(candidate.map_meta),"candidate retains valid editable river ownership and outlet dependencies")
	var streams:Array=candidate.map_meta.get("terrain_rivers",[]).filter(func(layer):return layer.id=="axel_s12_stream")
	check(streams.size()==1 and streams[0].request.get("outlet",{}).get("river_id","")=="axel_main_river" and streams[0].request.has("water_levels"),"S12 watercourse is a profiled tributary of the main river")
	var saved_layout:Dictionary=candidate.map_meta.get("town_reference",{}).get("house_layout",{})
	check(saved_layout.get("phase","")=="reference_houses" and City.token(saved_layout.get("placements",[]))==City.token(built.houses),"native house placements exactly match build evidence")
	var record_token:=City.token(candidate.records);var metadata_token:=City.token(candidate.map_meta)
	# Recheck immediately before publication. accept_save installs the expected
	# baseline; native atomic save performs its own final conflict comparison.
	check(FileAccess.get_sha256(FORMAL)==baseline_sha and FileAccess.get_sha256(CANDIDATE)==candidate_sha,"neither map changed while publication was prepared")
	if failures:finish();return
	candidate.accept_save(FORMAL,baseline_sha)
	var error:Error=candidate.save(FORMAL)
	report.save_error=error;report.save_metrics=candidate.last_save_metrics
	if not check(error==OK,"native atomic conflict-aware publication"):finish();return
	report.published=true;report.formal_sha256=FileAccess.get_sha256(FORMAL)
	var reopened=Doc.open_file(FORMAL)
	check(reopened!=null and City.token(reopened.records)==record_token and City.token(reopened.map_meta)==metadata_token,"formal native reopen preserves all accepted content")
	if reopened!=null:check(Buildings.valid_ownership(reopened.map_meta,reopened.records),"published houses retain editable ownership")
	check(FileAccess.get_sha256(CANDIDATE)==candidate_sha,"publication leaves reviewed candidate intact")
	report.record_token=record_token;report.metadata_token=metadata_token;report.house_count=built.houses.size()
	finish()
