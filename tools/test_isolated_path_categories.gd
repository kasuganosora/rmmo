extends SceneTree
const Builder=preload("res://tools/isolated_texture_map_builder.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
func _initialize()->void:
	var path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--inventory="):path=arg.trim_prefix("--inventory=")
	if path.is_empty() or not Paths.allowed(path,Builder.REVIEW_ROOT):printerr("invalid inventory");quit(2);return
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.get("path_fields") is Dictionary:printerr("invalid inventory content");quit(2);return
	var counts:Dictionary={};var unknown:Array=[]
	for key:String in data.path_fields:
		var category:=Builder._path_category(key)
		if category.is_empty():unknown.append(key)
		else:counts[category]=int(counts.get(category,0))+1
	if not Builder._path_category("record.not_yet_understood.source_path").is_empty():unknown.append("unknown field accepted")
	print("PATH_CATEGORIES fields=",data.path_fields.size()," counts=",counts," unknown=",unknown)
	quit(0 if unknown.is_empty() else 1)
