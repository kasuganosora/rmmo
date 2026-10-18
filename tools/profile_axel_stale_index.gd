extends "res://tools/profile_axel_game_pipeline.gd"
## Real entry with only the derived directory's generation invalidated. Preserve
## its exact previous bytes; author map, models and other caches are unchanged.
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_stale_index.gd"]=FileAccess.get_sha256("res://tools/profile_axel_stale_index.gd")
	return result
func run()->void:
	var target_report:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):target_report=arg.trim_prefix("--output=")
	var Index=preload("res://scripts/world3d/map_dependency_index.gd")
	if not Index.Paths.allowed(target_report,"D:/code/rmmo_runtime/review_artifacts"):quit(2);return
	var target:String=Index.cache_path(MAP,"D:/code/rmmo_runtime")
	var backup:String=target_report+".previous_dependency_index.bin"
	if not Index.Paths.allowed(target,"D:/code/rmmo_runtime/cache/world3d/dependency_indexes") or FileAccess.file_exists(backup):quit(2);return
	var bytes:=FileAccess.get_file_as_bytes(target)
	if bytes.size()<49 or bytes.slice(0,9).get_string_from_ascii()!=Index.MAGIC or bytes.decode_u64(9)!=bytes.size()-49 or Index.Store._sha(bytes.slice(49)).hex_decode()!=bytes.slice(17,49):quit(2);return
	var payload:Variant=bytes_to_var(bytes.slice(49))
	if not payload is Dictionary or payload.get("source_sha256")!=FileAccess.get_sha256(MAP):quit(2);return
	payload.generator="0".repeat(64)
	var body:=var_to_bytes(payload);var header:PackedByteArray=Index.MAGIC.to_ascii_buffer();header.resize(17);header.encode_u64(9,body.size());header.append_array(Index.Store._sha(body).hex_decode())
	if DirAccess.rename_absolute(target,backup)!=OK:quit(2);return
	var file:=FileAccess.open(target,FileAccess.WRITE)
	if file==null:DirAccess.rename_absolute(backup,target);quit(2);return
	file.store_buffer(header);file.store_buffer(body);file.close()
	report.cache_control="Derived dependency directory generation invalidated; complete original bytes preserved beside this report. Other caches retained."
	await super.run()
