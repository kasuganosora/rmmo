extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var path:="D:/code/rmmo_runtime/maps/medieval_house_showcase_v8/map.gltf"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):path=arg.trim_prefix("--map=")
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(path)
	var loaded:Array=await loader.finished
	if loaded[0]==null:print(loaded);quit(1);return
	print("CACHE_LOAD_PROFILE ",JSON.stringify(loaded[0].get_meta("load_profile",{})))
	loaded[0].free()
	await process_frame
	var Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
	var data:Dictionary=Cook.read(path,FileAccess.get_sha256(path),Cook.generator_key())
	print("PREFAB_CACHE ",data.get("specs_skip_reason","none")," specs=",data.get("specs",[]).size())
	quit()
