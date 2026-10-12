extends SceneTree
## Offline, one-map migration. Default is read-only metadata planning.
## --spec=<json> [--publish]. Publishing must use run_godot_background.py.
## No full-map instantiate; import only selected assets, then one reference save.
## This is not the missing UI/MCP batch-relink product capability.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const BoundsManifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
const Catalog=preload("res://scripts/world_editor/resource_pack_catalog.gd")
const HANDOFF="res://review_artifacts/town_asset_size_audit_20261011/candidate_handoff.json"
const ORIGINALS="res://review_artifacts/town_large_asset_art_handoff_20261011.json"
var publish:=false
var report_path:=""
var report:Dictionary={"scope":"Offline single-map asset reference promotion; no UI/MCP batch relink API", "checks":[],"failures":[],"imports":[],"map_published":false}

func _initialize()->void:
	run.call_deferred()

func canonical(path:String)->String:
	return ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()

func read_json(path:String,limit:int=4*1024*1024)->Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>limit:return {}
	var result:Variant=JSON.parse_string(file.get_as_text());file.close()
	return result if result is Dictionary else {}

func check(ok:bool,label:String)->bool:
	report.checks.append({"label":label,"ok":ok})
	if not ok:report.failures.append(label)
	print("PASS " if ok else "FAIL ",label)
	return ok

func finish()->void:
	report.ok=report.failures.is_empty();report.publish_requested=publish
	if publish and not report_path.is_empty():
		var error:=DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
		var file:=FileAccess.open(report_path,FileAccess.WRITE) if error==OK else null
		if file!=null:file.store_string(JSON.stringify(report,"\t",false,true));file.close()
		else:report.ok=false;report.failures.append("Cannot write publication receipt")
	print("JOINT_MODEL_PROMOTION ",JSON.stringify(report,"",false,true))
	quit(0 if report.ok else 1)

func replace_paths(value:Variant,mapping:Dictionary,changed:Array)->void:
	if value is Dictionary:
		for key in value:
			if key=="asset_path" and value[key] is String:
				var path:=canonical(value[key])
				if mapping.has(path):changed.append(path);value[key]=mapping[path]
			else:replace_paths(value[key],mapping,changed)
	elif value is Array:
		for item in value:replace_paths(item,mapping,changed)

func no_source_changed(rows:Dictionary)->bool:
	for row:Dictionary in rows.values():
		if FileAccess.get_sha256(row.original)!=row.original_sha256 or FileAccess.get_sha256(row.candidate)!=row.candidate_sha256:return false
	return true

func usable_label(value:Variant,row:Dictionary)->bool:
	if not value is String:return false
	var name:String=value.strip_edges()
	if name.is_empty() or name.length()>200 or name.contains("\n") or name.contains("\r"):return false
	return not Compiled._sha(name) and name!=row.label and not name.begins_with("obj_")

func original_label(row:Dictionary,catalog:Array,records:Array)->Dictionary:
	# Reuse an unambiguous author name, never infer a model's purpose from its
	# hash or an analysis identifier. Instance-specific conflicting names fall
	# back to the explicit art-review label in the migration specification.
	var names:Dictionary={}
	for entry:Dictionary in catalog:
		if canonical(str(entry.get("asset_path","")))==row.original and usable_label(entry.get("label"),row):names[entry.label]=true
	if names.size()==1:return {"label":names.keys()[0],"source":"original_catalog"}
	for field:String in ["editor_name","label"]:
		names.clear()
		for record:Dictionary in records:
			if canonical(str(record.get("asset_path","")))==row.original and usable_label(record.get(field),row):names[record[field]]=true
		if names.size()==1:return {"label":names.keys()[0],"source":"original_record."+field}
	return {"label":row.catalog_label,"source":row.catalog_label_source}

func closed_candidate(path:String)->Dictionary:
	# This migration only accepts the static closed native grammar already
	# checked by AssetBoundsManifest, including its recursive URI rejection and
	# material-extension allowlist. It does not widen the public import policy.
	if not Paths.allowed(path) or path.get_extension().to_lower()!="glb":return {}
	var manifest:Dictionary=BoundsManifest.read(path)
	if not manifest.get("known",false):return {}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()<28:return {}
	var length:=file.get_length()
	if length!=manifest.file_length or file.get_32()!=0x46546c67 or file.get_32()!=2 or file.get_32()!=length:return {}
	var json_size:=file.get_32()
	if file.get_32()!=0x4e4f534a or json_size<4 or json_size>BoundsManifest.MAX_JSON or json_size%4!=0 or json_size!=manifest.json_bytes or json_size+28>length:return {}
	var bytes:=file.get_buffer(json_size)
	var hash_context:=HashingContext.new();hash_context.start(HashingContext.HASH_SHA256);hash_context.update(bytes)
	if bytes.size()!=json_size or hash_context.finish().hex_encode()!=manifest.json_sha256:return {}
	var bin_size:=file.get_32()
	if file.get_32()!=0x004e4942 or bin_size%4!=0 or file.get_position()+bin_size!=length:return {}
	file.close()
	var data:Variant=JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary:return {}
	var images:Variant=data.get("images",[])
	var views:Array=data.bufferViews
	if not images is Array:return {}
	# Bounds eligibility is not an image validator. Require embedded PNG/JPEG
	# storage explicitly; the one PreparedSource will validate actual decoding.
	for image:Variant in images:
		if not image is Dictionary or not BoundsManifest._index(image.get("bufferView"),views.size()) or image.get("mimeType") not in ["image/png","image/jpeg"]:return {}
	var textures:Variant=data.get("textures",[])
	var samplers:Variant=data.get("samplers",[])
	if not textures is Array or not samplers is Array:return {}
	for texture:Variant in textures:
		if not texture is Dictionary or not BoundsManifest._index(texture.get("source"),images.size()):return {}
		if texture.has("sampler") and not BoundsManifest._index(texture.sampler,samplers.size()):return {}
	return {"ok":true,"contract":"AssetBoundsManifest closed static grammar plus embedded image/texture storage",
		"json_sha256":manifest.json_sha256,"file_length":length,"images":images.size(),"textures":textures.size(),
		"extensions_used":data.get("extensionsUsed",[])}

func copy_or_move_new(source:String,target:String,move:bool)->Error:
	# File.Move and the two-argument File.Copy refuse an existing destination.
	# Do not call Atomic.publish here: its replacement behavior is for mutable
	# documents, while these content-addressed assets must never be overwritten.
	if OS.get_name()!="Windows" or not Paths.allowed(source) or not Paths.allowed(target):return ERR_UNAVAILABLE
	if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):return ERR_ALREADY_EXISTS
	var command:="[System.IO.File]::%s('%s','%s')"%["Move" if move else "Copy",canonical(source).replace("'","''"),canonical(target).replace("'","''")]
	var output:Array=[]
	var code:=OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-Command","$ErrorActionPreference='Stop'; "+command]),output,true,false)
	return OK if code==0 else ERR_FILE_CANT_WRITE

func import_failure(reason:String,prepared:Compiled.PreparedSource=null,owned_staging:String="")->Dictionary:
	if prepared!=null:prepared.dispose()
	# Only a staging copy successfully created by this helper is passed here.
	# Never remove a final immutable target, even after later compilation fails.
	if not owned_staging.is_empty() and Paths.allowed(owned_staging) and owned_staging.get_file().begins_with("joint_promote_") and FileAccess.file_exists(owned_staging):DirAccess.remove_absolute(owned_staging)
	return {"ok":false,"error":reason}

func import_exact_candidate(row:Dictionary,library)->Dictionary:
	var source:String=row.candidate;var target:String=row.target;var expected:String=row.candidate_sha256
	if FileAccess.get_sha256(source)!=expected:return import_failure("candidate_source_sha")
	var proof:=closed_candidate(source)
	if proof.is_empty():return import_failure("candidate_not_closed_static_glb")
	var matches:Array=library.entries.filter(func(entry):return canonical(str(entry.get("asset_path","")))==canonical(target))
	if matches.size()>1:return import_failure("duplicate_catalog_target")
	var staging:=""
	var input:=target
	if FileAccess.file_exists(target):
		if FileAccess.get_sha256(target)!=expected or closed_candidate(target).is_empty():return import_failure("existing_immutable_target_corrupt")
	else:
		if DirAccess.make_dir_recursive_absolute(library.directory)!=OK:return import_failure("library_directory")
		staging=library.directory.path_join("joint_promote_%d_%d_%s.glb"%[OS.get_process_id(),Time.get_ticks_usec(),expected])
		if copy_or_move_new(source,staging,false)!=OK:return import_failure("copy_new_staging")
		if FileAccess.get_sha256(staging)!=expected or closed_candidate(staging).is_empty():return import_failure("staging_identity_or_closure",null,staging)
		input=staging
	var prepared:=Compiled.prepare_source(input)
	if prepared.error!=OK or prepared.source_digest!=expected:return import_failure("staged_parse_or_source_identity",prepared,staging)
	var scene:=prepared.get_scene() as Node3D
	if scene==null:return import_failure("staged_scene",prepared,staging)
	var bounds:AABB=Library.bounds_of(scene)
	scene=null # The sole owner retains this exact scene through native compilation.
	if not bounds.position.is_finite() or not bounds.size.is_finite():return import_failure("staged_bounds",prepared,staging)
	if not prepared.current() or FileAccess.get_sha256(source)!=expected:return import_failure("source_changed_before_publish",prepared,staging)
	if not staging.is_empty():
		if copy_or_move_new(staging,target,true)!=OK:return import_failure("immutable_target_publish_conflict",prepared,staging)
		staging=""
		if not prepared.relocate(target):return import_failure("immutable_target_identity",prepared)
	# This shared helper consumes the borrowed preparation exactly once and
	# retires its decoded graph before independently measuring the footprint.
	var native:Dictionary=Library._compile_import(target,prepared)
	var diagnostics:Dictionary=prepared.report()
	if not prepared.disposed:return import_failure("preparation_disposal_contract",prepared)
	if not native.get("ok",false) or not native.get("footprint",{}).get("ok",false):return {"ok":false,"error":"native_or_footprint","compiled_asset":native,"closed_source":proof,"import_preparation":diagnostics}
	if FileAccess.get_sha256(target)!=expected or FileAccess.get_sha256(source)!=expected:return import_failure("source_changed_after_compile")
	var entry:Dictionary=matches[0] if not matches.is_empty() else {"label":row.catalog_label,"category":"导入模型","asset_path":target,
		"thumbnail_path":library.directory.path_join("thumbnails").path_join(expected+".png"),
		"bounds_position":[bounds.position.x,bounds.position.y,bounds.position.z],"bounds_size":[bounds.size.x,bounds.size.y,bounds.size.z]}
	# Registration remains operation-private until every model has a complete
	# native/footprint proof and the caller saves the catalog exactly once.
	if matches.is_empty():library.entries.append(entry)
	return {"ok":true,"entry":entry,"compiled_asset":native,"closed_source":proof,"import_preparation":diagnostics,"exact_source_copy":true}

func run()->void:
	var spec_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--publish":publish=true
		elif arg.begins_with("--spec="):spec_path=arg.trim_prefix("--spec=")
		else:check(false,"Unknown argument: "+arg);finish();return
	var local_specs:=canonical("res://review_artifacts/joint_model_validation_20261011")+"/"
	if not check((Paths.allowed(spec_path) or canonical(spec_path).begins_with(local_specs)) and FileAccess.file_exists(spec_path),"explicit readable specification"):finish();return
	var spec:=read_json(spec_path)
	if not check(spec.get("version")==1 and spec.get("chosen") in ["preferred","combined"] and Compiled._sha(spec.get("expected_formal_sha")) and Compiled._sha(spec.get("fixture_manifest_sha256")),"versioned choice and frozen formal/fixture identities"):finish();return
	var formal:=Paths.external_root().path_join("maps/medieval_river_town/map.gltf")
	var pack_root:=Paths.external_root().path_join("packs/default")
	var library_root:=pack_root.path_join("assets")
	var manifest_path:String=spec.get("fixture_manifest","")
	var receipt:String=spec.get("report","")
	if not check(Paths.allowed(manifest_path,Paths.external_root().path_join("cache/world3d")) and manifest_path.get_file()=="fixture_manifest.json","confined fixture manifest"):finish();return
	var fixture:=read_json(manifest_path)
	var selected:String=spec.chosen
	if not check(not fixture.is_empty() and FileAccess.get_sha256(manifest_path)==spec.fixture_manifest_sha256,"small fixture manifest SHA matches the validated plan"):finish();return
	if not check(fixture.get("source_sha256")==spec.expected_formal_sha and fixture.get("fixtures",{}).has(selected),"fixture binds the requested formal generation and chosen scenario"):finish();return
	if not check(Paths.allowed(receipt,Paths.external_root().path_join("review_artifacts")) and receipt.get_extension()=="json" and not FileAccess.file_exists(receipt),"new confined receipt path (never overwrite earlier evidence)"):finish();return
	# Do not assign the output until it has passed the read-only path checks.
	report_path=receipt
	if not check(Paths.allowed(formal) and Paths.allowed(pack_root) and Paths.allowed(library_root) and Paths.allowed(library_root.path_join("library.json")),"formal map and persistent library path authority"):finish();return
	if not check(Catalog.new().packs().any(func(p):return canonical(p.root)==canonical(pack_root)),"persistent default resource pack is registered"):finish();return
	var handoff:=read_json(HANDOFF)
	var original_handoff:=read_json(ORIGINALS)
	var protected:Dictionary=fixture.get("protected_source_sha256",{})
	if not check(FileAccess.get_sha256(HANDOFF)==protected.get(canonical(HANDOFF),""),"small preferred handoff SHA matches fixture provenance"):finish();return
	if not check(handoff.get("preferred",[]).size()==11 and original_handoff.get("map_sha256")==spec.expected_formal_sha,"fixed art handoff and original town generation"):finish();return
	var known_originals:Dictionary={}
	for row:Dictionary in original_handoff.get("rows",[]):known_originals[canonical(row.path)]=row.source_sha256
	var rows:Dictionary={}
	for row:Dictionary in handoff.preferred:
		var origin:=canonical(row.original)
		if not check(known_originals.get(origin)==row.original_sha256,"original handoff identity "+str(row.label)):finish();return
		rows[origin]={"label":row.label,"original":origin,"original_sha256":row.original_sha256,"candidate":canonical(row.candidate),"candidate_sha256":row.candidate_sha256}
	if selected=="combined":
		if not check(fixture.get("metadata_transplants",[]).size()==7,"seven independently audited metadata overlays"):finish();return
		for row:Dictionary in fixture.metadata_transplants:
			var origin:=canonical(row.original_map_path)
			if not check(known_originals.has(origin) and row.get("all_other_json_exact")==true and row.get("bin_and_other_chunks_exact")==true and row.get("nodes_identity_exact")==true,"overlay receiver conservation "+str(row.label)):finish();return
			rows[origin]={"label":row.label,"original":origin,"original_sha256":known_originals[origin],"candidate":canonical(row.candidate),"candidate_sha256":row.candidate_sha256}
	var expected_types:=11 if selected=="preferred" else 14
	var expected_instances:=59 if selected=="preferred" else 690
	var chosen:Dictionary=fixture.fixtures[selected]
	if not check(rows.size()==expected_types and chosen.get("changed_instances")==expected_instances and chosen.get("changed_ids",[]).size()==expected_instances and chosen.get("records")==4437 and chosen.get("houses")==61,"fixed scenario population"):finish();return
	var mapping:Dictionary={}
	var labels:Variant=spec.get("catalog_labels",{})
	if not check(labels is Dictionary and spec.get("catalog_label_source") is String,"explicit catalog labels with author-review provenance"):finish();return
	for row:Dictionary in rows.values():
		if not check(usable_label(labels.get(row.label),row),"readable catalog label for "+str(row.label)):finish();return
		row.catalog_label=labels[row.label];row.catalog_label_source=spec.catalog_label_source
		if not check(Paths.allowed(row.original) and Paths.allowed(row.candidate) and Compiled._sha(row.candidate_sha256) and FileAccess.file_exists(row.original) and FileAccess.file_exists(row.candidate),"source path and declared identity "+str(row.label)):finish();return
		if not check(protected.get(row.original)==row.original_sha256,"original source identity matches validated fixture "+str(row.label)):finish();return
		if selected=="preferred" and not check(protected.get(row.candidate)==row.candidate_sha256,"preferred source identity matches validated fixture "+str(row.label)):finish();return
		row.target=library_root.path_join(row.candidate_sha256+".glb")
		if not check(Paths.allowed(row.target) and canonical(row.target)!=canonical(row.original),"new immutable persistent target "+str(row.label)):finish();return
		mapping[row.original]=row.target
	report.choice=selected;report.source=formal;report.expected_formal_sha=spec.expected_formal_sha
	report.fixture_manifest=manifest_path;report.expected_changed_instances=expected_instances;report.model_plan=rows.values()
	report.expected_counts={"records":4437,"houses":61,"model_types":expected_types}
	report.import_contract="Bounded offline exact-byte promotion: closed static GLB proof, one PreparedSource, shared native/footprint compiler, then one atomic catalog save; public import policy unchanged"
	report.postpublish_required=["Rebuild/read the dependency index for the final formal map path and SHA", "Real game/editor opening and save/reopen with the selected default switches", "Catalog discovery/thumbnail/new-instance smoke; preserve original source and prior catalog entries"]
	if not publish:
		report.mode="dry_run_metadata_only";report.note="No model/source hashes, imports, native builds, catalog or map writes performed. --publish requires completed joint acceptance and a background GPU process."
		finish();return
	if not check(DisplayServer.get_name()!="headless","publication imports require a real background GPU process"):finish();return
	if not check(FileAccess.get_sha256(formal)==spec.expected_formal_sha,"formal map expected SHA before publication work"):finish();return
	if not check(no_source_changed(rows),"all original and chosen candidate full SHAs match frozen handoff"):finish();return
	# Open once before import; save() keeps this observed signature through all awaits.
	var document=Doc.open_file(formal)
	if not check(document!=null and document._disk_signature==spec.expected_formal_sha and document.records.size()==4437 and document.map_meta.building_instances.size()==61,"CPU author document binds old signature and complete town"):finish();return
	var before:Array=document.records.duplicate(true);var before_meta:Dictionary=document.map_meta.duplicate(true)
	var changed_ids:Array=[];var changes:Dictionary={}
	for record:Dictionary in document.records:
		var paths:Array=[];replace_paths(record,mapping,paths)
		if not paths.is_empty():
			changed_ids.append(record.uuid)
			for path:String in paths:changes[path]=int(changes.get(path,0))+1
	var expected_ids:Array=chosen.changed_ids.duplicate();expected_ids.sort()
	var actual_ids:=changed_ids.duplicate();actual_ids.sort()
	if not check(changed_ids.size()==expected_instances and actual_ids==expected_ids and Pose.same(changes,chosen.changed_paths),"exact validated instance IDs and per-model replacement counts"):finish();return
	var reverse:Dictionary={}
	for origin:String in mapping:reverse[mapping[origin]]=origin
	var restored:Array=document.records.duplicate(true);var ignored:Array=[];replace_paths(restored,reverse,ignored)
	if not check(Pose.same(restored,before) and Pose.same(document.map_meta,before_meta),"only asset_path changes; complete field and metadata conservation"):finish();return
	report.changed_ids=changed_ids;report.changed_paths=changes
	var library=Library.new(library_root)
	var previous_catalog:Array=library.entries.duplicate(true)
	report.catalog_sha_before=library._revision
	report.catalog_entries_before=previous_catalog
	for row:Dictionary in rows.values():
		var name:=original_label(row,previous_catalog,before)
		row.catalog_label=name.label;row.catalog_label_source=name.source
	var generator:=Compiled.generator();var footprint_generator:=Footprint.generator()
	for row:Dictionary in rows.values():
		if not check(FileAccess.get_sha256(formal)==spec.expected_formal_sha and Compiled.generator()==generator and Footprint.generator()==footprint_generator,"map and pipeline generation unchanged before "+str(row.label)):finish();return
		var existed:bool=library.entries.any(func(entry):return canonical(str(entry.get("asset_path","")))==canonical(row.target))
		var result:Dictionary=import_exact_candidate(row,library)
		var native:Dictionary=result.get("compiled_asset",{})
		var footprint:Dictionary=native.get("footprint",{})
		report.imports.append({"label":row.label,"source":row.candidate,"expected_source_sha256":row.candidate_sha256,"original":row.original,"original_sha256":row.original_sha256,"target":row.target,"import_ok":result.get("ok",false),"native":native,"footprint":footprint,"error":result.get("error",""),"existing_catalog_entry":existed,"closed_source":result.get("closed_source",{}),"import_preparation":result.get("import_preparation",{}),"exact_source_copy":result.get("exact_source_copy",false)})
		if not check(result.get("ok",false) and canonical(str(result.get("entry",{}).get("asset_path","")))==canonical(row.target) and FileAccess.get_sha256(row.target)==row.candidate_sha256,"stable imported byte identity "+str(row.label)):finish();return
		if not check(native.get("ok",false) and footprint.get("ok",false),"native and footprint complete before any map save "+str(row.label)):finish();return
		# Resolve the exact pending catalog entry; it is saved only after all
		# selected native products and footprints have completed successfully.
		var matching:Array=library.entries.filter(func(entry):return canonical(str(entry.get("asset_path","")))==canonical(row.target))
		if not check(matching.size()==1 and is_same(matching[0],result.entry),"import returns the unique catalog-owned entry "+str(row.label)):finish();return
		var entry:Dictionary=matching[0]
		row.published_catalog_label=entry.label
		await process_frame
	if not check(previous_catalog.all(func(entry):return library.entries.any(func(current):return Pose.same(current,entry))),"all previous catalog entries preserved verbatim"):finish();return
	if not check(Compiled.generator()==generator and Footprint.generator()==footprint_generator and no_source_changed(rows),"source and pipeline SHA rechecked after all imports"):finish();return
	for row:Dictionary in rows.values():
		var identity:Dictionary=Library._verified_compiled_identity(row.target)
		var candidate:Dictionary=Footprint.candidate(row.target,Paths.external_root(),row.candidate_sha256)
		if not check(not identity.is_empty() and identity.source_sha==row.candidate_sha256 and not candidate.is_empty(),"final target native/source/footprint proof "+str(row.label)):finish();return
	if not check(document._disk_signature==spec.expected_formal_sha and FileAccess.get_sha256(formal)==spec.expected_formal_sha,"final optimistic map conflict check"):finish();return
	if not check(library.save()==OK,"all successful imports registered by one atomic catalog revision save"):finish();return
	report.catalog_published=true;report.catalog_sha_after=library._revision
	if not check(FileAccess.get_sha256(library_root.path_join("library.json"))==library._revision,"catalog revision still owns all final entries before map save"):finish();return
	if not check(document.validate_save()==OK,"final production author-document save validation"):finish();return
	var saved:int=document.save(formal)
	report.save_error=saved;report.save_metrics=document.last_save_metrics
	if not check(saved==OK,"single atomic reference save (ERR_BUSY never overwritten)"):finish();return
	report.map_published=true;report.published_sha256=document._disk_signature
	report.catalog_sha_after=FileAccess.get_sha256(library_root.path_join("library.json"))
	if not check(report.catalog_sha_after==library._revision,"catalog revision unchanged through map publication"):finish();return
	var reopened=Doc.open_file(formal)
	if not check(reopened!=null and reopened._disk_signature==report.published_sha256 and Pose.same(reopened.records,document.records) and Pose.same(reopened.map_meta,before_meta),"published formal reference map reopens with exact author state"):finish();return
	if not check(no_source_changed(rows),"original and candidate sources unchanged after publication"):finish();return
	report.compiled_generator=generator;report.footprint_generator=footprint_generator
	report.mode="published_reference_map";report.ui_mcp_batch_relink="Not implemented; this is a bounded offline migration using the shared author save contract."
	finish()
