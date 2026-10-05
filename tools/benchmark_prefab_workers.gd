extends SceneTree
const Cache=preload("res://scripts/world3d/map_metadata_cache.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var count:=4;var validate:=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--workers="):count=int(arg.trim_prefix("--workers="))
		if arg=="--validation":validate=true
	var path:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var context:={};var meta:=Cache.read(path,FileAccess.get_sha256(path),context)
	var loader:=Loader.new();var start:=Time.get_ticks_usec()
	var valid_:=true
	if validate:
		loader._content_root=preload("res://scripts/world3d/map_paths.gd").external_root();loader._prefab_worker_count=count
		loader._start_texture_prefetch(context.get("textures",[]))
		valid_=loader._valid_records(meta,context.get("paint_ids",[]))
		if loader._texture_thread!=null:loader._texture_thread.wait_to_finish();loader._texture_thread=null
	else:loader._decode_prefabs(meta.rmmo_records,count)
	var elapsed:=Time.get_ticks_usec()-start
	print("PREFAB_WORKERS ",JSON.stringify({"workers":count,"logical_processors":OS.get_processor_count(),"validation_and_textures":validate,"valid":valid_,"elapsed_us":elapsed}));loader.free();quit(0 if valid_ else 1)
