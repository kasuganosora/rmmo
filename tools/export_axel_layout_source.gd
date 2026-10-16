extends SceneTree
## Read-only native snapshot for the 2026-10-16 layout phase.
const Doc=preload("res://scripts/world3d/world_document.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const SOURCE="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
func _initialize()->void:
	var signature:=FileAccess.get_sha256(SOURCE)
	var doc=Doc.open_file(SOURCE)
	if doc==null:quit(1);return
	DirAccess.make_dir_recursive_absolute(OUT)
	for item in [["source_records",doc.records],["source_metadata",doc.map_meta],["source_identity",{"path":SOURCE,"sha256":signature,"signature":doc._disk_signature}]]:
		var f:=FileAccess.open(OUT.path_join(item[0]+".json"),FileAccess.WRITE)
		if f==null:quit(1);return
		f.store_string(JSON.stringify(item[1],"",true,true));f.close()
	if FileAccess.get_sha256(SOURCE)!=signature:quit(1);return
	print("EXPORTED_READONLY records=",doc.records.size()," sha256=",signature)
	quit(0)
