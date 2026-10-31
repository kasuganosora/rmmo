extends SceneTree
## Run on the private Windows desktop. The harness posts WM_NULL only to this
## process's main thread; the exported native scopes are checked after exit.
const Timeline=preload("res://scripts/util/debug_timeline.gd")
var output:=""
var failures:Array[String]=[]
var resized:=0
var python:=""
var harness:=""
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	if not ok:failures.append(label_);printerr("FAIL "+label_)
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):output=arg.trim_prefix("--output-dir=").replace("\\","/")
		elif arg.begins_with("--python="):python=arg.trim_prefix("--python=")
		elif arg.begins_with("--harness="):harness=arg.trim_prefix("--harness=")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/") or FileAccess.file_exists(output.path_join("result.json")):quit(2);return
	check(DisplayServer.get_name()=="Windows","real Windows private desktop")
	check(Timeline.available(),"native trace available")
	if not failures.is_empty():quit(2);return
	Engine.max_fps=60;root.size=Vector2i(480,320)
	root.size_changed.connect(func():resized+=1)
	for i in 3:await process_frame
	var delay_label:=Timeline.label("test.event_pump.main_delay")
	check(Timeline.start(262144,true)==OK,"capture starts")
	var ready:=FileAccess.open(output.path_join("ready.json"),FileAccess.WRITE)
	ready.store_string(JSON.stringify({"pid":OS.get_process_id()}));ready.close()
	for i:int in 180:
		if i==10:
			# OS.execute inherits this private desktop. A controller on the user's
			# desktop cannot post to its message queue (ERROR_INVALID_THREAD_ID).
			var captured:Array=[]
			check(OS.execute(python,[harness,"--post","--output",output],captured,true,false)==0,"owned helper posts on the same private desktop")
		if i in [20,40,60]:root.size=Vector2i(480+i,320)
		if i==90:
			var token:=Timeline.begin(delay_label)
			OS.delay_msec(25)
			Timeline.end(token)
		await process_frame
	var stats:=Timeline.stop()
	check(stats.dropped==0 and stats.events>0,"no native events dropped")
	check(resized>=3,"window resize notifications preserved")
	check(Timeline.export_capture(output.path_join("events.rmtrace"))==OK,"capture exported after stop")
	var result:Dictionary={"failures":failures,"stats":stats,"resized":resized,"pid":OS.get_process_id(),"scope":"native event coverage contract; injected main-thread delay is not a performance sample"}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("WINDOWS_EVENT_TRACE "+JSON.stringify(result));quit(0 if failures.is_empty() else 1)
