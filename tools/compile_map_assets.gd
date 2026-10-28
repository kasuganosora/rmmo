extends SceneTree
## Explicit import/build-stage migration. GPU work uses run_godot_background.py.
## --map/--asset remain supported; --library/--prefab include their whole closure.
## --plan-only is read-only and may run headless. No normal reader calls this tool.
## Existing publications are preserved by default; --reimport updates the source
## or producer version explicitly instead of treating native products as a cache.
const Cache=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Migration=preload("res://tools/native_asset_migration.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
func _initialize()->void:run.call_deferred()

func run()->void:
	Engine.max_fps=60
	var map_path:="";var output:="";var assets:Array=[];var libraries:Array=[];var prefabs:Array=[]
	var plan_only:=false;var refresh_bounds:=false;var refresh_building:=false;var reimport:=false;var argument_error:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			if not map_path.is_empty():argument_error="only one --map is supported"
			map_path=arg.trim_prefix("--map=")
		elif arg.begins_with("--asset="):assets.append(arg.trim_prefix("--asset="))
		elif arg.begins_with("--library="):libraries.append(arg.trim_prefix("--library="))
		elif arg.begins_with("--prefab="):prefabs.append(arg.trim_prefix("--prefab="))
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--plan-only":plan_only=true
		elif arg=="--refresh-bounds":refresh_bounds=true
		elif arg=="--refresh-building":refresh_building=true
		elif arg=="--reimport":reimport=true
		else:argument_error="unknown argument: "+arg
	var root_path:=Paths.external_root()
	if not argument_error.is_empty():push_error(argument_error);quit(1);return
	if output.get_extension().to_lower()!="json" or not Paths.allowed(output,root_path.path_join("review_artifacts")):
		push_error("--output must be JSON in external review_artifacts");quit(1);return
	if map_path.is_empty() and assets.is_empty() and libraries.is_empty() and prefabs.is_empty():
		_publish(output,{"ok":false,"error":"at least one map, asset, library or prefab is required"});quit(1);return
	if not map_path.is_empty() and not assets.is_empty():
		_publish(output,{"ok":false,"error":"--map and --asset cannot be combined"});quit(1);return
	var records:Array=[];var map_digest:=""
	if not map_path.is_empty():
		if not Paths.allowed(map_path) or not FileAccess.file_exists(map_path):
			_publish(output,{"ok":false,"error":"map missing or outside content root"});quit(1);return
		map_digest=FileAccess.get_sha256(map_path)
		var document=preload("res://scripts/world3d/world_document.gd").open_file(map_path)
		if document==null:_publish(output,{"ok":false,"error":"map read failed"});quit(1);return
		records=document.records
	var plan_:=Migration.plan(assets,libraries,prefabs,records,root_path,map_path)
	plan_.product_mode="explicit_reimport" if reimport else "preserve_existing_published_product"
	if not map_path.is_empty():plan_.inputs[map_path]=map_digest
	if plan_only:
		plan_.plan_only=true;plan_.native_products_modified=false;plan_.source_assets_modified=false
		plan_.build_count=0;plan_.preserve_count=0
		for model:Dictionary in plan_.models:
			model.publication=Migration.product_plan(model.path,root_path,reimport)
			if not model.publication.get("ok",false):
				plan_.errors.append({"reason":model.publication.get("reason","publication_unknown"),"origin":model.path})
			else:plan_["preserve_count" if model.publication.action=="preserve" else "build_count"]+=1
		plan_.ok=plan_.errors.is_empty()
		plan_.inputs_unchanged=Migration.inputs_unchanged(plan_);plan_.ok=plan_.ok and plan_.inputs_unchanged
		var saved:=_publish(output,plan_);print("NATIVE_MIGRATION_PLAN ",JSON.stringify(plan_))
		quit(0 if saved and plan_.ok else 1);return
	# Every execution mode publishes a complete consumer contract. Flags force a
	# refresh; their absence must never mean that missing metadata is acceptable.
	var report:=Migration.begin_report(plan_,true,true)
	report.product_mode=plan_.product_mode
	report.force_bounds_refresh=refresh_bounds;report.force_building_refresh=refresh_building
	var single_asset:bool=assets.size()==1 and libraries.is_empty() and prefabs.is_empty()
	var source_before:=FileAccess.get_sha256(assets[0]) if single_asset and plan_.ok else ""
	var started:=Time.get_ticks_usec()
	# An incomplete closure never starts a partially guessed batch.
	if plan_.ok and DisplayServer.get_name()!="headless":
		for model:Dictionary in plan_.models:
			var result:=_compile(str(model.path),refresh_bounds,refresh_building,reimport)
			Migration.record_result(report,model.path,result)
			print("COMPILED_ASSET ",JSON.stringify(report.models.back()))
			await process_frame
	elif plan_.ok:
		report.failures+=1;report.error="graphics_required: use private background GPU runner"
	report.map=map_path;report.source_sha=map_digest
	report.elapsed_ms=(Time.get_ticks_usec()-started)/1000.
	Migration.finish_report(report)
	if not map_path.is_empty():
		report.source_unchanged=FileAccess.get_sha256(map_path)==map_digest
		if not report.source_unchanged:report.ok=false;report.failures+=1
	# Preserve the original single-asset JSON fields; strict batch status remains
	# available alongside them instead of changing its reused boolean to a count.
	if single_asset and report.models.size()==1:
		var single:Dictionary=report.models[0].duplicate(true)
		single.source_sha=source_before;single.source_unchanged=FileAccess.get_sha256(assets[0])==source_before
		if not single.source_unchanged:report.ok=false;report.failures+=1
		single.ok=report.ok;single.migration=report
		var saved:=_publish(output,single);print("COMPILED_SINGLE_ASSET ",JSON.stringify(single))
		quit(0 if saved and single.ok else 1);return
	var saved:=_publish(output,report)
	print("COMPILED_MAP_ASSETS ",JSON.stringify({"ok":report.ok,"built":report.built,"reused":report.reused,"failures":report.failures,"unsupported":report.unsupported,"footprints_failed":report.footprints_failed,"closure_complete":report.closure_complete,"report":output}))
	quit(0 if saved and report.ok else 1)

func _compile(path:String,refresh_bounds:bool=false,refresh_building:bool=false,reimport:bool=false)->Dictionary:
	var started:=Time.get_ticks_usec()
	var root_path:=Paths.external_root()
	var action:=Migration.product_plan(path,root_path,reimport)
	if not action.get("ok",false):return action
	var preserve:bool=action.action=="preserve"
	var result:Dictionary
	if preserve:
		result={"ok":true,"reused":true,"bytes":action.identity.bytes,"preserved_published":true,"product_generator":action.identity.generator,"source_sha":action.identity.source_sha}
	else:result=Cache.build(path)
	if result.get("ok",false):
		if preserve:
			var footprint_started:=Time.get_ticks_usec()
			var existing:=Footprint.candidate(path,root_path,action.source_sha,true)
			if not existing.is_empty():result.footprint={"ok":true,"reused":true,"estimated_bytes":existing.estimated_bytes,"resident_bytes":existing.resident_bytes,"exclusive":existing.exclusive}
			else:
				result.footprint=Footprint.build(path,root_path,true)
				result.footprint.reused=false
				if result.footprint.get("ok",false) and result.footprint.get("candidate",{}).is_empty():
					result.footprint={"ok":false,"reused":false,"reason":"candidate_changed_after_build"}
			result.footprint.elapsed_us=Time.get_ticks_usec()-footprint_started
		else:result.footprint=Library._compile_footprint(path)
		result.footprint_elapsed_us=result.footprint.elapsed_us
		if result.footprint.get("ok",false):
			var native:=preload("res://scripts/world3d/native_model_product.gd").read(path,Paths.external_root())
			result.bounds={"ok":true,"reused":true}
			if refresh_bounds or native.is_empty():
				result.bounds=Footprint.refresh_bounds(path,Paths.external_root())
				native=preload("res://scripts/world3d/native_model_product.gd").read(path,Paths.external_root())
			# A just-built footprint already inspected the exact SceneState. Older
			# products reuse only a persisted sidecar bound to this source/payload.
			var fresh_building:Variant=result.footprint.get("building_present")
			if not refresh_building and not result.footprint.get("reused",true) and fresh_building is bool:
				result.building={"ok":true,"present":fresh_building,"reused":false}
			else:result.building=Footprint.ensure_imported_building(path,Paths.external_root(),refresh_building)
			result.native_ready=not native.is_empty()
			if not native.is_empty():result.native_product=native.native_product_path;result.source_sha=native.native_source_sha
		if preserve and (Footprint._identity(path,root_path,true)!=action.identity or FileAccess.get_sha256(path)!=action.source_sha):
			result.ok=false;result.reason="published_identity_changed_during_migration"
	result.total_elapsed_us=Time.get_ticks_usec()-started
	return result

func _publish(path:String,report:Dictionary)->bool:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir())!=OK:return false
	var temporary:=path+".%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(report,"\t"));file.flush();var error:=file.get_error();file.close()
	if error==OK:error=preload("res://scripts/world3d/atomic_file.gd").publish(temporary,path)
	if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
	return error==OK
