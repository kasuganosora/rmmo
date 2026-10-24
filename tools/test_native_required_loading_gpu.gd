extends "res://tools/test_asset_bounds_manifest.gd"
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Source=preload("res://scripts/world3d/asset_source_metadata.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
func initial(path:String,directory:String,manifest:Dictionary)->Dictionary:
	var job:=Preparation.new();job.require_native_products=true;job.static_scene_paths[path]=manifest
	return job.run([path],Callable(),2,Callable(),directory)
func deferred(path:String,directory:String,digest:String,manifest:Dictionary,raw:bool=false)->Dictionary:
	return Deferred.prepare_scene(path,digest,null,manifest,false,directory,raw,Deferred.CollisionGeometry.ALL,true,true,true)
func reject(path:String,directory:String,digest:String,manifest:Dictionary,label:String)->void:
	Trace.minimum_event_us=0;Trace.start()
	var result:=initial(path,directory,manifest)
	check(result.error!=OK and result.entries.size()==1 and result.entries[0].get("native_product_required",false),label+": initial load reports missing native product")
	check(not result.admission_profile.stages.has("raw_import") and result.threads_joined==result.threads_started and result.inflight_reserved_at_return==0,label+": no raw stage, worker or lease left")
	Drainer.dispose_result(result);result={}
	var packet:=deferred(path,directory,digest,manifest)
	check(not packet.error.is_empty() and not packet.has("scene") and not packet.has("packed"),label+": deferred load refuses raw import")
	Drainer.dispose_result(packet);packet={}
	check(not Source.read(path,directory,"",true).get("known",false),label+": native metadata miss cannot reconstruct from GLB")
	var events:Array=Trace.stop().events
	check(events.all(func(e):return e.label not in ["model.raw_append","model.bounds_manifest","deferred.raw_import_wait","deferred.cpu_capture"]),label+": no raw parsing, bounds scan or capture events")
func run()->void:
	check(DisplayServer.get_name()!="headless","isolated real GPU context")
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd");controls.enable_white_materials();controls.discard_map_textures=true
	var directory:=Paths.cache_directory("native_required_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("fixture.glb");write(path,data())
	var digest:=FileAccess.get_sha256(path);var manifest:=Manifest.read(path)
	manifest.memory=preload("res://scripts/world3d/asset_memory_estimate.gd").estimate(path)
	reject(path,directory,digest,manifest,"absent")
	var built:=Native.build(path,directory);check(built.ok,"editor exporter creates native product")
	if not built.ok:quit(1);return
	var result:=initial(path,directory,manifest)
	check(result.error==OK and result.native_cache_hits==1 and not result.admission_profile.stages.has("raw_import"),"initial native-only load succeeds")
	Drainer.dispose_result(result);result={}
	var packet:=deferred(path,directory,digest,manifest)
	check(packet.error.is_empty() and packet.compiled and packet.has("packed"),"deferred native-only load succeeds")
	Drainer.dispose_result(packet);packet={}
	check(Source.read(path,directory,"",true).get("native_metadata_hit",false),"native metadata works with explicit required policy")
	var index:=Native.index_path(path,directory);var stale:Dictionary=built.manifest.duplicate(true);stale.generator="stale"
	FileAccess.open(index,FileAccess.WRITE).store_string(JSON.stringify(stale))
	reject(path,directory,digest,manifest,"stale")
	check(not deferred(path,directory,digest,manifest,true).error.is_empty(),"raw_only cannot bypass required-native policy")
	# Explicit editor parsing/export remains available, with ownership cleanup.
	var editor:=Preparation._parse_fallback(path,directory,digest,false,true)
	check(editor.error==OK and editor.state is GLTFState and editor.get("compiled")==false,"explicit editor GLB import remains available")
	Drainer.dispose_result(editor);editor={}
	var job:=Preparation.new();job.require_native_products=true
	var called:=[0]
	job.cache_reader=func(_path:String):return {"hit":false,"reason":"absent"}
	job.memory_estimator=func(_path:String):return {"estimated_bytes":1,"exclusive":false,"known":true}
	result=job.run(["missing"],func(_path:String):called[0]+=1;return {"error":OK})
	check(result.error!=OK and called[0]==0,"cache miss never calls injected raw parser")
	Drainer.dispose_result(result);result={}
	var candidate:={"source_sha":"a".repeat(64)}
	job.candidate_reader=func(_path:String,_candidate:Dictionary):return {"error":ERR_BUSY,"native_source_retry":true,"packed":PackedScene.new(),"compiled":true,"source_digest":candidate.source_sha,"cache_reason":"candidate_source_changed_after_read"}
	packet=job._candidate_stage(path,candidate,directory)
	check(packet.error!=OK and packet.has("packed") and not packet.has("native_source_retry") and not packet.has("fallback_required"),"source-change error preserves allocated owners without a raw retry")
	Drainer.dispose_result(packet);packet={}
	FileAccess.open(index,FileAccess.WRITE).store_string(JSON.stringify(built.manifest))
	Drainer.synchronize_transfer()
	check(FileAccess.get_sha256(path)==digest,"source asset unchanged")
	print("NATIVE_REQUIRED_LOADING_GPU passed=",passed," failures=",failures)
	quit(1 if failures else 0)
