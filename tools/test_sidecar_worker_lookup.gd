extends SceneTree
## Exercise the actual MapLoader worker entry; no GPU or authored assets.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Compressed=preload("res://scripts/world3d/compressed_texture_source.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
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
	var expected:Dictionary={}
	for item:Array in requested:
		var row:=Compressed.plan(item[0],item[1],item[2],loader._content_root)
		check(not row.is_empty(),"fixture provides supported DDS for each role")
		if row.is_empty():loader.free();quit(2);return
		expected[Paint.texture_key(item[0],item[1],item[2])]=Compressed.read(row).get_data()
	Paint.refresh_sources();Paint._sidecar_cache["sentinel"]="main only"
	Pixels.profile_enabled=true;Pixels.reset_profile()
	var worker:=Thread.new();worker.start(loader._start_texture_prefetch.bind(requested))
	while worker.is_alive():await process_frame
	worker.wait_to_finish()
	check(Paint._sidecar_cache=={"sentinel":"main only"},"MapLoader worker cannot mutate the main-thread DDS cache")
	check(loader._texture_thread!=null,"DDS variants are scheduled on the CPU preparation worker")
	if loader._texture_thread!=null:
		while loader._texture_thread.is_alive():await process_frame
		var prepared:Dictionary=loader._texture_thread.wait_to_finish();loader._texture_thread=null
		check(prepared.images.size()==2,"both color and normal roles return prepared images")
		for key:String in expected:
			check(prepared.images.has(key) and prepared.images[key].is_compressed() and prepared.images[key].get_data()==expected[key],"worker preserves DDS mip bytes for "+key)
	if "--single" not in OS.get_cmdline_user_args():
		var task:=func():
			var completed:=0
			# These calls now read actual DDS payloads. Bound the concurrency test
			# rather than repeating the old 2,000 filesystem-only probes.
			for i:int in 32:
				loader._start_texture_prefetch(requested)
				if loader._texture_thread==null:continue
				var prepared:Dictionary=loader._texture_thread.wait_to_finish();loader._texture_thread=null
				var valid:bool=prepared.images.size()==2
				for key:String in expected:
					valid=valid and prepared.images.has(key) and prepared.images[key].is_compressed() and prepared.images[key].get_data()==expected[key]
				if valid:completed+=1
			return completed
		worker=Thread.new();worker.start(task)
		var refreshes:=0
		while worker.is_alive():
			Paint.refresh_sources();Paint._sidecar_cache["main"]=str(refreshes);refreshes+=1
			await process_frame
		check(worker.wait_to_finish()==32 and refreshes>0,"DDS workers complete while main refreshes sources")
		check(Paint._sidecar_cache.keys()==["main"],"parallel worker leaves only main-owned cache entries")
		print("SIDECAR_REFRESHES ",refreshes)
	check(Pixels.profile_snapshot().counters.is_empty(),"compressed workers perform no PNG image lookup/decode/cache work")
	Pixels.profile_enabled=false;Pixels.reset_profile()
	Paint.refresh_sources();loader.free()
	print("SIDECAR_WORKER_LOOKUP ",JSON.stringify({"failures":failures}));quit(0 if failures.is_empty() else 1)
