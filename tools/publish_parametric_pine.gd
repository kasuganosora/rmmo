extends SceneTree
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Prefabs=preload("res://scripts/world_editor/prefab_library.gd")
const BASE="D:/code/rmmo_runtime"
func _initialize()->void:run.call_deferred()
func run()->void:
	var out=BASE+"/review_artifacts/pine_parametric"
	var tested=JSON.parse_string(FileAccess.get_file_as_string(out+"/validation.json"))
	var visual=JSON.parse_string(FileAccess.get_file_as_string(out+"/visual_review.json"))
	if not tested is Dictionary or tested.get("failures",-1)!=0 or not visual is Dictionary or not visual.get("accepted",false):push_error("Validated geometry and visual review required");quit(1);return
	var library=Library.new(BASE+"/packs/default/assets");var rows=[];var intermediate=[]
	for row in tested.entries:
		var source:String=row.entry.asset_path
		if FileAccess.get_sha256(source)!=visual.validated_hashes[row.variant]:push_error("Validated source changed");quit(1);return
		var label="参数化松树·"+{"compact":"小型","mature":"成熟","windswept":"倾斜"}[row.variant]
		var existing=library.entries.filter(func(e):return e.get("label","")==label and e.has("prefab_path"))
		if not existing.is_empty():rows.append(existing[0]);continue
		var imported=library.import_file(source)
		if not imported.ok:push_error(str(imported));quit(1);return
		intermediate.append(imported.entry.asset_path)
		var doc=preload("res://scripts/world3d/world_document.gd").new()
		# Match the ordinary asset placement record: bounds, units and collision.
		var record={"uuid":"obj_1","kind":"asset","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"asset_path":imported.entry.asset_path,"bounds_position":imported.entry.bounds_position,"bounds_size":imported.entry.bounds_size,"collision":""}
		var saved=Prefabs.capture([record],library,label)
		if not saved.ok:push_error(str(saved));quit(1);return
		var preview=Prefabs.preview(saved.entry)
		if preview==null:quit(1);return
		if preload("res://scripts/world3d/parametric_tree.gd").recipe(preview).is_empty():preview.free();quit(1);return
		preview.free()
		if DirAccess.copy_absolute(BASE+"/review_artifacts/pine_dense_v3_game/pine_dense_"+row.variant+".png",saved.entry.thumbnail_path)!=OK:quit(1);return
		rows.append(saved.entry)
	library.entries=library.entries.filter(func(e):return not intermediate.has(e.get("asset_path","")))
	if library.save()!=OK:push_error("Library changed concurrently");quit(1);return
	var reopened=Library.new(library.directory)
	for row in rows:
		if not reopened.entries.any(func(e):return e.get("prefab_path","")==row.prefab_path):quit(1);return
	var f=FileAccess.open(out+"/published.json",FileAccess.WRITE);f.store_string(JSON.stringify({"count":rows.size(),"entries":rows,"user_maps_modified":false,"fixed_prefabs_preserved":true},"\t"));f.close()
	print("PARAMETRIC_PINE_PUBLISHED ",rows.size());quit()
