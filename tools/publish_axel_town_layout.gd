extends SceneTree
## Publish only the exact natively saved candidate reviewed outdoors.
const Doc=preload("res://scripts/world3d/world_document.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Buildings=preload("res://scripts/world3d/building_blueprint.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const CANDIDATE="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
var report:Dictionary={"published":false,"checks":[]}
var failures:=0
var pins:Dictionary={}
var functional_receipt:Dictionary={}
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	report.checks.append({"name":label,"passed":ok});print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok
func canonical(path:String)->String:return path.replace("\\","/").simplify_path().to_lower()
func pin(path:String,sha:String,label:String)->bool:
	if not check(not path.is_empty() and sha.length()==64 and FileAccess.file_exists(path) and FileAccess.get_sha256(path)==sha,label):return false
	var key:=canonical(path)
	if pins.has(key) and not check(pins[key].sha256==sha,"consistent evidence revision "+path):return false
	pins[key]={"path":path,"sha256":sha};return true
func read(path:String)->Dictionary:
	if not check(not path.is_empty() and FileAccess.file_exists(path),"evidence exists "+path):return {}
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not check(value is Dictionary,"JSON object evidence "+path):return {}
	return value
func finish()->void:
	report.status="passed" if failures==0 else "failed";report.failures=failures
	var file:=OUT+"/publication.json";var pending:=file+".pending"
	var f:=FileAccess.open(pending,FileAccess.WRITE)
	if f==null:push_error("Publication receipt could not be written");quit(1);return
	f.store_string(JSON.stringify(report,"\t"));f.close()
	if Atomic.publish(pending,file)!=OK:push_error("Publication receipt atomic publish failed");quit(1);return
	quit(0 if failures==0 else 1)
func evidence(acceptance:Dictionary)->Dictionary:
	var roles:Dictionary={};var resource_scopes:Dictionary={}
	var entries:Variant=acceptance.get("evidence",[])
	if not check(entries is Array and not entries.is_empty(),"nonempty authoring, runtime and resource evidence manifest"):return roles
	for item:Variant in entries:
		if not check(item is Dictionary,"typed evidence entry"):continue
		var entry:Dictionary=item;var role:=str(entry.get("role",""))
		pin(str(entry.get("path","")),str(entry.get("sha256","")),"exact evidence revision "+role)
		if role=="resource_review":
			check(entry.get("passed",false)==true,"explicit resource acceptance "+str(entry.get("path","")))
			for scope:String in entry.get("scopes",[]):resource_scopes[scope]=true
			continue
		if not check(not role.is_empty() and not roles.has(role),"unique evidence role "+role):continue
		roles[role]=entry
	for role:String in ["fortification_build","market_build","vegetation_build","runtime"]:check(roles.has(role),"required evidence role "+role)
	for scope:String in ["fortification","market","vegetation"]:check(resource_scopes.has(scope),"resource acceptance covers "+scope)
	if roles.has("functional_buildings_build"):check(resource_scopes.has("functional_buildings"),"functional building resources explicitly accepted")
	return roles
func building_inventory(receipt:Dictionary)->Dictionary:
	var descriptor:Dictionary=receipt.get("building_inputs",{})
	var path:=str(descriptor.get("path",""));var sha:=str(descriptor.get("sha256",""))
	check(canonical(path.get_base_dir())==canonical(OUT+"/functional_inputs") and path.get_file()==sha+".json","content-addressed scoped building descriptor")
	if not pin(path,sha,"exact scoped building input"):return {}
	check(receipt.get("inputs",{}).get(path,"")==sha,"successful native receipt pins scoped descriptor")
	var data:=read(path)
	check(data.get("schema",0)==1 and data.get("formal_publications",{}).size()==3 and data.get("designs",{}).size()==3,"three complete scoped building entries")
	check(City.token(data)==descriptor.get("scope_token",""),"scoped building content token")
	for key:String in ["guardhouse","church","watermill"]:
		var model:Dictionary=data.get("formal_publications",{}).get(key,{})
		var design:Dictionary=data.get("designs",{}).get(key,{})
		var source_field:String={"guardhouse":"candidate","church":"source","watermill":"candidate_glb"}[key]
		var anchor_field:String={"guardhouse":"main_entrance","church":"entrances","watermill":"front_door"}[key]
		var source:=str(model.get("source",{}).get("sha256",""))
		check(source.length()==64 and design.get(source_field,{}).get("sha256","")==source and not design.get(anchor_field,[]).is_empty(),"published source and used anchors agree "+key)
		check(model.get("status",{}).get("resource","")=="passed" and model.get("status",{}).get("visual","")=="passed","formal model acceptance "+key)
		for field:String in ["source","manifest","acceptance","formal_catalog_use","publication_receipt"]:
			var proof:Dictionary=model.get(field,{})
			pin(str(proof.get("path","")),str(proof.get("sha256","")),"formal building proof "+key+" "+field)
		pin(str(model.get("asset_id","")),source,"exact placed source "+key)
		var acceptance:=read(str(model.get("acceptance",{}).get("path","")))
		check(acceptance.get("passed",false) and acceptance.get("asset","")==key and acceptance.get("source_sha256","")==source,"same-source building acceptance "+key)
		for stage:String in ["resource_status","visual_status","pipeline_status"]:check(acceptance.get(stage,"")=="passed","building accepted stage "+key+" "+stage)
		var publication:=read(str(model.get("publication_receipt",{}).get("path","")))
		check(publication.get("ok",false) and publication.get("completed",false) and publication.get("failures",["missing"])==[] and publication.get("source_sha256","")==source,"completed formal building publication "+key)
		var matches:Array=receipt.get("placements",[]).filter(func(p):return p.get("key","")==key)
		check(matches.size()==1 and matches[0].get("source_sha256","")==source and canonical(str(matches[0].get("asset_path","")))==canonical(str(model.get("asset_id",""))),"placed building matches scoped source "+key)
	return data
func history_record(descriptor:Dictionary)->Dictionary:
	var path:=str(descriptor.get("path",""));var sha:=str(descriptor.get("sha256",""))
	check(canonical(path.get_base_dir())==canonical(OUT+"/fortification_history") and path.get_file()==sha+".json","immutable fortification history path")
	if not pin(path,sha,"exact historical receipt bytes"):return {}
	return read(path)
func stable_construction(value:Dictionary)->String:
	var stable:=value.duplicate(true)
	for field:String in ["candidate_sha256","native_reopen_passed","initial_build","regenerations","latest_regeneration","visual","runtime","history_note"]:stable.erase(field)
	return City.token(stable)
func fortification_history(fort:Dictionary,baseline:String)->void:
	var history:Array=fort.get("regenerations",[])
	if history.is_empty():
		check(not fort.has("initial_build"),"legacy build has no dangling initial receipt");return
	var initial_desc:Dictionary=fort.get("initial_build",{});var initial:=history_record(initial_desc)
	check(initial.get("saved",false) and initial.get("apply",false) and initial.get("failures",-1)==0 and initial.get("source_sha256","")==baseline and initial.get("phase","")=="native_candidate_complete_review_pending" and not initial.has("regenerations") and not initial.has("initial_build"),"original native construction complete")
	check(stable_construction(initial)==stable_construction(fort),"original construction source recipe operations and relocations retained")
	var output:=str(initial.get("candidate_sha256",""));var prior:Array=[]
	for entry:Dictionary in history:
		var proof:=history_record(entry);var prev_desc:Dictionary=proof.get("previous_build",{});var previous:=history_record(prev_desc)
		check(proof.get("previous_build_sha256","")==prev_desc.get("sha256","") and previous.get("candidate_sha256","")==output and stable_construction(previous)==stable_construction(initial) and City.token(previous.get("regenerations",[]))==City.token(prior),"exact previous receipt and append-only history")
		check((prior.is_empty() and City.token(prev_desc)==City.token(initial_desc)) or (not prior.is_empty() and City.token(previous.get("initial_build",{}))==City.token(initial_desc)),"consistent initial build identity")
		check(City.token(proof.get("initial_build",{}))==City.token(initial_desc) and proof.get("input_sha256","")==output and entry.get("input_sha256","")==output and proof.get("output_sha256","")==entry.get("output_sha256","") and str(proof.get("output_sha256","")).length()==64,"continuous regeneration input output SHA chain")
		check(proof.get("saved",false) and proof.get("apply",false) and proof.get("failures",-1)==0 and proof.get("native_reopen_passed",false) and proof.get("phase","")=="native_fortification_regeneration_complete_review_pending","native regeneration actually saved and reopened")
		for step:String in ["undo_passed","redo_passed","save_reopen"]:check(proof.get("transaction",{}).get(step,false)==true,"regeneration transaction "+step)
		check(proof.get("source_sha256","")==baseline and canonical(str(proof.get("source","")))==canonical(FORMAL) and canonical(str(proof.get("map","")))==canonical(CANDIDATE) and not str(proof.get("method","")).is_empty() and entry.get("method","")==proof.get("method",""),"regeneration source target method")
		var ops:Array=proof.get("operations",[])
		check(ops.map(func(x):return x.get("tool",""))==["remove_fortification","preview_fortification","generate_fortification"] and ops.all(func(x):return x.get("result",{}).get("ok",false)==true) and not ops.is_empty() and ops[0].get("request",{}).get("keep_objects",true)==false,"actual native remove preview generate transaction")
		var comparisons:Array=proof.get("frozen_comparison",[])
		check(not comparisons.is_empty() and comparisons.all(func(x):return x.get("non_tangent_data_identical",false)==true and x.get("invalid_after",-1)==0 and x.get("valid_tangents_changed",-1)==0),"only invalid tangent channels changed")
		for field:String in ["non_fortification_records_identical","non_fortification_metadata_identical","component_ids_stable"]:check(proof.get("preservation",{}).get(field,false)==true,"regeneration preservation "+field)
		# The historical proof pins its then-current inputs. Old map/build paths
		# must not be compared to those historical hashes after native replacement.
		output=str(proof.get("output_sha256",""));prior.append(entry)
	var last:Dictionary=history[-1]
	check(fort.get("candidate_sha256","")==output and City.token(fort.get("latest_regeneration",{}))==City.token({"path":last.path,"sha256":last.sha256}),"final wall is last proven regenerated output")
func native_chain(roles:Dictionary,baseline_sha:String,candidate_sha:String)->Dictionary:
	var fort:=read(roles.fortification_build.path);var market:=read(roles.market_build.path);var vegetation:=read(roles.vegetation_build.path)
	fortification_history(fort,baseline_sha)
	check(fort.get("saved",false)==true and fort.get("apply",false)==true and fort.get("failures",-1)==0 and fort.get("phase","")=="native_candidate_complete_review_pending","fortification native save/reopen completed with zero failures")
	check(market.get("saved",false)==true and market.get("apply",false)==true and market.get("failures",-1)==0 and market.get("phase","")=="native_market_complete_review_pending","market native save/reopen completed with zero failures")
	check(vegetation.get("saved",false)==true and vegetation.get("dry_run",true)==false and vegetation.get("failures",-1)==0 and vegetation.get("native_reopen_passed",false)==true and vegetation.get("native_save_validation",-1)==OK and vegetation.get("input_unchanged",false)==true and not vegetation.has("error"),"vegetation actual native save/reopen completed with zero failures")
	check(canonical(str(fort.get("source","")))==canonical(FORMAL) and fort.get("source_sha256","")==baseline_sha,"fortification starts at exact formal baseline")
	check(canonical(str(fort.get("candidate","")))==canonical(CANDIDATE) and canonical(str(market.get("map","")))==canonical(CANDIDATE) and canonical(str(vegetation.get("map_path","")))==canonical(CANDIDATE),"all native stages target the same candidate")
	var fort_sha:=str(fort.get("candidate_sha256",""));var market_sha:=str(market.get("candidate_sha256",""))
	check(fort_sha.length()==64 and market.get("input_sha256","")==fort_sha,"fortification output is market input")
	check(market.get("formal_before_sha256","")==baseline_sha,"market retains same formal baseline")
	var middle_sha:=market_sha
	if roles.has("functional_buildings_build"):
		functional_receipt=read(roles.functional_buildings_build.path)
		var b:=functional_receipt
		check(b.get("saved",false) and b.get("apply",false) and b.get("failures",-1)==0 and b.get("native_reopen_passed",false) and b.get("blocking_findings",["missing"])==[] and b.get("phase","")=="native_functional_buildings_complete_outdoor_review_pending","functional buildings native save/reopen complete")
		check(canonical(str(b.get("map","")))==canonical(CANDIDATE) and b.get("formal_before_sha256","")==baseline_sha and b.get("input_sha256","")==market_sha,"market output is functional building input")
		for step:String in ["undo_passed","redo_passed","save_reopen"]:check(b.get("transaction",{}).get(step,false)==true,"functional native transaction "+step)
		building_inventory(b)
		middle_sha=str(b.get("output_sha256",""))
		check(not b.get("inputs",{}).is_empty(),"functional building actual input identities recorded")
		for path:String in b.get("inputs",{}):pin(path,str(b.inputs[path]),"functional building input unchanged "+path)
	check(middle_sha.length()==64 and vegetation.get("input_sha256","")==middle_sha,"preceding native output is vegetation input")
	check(vegetation.get("output_sha256","")==candidate_sha,"vegetation output is final reviewed candidate")
	pin(str(fort.get("plan_path","")),str(fort.get("plan_sha256","")),"fortification authoring recipe unchanged")
	var market_inputs:Dictionary=market.get("inputs",{})
	check(not market_inputs.is_empty(),"market records actual authoring input identities")
	for path:String in market_inputs:pin(path,str(market_inputs[path]),"market authoring input unchanged "+path)
	var vegetation_plan_path:=OUT+"/functional_vegetation_plan.json"
	pin(vegetation_plan_path,str(vegetation.get("plan_sha256","")),"vegetation authoring recipe unchanged")
	var vegetation_plan:=read(vegetation_plan_path)
	check(vegetation_plan.get("formal_source_sha256","")==baseline_sha,"vegetation recipe uses same formal source")
	for asset:Dictionary in vegetation_plan.get("assets",[]):pin(str(asset.get("asset_id","")),str(asset.get("sha256","")),"reused vegetation resource unchanged "+str(asset.get("label","")))
	if vegetation.has("future_sites_sha256"):pin(OUT+"/functional_building_sites.json",str(vegetation.future_sites_sha256),"future building exclusions unchanged")
	report.authoring_chain={"formal":baseline_sha,"fortification":fort_sha,"market":market_sha,"functional_buildings":str(functional_receipt.get("output_sha256","")),"vegetation":candidate_sha,"receipts":roles}
	return fort
func relocation_exceptions(fort:Dictionary,source,candidate)->Dictionary:
	var tokens:Dictionary=candidate.map_meta.get("town_reference",{}).get("fortification_layout",{}).get("relocated_vegetation",{})
	var allowed:Dictionary={}
	if not fort.has("relocation_plan"):
		check(tokens.is_empty(),"no unreceipted vegetation relocation metadata");return allowed
	var descriptor:Dictionary=fort.relocation_plan
	if not pin(str(descriptor.get("path","")),str(descriptor.get("sha256","")),"exact authorized fortification grass relocation plan"):return allowed
	var relocations:=read(descriptor.path)
	check(relocations.get("ok",false)==true and relocations.get("source_sha256","")==fort.get("source_sha256",""),"relocation plan passed against exact formal source")
	check(relocations.get("recipe_sha256","")==fort.get("plan_sha256",""),"relocations checked against exact fortification terrain recipe")
	for move:Dictionary in relocations.get("relocations",[]):
		var id:=str(move.get("id",""));var old:Dictionary=source._find(id);var actual:Dictionary=candidate._find(id)
		if not check(not id.is_empty() and not allowed.has(id) and not old.is_empty() and not actual.is_empty() and old.get("kind","")=="asset" and not old.has("building"),"explicit existing grass instance "+id):continue
		if not check(move.get("old_position",[]).size()==3 and move.get("position",[]).size()==3,"relocation has original and target pose "+id):continue
		check(City.vec(old.position).distance_to(City.vec(move.old_position))<.001 and City.vec(actual.position).distance_to(City.vec(move.position))<.001,"source and target relocation position "+id)
		var expected_rotation:Array=move.get("rotation",old.rotation)
		check(City.vec(actual.rotation).distance_to(City.vec(expected_rotation))<.001,"only planned relocation rotation "+id)
		var restored:=actual.duplicate(true);restored.position=old.position;restored.rotation=old.rotation
		check(City.token(restored)==City.token(old),"relocation retains resource, scale, collision and all nonpose fields "+id)
		var token:=City.token(actual)
		check(tokens.get(id,"")==token,"saved metadata pins actual relocated record "+id)
		var successful:=false
		for operation:Dictionary in fort.get("operations",[]):
			if operation.get("tool","")!="set_object_transform":continue
			var request:Dictionary=operation.get("request",{})
			if request.get("id","")==id and request.get("position",[]).size()==3 and City.vec(request.position).distance_to(City.vec(move.position))<.001 and operation.get("result",{}).get("ok",false):successful=true
		check(successful,"native transform success recorded for "+id)
		allowed[id]=token
	check(allowed.size()==tokens.size(),"relocation exceptions exactly match saved metadata")
	report.allowed_grass_relocations=allowed;return allowed
func building_relocations(source,candidate,already:Dictionary)->Dictionary:
	var allowed:Dictionary={}
	var metadata:Dictionary=candidate.map_meta.get("town_reference",{}).get("functional_buildings",{})
	check(metadata.is_empty()==functional_receipt.is_empty(),"functional building metadata has matching authoring receipt")
	if functional_receipt.is_empty():return allowed
	check(City.token(metadata.get("placements",[]))==City.token(functional_receipt.get("placements",[])),"saved functional building placements equal receipt")
	var tokens:Dictionary=metadata.get("relocated_vegetation",{})
	for move:Dictionary in functional_receipt.get("grass_relocations",[]):
		var id:=str(move.get("id",""));var old:Dictionary=source._find(id);var actual:Dictionary=candidate._find(id)
		if not check(not id.is_empty() and not already.has(id) and not allowed.has(id) and not old.is_empty() and not actual.is_empty() and old.get("kind","")=="asset" and not old.has("building") and not old.has("model_building"),"explicit nonoverlapping functional-site old grass "+id):continue
		if not check(move.get("old_position",[]).size()==3 and move.get("position",[]).size()==3,"functional grass old/target position "+id):continue
		var old_token:=City.token(old);var actual_token:=City.token(actual)
		check(City.token(move.get("before_record",{}))==old_token and move.get("before_token","")==old_token,"functional grass exact formal before record "+id)
		check(City.token(move.get("after_record",{}))==actual_token and move.get("after_token","")==actual_token,"functional grass exact candidate after record "+id)
		check(City.vec(move.old_position).distance_to(City.vec(old.position))<.001 and City.vec(move.position).distance_to(City.vec(actual.position))<.001,"functional grass before/target position matches "+id)
		var restored:=actual.duplicate(true);restored.position=old.position
		check(City.token(restored)==old_token,"functional grass ONLY position changed; resource rotation scale ownership collision retained "+id)
		check(tokens.get(id,"")==actual_token,"functional grass metadata pins exact final record "+id)
		var successful:=false
		for op:Dictionary in functional_receipt.get("operations",[]):
			var request:Dictionary=op.get("request",{})
			if op.get("tool","")=="set_object_transform" and request.get("id","")==id and request.get("position",[]).size()==3 and City.vec(request.position).distance_to(City.vec(move.position))<.001 and op.get("result",{}).get("ok",false):successful=true
		check(successful,"functional grass native transform succeeded "+id);allowed[id]=actual_token
	check(tokens.size()==allowed.size(),"functional grass exceptions exactly match metadata")
	var keys:Dictionary={}
	for placement:Dictionary in functional_receipt.get("placements",[]):
		var key:=str(placement.get("key",""));var record:Dictionary=candidate._find(str(placement.get("uuid","")))
		check(key in ["guardhouse","church","watermill"] and not keys.has(key),"unique functional building "+key);keys[key]=true
		check(not record.is_empty() and record.get("asset_path","")==placement.get("asset_path","") and City.token(record.get("model_building",{}))==placement.get("model_building_token",""),"functional placed asset and semantic ownership "+key)
		check(City.token(record.get("position",[]))==City.token(placement.get("position",[])) and City.token(record.get("rotation",[]))==City.token(placement.get("rotation",[])) and City.token(record.get("size",[]))==City.token(placement.get("scale",[])),"functional building final pose unchanged "+key)
		pin(str(placement.get("asset_path","")),str(placement.get("source_sha256","")),"functional formal source "+key)
	check(keys.size()==3,"three functional buildings retained")
	report.allowed_functional_grass_relocations=allowed;return allowed

func reviewed_images(acceptance:Dictionary,runtime:Dictionary)->void:
	var captured:Dictionary={};var seen:Dictionary={}
	for shot:Dictionary in runtime.get("screenshots",[]):
		var id:=str(shot.get("id",""))
		check(not id.is_empty() and not captured.has(id),"unique actual runtime image "+id);captured[id]=shot
	var views:Array=acceptance.get("views",[])
	check(not views.is_empty() and captured.size()==views.size(),"all final runtime images explicitly reviewed")
	for view:Dictionary in views:
		var id:=str(view.get("id",""));var path:=str(view.get("path",""));var sha:=str(view.get("sha256",""))
		if not check(view.get("passed",false)==true and captured.has(id) and not seen.has(id),"explicit unique view acceptance "+id):continue
		seen[id]=true
		check(canonical(path)==canonical(str(captured[id].get("path",""))) and sha==captured[id].get("sha256",""),"view belongs to exact final runtime capture "+id)
		pin(path,sha,"reviewed image revision "+id)
		var encoding_path:=path+".review-image.json";var encoding:=read(encoding_path)
		if FileAccess.file_exists(encoding_path):pin(encoding_path,FileAccess.get_sha256(encoding_path),"Q90 receipt revision "+id)
		check(path.get_extension().to_lower()=="webp" and encoding.get("sha256","")==sha and encoding.get("quality",0)==90 and encoding.get("lossless",true)==false,"actual lossy quality90 WebP "+id)
func run()->void:
	var acceptance_path:=OUT+"/layout_acceptance.json"
	var acceptance:=read(acceptance_path)
	if failures:finish();return
	var acceptance_sha:=FileAccess.get_sha256(acceptance_path)
	pin(acceptance_path,acceptance_sha,"acceptance manifest revision")
	var baseline_sha:=FileAccess.get_sha256(FORMAL);var candidate_sha:=FileAccess.get_sha256(CANDIDATE)
	check(candidate_sha.length()==64 and baseline_sha==acceptance.get("source_sha256",""),"formal source revision unchanged")
	check(candidate_sha==acceptance.get("candidate_sha256","") and acceptance.get("passed",false)==true,"explicit outdoor and macro visual acceptance pins current candidate")
	var roles:=evidence(acceptance)
	if failures:finish();return
	var fort:=native_chain(roles,baseline_sha,candidate_sha)
	check(canonical(str(acceptance.get("runtime_report","")))==canonical(str(roles.runtime.path)),"runtime report is SHA-pinned evidence")
	var runtime:=read(roles.runtime.path)
	report.deferred_checks=runtime.get("deferred_checks",[])
	report.all_work_complete=runtime.get("all_work_complete",true)
	for child:Dictionary in runtime.get("child_reports",[]):
		pin(str(child.get("path","")),str(child.get("sha256","")),"actual child runtime revision")
		var sub:=read(str(child.get("path","")))
		check(sub.get("map_sha256","")==candidate_sha and sub.get("phase","")=="complete" and sub.get("status","")=="passed" and sub.get("failures",-1)==0,"actual child runtime complete on final SHA")
		for shot:Dictionary in sub.get("screenshots",[]):check(shot in runtime.get("screenshots",[]),"actual child screenshot retained")
	check(runtime.get("map_sha256","")==candidate_sha and runtime.get("status","")=="passed" and runtime.get("failures",-1)==0 and runtime.get("phase","")=="complete","current final candidate passed outdoor runtime")
	if not functional_receipt.is_empty():
		var outdoor:Dictionary=runtime.get("functional_buildings",{})
		check(outdoor.get("passed",false) and outdoor.get("build_receipt_sha256","")==roles.functional_buildings_build.sha256,"functional outdoor runtime pins exact build receipt")
		for key:String in ["guardhouse","church","watermill"]:
			check(outdoor.get("checks",[]).any(func(c):return c.get("key","")==key and c.get("passed",false)),"functional outdoor entry checked "+key)
	reviewed_images(acceptance,runtime)
	check(canonical(str(ProjectSettings.get_setting("rmmo/world3d_start_map","")))==canonical(FORMAL),"new town remains configured birth map")
	if failures:finish();return
	var source=Doc.open_file(FORMAL);var candidate=Doc.open_file(CANDIDATE)
	if not check(source!=null and candidate!=null,"native source and candidate open"):finish();return
	check(source._disk_signature==baseline_sha and candidate._disk_signature==candidate_sha,"native documents have exact reviewed revisions")
	check(candidate.validate_save()==OK and Buildings.valid_ownership(candidate.map_meta,candidate.records),"whole native document and house semantics valid")
	check(City.token(source.map_meta.terrain_rivers)==City.token(candidate.map_meta.terrain_rivers),"continuous watercourse ownership preserved")
	check(City.token(City.resolve(source.map_meta).zones)==City.token(City.resolve(candidate.map_meta).zones),"R1-R5 unchanged")
	var fortifications:Array=City.resolve(candidate.map_meta).get("fortifications",[])
	check(fortifications.size()==1 and fortifications[0].settings.closed and fortifications[0].settings.gates.size()==7,"one closed town circuit with seven gates")
	if fortifications.size()==1:
		var water_count:=0
		for gate:Dictionary in fortifications[0].settings.gates:
			if gate.get("kind","")=="water":water_count+=1
		check(water_count==3,"three water gates and four land gates")
	var reference:Dictionary=candidate.map_meta.get("town_reference",{})
	check(reference.has("fortification_layout") and reference.has("market_functional_layout"),"native final layout metadata retained")
	check(candidate.map_meta.get("building_instances",{}).size()==acceptance.get("house_count",-1),"native house count matches reviewed layout")
	check(City.token(source.map_meta.spawn)==City.token(candidate.map_meta.spawn),"birth point preserved")
	var allowed:=relocation_exceptions(fort,source,candidate);var extra_allowed:=building_relocations(source,candidate,allowed);allowed.merge(extra_allowed);var preserved:=0
	for row:Dictionary in source.records:
		if row.has("terrain_mesh") or row.has("road_mesh"):continue
		if allowed.has(str(row.uuid)):continue
		if City.token(row)!=City.token(candidate._find(row.uuid)):check(false,"existing object changed unexpectedly "+row.uuid);break
		preserved+=1
	report.preserved_objects=preserved
	for item:Dictionary in pins.values():check(FileAccess.get_sha256(item.path)==item.sha256,"evidence unchanged before publication "+str(item.path))
	check(FileAccess.get_sha256(FORMAL)==baseline_sha and FileAccess.get_sha256(CANDIDATE)==candidate_sha,"last conflict check before publication")
	if failures:finish();return
	var records_token:=City.token(candidate.records);var meta_token:=City.token(candidate.map_meta)
	candidate.accept_save(FORMAL,baseline_sha)
	check(candidate.save(FORMAL)==OK,"native atomic conflict-aware publication")
	if failures:finish();return
	report.published=true;report.before_sha256=baseline_sha;report.candidate_sha256=candidate_sha;report.formal_sha256=FileAccess.get_sha256(FORMAL)
	report.acceptance_sha256=acceptance_sha;report.save_metrics=candidate.last_save_metrics
	var reopened=Doc.open_file(FORMAL)
	check(reopened!=null and City.token(reopened.records)==records_token and City.token(reopened.map_meta)==meta_token,"formal native save reopens exactly")
	report.house_count=candidate.map_meta.building_instances.size();report.record_count=candidate.records.size();finish()
