extends SceneTree
## Exact initial native-reader isolation; optional external gate is diagnostic only.
const ROOT="D:/code/rmmo_runtime"
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Reader=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var output:="";var gate:=""
	var path:=ROOT+"/packs/default/assets/7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9).replace("\\","/")
		elif arg.begins_with("--gate="):gate=arg.substr(7).replace("\\","/")
	if not output.begins_with(ROOT+"/review_artifacts/") or (not gate.is_empty() and not gate.begins_with(ROOT+"/review_artifacts/")):quit(2);return
	if DisplayServer.get_name()=="headless":quit(2);return
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var candidate:=Assets.native_candidate(path,ROOT)
	if candidate.is_empty():print("FAIL missing exact native product");quit(1);return
	if not gate.is_empty():
		FileAccess.open(gate+".ready",FileAccess.WRITE).store_string(str(OS.get_process_id()))
		var limit:=Time.get_ticks_msec()+120000
		while not FileAccess.file_exists(gate) and Time.get_ticks_msec()<limit:await process_frame
		if not FileAccess.file_exists(gate):print("FAIL diagnostic gate timeout");quit(1);return
	Trace.minimum_event_us=0;Trace.start()
	var began:=Time.get_ticks_usec();var thread:=Thread.new()
	var code:=thread.start(Reader.read.bind(path,candidate,ROOT,Callable(),true,false,"",true,true))
	if code!=OK:print("FAIL native reader thread");quit(1);return
	while thread.is_alive():await process_frame
	var result:Dictionary=thread.wait_to_finish();var elapsed:=Time.get_ticks_usec()-began
	if not gate.is_empty():FileAccess.open(gate+".done",FileAccess.WRITE).store_string(str(elapsed))
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	var okay:bool=result.get("error",FAILED)==OK and result.get("packed") is PackedScene
	var report:={"ok":okay,"candidate":candidate,"elapsed_us":elapsed,"cache_us":result.get("cache_us",0),"trace":Trace.stop(),"gated_diagnostic":not gate.is_empty()}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	result.clear();await process_frame
	print("PASS " if okay else "FAIL ","NATIVE_PRODUCT_READ ",elapsed)
	quit(0 if okay else 1)
