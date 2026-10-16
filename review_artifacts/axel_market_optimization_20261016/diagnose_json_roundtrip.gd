extends SceneTree
func inspect(a:Variant,b:Variant,path:String)->void:
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key):print("MISSING ",path,"/",key)
			else:inspect(a[key],b[key],path+"/"+str(key))
	elif a is Array and b is Array:
		for i in mini(a.size(),b.size()):inspect(a[i],b[i],path+"/"+str(i))
	elif a!=b:print("DIFF ",path," ",var_to_str(a)," ",var_to_str(b)," delta=",str(float(a)-float(b)) if (a is float or a is int) and (b is float or b is int) else "nonnumeric")
func _initialize()->void:
	var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/art_sources/axel_market_optimization_20261016/publication_plan.json"))
	for row:Dictionary in plan.rows:
		var current:Variant=JSON.parse_string(FileAccess.get_file_as_string(row.existing_prefab.prefab_path))
		inspect(current,row.existing_prefab.prefab,row.asset)
		var geo=preload("res://scripts/world_editor/selection_geometry.gd")
		var bounds:AABB=geo.bounds(current.records)
		var pivot:=Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
		var before:Dictionary=current.records[0].duplicate(true)
		var position:Vector3=geo.vector(before,"position")-pivot
		var after:Dictionary=before.duplicate(true);after.position=[position.x,position.y,position.z]
		inspect(before,after,row.asset+"/normal_capture_transform")
		var stage:String="D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016/publication/publish02/staging/"+row.asset+"/assets/prefabs"
		for name_:String in DirAccess.get_files_at(stage):
			if not name_.ends_with(".json"):continue
			var captured:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(stage.path_join(name_)))
			var expected:Dictionary=current.duplicate(true);expected.records[0].asset_path=row.candidate_sha256+".glb";expected.records[0].position=after.position
			inspect(expected,captured,row.asset+"/captured")
	quit()
