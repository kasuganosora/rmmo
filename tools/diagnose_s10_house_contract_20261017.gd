extends SceneTree
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Bounds=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const SHA="522e58d7080bc010d0a512343ff8b7d9837818ebce454373f4b3ec0f28748d78"
func diff(a:Variant,b:Variant,path:String="root")->void:
	if Imported.same(a,b):return
	if a is Dictionary and b is Dictionary:
		for k in a:
			if b.has(k):diff(a[k],b[k],path+"/"+str(k))
			else:print("MISSING ",path," ",k)
	elif a is Array and b is Array:
		for i in mini(a.size(),b.size()):diff(a[i],b[i],path+"/"+str(i))
	else:print("DIFF ",path," ",var_to_str(a)," ",var_to_str(b))
func _initialize()->void:call_deferred("run")
func run()->void:
	var path:="D:/code/rmmo_runtime/packs/default/assets/"+SHA+".glb"
	var source:=Imported.source_descriptor(path,SHA)
	var lib:=Library.new(path.get_base_dir());var entry:Dictionary=lib.entries.filter(func(e):return e.get("asset_path")==path)[0]
	print("SOURCE_EMPTY ",source.is_empty()," CATALOG_VALID ",Imported.valid_descriptor(entry.model_building)," SOURCE_VALID ",Imported.valid_descriptor(source)," EQUAL ",Imported.same(source,entry.model_building))
	diff(source,entry.model_building)
	var record:Dictionary={"asset_path":path,"kind":"asset","uuid":"debug","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"model_building":entry.model_building}
	print("RECORD_VALID ",Imported.valid_record(record)," VERIFY_SOURCE ",Imported.verify_source(record))
	for id in entry.model_building.members:
		if not Imported.source_id(id) or not Imported.valid_part(entry.model_building.members[id]):print("BAD_MEMBER ",id,entry.model_building.members[id])
	quit()
