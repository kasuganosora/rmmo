extends SceneTree
## Read-only native snapshot for the 2026-10-16 layout phase.
const Doc=preload("res://scripts/world3d/world_document.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const SOURCE="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
func _initialize()->void:
	var source:=SOURCE;var output:=OUT
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):source=arg.trim_prefix("--map=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	var signature:=FileAccess.get_sha256(source)
	var doc=Doc.open_file(source)
	if doc==null:quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	for item in [["source_records",doc.records],["source_metadata",doc.map_meta],["source_identity",{"path":source,"sha256":signature,"signature":doc._disk_signature}]]:
		var f:=FileAccess.open(output.path_join(item[0]+".json"),FileAccess.WRITE)
		if f==null:quit(1);return
		f.store_string(JSON.stringify(item[1],"",true,true));f.close()
	if FileAccess.get_sha256(source)!=signature:quit(1);return
	print("EXPORTED_READONLY records=",doc.records.size()," sha256=",signature)
	quit(0)
