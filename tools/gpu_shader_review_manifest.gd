extends RefCounted
## Review-only guard: a game launch does not necessarily reimport edited GLSL.
## Refuse stale cached SPIR-V and record both source and compiled hashes.
static func collect()->Dictionary:
	var result:Dictionary={}
	var directory:="res://addons/godot_gpu_cloth/shaders/compute/"
	for name:String in DirAccess.get_files_at(directory):
		if not name.ends_with(".glsl"):continue
		var source:=directory+name
		var config:=ConfigFile.new()
		if config.load(source+".import")!=OK:push_error("Missing shader import: "+source);return {}
		var compiled:String=config.get_value("remap","path","")
		var cache:=compiled.get_basename()+".md5"
		var expected:='source_md5="'+FileAccess.get_md5(source)+'"'
		if not FileAccess.file_exists(compiled) or not FileAccess.file_exists(cache) or not FileAccess.get_file_as_string(cache).contains(expected):
			push_error("Stale shader import; run Godot --editor --import --quit: "+source)
			return {}
		result[name]={"source_sha256":FileAccess.get_sha256(source),"compiled_sha256":FileAccess.get_sha256(compiled)}
	return result
