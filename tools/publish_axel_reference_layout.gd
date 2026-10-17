extends SceneTree
## Publish only the exact scoped layout candidate with outdoor visual evidence.
const Doc=preload("res://scripts/world3d/world_document.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
var output:=""
var report:Dictionary={"published":false,"checks":[],"all_reference_shots_complete":false}
var failures:=0
func check(ok:bool,label:String)->bool:
	report.checks.append({"name":label,"passed":ok})
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label);return ok
func read(path:String)->Dictionary:
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
func finish()->void:
	report.failures=failures
	var f:=FileAccess.open(output+".pending",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	if Atomic.publish(output+".pending",output)!=OK:failures+=1
	quit(0 if failures==0 else 1)
func _initialize()->void:
	var review_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--review="):review_path=arg.trim_prefix("--review=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	if review_path.is_empty() or output.is_empty() or FileAccess.file_exists(output):quit(1);return
	var review:=read(review_path)
	check(review.get("layout_passed",false) and not review.get("reference_complete",true),"explicit scoped layout acceptance, full shot still pending")
	var authored:=read(review.get("authoring_path",""));var runtime:=read(review.get("runtime_path",""))
	check(FileAccess.get_sha256(review.authoring_path)==review.authoring_sha256 and authored.get("saved",false) and authored.get("failures",-1)==0,"exact successful native authoring receipt")
	check(FileAccess.get_sha256(review.runtime_path)==review.runtime_sha256 and runtime.get("status","")=="passed" and runtime.get("failures",-1)==0,"exact successful outdoor runtime receipt")
	var source:=str(review.source);var candidate:=str(review.candidate)
	check(FileAccess.get_sha256(source)==review.source_sha256,"formal source conflict check")
	check(FileAccess.get_sha256(candidate)==review.candidate_sha256 and runtime.get("map_sha256","")==review.candidate_sha256 and authored.get("target_sha256","")==review.candidate_sha256,"same reviewed and authored candidate")
	check(not review.get("viewed_images",[]).is_empty(),"images actually reviewed")
	for image:Dictionary in review.get("viewed_images",[]):
		check(FileAccess.get_sha256(image.path)==image.sha256 and image.quality==90 and image.lossless==false,"exact Q90 visual evidence "+str(image.id))
	if failures:finish();return
	var formal=Doc.open_file(source);var staged=Doc.open_file(candidate)
	if not check(formal!=null and staged!=null,"native source and candidate open"):finish();return
	check(staged.validate_save()==OK,"native candidate validation")
	var allowed:Dictionary={}
	for row:Dictionary in authored.placements:allowed[row.id]=true
	var residence_stage:bool=authored.has("deleted_records")
	if residence_stage:
		check(authored.get("root_source_sha256",authored.source_sha256)==review.source_sha256,"residence transaction chain starts at this exact formal revision")
		for field:String in ["changed_records","deleted_records","new_records"]:
			for id:String in authored.get(field,[]):allowed[id]=true
	var old_ids:Dictionary={}
	for row:Dictionary in formal.records:
		old_ids[row.uuid]=true
		if not allowed.has(row.uuid):check(City.token(row)==City.token(staged._find(row.uuid)),"unaffected record "+str(row.uuid))
	for row:Dictionary in staged.records:
		if not old_ids.has(row.uuid):check(allowed.has(row.uuid),"new instance belongs to scoped operation "+str(row.uuid))
	var old_meta:Dictionary=formal.map_meta.duplicate(true);var new_meta:Dictionary=staged.map_meta.duplicate(true)
	var s1_stage:bool=authored.get("scene_id","")=="s1_bridge"
	var s2_stage:bool=authored.get("scene_id","")=="S2"
	var s10_stage:bool=authored.get("scene_id","")=="S10"
	var residence_id:String="building_061ac981f7e8922e09fa" if s1_stage else "building_ddf6bf729213bd14c951"
	var reference_id:String="s1_north_courtyard" if s1_stage else "s12_arch_home"
	for meta:Dictionary in [old_meta,new_meta]:
		if s2_stage:continue # Instance-only S2 delivery permits no metadata drift.
		if s10_stage:
			for id:String in ["building_2f6d20abcdba46dee584","building_19d4aeac100dd1547fea",str(authored.background_replacement.new)]:meta.building_instances.erase(id)
			meta.editor_layout.erase("roads");meta.editor_layout.erase("road_surface")
			meta.town_reference.house_layout.placements=meta.town_reference.house_layout.placements.filter(func(r):return r.get("id","") not in ["s10_front_home","s10_back_home"])
			continue
		meta.editor_layout.bookmarks=meta.editor_layout.bookmarks.filter(func(b):return b.id!=("s1_bridge" if s1_stage else "s12_stream"))
		if residence_stage:
			meta.building_instances.erase(residence_id)
			meta.editor_layout.erase("roads");meta.editor_layout.erase("road_surface")
			meta.town_reference.house_layout.placements=meta.town_reference.house_layout.placements.filter(func(r):return r.get("id","")!=reference_id)
	check(City.token(old_meta)==City.token(new_meta),"unaffected metadata identical outside explicit reference-scene authoring scope")
	if s2_stage:
		for id:String in authored.get("changed_records",[]):check(id in ["obj_787","obj_789"],"original S2 pole change only "+id)
		for id:String in authored.get("deleted_records",[]):check(id in ["obj_851","obj_852"],"incorrect S2 pennant removal only "+id)
	if s10_stage:
		var s10_owned:Dictionary={}
		for bid:String in ["building_2f6d20abcdba46dee584","building_19d4aeac100dd1547fea"]:
			for id:String in formal.map_meta.building_instances[bid].parts.values():s10_owned[id]=true
		for id:String in ["obj_840","obj_842","obj_843","obj_844","obj_882","axel_terrain_01_01","axel_terrain_01_02","axel_terrain_02_02"]:s10_owned[id]=true
		for id:String in authored.get("changed_records",[])+authored.get("deleted_records",[]):
			var prior:Dictionary=formal._find(id)
			check(s10_owned.has(id) or prior.has("road_mesh"),"original record belongs to explicit S10 scope "+id)
			if prior.has("terrain_mesh"):
				var current:Dictionary=staged._find(id).duplicate(true);prior=prior.duplicate(true)
				prior.erase("terrain_regions");current.erase("terrain_regions")
				check(City.token(prior)==City.token(current),"S10 only paints local grass, preserving terrain geometry "+id)
		var graph_before:Dictionary=formal.map_meta.editor_layout.roads.duplicate(true)
		var graph_after:Dictionary=staged.map_meta.editor_layout.roads.duplicate(true)
		for graph:Dictionary in [graph_before,graph_after]:
			graph.nodes=graph.nodes.filter(func(n):return n.id not in ["home_n_c8a0f6af8ec3","home_n_370715ca6b05","home_n_40a83cd9f0a4"])
			graph.edges=graph.edges.filter(func(e):return e.id not in ["home_e_s10_front_home_0","home_e_s10_front_home_1","home_e_s10_front_home_2"])
		check(City.token(graph_before)==City.token(graph_after),"only S10 front-door branch changes; public street graph preserved")
	if failures:finish();return
	var before:Dictionary=formal.recovery_snapshot();formal.apply_recovery(staged.recovery_snapshot());formal.commit_recovery_change(before)
	check(formal.save(source)==OK,"native formal atomic save with conflict detection")
	var reopened=Doc.open_file(source)
	check(reopened!=null and reopened.validate_save()==OK and City.token(reopened.records)==City.token(staged.records) and City.token(reopened.map_meta)==City.token(staged.map_meta),"formal reopens with exact reviewed content")
	report.published=failures==0;report.source=source;report.before_sha256=review.source_sha256;report.after_sha256=FileAccess.get_sha256(source);report.review_path=review_path;report.review_sha256=FileAccess.get_sha256(review_path);report.pending=review.get("pending",[])
	finish()
