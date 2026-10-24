extends "res://tools/profile_white_native_asset.gd"
## Real largest-building reproduction: native worker handoff must not repack
## 2,319 nodes on main. Run on the private GPU desktop after offline conversion.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
func run()->void:
	var output:="";var expect_scene:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--expect-scene":expect_scene=true
	if output.is_empty():quit(2);return
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	check(DisplayServer.get_name()!="headless","real GPU desktop")
	var sha:=FileAccess.get_sha256(SOURCE)
	var report:={"source_sha":sha,"expect_scene":expect_scene}
	Trace.minimum_event_us=1000;Trace.start()
	var worker:=Thread.new();var started:=Time.get_ticks_usec()
	check(worker.start(Deferred.prepare_scene.bind(SOURCE,sha,null,{},true,"D:/code/rmmo_runtime",false,Deferred.CollisionGeometry.ALL,true,true))==OK,"native worker starts")
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish()
	Drainer.synchronize_transfer()
	report.prepare_wall_us=Time.get_ticks_usec()-started
	check(result.get("error","").is_empty() and result.get("compiled",false),"native product read without raw fallback")
	check(result.has("scene") if expect_scene else result.has("packed") and not result.has("scene"),"handoff shape matches expected route")
	check(not Library.has_cached_scene(SOURCE),"worker has not published global library")
	var packed:PackedScene=result.get("packed")
	started=Time.get_ticks_usec()
	var cached:=Library.cache_packed(SOURCE,packed,sha) if packed!=null else Library.cache_scene(SOURCE,result.scene,sha)
	report.accept_us=Time.get_ticks_usec()-started
	check(cached,"actual library accepts result")
	if packed!=null:
		check(Library._scenes[SOURCE]==packed,"library adopts exact native template without repacking")
		result.resource_owners.transfer_template(packed)
		check(result.resource_owners.packed==null,"worker transfers template ownership after acceptance")
	result.erase("scene");result.erase("packed")
	var first:Node3D=Library.instantiate(SOURCE);var second:Node3D=Library.instantiate(SOURCE)
	check(first!=null and second!=null,"two instances open from the accepted template")
	if first!=null and second!=null:
		report.fingerprint=fingerprint(first)
		var document:=GLTFDocument.new();var state:=GLTFState.new();Controls.configure_gltf(state)
		check(document.append_from_file(SOURCE,state,0,SOURCE.get_base_dir())==OK,"current GLB source reference parses")
		var raw:Node=Io.generate_scene(document,state,true)
		check(raw!=null,"current GLB source reference instantiates")
		if raw==null:quit(1);return
		check(Capture.capture(raw,true).error.is_empty(),"current GLB source CPU capture succeeds")
		report.current_source_fingerprint=fingerprint(raw)
		check(report.fingerprint==report.current_source_fingerprint,"structure, exact geometry, LODs and collision equal current GLB")
		Drainer.dispose_scene(raw);raw=null;Drainer.synchronize_transfer();document=null;state=null
		var a:Array=first.find_children("*","MeshInstance3D",true,false);var b:Array=second.find_children("*","MeshInstance3D",true,false)
		var shared:=a.size()==b.size() and not a.is_empty()
		for i:int in mini(a.size(),b.size()):shared=shared and a[i].mesh==b[i].mesh and a[i].mesh.get_meta("ground_cpu_cache")==b[i].mesh.get_meta("ground_cpu_cache")
		check(shared,"repeated instances share mesh and prepared CPU owners")
	Drainer.dispose_scene(first);Drainer.dispose_scene(second)
	Drainer.dispose_result(result);Library.evict_cached_scene(SOURCE);packed=null
	Drainer.synchronize_transfer()
	check(FileAccess.get_sha256(SOURCE)==sha,"source unchanged")
	report.trace=Trace.stop();report.failures=failures
	var instances:=0;var captures:=0
	for event:Dictionary in report.trace.stats:
		if event.label=="deferred.compiled_instantiate":instances+=int(event.count)
		if event.label=="deferred.cpu_capture":captures+=int(event.count)
	report.worker_instances=instances;report.worker_captures=captures
	var expect_instances:=expect_scene
	check(instances==1 and captures==1 if expect_instances else instances==0 and captures==0,"native cached-template handoff performs expected instance and capture work")
	report.failures=failures
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WHITE_NATIVE_HANDOFF ",report.accept_us," us failures=",failures)
	quit(1 if failures else 0)
