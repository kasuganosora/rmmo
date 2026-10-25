extends SceneTree
## Exercise the actual MapLoader worker entry; no GPU or authored assets.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
var failures:Array[String]=[]
func check(value:bool,label:String)->void:
	if not value:failures.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var source:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=").replace("\\","/")
	if source.is_empty():quit(2);return
	var loader:=Loader.new();loader.background_preload=false;loader._content_root=Paint.Paths.external_root()
	var requested:Array=[[source,false,false],[source,false,true]]
	Paint.refresh_sources();Paint._sidecar_cache["sentinel"]="main only"
	var worker:=Thread.new();worker.start(loader._start_texture_prefetch.bind(requested))
	while worker.is_alive():await process_frame
	worker.wait_to_finish()
	check(Paint._sidecar_cache=={"sentinel":"main only"},"MapLoader worker cannot mutate the main-thread DDS cache")
	check(loader._texture_thread==null,"all DDS variants avoid creating duplicate PNG worker work")
	if "--single" not in OS.get_cmdline_user_args():
		var task:=func():
			for i:int in 2000:loader._start_texture_prefetch(requested)
			return 2000
		worker=Thread.new();worker.start(task)
		var refreshes:=0
		while worker.is_alive():
			Paint.refresh_sources();Paint._sidecar_cache["main"]=str(refreshes);refreshes+=1
			await process_frame
		check(worker.wait_to_finish()==2000 and refreshes>0,"worker probes complete while main refreshes sources")
		check(Paint._sidecar_cache.keys()==["main"],"parallel worker leaves only main-owned cache entries")
		print("SIDECAR_REFRESHES ",refreshes)
	Paint.refresh_sources();loader.free()
	print("SIDECAR_WORKER_LOOKUP ",JSON.stringify({"failures":failures}));quit(0 if failures.is_empty() else 1)
