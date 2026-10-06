extends SceneTree
const Library=preload("res://scripts/world_editor/asset_library.gd")
const BASE="D:/code/rmmo_runtime"
func _initialize()->void:
	var accepted=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/review_artifacts/pine_parametric/published.json"))
	if not accepted is Dictionary or accepted.get("count",0)!=3:quit(1);return
	var lib=Library.new(BASE+"/packs/default/assets")
	for entry in accepted.entries:
		if not lib.entries.any(func(e):return e.get("prefab_path","")==entry.prefab_path):quit(1);return
	var models=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/review_artifacts/pine_dense_v3_game/published.json"))
	var prefabs=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/review_artifacts/pine_density/prefab_publication.json"))
	var old:Array=prefabs.entries.duplicate(true)
	for row in models.items:old.append(row.entry)
	var removed=[]
	for index in range(lib.entries.size()-1,-1,-1):
		var candidate:Dictionary=lib.entries[index]
		if old.any(func(e):return candidate.get("label","")==e.label and candidate.get("asset_path","")==e.get("asset_path","") and candidate.get("prefab_path","")==e.get("prefab_path","")):
			removed.append(candidate);lib.entries.remove_at(index)
	if lib.save()!=OK:push_error("Concurrent library change; nothing overwritten");quit(1);return
	var readback=Library.new(lib.directory)
	if readback.entries.any(func(e):return old.any(func(o):return e.get("label","")==o.label)):quit(1);return
	var remaining=readback.search("参数化松树")
	if remaining.size()!=3:quit(1);return
	var f=FileAccess.open(BASE+"/review_artifacts/pine_parametric/retired_fixed_catalog.json",FileAccess.WRITE);f.store_string(JSON.stringify({"removed":removed,"remaining":remaining,"dependency_files_preserved":true,"user_maps_modified":false},"\t"));f.close()
	print("FIXED_PINE_CATALOG_REMOVED ",removed.size()," PARAMETRIC_REMAINING ",remaining.size());quit()
