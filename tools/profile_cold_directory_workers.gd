extends SceneTree
## Same actual definitions, bounds, ordering and source checks under ABBA.
## CPU-only: never writes a map, resource, dependency index or cooked mesh.
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const ROOT="D:/code/rmmo_runtime"
func _initialize()->void:run.call_deferred()
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if DisplayServer.get_name()!="headless" or not Index.Paths.allowed(output,ROOT+"/review_artifacts"):quit(2);return
	var source:=Index._source(MAP,ROOT,"")
	if not source.ok:quit(1);return
	var read:=Index.Store.read_records(source.extras.rmmo_records,MAP,ROOT,source.dependencies)
	if not read.ok:quit(1);return
	# Production validates/prewarms all prefabs before directory construction.
	# Keep that cache state identical even on the first serial comparison arm.
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();loader._content_root=ROOT
	var extras:Dictionary=source.extras.duplicate();extras.rmmo_records=read.records
	var ids:Array=[]
	for compact:Dictionary in source.extras.rmmo_records:ids.append(compact.rmmo_ref.sha256)
	if not loader._valid_records(extras,ids):loader.free();quit(1);return
	loader.free()
	var lengths:Dictionary={}
	for i:int in read.records.size():
		var sha:String=source.extras.rmmo_records[i].rmmo_ref.sha256
		if not lengths.has(sha):lengths[sha]=var_to_bytes(Index.Store._definition(read.records[i])).size()
	var report:={"sha":source.source._signature,"records":read.records.size(),"definitions":lengths.size(),"runs":[],"failures":[]}
	var expected:Dictionary={}
	for enabled:bool in [false,true,true,false]:
		Index.parallel_native_classification=enabled;Index.parallel_imported_sources=enabled
		preload("res://scripts/world3d/document_schema.gd").numeric_rows_enabled=enabled
		var began:=Time.get_ticks_usec()
		var result:=Index._build_rows(read.records,source.extras.rmmo_records,lengths,ROOT)
		var row:={"parallel":enabled,"classification_us":Time.get_ticks_usec()-began,"profile":result.get("profile",{})}
		if not result.ok:report.failures.append("classify_failed");break
		if expected.is_empty():expected=result
		if result.rows!=expected.rows or result.models!=expected.models:report.failures.append("directory_changed")
		began=Time.get_ticks_usec()
		row.imported_ok=Index._imported_sources_valid(source.extras,result.rows)
		row.imported_us=Time.get_ticks_usec()-began
		if not row.imported_ok:report.failures.append("source_check_failed")
		report.runs.append(row);print(JSON.stringify(row));await process_frame
	Index.parallel_native_classification=true;Index.parallel_imported_sources=true
	report.unchanged=source.source.matches_disk()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit(0 if report.failures.is_empty() and report.unchanged else 1)
