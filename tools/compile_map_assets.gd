extends SceneTree
## Import/build-stage preparation. Reads a map; writes disposable native products.
## GPU execution must use run_godot_background.py, never a foreground window.
const Cache=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	Engine.max_fps=60
	var path:="";var output:="";var asset:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):path=arg.trim_prefix("--map=")
		elif arg.begins_with("--asset="):asset=arg.trim_prefix("--asset=")
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not asset.is_empty():
		if not path.is_empty() or not Paths.allowed(asset) or not FileAccess.file_exists(asset) or not Paths.allowed(output,Paths.external_root().path_join("review_artifacts")):quit(1);return
		var before:=FileAccess.get_sha256(asset)
		var result:=_compile(asset);result.path=asset;result.source_sha=before;result.source_unchanged=FileAccess.get_sha256(asset)==before
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file==null:quit(1);return
		file.store_string(JSON.stringify(result,"\t"));file.close()
		print("COMPILED_SINGLE_ASSET ",JSON.stringify(result))
		quit(0 if result.ok and result.source_unchanged else 1);return
	if not Paths.allowed(path) or not FileAccess.file_exists(path) or not Paths.allowed(output,Paths.external_root().path_join("review_artifacts")):quit(1);return
	var digest:=FileAccess.get_sha256(path)
	var document=preload("res://scripts/world3d/world_document.gd").open_file(path)
	if document==null:quit(1);return
	var unique:Dictionary={}
	for record:Dictionary in document.records:
		if record.get("kind")=="asset" and not record.has("house_prefab") and not record.has("bridge_mesh"):unique[str(record.asset_path)]=true
	var report:Dictionary={"map":path,"source_sha":digest,"models":[],"built":0,"reused":0,"skipped":0,"failures":0,"bytes":0,"footprints_built":0,"footprints_reused":0,"footprints_failed":0,"footprint_elapsed_us":0}
	var started:=Time.get_ticks_usec()
	for source:String in unique:
		var result:=_compile(source);result.path=source;report.models.append(result)
		if result.ok:
			report["reused" if result.reused else "built"]+=1;report.bytes+=result.bytes
			var footprint:Dictionary=result.footprint
			report.footprint_elapsed_us+=footprint.elapsed_us
			if footprint.ok:report["footprints_reused" if footprint.reused else "footprints_built"]+=1
			else:report.footprints_failed+=1
		elif str(result.get("reason","")).begins_with("unsupported:"):report.skipped+=1
		else:report.failures+=1
		print("COMPILED_ASSET ",JSON.stringify(result))
		await process_frame
	report.elapsed_ms=(Time.get_ticks_usec()-started)/1000.
	report.source_unchanged=FileAccess.get_sha256(path)==digest
	if not report.source_unchanged:report.failures+=1
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("COMPILED_MAP_ASSETS ",report.built," built / ",report.reused," reused / ",report.skipped," skipped / ",report.failures," failures; ",report.elapsed_ms," ms")
	quit(0 if report.failures==0 else 1)

func _compile(path:String)->Dictionary:
	var started:=Time.get_ticks_usec()
	var result:=Cache.build(path)
	if result.get("ok",false):
		result.footprint=Library._compile_footprint(path)
		result.footprint_elapsed_us=result.footprint.elapsed_us
	# Optional budgeting failures are reported independently, never as a failed
	# model import/compile. The runtime then uses its conservative GLB estimate.
	result.total_elapsed_us=Time.get_ticks_usec()-started
	return result
