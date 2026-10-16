extends SceneTree
## Batch promotion of four reviewed market prefabs. No map writes.
## Default is read-only preflight; --publish requires the private GPU desktop.
## Normal capture happens in an isolated library before immutable publication.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Prefabs=preload("res://scripts/world_editor/prefab_library.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Embedded=preload("res://scripts/world3d/embedded_glb.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Thumbnails=preload("res://scripts/world_editor/asset_thumbnails.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const PreviewEnvironment=preload("res://scripts/world_editor/asset_preview_environment.gd")
const ART="D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016"
const REVIEW="D:/code/rmmo_runtime/review_artifacts/axel_market_realism_20261016"
const FORMAL="D:/code/rmmo_runtime/packs/default/assets"
var publishing:=false
var take:=""
var review_take:=""
var plan_version:="v1"
var receipt:=""
var rows:Array=[]
var source_masters:Array=[]
var promoted:Array=[]
var native_files_before:Dictionary={}
var report:Dictionary={"status":"initializing","catalog_committed":false,"map_modified":false,"checks":[],"failures":[],"new_immutable_files":[],"reused_immutable_files":[],"captures":[],"imports":[],"mapping":[],"thumbnail_outputs":[]}

func _initialize()->void:run.call_deferred()
func canonical(path:String)->String:return ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()
func same(a:Variant,b:Variant)->bool:return JSON.stringify(a,"",true,true)==JSON.stringify(b,"",true,true)
func read_json(path:String)->Dictionary:
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return value if value is Dictionary else {}
func write_receipt()->void:
	if receipt.is_empty():return
	var file:=FileAccess.open(receipt,FileAccess.WRITE)
	if file==null:push_error("Cannot write publication receipt");return
	file.store_string(JSON.stringify(report,"\t",true,true));file.flush();file.close()
func check(ok:bool,label:String)->bool:
	report.checks.append({"check":label,"pass":ok})
	if not ok:report.failures.append(label)
	print("PASS " if ok else "FAIL ",label);write_receipt();return ok
func finish()->void:
	if not report.failures.is_empty():report.status="failed_after_commit" if report.catalog_committed else "failed_not_committed"
	elif report.catalog_committed:report.status="published_maps_unchanged"
	else:report.status="preflight_only_no_publication"
	if publishing and not native_files_before.is_empty():
		report.observed_new_derived_files=[]
		for path:String in native_inventory():
			if not native_files_before.has(path):report.observed_new_derived_files.append({"path":path,"sha256":FileAccess.get_sha256(path),"attribution":"Appeared during this run; source-bound formal identities are recorded separately. Concurrent external cache writers are not claimed as this tool's work."})
	report.ok=report.failures.is_empty();report.publish_requested=publishing;write_receipt()
	print("AXEL_MARKET_PUBLICATION ",JSON.stringify({"ok":report.ok,"status":report.status,"catalog_committed":report.catalog_committed,"receipt":receipt,"failures":report.failures,"mapping":report.mapping},"",true,true));quit(0 if report.ok else 1)
func native_inventory()->Dictionary:
	var result:Dictionary={};var base:=Compiled.directory(Paths.external_root())
	for directory_:String in [base,Footprint.directory(Paths.external_root())]:
		for name_:String in DirAccess.get_files_at(directory_):result[directory_.path_join(name_)]=true
	return result
func expanded(entry:Dictionary)->Dictionary:
	var result:=entry.duplicate(true)
	for key:String in ["asset_path","prefab_path","thumbnail_path"]:
		if result.get(key) is String:
			var path:String=result[key];result[key]=canonical(path if path.is_absolute_path() else FORMAL.path_join(path))
	return result
func validate_row(row:Dictionary)->bool:
	var old:Dictionary=row.existing_prefab
	if not check(Compiled._sha(row.source_sha256) and Compiled._sha(row.candidate_sha256) and canonical(row.source)==FORMAL.path_join(row.source_sha256+".glb") and Paths.allowed(canonical(row.candidate),ART) and str(row.candidate).get_extension()=="glb" and canonical(row.prospective_formal_glb)==FORMAL.path_join(row.candidate_sha256+".glb") and canonical(old.prefab_path).begins_with(FORMAL+"/prefabs/") and canonical(old.prefab_path)==canonical(expanded(old.entry).prefab_path),row.asset+" confined fixed publication paths"):return false
	if not check(FileAccess.get_sha256(row.source)==row.source_sha256 and FileAccess.get_sha256(row.candidate)==row.candidate_sha256,row.asset+" frozen source/candidate SHA"):return false
	if not check(FileAccess.get_sha256(old.prefab_path)==old.prefab_sha256,row.asset+" old prefab retained and unchanged"):return false
	if not check(Embedded.can_copy(row.candidate),row.asset+" production embedded exact-copy grammar"):return false
	var current:=read_json(old.prefab_path)
	# The immutable old file SHA is authoritative. A Python JSON plan can expand
	# tiny scientific-notation values (scroll position.x differs by 7.8e-19).
	# Never replace actual old data with that diagnostic copy or loosen equality.
	if not check(current.get("records",[]).size()==1 and current.records[0].kind=="asset" and current.records[0].asset_path==row.source_sha256+".glb",row.asset+" SHA-pinned actual one-record old prefab"):return false
	var expected:=current.duplicate(true);expected.records[0].asset_path=row.candidate_sha256+".glb"
	# Normal Prefabs.capture serializes position through Godot Vector3. Verify
	# its pivot is exactly zero and float32 position exactly unchanged. Compare
	# the saved JSON to the original JSON (the production serializer rounds the
	# Vector3 back to its original decimal notation), not full-precision float32.
	var geometry=preload("res://scripts/world_editor/selection_geometry.gd")
	var bounds:AABB=geometry.bounds(current.records)
	var pivot:=Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	var source_position:Vector3=geometry.vector(current.records[0],"position")
	if not check(pivot==Vector3.ZERO,row.asset+" production capture pivot is exactly zero"):return false
	row.actual_old_payload=current
	row.actual_expected_payload=expected
	row.position_serialization={"original_json":current.records[0].position,"production_vector3":[source_position.x,source_position.y,source_position.z],"effective_position_unchanged":true,"saved_json_required_exact_original":true}
	return true
func validate_acceptance()->bool:
	var folder:=REVIEW.path_join(review_take);var accepted:=read_json(folder.path_join("acceptance.json"))
	if not check(accepted.get("version")==1 and accepted.get("visual_accepted")==true and accepted.get("intentional_visual_change")==true and accepted.get("assets",{}).size()==4,"actual four-asset visual acceptance receipt"):return false
	report.acceptance_asset_evidence=[]
	for row:Dictionary in rows:
		var name_:String=row.asset;var accepted_row:Dictionary=accepted.assets.get(name_,{});var evidence:Dictionary=accepted_row.get("evidence",{})
		var evidence_take:String=evidence.get("take","");var evidence_version:String=evidence.get("plan_version","")
		if not check(evidence_take.is_valid_identifier() and evidence_version.is_valid_identifier() and evidence_version.begins_with("v") and evidence_version.substr(1).is_valid_int(),name_+" explicit confined per-asset review take/version"):return false
		var evidence_folder:=REVIEW.path_join(evidence_take).path_join(name_);var evidence_plan_path:=ART.path_join(evidence_version).path_join("review_plan.json")
		var evidence_plan:=read_json(evidence_plan_path);var evidence_rows:Array=evidence_plan.get("rows",[]).filter(func(value):return value.get("asset")==name_)
		if not check(evidence_rows.size()==1 and FileAccess.get_sha256(evidence_plan_path)==evidence.get("plan_sha256"),name_+" per-asset evidence plan exists and matches accepted SHA"):return false
		if not check(evidence_rows[0].get("source_sha256")==row.source_sha256 and evidence_rows[0].get("candidate_sha256")==row.candidate_sha256,name_+" reused evidence is for exact current baseline/candidate bytes"):return false
		var a:=read_json(evidence_folder.path_join("baseline.json"));var b:=read_json(evidence_folder.path_join("candidate.json"));var c:=read_json(evidence_folder.path_join("compare.json"))
		if not check(FileAccess.get_sha256(evidence_folder.path_join("baseline.json"))==evidence.get("baseline_report_sha256") and FileAccess.get_sha256(evidence_folder.path_join("candidate.json"))==evidence.get("candidate_report_sha256"),name_+" accepted source/native/render reports match SHA"):return false
		if not check(a.get("passed",false) and b.get("passed",false) and c.get("passed",false),name_+" actual native/A-B reports passed"):return false
		if not check(a.get("plan_sha256")==FileAccess.get_sha256(evidence_plan_path) and b.get("plan_sha256")==a.get("plan_sha256") and c.get("plan_sha256")==a.get("plan_sha256"),name_+" reports bind explicit per-asset frozen review plan version"):return false
		if not check(a.get("original_sha")==row.source_sha256 and b.get("original_sha")==row.candidate_sha256 and accepted_row.get("candidate_sha256")==row.candidate_sha256,name_+" accepted actual candidate identity"):return false
		if not check(a.get("generator")==Compiled.generator() and b.get("generator")==Compiled.generator(),name_+" current native generator"):return false
		if not check(accepted_row.get("compare_sha256")==FileAccess.get_sha256(evidence_folder.path_join("compare.json")) and accepted_row.get("visual_accepted")==true,name_+" visual receipt pins comparison evidence"):return false
		if not check(a.get("camera_views")==b.get("camera_views") and a.get("render_spec")==b.get("render_spec"),name_+" reused A/B retains exact camera and illumination contract"):return false
		var native_payload:String=b.get("native",{}).get("payload","");var native_sha:String=b.get("native",{}).get("payload_sha256","")
		if not check(Paths.allowed(native_payload,evidence_folder) and FileAccess.file_exists(native_payload) and FileAccess.get_sha256(native_payload)==native_sha,name_+" actual isolated native payload still matches reviewed identity"):return false
		var view_count:=12 if name_=="potion" else 9
		if not check(c.get("intentional_visual_change",false) and c.get("images",[]).size()==view_count and c.images.all(func(image):return image.get("valid",false)) and b.get("screenshots",[]).size()==view_count,name_+" full same-camera realism A-B coverage, no pixel-equality gate"):return false
		if not check(not b.get("active_material_proof",{}).is_empty(),name_+" actual active material channel proof"):return false
		if not check(a.get("active_material_proof",{}).get("uv_binding_contract_version")==1 and b.active_material_proof.get("uv_binding_contract_version")==1,name_+" actual source-to-prepared UV sampling proof; old v2 diagnostics cannot publish"):return false
		if not check(b.get("render_spec",{}).get("reflection_environment",{}).get("helper_sha256")==FileAccess.get_sha256("res://scripts/world_editor/asset_preview_environment.gd") and a.render_spec.reflection_environment==b.render_spec.reflection_environment,name_+" same current shared reflection recipe in accepted baseline/candidate"):return false
		if name_=="potion":
			var optical_review:Dictionary=accepted_row.get("optics_review",{})
			for criterion:String in ["bright_background_visible","dark_background_visible","liquid_surface_visible","no_plastic_or_emissive_panel_appearance"]:
				if not check(optical_review.get(criterion)==true,"actual potion image review: "+criterion):return false
		for shot:Dictionary in b.screenshots:
			var image_path:String=shot.path;var q:=read_json(image_path+".review-image.json")
			if not check(image_path.ends_with(".webp") and q.get("quality")==90 and q.get("lossless")==false and q.get("sha256")==FileAccess.get_sha256(image_path) and accepted_row.get("viewed_image_sha256",[]).has(q.sha256),name_+" actual viewed Q90 "+str(shot.name)):return false
		report.acceptance_asset_evidence.append({"asset":name_,"evidence":evidence,"baseline_report":evidence_folder.path_join("baseline.json"),"candidate_report":evidence_folder.path_join("candidate.json"),"comparison_report":evidence_folder.path_join("compare.json"),"compare_sha256":accepted_row.compare_sha256,"source_sha256":row.source_sha256,"candidate_sha256":row.candidate_sha256,"isolated_native_payload":native_payload,"isolated_native_payload_sha256":native_sha,"reused_prior_version":evidence_version!=plan_version})
	report.acceptance={"path":folder.path_join("acceptance.json"),"sha256":FileAccess.get_sha256(folder.path_join("acceptance.json"))};return true
func copy_immutable(source:String,target:String,expected:String)->bool:
	if not check(Paths.allowed(source) and Paths.allowed(target) and FileAccess.get_sha256(source)==expected,"immutable source identity "+target.get_file()):return false
	if FileAccess.file_exists(target):
		var equal:=FileAccess.get_sha256(target)==expected
		if equal:report.reused_immutable_files.append({"path":target,"sha256":expected})
		return check(equal,"existing immutable target verified "+target.get_file())
	if not check(DirAccess.make_dir_recursive_absolute(target.get_base_dir())==OK,"create immutable destination directory"):return false
	# File.Copy(source,target) refuses replacement. Never publish mutable bytes
	# with AtomicFile under a content-addressed prefab or source filename.
	var command:="$ErrorActionPreference='Stop'; [System.IO.File]::Copy('%s','%s')"%[canonical(source).replace("'","''"),canonical(target).replace("'","''")]
	var output:Array=[];var code:=OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-Command",command]),output,true,false)
	if code==0:report.new_immutable_files.append({"path":target,"sha256":expected});write_receipt()
	return check(code==0 and FileAccess.get_sha256(target)==expected,"exclusive immutable copy "+target.get_file())
func stage_capture(row:Dictionary,staging:String)->Dictionary:
	# Import/capture compile under this process-local private root. Every normal
	# return restores the real root before immutable promotion/formal compilation.
	# Copy the exact candidate before switching roots so validation stays confined.
	var local_input:=staging.path_join("input").path_join(row.candidate_sha256+".glb")
	if not check(DirAccess.make_dir_recursive_absolute(local_input.get_base_dir())==OK and DirAccess.copy_absolute(row.candidate,local_input)==OK and FileAccess.get_sha256(local_input)==row.candidate_sha256,row.asset+" exact private staging input"):return {}
	var manager:Node=root.get_node_or_null("AssetManager")
	if not check(manager!=null,row.asset+" process content-root owner available"):return {}
	var previous:String=manager.content_root_override
	manager.content_root_override=canonical(staging)
	var output:=stage_capture_local(row,staging,local_input)
	manager.content_root_override=previous
	if not check(Paths.external_root()==canonical(FORMAL.get_base_dir().get_base_dir().get_base_dir()),row.asset+" formal root restored after private capture"):return {}
	return output
func stage_capture_local(row:Dictionary,staging:String,local_input:String)->Dictionary:
	report.phase="stage_import:"+row.asset;write_receipt()
	var library:=Library.new(staging.path_join("assets"))
	var imported:Dictionary=library.import_file(local_input)
	if not check(imported.get("ok",false) and imported.get("compiled_asset",{}).get("ok",false) and imported.get("compiled_asset",{}).get("footprint",{}).get("ok",false),row.asset+" normal staging import/native/footprint"):return {}
	var source_path:String=imported.entry.asset_path
	if not check(FileAccess.get_sha256(source_path)==row.candidate_sha256 and source_path.get_file()==row.candidate_sha256+".glb",row.asset+" importer preserved candidate exact bytes"):return {}
	var records:Array=row.actual_old_payload.records.duplicate(true);records[0].asset_path=source_path
	report.phase="stage_capture:"+row.asset;write_receipt()
	var result:=Prefabs.capture(records,library,row.label)
	if not check(result.get("ok",false),row.asset+" normal production Prefabs.capture"):return {}
	var payload:=read_json(result.entry.prefab_path)
	if not check(same(payload,row.actual_expected_payload),row.asset+" captured payload preserves UUID/position/rotation/size/all other fields"):return {}
	var reopened:=Prefabs.read(result.entry)
	if not check(reopened.get("ok",false) and reopened.records.size()==1 and canonical(reopened.records[0].asset_path)==canonical(source_path),row.asset+" capture save/reopen actual candidate dependency"):return {}
	var isolated_identity:=Library._verified_compiled_identity(source_path)
	if not check(not isolated_identity.is_empty() and str(isolated_identity.get("product","")).begins_with(canonical(staging)+"/cache/world3d/compiled_assets_v1/"),row.asset+" staging native lives only under its private root"):return {}
	var output:={"asset":row.asset,"stage_entry":result.entry,"prefab_sha256":FileAccess.get_sha256(result.entry.prefab_path),"source":source_path,"source_sha256":row.candidate_sha256,"isolated_native_identity":isolated_identity,"isolated_content_root":canonical(staging),"position_serialization":row.position_serialization}
	report.captures.append(output);write_receipt();return output
func promote_files(row:Dictionary,capture:Dictionary)->Dictionary:
	report.phase="immutable_promote:"+row.asset;write_receipt()
	var target:String=row.prospective_formal_glb;var prefab:String=FORMAL.path_join("prefabs").path_join(str(capture.stage_entry.prefab_path).get_file())
	if not copy_immutable(capture.source,target,row.candidate_sha256):return {}
	if not copy_immutable(capture.stage_entry.prefab_path,prefab,capture.prefab_sha256):return {}
	report.phase="formal_native:"+row.asset;write_receipt()
	var native:=Library._compile_import(target)
	report.imports.append({"asset":row.asset,"formal_source":target,"source_sha256":FileAccess.get_sha256(target),"native":native});write_receipt()
	if not check(native.get("ok",false) and native.get("footprint",{}).get("ok",false),row.asset+" actual formal-source native/footprint"):return {}
	var loaded:Dictionary=Compiled.read(target,row.candidate_sha256)
	if not check(loaded.get("hit",false) and loaded.get("source_digest")==row.candidate_sha256,row.asset+" native index and source digest match candidate"):Drainer.dispose_result(loaded);return {}
	var candidate:Dictionary=Footprint.candidate(target,Paths.external_root(),row.candidate_sha256)
	Drainer.dispose_result(loaded)
	if not check(not candidate.is_empty(),row.asset+" formal native footprint identity"):return {}
	var entry:=expanded(row.existing_prefab.entry);entry.prefab_path=prefab
	entry.thumbnail_path=FORMAL.path_join("thumbnails").path_join(prefab.get_file().get_basename()+".png")
	# Appearance changes invalidate old thumbnails. Generate before catalog commit.
	var thumbnail:Dictionary=await render_new_thumbnail(entry,row.candidate_sha256,capture.prefab_sha256)
	if not check(thumbnail.get("ok",false),row.asset+" new production thumbnail ready before commit"):return {}
	report.thumbnail_outputs.append({"asset":row.asset,"source_sha256":row.candidate_sha256,"prefab_sha256":capture.prefab_sha256,"path":entry.thumbnail_path,"sha256":FileAccess.get_sha256(entry.thumbnail_path),"dimensions":[96,80],"method":"AssetThumbnails.queue_import + PrefabLibrary.preview","environment_helper_sha256":FileAccess.get_sha256("res://scripts/world_editor/asset_preview_environment.gd"),"environment_recipe_version":PreviewEnvironment.RECIPE_VERSION})
	var reopened:=Prefabs.read(entry)
	if not check(reopened.get("ok",false) and canonical(reopened.records[0].asset_path)==canonical(target) and FileAccess.get_sha256(target)==row.candidate_sha256,row.asset+" formal prefab resolves exact native candidate"):return {}
	return {"asset":row.asset,"entry":entry,"old_asset_id":canonical(row.existing_prefab.old_asset_id),"new_asset_id":canonical(prefab),"old_glb":canonical(row.source),"new_glb":canonical(target),"candidate_sha256":row.candidate_sha256,"prefab_sha256":capture.prefab_sha256,"formal_native_identity":candidate}
func render_new_thumbnail(entry:Dictionary,source_sha:String,prefab_sha:String)->Dictionary:
	if FileAccess.file_exists(entry.thumbnail_path):
		# An interrupted prior take may have completed the immutable image before
		# catalog commit. Reuse only its SHA-bound production receipt, never the
		# previous visual version's thumbnail or an arbitrary existing image.
		for sibling:String in DirAccess.get_directories_at(REVIEW.path_join("publication")):
			var previous:Dictionary=read_json(REVIEW.path_join("publication").path_join(sibling).path_join("publication.json"))
			for item:Dictionary in previous.get("thumbnail_outputs",[]):
				if item.get("path")==entry.thumbnail_path and item.get("source_sha256")==source_sha and item.get("prefab_sha256")==prefab_sha and item.get("sha256")==FileAccess.get_sha256(entry.thumbnail_path) and item.get("environment_helper_sha256")==FileAccess.get_sha256("res://scripts/world_editor/asset_preview_environment.gd"):
					var existing:=Image.load_from_file(entry.thumbnail_path)
					if existing!=null and existing.get_size()==Vector2i(96,80):return {"ok":true,"reused_own_verified_production_thumbnail":true}
		return {"ok":false,"error":"Existing thumbnail lacks this exact candidate's production receipt"}
	var thumbs:=Thumbnails.new();root.add_child(thumbs)
	var done:Dictionary={};var key:=Thumbnails.key_for(entry)
	thumbs.import_finished.connect(func(id:String,path:String,error:int):done[id]={"path":path,"error":error})
	thumbs.queue_import(entry)
	var deadline:=Time.get_ticks_msec()+180000
	while not done.has(key) and Time.get_ticks_msec()<deadline:await process_frame
	var ok:bool=done.has(key) and done[key].error==OK and FileAccess.file_exists(entry.thumbnail_path)
	if ok:
		var image:=Image.load_from_file(entry.thumbnail_path)
		ok=image!=null and image.get_size()==Vector2i(96,80) and thumbs.state(entry).status=="ready"
	thumbs.queue_free();await process_frame
	return {"ok":ok}

func commit_catalog()->bool:
	# Rebase onto the current generation, preserving all unrelated concurrent work.
	var library:=Library.new(FORMAL);var before:Array=library.entries.duplicate(true);var touched:Array=[]
	report.catalog_before_commit={"sha256":FileAccess.get_sha256(FORMAL.path_join("library.json")),"entry_count":before.size()}
	for i in rows.size():
		var row:Dictionary=rows[i];var replacement:Dictionary=promoted[i];var matches:Array=[]
		for slot in library.entries.size():
			if canonical(str(library.entries[slot].get("prefab_path","")))==replacement.old_asset_id:matches.append(slot)
		if not check(matches.size()==1,row.asset+" unique old slot in fresh catalog"):return false
		var slot:int=matches[0]
		if not check(same(expanded(library.entries[slot]),expanded(row.existing_prefab.entry)),row.asset+" target catalog entry unchanged since plan"):return false
		if not check(not library.entries.any(func(e):return canonical(str(e.get("prefab_path","")))==replacement.new_asset_id),row.asset+" no duplicate candidate slot"):return false
		library.entries[slot]=replacement.entry.duplicate(true);touched.append(slot);replacement.catalog_slot=slot
		if not validate_row(row):return false
	for i in before.size():
		if i not in touched and not check(same(library.entries[i],before[i]),"unrelated catalog slot retained "+str(i)):return false
	if not check(library.entries.size()==before.size() and touched.size()==4,"replace exactly four current slots; no temporary import entries"):return false
	for master:Dictionary in source_masters:
		if not check(FileAccess.get_sha256(master.file)==master.sha256,"source master retained before commit"):return false
	report.mapping=promoted;report.status="ready_for_atomic_catalog_commit";write_receipt()
	var error:Error=library.save()
	if not check(error==OK,"single production revision/lock/atomic catalog save: "+error_string(error)):return false
	report.catalog_committed=true;report.catalog_committed_sha256=FileAccess.get_sha256(FORMAL.path_join("library.json"));write_receipt()
	var reopened:=Library.new(FORMAL)
	for item:Dictionary in promoted:
		if not check(reopened.entries.any(func(e):return same(expanded(e),item.entry)),item.asset+" new catalog entry reopens"):return false
	return true
func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("AXEL_MARKET_PUBLISH_SYNTAX_OK");quit();return
	if "--inspect-capture-pivots" in OS.get_cmdline_user_args():
		var plan_=read_json(ART.path_join(plan_version).path_join("publication_plan.json"))
		for row_:Dictionary in plan_.get("rows",[]):
			var bounds_:AABB=preload("res://scripts/world_editor/selection_geometry.gd").bounds(row_.existing_prefab.prefab.records)
			print("CAPTURE_PIVOT ",row_.asset," ",Vector3(bounds_.get_center().x,bounds_.position.y,bounds_.get_center().z))
		quit();return
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--publish":publishing=true
		elif arg.begins_with("--take="):take=arg.trim_prefix("--take=")
		elif arg.begins_with("--review-take="):review_take=arg.trim_prefix("--review-take=")
		elif arg.begins_with("--plan-version="):plan_version=arg.trim_prefix("--plan-version=")
		else:check(false,"unknown argument "+arg);finish();return
	if not check(take.is_valid_identifier() and review_take.is_valid_identifier() and plan_version.is_valid_identifier() and plan_version.begins_with("v") and plan_version.substr(1).is_valid_int(),"explicit valid publication/review take identifiers"):finish();return
	var output:=REVIEW.path_join("publication").path_join(take)
	if not check(not DirAccess.dir_exists_absolute(output),"fresh receipt/staging directory; retain previous attempt"):finish();return
	if DirAccess.make_dir_recursive_absolute(output)!=OK:check(false,"receipt directory");finish();return
	receipt=output.path_join("publication.json");report.take=take;report.review_take=review_take
	var plan:=read_json(ART.path_join(plan_version).path_join("publication_plan.json"));rows=plan.get("rows",[])
	if not check(plan.get("version")==1 and rows.size()==4 and rows.map(func(row):return row.asset)==["pottery","scroll","potion","ore"],"fixed four-model publication plan"):finish();return
	report.plan_path=ART.path_join(plan_version).path_join("publication_plan.json");report.plan_sha256=FileAccess.get_sha256(ART.path_join(plan_version).path_join("publication_plan.json"));report.catalog_plan_sha256=plan.catalog_before.sha256
	source_masters=plan.get("source_masters",[])
	if not check(not source_masters.is_empty(),"pinned source Blender masters"):finish();return
	for master:Dictionary in source_masters:
		if not check(FileAccess.get_sha256(master.file)==master.sha256,"original source Blender master retained"):finish();return
	report.source_masters=source_masters
	for row:Dictionary in rows:
		if not validate_row(row):finish();return
	if not validate_acceptance():finish();return
	if not publishing:finish();return
	if not check(DisplayServer.get_name()!="headless" and OS.get_name()=="Windows","private-desktop graphics publication required"):finish();return
	native_files_before=native_inventory()
	var captures:Array=[]
	for row:Dictionary in rows:
		var capture:=stage_capture(row,output.path_join("staging").path_join(row.asset))
		if capture.is_empty():finish();return
		captures.append(capture)
	for i in rows.size():
		var item:Dictionary=await promote_files(rows[i],captures[i])
		if item.is_empty():finish();return
		promoted.append(item)
	if not commit_catalog():finish();return
	report.old_files_retained=rows.all(func(row):return FileAccess.get_sha256(row.source)==row.source_sha256 and FileAccess.get_sha256(row.existing_prefab.prefab_path)==row.existing_prefab.prefab_sha256)
	check(report.old_files_retained,"all old source GLBs and prefabs retained unchanged")
	finish()
