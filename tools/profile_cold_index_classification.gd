extends SceneTree
## CPU-only reproduction of cold directory classification using real hydrated
## records. Writes diagnostics only; never updates the author map or its index.
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const ROOT="D:/code/rmmo_runtime"
var output:=""
var repeats:=1
var abba:=false
var numeric_abba:=false
func _initialize()->void:run.call_deferred()
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--repeats="):repeats=clampi(int(arg.trim_prefix("--repeats=")),1,16)
		elif arg=="--abba":abba=true;repeats=4
		elif arg=="--numeric-abba":numeric_abba=true;repeats=4
	if DisplayServer.get_name()!="headless" or not Index.Paths.allowed(output,ROOT+"/review_artifacts"):quit(2);return
	var source:=Index._source(MAP,ROOT,"")
	if not source.ok:quit(1);return
	var restored:=Cursor.hydrate_references(source.extras,MAP,ROOT)
	if not restored.ok:quit(1);return
	var loader:=Loader.new();loader._content_root=ROOT
	var paint_ids:Array=[]
	for record:Dictionary in source.extras.rmmo_records:paint_ids.append(record.rmmo_ref.sha256)
	if not loader._valid_records(restored.extras,paint_ids):loader.free();quit(1);return
	print("COLD_CLASSIFY_BEGIN")
	await process_frame
	var report:={"sha":source.source._signature,"runs":[]}
	var expected:Array=[]
	for pass_:int in repeats:
		preload("res://scripts/world3d/road_surface.gd").boolean_schema_enabled=not abba or pass_ in [1,2]
		preload("res://scripts/world3d/document_schema.gd").numeric_rows_enabled=not numeric_abba or pass_ in [1,2]
		var started:=Time.get_ticks_usec();var models:Dictionary={};var groups:Dictionary={}
		var paths:Dictionary={}
		var rows:Array=[]
		for record:Dictionary in restored.extras.rmmo_records:
			var began:=Time.get_ticks_usec();var row:=Index._classify(record,ROOT,models,paths if not abba or pass_ in [1,2] else {})
			var elapsed:=Time.get_ticks_usec()-began
			var key:String=row.reason
			if not groups.has(key):groups[key]={"count":0,"total_us":0,"max_us":0}
			groups[key].count+=1;groups[key].total_us+=elapsed;groups[key].max_us=maxi(groups[key].max_us,elapsed)
			rows.append(row)
		var result:={"elapsed_us":Time.get_ticks_usec()-started,"groups":groups,"models":models.size()}
		result.boolean_schema=preload("res://scripts/world3d/road_surface.gd").boolean_schema_enabled
		result.numeric_rows=preload("res://scripts/world3d/document_schema.gd").numeric_rows_enabled
		result.unique_path_checks=paths.size()
		if pass_==0:expected=rows
		result.identical=rows==expected
		report.runs.append(result);print(JSON.stringify(result))
		await process_frame
	report.unchanged=source.source.matches_disk();FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	loader.free();quit(0 if report.unchanged and report.runs.all(func(row):return row.identical) else 1)
