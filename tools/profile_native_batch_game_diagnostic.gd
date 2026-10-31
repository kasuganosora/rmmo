extends "res://tools/profile_axel_native_lifecycle.gd"
## Explicit diagnostic gate before ordinary full-game loading. GDB pauses are
## excluded from performance comparisons; this does not change the game path.
func run()->void:
	var destination:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):destination=arg.trim_prefix("--output=").replace("\\","/")
	if not destination.begins_with(TEST_ROOT+"/"):quit(2);return
	report.normal_performance_sample=false;report.native_batch_gdb_diagnostic=true
	var gate:=destination.get_base_dir().path_join("native_batch.gate")
	FileAccess.open(gate+".ready",FileAccess.WRITE).store_string(str(OS.get_process_id()))
	var deadline:=Time.get_ticks_msec()+120000
	while not FileAccess.file_exists(gate) and Time.get_ticks_msec()<deadline:await process_frame
	if not FileAccess.file_exists(gate):printerr("native batch diagnostic gate timed out");quit(2);return
	await super.run()
