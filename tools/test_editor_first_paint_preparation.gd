extends "res://tools/test_world3d_mcp.gd"
## RED contract for first use. Run each --case=dds-http|dds-ui|png-http|png-ui
## on a private desktop with the editor CPU-compression API candidate. Its
## source/content root and APPDATA must be isolated by the external runner.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Thumbnail=preload("res://scripts/world_editor/material_thumbnails.gd")
var gate:=Semaphore.new()
var gate_mutex:=Mutex.new()
var gate_entered:=false
var import_result:Dictionary={}
var import_done:=false
var paint_result:Dictionary={}
var paint_done:=false
var recording_frames:=false
var previous_frame_usec:=0
var frame_intervals:Array[int]=[]

func _start_gated(thread:Thread,task:Callable)->int:
	return thread.start(_gated.bind(task),Thread.PRIORITY_LOW)
func _gated(task:Callable)->Variant:
	gate_mutex.lock();gate_entered=true;gate_mutex.unlock()
	gate.wait()
	return task.call()
func _gate_entered()->bool:
	gate_mutex.lock();var result:=gate_entered;gate_mutex.unlock();return result
func _frame_probe()->void:
	if not recording_frames:return
	var now:=Time.get_ticks_usec()
	if previous_frame_usec>0:frame_intervals.append(now-previous_frame_usec)
	previous_frame_usec=now
func _do_import(path:String)->void:
	import_result=await call_tool("import_surface_material",{"path":path,"name":"first paint fixture"})
	import_done=true
func _do_paint(args:Dictionary)->void:
	paint_result=await call_tool("paint_surface",args)
	paint_done=true
func _do_ui_apply()->void:
	editor._material_panel._apply()
	paint_done=true
func _wait_until(test:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if test.call():return true
		await process_frame
	return test.call()
func _painted(id:String)->bool:
	return not editor._doc._find(id).get("surface_paint",[]).is_empty()
func _max_frame_ms()->float:
	var value:=0
	for span:int in frame_intervals:value=maxi(value,span)
	return value/1000.0

func _check_paint_work(_profile:Dictionary)->void:
	pass

func run()->void:
	var case_name:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):case_name=arg.trim_prefix("--case=")
	if case_name not in ["dds-http","dds-ui","png-http","png-ui"]:
		push_error("--case=dds-http|dds-ui|png-http|png-ui required");quit(1);return
	if DisplayServer.get_name()=="headless":push_error("actual editor rendering needs private desktop");quit(1);return
	if not Image.new().has_method("compress_from_channels_cpu"):
		push_error("candidate CPU compression API is required to validate the DDS arm");quit(1);return
	rpc_timeout_ms=30000
	var directory:=Paths.external_root().path_join("review_artifacts/first_paint_%s_%d_%d"%[case_name,OS.get_process_id(),Time.get_ticks_usec()])
	if DirAccess.dir_exists_absolute(directory):push_error("fresh isolated fixture required");quit(1);return
	check(DirAccess.make_dir_recursive_absolute(directory)==OK,"create external isolated fixture")
	var source:=directory.path_join("source.png")
	var size:=Vector2i(32,32) if case_name.begins_with("dds-") else Vector2i(31,29)
	var image:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8);image.fill(Color(.21,.53,.81,1))
	check(image.save_png(source)==OK,"create distinct real source image")
	var path:=directory.path_join("maps/test/map.gltf")
	var doc:=Doc.new();var box_id:String=doc.add_box("block",Vector3(0,1,0),Vector3(2,2,2))
	check(doc.save(path)==OK,"save isolated unpainted map")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._material_directory=directory.path_join("materials");editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start real loopback MCP")
	var queue:Node=editor._surface_texture_imports._queue
	queue.thread_starter=Callable(self,"_start_gated")
	_do_import.call_deferred(source)
	var entered:=await _wait_until(Callable(self,"_gate_entered"),10.0)
	check(entered and not import_done and not editor._mcp._pending_imports.is_empty(),"real import worker is gated while HTTP remains pending")
	if entered:
		var live:=await call_tool("editor_state")
		check(live.get("ok",false) and not import_done,"editor_state remains responsive during gated preparation")
	queue.thread_starter=Callable();gate.post()
	check(await _wait_until(func():return import_done,30.0),"actual import completes after worker release")
	if not import_result.get("ok",false):
		editor.queue_free();await settle();print("FIRST_PAINT fixture failure ",JSON.stringify({"case":case_name,"fixture":directory,"failed":failed}));quit(1);return
	check(bool(import_result.get("dds_ready",false))==case_name.begins_with("dds-"),"actual production result selects requested DDS/PNG arm")
	if case_name.begins_with("png-"):check(import_result.get("dds_reason","")=="dimensions_not_multiple_of_four","PNG is genuine non-multiple-of-four fallback")
	check(FileAccess.file_exists(import_result.material.texture_path),"imported material points at its published source")
	var faces:=await call_tool("list_object_surfaces",{"id":box_id})
	if faces.get("faces",[]).is_empty():
		check(false,"box exposes real paint face");editor.queue_free();await settle();quit(1);return
	var target:Dictionary=faces.faces[0].target
	var before:Array=editor._doc.records.duplicate(true)
	var args:={"id":box_id,"target":target,"material_id":import_result.material_id}
	# Do not clear production caches here: any retained result produced by import
	# is exactly what this regression is meant to preserve.
	Pixels.reset_profile();Pixels.profile_enabled=true;Paint.texture_profile_enabled=true
	frame_intervals.clear();previous_frame_usec=0;recording_frames=true
	process_frame.connect(_frame_probe)
	gate_mutex.lock();gate_entered=false;gate_mutex.unlock()
	queue.thread_starter=Callable(self,"_start_gated")
	var started:=Time.get_ticks_usec();var start_frame:=Engine.get_process_frames()
	if case_name.ends_with("http"):_do_paint.call_deferred(args)
	else:
		editor._material_tool.selected={"ok":true,"id":box_id,"target":target}
		editor._material_tool.material_id=import_result.material_id
		_do_ui_apply.call_deferred()
	# A future first-use preparation may start a worker; hold it while a second
	# HTTP request is served. An import-time prepared hit can complete directly
	# and needs no additional worker, so it is not an artificial failure.
	var paint_gate:=await _wait_until(func():return _gate_entered() or _painted(box_id),3.0)
	var gated_paint:=paint_gate and _gate_entered()
	if gated_paint:
		var live:=await call_tool("editor_state")
		check(live.get("ok",false) and not _painted(box_id),"editor_state remains responsive during gated first-use worker")
	queue.thread_starter=Callable()
	# Release even if the worker entered just after the bounded observation.
	gate.post()
	check(await _wait_until(func():return paint_done and _painted(box_id),30.0),"first actual paint invocation completes")
	await process_frame
	var elapsed_usec:=Time.get_ticks_usec()-started
	var frames_during_paint:=Engine.get_process_frames()-start_frame
	recording_frames=false;process_frame.disconnect(_frame_probe)
	var snapshot:Dictionary=Pixels.profile_snapshot("")
	_check_paint_work(snapshot)
	var counters:Dictionary=snapshot.counters
	var sidecar_reads:=int(counters.get("paint.texture.sidecar_main_reads",0))
	var runtime_lookup:=int(counters.get("paint.texture.runtime_image_lookup",0))
	var prepared_hits:=int(counters.get("paint.texture.prepared_image_hit",0))+int(counters.get("paint.texture.gpu_cache_hit",0))
	check(_painted(box_id),"real paint modifies the requested surface")
	check(sidecar_reads==0,"RED: first paint must not synchronously reread the DDS on main")
	check(runtime_lookup==0,"RED: first paint must not synchronously decode/read PNG on main")
	check(prepared_hits>0 or int(counters.get("paint.texture.sidecar_uploads",0))>0,"paint actually consumed its image; zero counters alone cannot pass")
	var after:Array=editor._doc.records.duplicate(true)
	await call_tool("undo");check(equivalent(editor._doc.records,before),"undo restores pre-paint record")
	await call_tool("redo");check(equivalent(editor._doc.records,after),"redo restores painted record")
	await call_tool("save_world")
	await call_tool("open_world",{"path":path,"discard_changes":true})
	check(equivalent(editor._doc.records,after),"save/reopen preserves painted material and face")
	# The current thumbnail loader owns a bare Thread, not the editor ledger.
	# This structural red assertion makes the missing coordination explicit;
	# replace it with functional per-lease instrumentation if implementation
	# uses a different shared-ledger architecture.
	var loader:Node=editor._material_panel._loader
	var thumb_queue:Variant=loader.get("_queue") if "_queue" in loader else null
	var shared_thumbnail:bool=is_instance_valid(thumb_queue) and "ledger" in thumb_queue and thumb_queue.ledger==editor._shared_preparation_ledger
	check(shared_thumbnail,"RED: thumbnail preparation must use the shared editor ledger")
	print("FIRST_PAINT_RESULT ",JSON.stringify({"case":case_name,"fixture":directory,"failed":failed,"source_path":source,"published":import_result.material.texture_path,"dds_ready":import_result.get("dds_ready",false),"paint_ms":elapsed_usec/1000.0,"frame_max_ms":_max_frame_ms(),"frame_count":frame_intervals.size(),"process_frames":frames_during_paint,"gated_first_use_worker":gated_paint,"sidecar_main_reads":sidecar_reads,"runtime_image_lookup":runtime_lookup,"prepared_or_gpu_hits":prepared_hits,"thumbnail_shared_ledger":shared_thumbnail,"profile":snapshot}))
	Pixels.profile_enabled=false;Paint.texture_profile_enabled=false
	editor.queue_free();await settle()
	session.world3d_editor_doc=null;session.world3d_editor_path=""
	quit(1 if failed else 0)
