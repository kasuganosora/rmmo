extends SceneTree
## Engine/project startup cost before a script's first line, optionally followed
## by loading one script (and its preload graph): --load=res://path.gd
func _initialize()->void:
	var row:Dictionary={"initialize_us":Time.get_ticks_usec()}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--load="):
			var began:=Time.get_ticks_usec()
			var script:Resource=load(arg.trim_prefix("--load="))
			row.load_us=Time.get_ticks_usec()-began;row.loaded=script!=null
	print("STARTUP_TICKS ",JSON.stringify(row))
	quit()
