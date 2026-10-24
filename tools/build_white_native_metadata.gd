extends SceneTree
## Export descriptors for existing immutable native products. Never rewrites a
## geometry manifest/signature, source GLB, PackedScene or authored map.
const Metadata=preload("res://scripts/world3d/white_native_asset_metadata.gd")
const ROOT="D:/code/rmmo_runtime"
func _initialize()->void:run.call_deferred()
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty():push_error("--output is required");quit(2);return
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd");controls.enable_white_materials();controls.discard_map_textures=true
	var rows:Array=[];var failures:=0
	for name:String in DirAccess.get_files_at(Metadata.Writer.directory(ROOT)):
		if not name.ends_with(".json"):continue
		var index:=Metadata.Writer.directory(ROOT).path_join(name)
		var info:Variant=JSON.parse_string(FileAccess.get_file_as_string(index))
		if not info is Dictionary or info.get("generator")!=Metadata.Writer.generator():continue
		var path:=ROOT.path_join("packs/default/assets").path_join(str(info.source_sha)+".glb")
		if Metadata.Writer.index_path(path,ROOT)!=index:continue
		var before:=FileAccess.get_sha256(index);var began:=Time.get_ticks_usec();var result:=Metadata.build(path,ROOT)
		result.elapsed_us=Time.get_ticks_usec()-began;result.index=index;result.index_sha_before=before;result.index_sha_after=FileAccess.get_sha256(index)
		if result.ok:
			var read:=Metadata.read(path,ROOT,info.source_sha,result.observation.file_length)
			result.reopened_exact=not read.is_empty()
			for field:String in Metadata.FIELDS:result.reopened_exact=result.reopened_exact and read.get(field)==result.observation[field]
			result.source_unchanged=FileAccess.get_sha256(path)==info.source_sha
			result.native_unchanged=FileAccess.get_sha256(result.product)==info.payload_sha
		if not result.ok or not result.get("reopened_exact",false) or not result.get("source_unchanged",false) or not result.get("native_unchanged",false) or before!=result.index_sha_after:failures+=1
		rows.append(result);print("WHITE_NATIVE_METADATA ",rows.size()," ok=",result.ok)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"failures":failures,"scope":"offline metadata only; original source/native/geometry manifests must retain their exact SHA"},"\t"))
	quit(1 if failures else 0)
