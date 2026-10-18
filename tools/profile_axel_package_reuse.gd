extends SceneTree
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var path:="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var source:=Snapshot.read_file(path);var at:=Cursor.native_root(source._data)
	var restored:=Cursor.hydrate_references(source._data.nodes[at].extras,path,Paths.external_root(),4,true)
	if not restored.ok:quit(1);return
	var prefabs:Dictionary={};var models:Dictionary={};var instances:=0;var frozen:=0
	for record:Dictionary in restored.extras.rmmo_records:
		if record.has("house_prefab"):
			frozen+=1;var key:String=record.house_prefab.sha256
			if not prefabs.has(key):prefabs[key]={"instances":0,"raw_bytes":record.house_prefab.length}
			prefabs[key].instances+=1
		elif record.get("kind")=="asset":
			instances+=1;var key:String=record.asset_path
			if not models.has(key):models[key]={"instances":0}
			models[key].instances+=1
	var report:={"records":restored.extras.rmmo_records.size(),"unique_definitions":restored.read_profile.unique_resources,"frozen_instances":frozen,"unique_frozen_payloads":prefabs.size(),"model_instances":instances,"unique_model_paths":models.size(),"prefabs":prefabs,"models":models,"map_unchanged":source.matches_disk()}
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	report.erase("models");report.erase("prefabs");print("AXEL_PACKAGE_REUSE ",JSON.stringify(report));quit(0 if report.map_unchanged else 1)
