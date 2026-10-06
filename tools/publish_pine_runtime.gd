extends SceneTree
const Library=preload("res://scripts/world_editor/asset_library.gd")
const BASE="D:/code/rmmo_runtime"
func _initialize()->void:run.call_deferred()
func run()->void:
	var out:=BASE+"/review_artifacts/pine_dense_v3"
	if OS.get_cmdline_user_args().has("--fine-clusters"):out+="_fine"
	if OS.get_cmdline_user_args().has("--game-cards"):out+="_game"
	var verification:Variant=JSON.parse_string(FileAccess.get_file_as_string(out+"/validation.json"))
	var visual:Variant=JSON.parse_string(FileAccess.get_file_as_string(out+"/visual_review.json"))
	if not verification is Dictionary or verification.get("failures",-1)!=0 or verification.get("assets",[]).size()!=3 or not visual is Dictionary or not visual.get("accepted",false):
		push_error("Passing functional and visual review required");quit(1);return
	var lib:=Library.new(BASE+"/packs/default/assets");var rows:Array=[];var replaced:Array=[]
	if OS.get_cmdline_user_args().has("--game-cards"):
		var previous:Variant=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/review_artifacts/pine_dense_v3_fine/published.json"))
		if not previous is Dictionary or previous.get("count",0)!=3:push_error("V5 publication provenance required");quit(1);return
		for old in previous.items:
			for index in range(lib.entries.size()-1,-1,-1):
				if lib.entries[index].get("asset_path","")==old.entry.asset_path and lib.entries[index].get("label","")==old.label:
					replaced.append(lib.entries[index].duplicate(true));lib.entries.remove_at(index)
	for row in verification.assets:
		var entry:Dictionary=row.entry.duplicate(true);var source:String=entry.asset_path;var hash:=FileAccess.get_sha256(source)
		if hash!=source.get_file().get_basename():push_error("Validated source changed");quit(1);return
		if hash!=str(visual.get("validated_hashes",{}).get(row.id,"")):push_error("Visual/functional versions differ");quit(1);return
		var target:=lib.directory.path_join(hash+".glb")
		if not FileAccess.file_exists(target) and DirAccess.copy_absolute(source,target)!=OK:quit(1);return
		if FileAccess.get_sha256(target)!=hash:quit(1);return
		entry.asset_path=target;entry.label=row.label;entry.category="树木·写实松树"
		entry.thumbnail_path=lib.directory.path_join("thumbnails/"+hash+".png")
		DirAccess.make_dir_recursive_absolute(entry.thumbnail_path.get_base_dir())
		if DirAccess.copy_absolute(out+"/"+str(row.id)+".png",entry.thumbnail_path)!=OK:quit(1);return
		if not lib.entries.any(func(e):return e.get("asset_path","")==target):lib.entries.append(entry)
		rows.append({"id":row.id,"label":entry.label,"entry":entry,"triangles":row.triangles,"lod_triangles":row.get("lod_triangles",[]),"sha256":hash})
	if lib.save()!=OK:push_error("Shared library changed concurrently; reload before retry");quit(1);return
	var reopened:=Library.new(lib.directory)
	for row in rows:
		if not reopened.entries.any(func(e):return e.get("asset_path","")==row.entry.asset_path and e.get("label","")==row.label):quit(1);return
	var f:=FileAccess.open(out+"/published.json",FileAccess.WRITE);f.store_string(JSON.stringify({"count":rows.size(),"items":rows,"replaced_catalog_entries":replaced,"old_immutable_assets_preserved":true,"user_maps_modified":false,"library":lib.directory+"/library.json"},"\t"));f.close()
	print("PINE_LIBRARY_PUBLISHED ",rows.size());quit()
