extends SceneTree
## Read-only CPU audit: never creates meshes, writes map data or runs a scene.
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Source=preload("res://scripts/world3d/document_source_snapshot.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var path:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var mark:=Time.get_ticks_usec();var snapshot:=Source.read_file(path)
	var report:={"read_ms":(Time.get_ticks_usec()-mark)/1000.}
	var native:=Cursor.native_root(snapshot._data)
	if native<0:push_error("Expected current reference map");quit(1);return
	var compact:Array=snapshot._data.nodes[native].extras.rmmo_records
	mark=Time.get_ticks_usec()
	var restored:=Cursor.hydrate_references(snapshot._data.nodes[native].extras,path,Paths.external_root())
	report.hydrate_ms=(Time.get_ticks_usec()-mark)/1000.
	if not restored.ok:push_error(restored.reason);quit(1);return
	var records:Array=restored.extras.rmmo_records
	var unique:Dictionary={};var prefab_count:=0;var raw_bytes:=0;var with_paint:=0
	var baseline:Array=[];var indexed:Array=[]
	for i in records.size():
		var record:Dictionary=records[i]
		if record.has("surface_paint"):with_paint+=1
		if record.has("house_prefab"):
			prefab_count+=1
			if not unique.has(record.house_prefab.sha256):
				unique[record.house_prefab.sha256]=true;raw_bytes+=int(record.house_prefab.length)
		baseline.append({"record":record,"paint_id":null})
		indexed.append({"record":record,"paint_id":compact[i].rmmo_ref.sha256})
	report.records=records.size();report.prefabs=prefab_count;report.unique_prefabs=unique.size();report.prefab_raw_bytes=raw_bytes;report.records_with_paint=with_paint
	var loader:=Loader.new();loader._content_root=Paths.external_root()
	mark=Time.get_ticks_usec();var valid:=loader._valid_records(restored.extras)
	report.runtime_validate_ms=(Time.get_ticks_usec()-mark)/1000.;report.runtime_profile=loader._profile.duplicate(true)
	for entry in [["without_ids",baseline],["with_definition_ids",indexed]]:
		mark=Time.get_ticks_usec();var result:Dictionary=loader._validate_record_batch(entry[1])
		report[entry[0]]={"elapsed_ms":(Time.get_ticks_usec()-mark)/1000.,"ok":result.ok,"parts":result.get("timings",{}),"textures":result.get("textures",{}).size()}
	report.prefab_decode_cache_bytes=Prefab._decoded_bytes;report.prefab_decode_cache_entries=Prefab._decoded.size()
	report.source_unchanged=snapshot.matches_disk()
	loader.free()
	print("REFERENCE_LOAD_CPU ",JSON.stringify(report))
	quit(0 if valid and report.source_unchanged else 1)
