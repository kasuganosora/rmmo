extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var report:Dictionary={"pid":OS.get_process_id(),"anchor_ticks_us":Time.get_ticks_usec(),"anchor_unix_us":int(Time.get_unix_time_from_system()*1000000),"spans":[]}
	for mode:String in ["busy","wait","busy","wait"]:
		var began:=Time.get_ticks_usec();var value:=0.
		if mode=="busy":
			while Time.get_ticks_usec()-began<500000:value+=sqrt(float(Time.get_ticks_usec()%10000))
		else:OS.delay_msec(500)
		report.spans.append({"mode":mode,"start_us":began,"end_us":Time.get_ticks_usec(),"checksum":value})
		await process_frame
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			var file:=FileAccess.open(argument.trim_prefix("--output="),FileAccess.WRITE);file.store_string(JSON.stringify(report))
	print("THREAD_CPU_CALIBRATION completed busy/wait pairs")
	quit()
