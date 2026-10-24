extends SceneTree
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const ROOT="D:/code/rmmo_runtime"
const FIRST="D:/code/rmmo_runtime/packs/default/assets/7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb"
func _initialize()->void:run.call_deferred()
func run()->void:
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	var paths:Array=[FIRST];var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--town":
			var index:=preload("res://scripts/world3d/map_dependency_index.gd").read("D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf",ROOT,"",33554432,67108864,4,true)
			if not index.ok:print("FAIL directory ",index);quit(1);return
			paths=index.models.keys()
	var rows:Array=[];var failures:=0
	for path:String in paths:
		var built:Dictionary={};var index_path:=Native.index_path(path,ROOT)
		if FileAccess.file_exists(index_path):
			var previous:Variant=JSON.parse_string(FileAccess.get_file_as_string(index_path))
			if previous is Dictionary and previous.get("generator")==Native.generator() and previous.get("source_sha")==preload("res://scripts/world3d/runtime_package_policy.gd").source_identity(path):
				var product:=Native.directory(ROOT).path_join(str(previous.get("payload_sha",""))+".scn")
				if FileAccess.file_exists(product) and FileAccess.get_sha256(product)==previous.payload_sha:built={"ok":true,"reused":true,"product":product,"manifest":previous}
		if built.is_empty():built=Native.build(path,ROOT)
		elif built.ok:
			var metadata:=preload("res://scripts/world3d/white_native_asset_metadata.gd").build(path,ROOT)
			if metadata.ok:built.metadata=metadata
			else:built=metadata
		built.source=path;rows.append(built)
		if not built.ok:failures+=1
		print("WHITE_NATIVE_BUILD ",JSON.stringify(built))
		await process_frame
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"models":rows,"failures":failures},"\t"))
	quit(1 if failures else 0)
