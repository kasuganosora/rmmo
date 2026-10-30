extends SceneTree
## Exercise the same stdout/stderr delivery as performance probes, with no map.
var output:=""
var count:=80
var marker:=""
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--iterations="):count=arg.trim_prefix("--iterations=").to_int()
		elif arg.begins_with("--phase-marker="):marker=arg.trim_prefix("--phase-marker=")
	run.call_deferred()
func run()->void:
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not marker.is_empty():FileAccess.open(marker,FileAccess.WRITE).store_line("WHITE_TRAVERSAL logging")
	var elapsed:Array=[]
	for i in count:
		var began:=Time.get_ticks_usec()
		print("LOG_CAPTURE_ROW ",i," 测试输出")
		elapsed.append(Time.get_ticks_usec()-began)
		await process_frame
	printerr("LOG_CAPTURE_STDERR 完整保留")
	var sorted:=elapsed.duplicate();sorted.sort()
	var report:={"iterations":count,"elapsed_us":elapsed,"p50_us":sorted[sorted.size()/2],"max_us":sorted.back(),"scope":"stdout dispatch only; not frame or map time"}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LOG_CAPTURE_FINISHED ",count);quit()
