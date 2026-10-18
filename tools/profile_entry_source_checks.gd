extends SceneTree
## Isolate exact source checks with CPU-only real map data; no cache or asset writes.
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const ROOT="D:/code/rmmo_runtime"
var report:Dictionary={"checks":[],"manifests":[],"failures":[]}
func _initialize()->void:run.call_deferred()
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty() or DisplayServer.get_name()!="headless":quit(2);return
	var opened:Dictionary=Index._source(MAP,ROOT,"")
	if not opened.ok:quit(1);return
	var file:=FileAccess.open(Index.cache_path(MAP,ROOT),FileAccess.READ)
	file.seek(9);var length:=file.get_64();file.seek(49)
	var data:Dictionary=bytes_to_var(file.get_buffer(length));file.close()
	var descriptors:Dictionary={};var hashes:Dictionary={}
	for row:Dictionary in data.rows:
		var state:Dictionary=opened.extras.rmmo_records[row.order].rmmo_state
		if not state.has("model_building"):continue
		var path:String=row.asset_path
		var result:Dictionary={"path":path,"uuid":row.uuid}
		var started:=Time.get_ticks_usec()
		if not hashes.has(path):
			hashes[path]=FileAccess.get_sha256(path)
			result.hash_us=Time.get_ticks_usec()-started;started=Time.get_ticks_usec()
			descriptors[path]=Imported.source_descriptor(path,hashes[path])
			result.descriptor_us=Time.get_ticks_usec()-started;started=Time.get_ticks_usec()
		var matches:bool=hashes[path]==state.model_building.source_sha and Imported.same(descriptors[path],state.model_building)
		result.compare_us=Time.get_ticks_usec()-started;result.ok=matches
		report.checks.append(result)
		if not matches:report.failures.append(row.uuid)
	for path:String in data.models:
		var started:=Time.get_ticks_usec()
		var result:Dictionary=Manifest.read(path)
		report.manifests.append({"path":path,"us":Time.get_ticks_usec()-started,"known":result.get("known",false),"bytes":result.get("file_length",0),"json_bytes":result.get("json_bytes",0)})
	var out:=FileAccess.open(output,FileAccess.WRITE);out.store_string(JSON.stringify(report,"\t"));out.close()
	print("ENTRY_SOURCE_CHECKS ",JSON.stringify(report.checks))
	quit(0 if report.failures.is_empty() else 1)
