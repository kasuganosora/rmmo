extends SceneTree
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Prefabs=preload("res://scripts/world_editor/prefab_library.gd")
const BASE="D:/code/rmmo_runtime"
func _initialize()->void:run.call_deferred()
func run()->void:
	var out=BASE+"/review_artifacts/reference_grass_clumps"
	var test=JSON.parse_string(FileAccess.get_file_as_string(out+"/validation.json"))
	var review=JSON.parse_string(FileAccess.get_file_as_string(out+"/visual_review.json"))
	if not test is Dictionary or test.get("failures",-1)!=0 or not review is Dictionary or not review.get("accepted",false):quit(1);return
	var lib=Library.new(BASE+"/packs/default/assets");var results=[]
	var previous=JSON.parse_string(FileAccess.get_file_as_string(out+"/published.json"));var retired=[]
	if previous is Dictionary:
		for old in previous.get("entries",[]):retired.append({"id":old.id,"path":str(old.entry.get("prefab_path",""))})
	for row in test.entries:
		if FileAccess.get_sha256(BASE+"/assets/reference_grass_clumps/"+row.id+".glb")!=row.sha256 or review.hashes.get(row.id)!=row.sha256:quit(1);return
		var label="宽弧桥头草堆·"+row.id.get_slice("_",1)
		var entry:Dictionary=row.entry.duplicate(true);var source:String=entry.asset_path;var hash_=FileAccess.get_sha256(source)
		if hash_!=source.get_file().get_basename():quit(1);return
		entry.asset_path=lib.directory+"/"+hash_+".glb";entry.thumbnail_path=lib.directory+"/thumbnails/"+hash_+".png";entry.label=label;entry.category="写实草丛"
		if not FileAccess.file_exists(entry.asset_path) and DirAccess.copy_absolute(source,entry.asset_path)!=OK:quit(1);return
		if not lib.entries.any(func(e):return e.get("asset_path","")==entry.asset_path):lib.entries.append(entry)
		var record={"uuid":"obj_1","kind":"asset","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"asset_path":entry.asset_path,"bounds_position":entry.bounds_position,"bounds_size":entry.bounds_size,"collision":"none"}
		var saved=Prefabs.capture([record],lib,label)
		if not saved.ok:push_error(str(saved));quit(1);return
		DirAccess.make_dir_recursive_absolute(saved.entry.thumbnail_path.get_base_dir())
		if DirAccess.copy_absolute(out+"/"+row.id+".png",saved.entry.thumbnail_path)!=OK:quit(1);return
		lib.entries=lib.entries.filter(func(e):return e.get("asset_path","")!=entry.asset_path and (not retired.any(func(old):return old.id==row.id and old.path==str(e.get("prefab_path",""))) or e.get("prefab_path")==saved.entry.prefab_path))
		if lib.save()!=OK:quit(1);return
		var preview=Prefabs.preview(saved.entry)
		if preview==null:quit(1);return
		preview.free();results.append({"id":row.id,"entry":saved.entry,"source_sha256":row.sha256,"library_model_sha256":hash_})
	var reopened=Library.new(lib.directory)
	for row in results:
		if not reopened.entries.any(func(e):return e.get("prefab_path","")==row.entry.prefab_path):quit(1);return
	var f=FileAccess.open(out+"/published.json",FileAccess.WRITE);f.store_string(JSON.stringify({"count":results.size(),"entries":results,"user_maps_modified":false},"\t"));f.close()
	print("TOWN_GRASS_PUBLISHED ",results.size());quit()

