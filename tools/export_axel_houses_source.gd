extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
func _initialize()->void:
	var path:="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
	var doc=Doc.open_file(path)
	if doc==null:quit(1);return
	DirAccess.make_dir_recursive_absolute(OUT)
	for item in [["source_records",doc.records],["source_metadata",doc.map_meta],["source_identity",{"path":path,"sha256":FileAccess.get_sha256(path),"signature":doc._disk_signature}]]:
		var f:=FileAccess.open(OUT.path_join(item[0]+".json"),FileAccess.WRITE)
		f.store_string(JSON.stringify(item[1],"",true,true));f.close()
	print("EXPORTED ",doc.records.size()," SHA ",FileAccess.get_sha256(path));quit(0)
