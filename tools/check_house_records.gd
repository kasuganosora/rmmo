extends SceneTree
func _initialize()->void:
	var path:="D:/code/rmmo_runtime/maps/medieval_house_showcase_v8/map.gltf"
	for arg in OS.get_cmdline_user_args():path=arg
	var doc=preload("res://scripts/world3d/world_document.gd").open_file(path)
	if doc==null:push_error("map did not open");quit(1);return
	var Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
	var bad:=0
	for r:Dictionary in doc.records:
		if not r.has("building"):continue
		var registry:Dictionary=doc.map_meta.building_instances[r.building.id]
		var current:String=Blueprint.geometry_signature(r);var saved:String=registry.signatures[r.building.part]
		if current!=saved:
			bad+=1
			if bad<4:print("CHANGED ",r.building.part,"\n",saved,"\n",current)
	print("HOUSE_RECORD_CHECK loaded=",doc.records.size()," signature_conflicts=",bad);quit(1 if bad else 0)
