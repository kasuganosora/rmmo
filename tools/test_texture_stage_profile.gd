extends SceneTree
## Small CPU/dummy-renderer regression. No authored files or renderer readback.
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
var passed:=0
var failed:=0
var created:Array[String]=[]
class Errors extends Logger:
	var entries:Array[String]=[]
	var mutex:=Mutex.new()
	func _log_error(function:String,_file:String,_line:int,code:String,rationale:String,_notify:bool,_type:int,_backtraces:Array)->void:
		mutex.lock();entries.append(function+": "+code+" "+rationale);mutex.unlock()
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failed+=1
func count(profile:Dictionary,label:String)->int:return int(profile.counters.get(label,0))
func calls(profile:Dictionary,label:String)->int:return int(profile.stages.get(label,{}).get("calls",0))
func source(path:String,color:Color,format:int=Image.FORMAT_RGB8)->void:
	var image:=Image.create(19,13,false,format);image.fill(color)
	image.set_pixel(2,3,Color(.2,.7,.4,.3) if format==Image.FORMAT_RGBA8 else Color(.2,.7,.4))
	check(image.save_png(path)==OK,"write tiny temporary PNG")
	if not created.has(path):created.append(path)
func forget_cache(path:String,flip:bool=false)->void:
	var cache:=Pixels.cache_path(path,flip)
	if not created.has(cache):created.append(cache)
	if FileAccess.file_exists(cache):DirAccess.remove_absolute(cache)
static func worker_images(path:String,iterations:int)->bool:
	for i:int in iterations:
		var image:=Pixels.image(path,false)
		if image==null or image.get_format()!=Image.FORMAT_RGBA8:return false
	return true
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var folder:=OS.get_environment("TEMP").replace("\\","/").path_join("rmmo_texture_profile_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"create isolated temporary source directory")
	var manager:Node=root.get_node("AssetManager")
	var old_root:String=manager.content_root_override;manager.content_root_override=folder
	var old_upload:bool=Pixels.upload_preparation_enabled;Pixels.upload_preparation_enabled=true
	var path:=folder.path_join("rgb.png");source(path,Color(.4,.2,.8))
	forget_cache(path);forget_cache(path,true)
	Paint.texture_profile_enabled=false;Pixels.profile_enabled=false;Pixels.reset_profile();Trace.start()
	var baseline:=Pixels.image(path,false)
	check(baseline!=null and baseline.has_mipmaps() and baseline.get_format()==Image.FORMAT_RGBA8,"disabled diagnostics retain upload-ready image")
	check(Pixels.profile_snapshot("").stages.is_empty() and Pixels.profile_snapshot("").counters.is_empty(),"disabled diagnostics produce no counters or spans")
	check(Trace.stop().stats.is_empty(),"disabled stage profiling emits no Trace even when Trace is enabled")
	var cache_writable:=FileAccess.file_exists(Pixels.cache_path(path,false))
	check(cache_writable,"temporary decoded cache can be written")
	if not cache_writable:
		manager.content_root_override=old_root;Pixels.upload_preparation_enabled=old_upload
		for made:String in created:
			if FileAccess.file_exists(made):DirAccess.remove_absolute(made)
		DirAccess.remove_absolute(folder);OS.remove_logger(logger)
		print("Texture stage profile blocked: user:// cache is not writable in this execution environment")
		quit(1);return
	forget_cache(path)
	Pixels.profile_enabled=true;Trace.start()
	var cold:=Pixels.image(path,false);var warm:=Pixels.image(path,false)
	check(cold!=null and warm!=null and cold.get_data()==baseline.get_data() and warm.get_data()==baseline.get_data(),"enabled cold/warm paths preserve all pixel and mip bytes")
	check(cold.get_meta("runtime_source_sha256")==baseline.get_meta("runtime_source_sha256") and not cold.get_meta("runtime_upload_has_alpha") and warm.get_meta("runtime_upload_has_alpha")==cold.get_meta("runtime_upload_has_alpha"),"source and alpha metadata are unchanged")
	var pixels:=Pixels.profile_snapshot()
	check(calls(pixels,"texture.image")==2 and count(pixels,"texture.image.cache_miss")==1 and count(pixels,"texture.image.cache_hit")==1,"cold and warm totals count each path once")
	check(calls(pixels,"texture.image.source_sha")==2 and calls(pixels,"texture.image.cache_read")==2 and calls(pixels,"texture.image.cache_checksum")==1 and calls(pixels,"texture.image.cache_variant")==1,"SHA, bounded cache read, checksum and variant decode have separate spans")
	check(calls(pixels,"texture.image.cache_decompress")==1 and calls(pixels,"texture.image.cache_image")==1 and calls(pixels,"texture.image.upload_prepare")==2,"decompression, CPU image construction and format preparation have separate spans")
	check(calls(pixels,"texture.image.source_decode")==1 and calls(pixels,"texture.image.mipmaps")==1 and calls(pixels,"texture.image.cache_store")==1,"cold decode, mipmaps and cache write have separate spans")
	var traced:=Trace.stop();var found:=false
	for row:Dictionary in traced.stats:
		if row.label=="texture.image.source_sha":found=true
	check(found,"timings use existing bounded Trace collector")
	pixels.stages["texture.image"].calls=999;pixels.counters["texture.image.cache_hit"]=999
	check(calls(Pixels.profile_snapshot(),"texture.image")==2 and count(Pixels.profile_snapshot(),"texture.image.cache_hit")==1,"snapshot mutation cannot corrupt shared accumulator")
	var flip:=Pixels.image(path,true)
	Pixels.profile_enabled=false;var flip_baseline:=Pixels.image(path,true);Pixels.profile_enabled=true
	check(flip.get_data()==flip_baseline.get_data() and calls(Pixels.profile_snapshot(),"texture.image.normal_flip")==1,"normal orientation and its span survive cache parity")
	var file:=FileAccess.open(Pixels.cache_path(path,false),FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1,2,3]));file.close()
	var repaired:=Pixels.image(path,false)
	check(repaired.get_data()==baseline.get_data(),"corrupt decoded cache rebuilds with profiling enabled")
	source(path,Color(.8,.6,.1),Image.FORMAT_RGBA8)
	var replacement:=Pixels.image(path,false)
	check(replacement.get_data()!=baseline.get_data() and replacement.get_meta("runtime_source_sha256")==FileAccess.get_sha256(path) and replacement.get_meta("runtime_upload_has_alpha"),"same-path source replacement retains full SHA invalidation and alpha")
	Pixels.reset_profile()
	var workers:Array[Thread]=[]
	for i:int in 4:
		var thread:=Thread.new();check(thread.start(worker_images.bind(path,3))==OK,"CPU image worker starts");workers.append(thread)
	for thread:Thread in workers:
		while thread.is_alive():await process_frame
		check(thread.wait_to_finish(),"CPU image worker finishes with expected data")
	pixels=Pixels.profile_snapshot()
	check(calls(pixels,"texture.image")==12 and count(pixels,"texture.image.cache_hit")==12,"concurrent workers retain exact aggregate counts")
	check(int(pixels.stages["texture.image"].total_us)>=int(pixels.stages["texture.image"].max_us),"concurrent aggregate has consistent wall durations")
	Paint.texture_profile_enabled=true;Pixels.reset_profile()
	Paint._textures.clear();Paint._materials.clear();Paint.prepared_images={path:replacement}
	var definition:={"name":"profile fixture","color":[1,1,1,1],"roughness":.8,"texture_path":path}
	var material:=Paint.make_material(definition);var same_material:=Paint.make_material(definition)
	var same_texture:=Paint.texture(definition)
	var paint:=Paint.profile_snapshot()
	check(material==same_material and same_texture==material.albedo_texture and material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"dummy renderer preserves prepared texture/material identity and alpha")
	check(count(paint,"paint.material.cache_miss")==1 and count(paint,"paint.material.cache_hit")==1 and count(paint,"paint.texture.prepared_image_hit")==1 and count(paint,"paint.texture.gpu_cache_hit")==1,"material, resident GPU cache and prepared CPU image paths are distinguished")
	check(calls(paint,"paint.texture.upload")==1 and count(paint,"paint.texture.upload_bytes")==replacement.get_data_size() and calls(paint,"paint.texture.path_check")==2,"upload submission and path authorization remain explicit")
	check(Pixels.profile_snapshot().stages.is_empty(),"prepared images do not introduce a new CPU texture-cache lookup")
	Paint._textures.clear();Paint._materials.clear();Paint.prepared_images.clear();Pixels.reset_profile()
	var lookup:=Paint.texture(definition)
	check(lookup!=null and count(Paint.profile_snapshot(),"paint.texture.runtime_image_lookup")==1 and count(Pixels.profile_snapshot(),"texture.image.cache_hit")==1,"ordinary Paint path keeps existing runtime image fallback")
	var blocked:=Paint.texture({"texture_path":ProjectSettings.globalize_path("res://icon.svg")})
	check(blocked==null,"profiling does not bypass path authorization")
	Paint.texture_profile_enabled=false;Pixels.profile_enabled=false;Pixels.reset_profile()
	Paint.texture(definition);Paint.make_material(definition)
	check(Pixels.profile_snapshot("").stages.is_empty() and Pixels.profile_snapshot("").counters.is_empty(),"both flags disabled suppress material and pixel statistics")
	Paint._textures.clear();Paint._materials.clear();Paint.prepared_images.clear()
	material=null;same_material=null;same_texture=null;lookup=null
	manager.content_root_override=old_root;Pixels.upload_preparation_enabled=old_upload
	for made:String in created:
		if FileAccess.file_exists(made):DirAccess.remove_absolute(made)
	DirAccess.remove_absolute(folder)
	check(logger.entries.is_empty(),"no script, image or resource errors")
	OS.remove_logger(logger)
	print("Texture stage profile: %d PASS / %d FAIL"%[passed,failed]);quit(1 if failed else 0)
