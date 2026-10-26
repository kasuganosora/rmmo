extends "res://tools/profile_axel_worker_capacity.gd"
## Diagnostic only: no polling, debugger or priority changes. Never game-loaded.
func _initialize()->void:
	var extension:=""
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--fault-capture-extension="):extension=arg.trim_prefix("--fault-capture-extension=")
		if arg.begins_with("--fault-capture-file="):output=arg.trim_prefix("--fault-capture-file=")
	if not extension.is_absolute_path() or not output.is_absolute_path():
		push_error("Fault capture requires absolute extension/output paths")
		quit(2);return
	OS.set_environment("RMMO_FAULT_CAPTURE_FILE",output)
	OS.set_environment("RMMO_FAULT_CAPTURE_TEST","0")
	OS.set_environment("RMMO_FAULT_CAPTURE_DISABLED","0")
	var status:=GDExtensionManager.load_extension(extension)
	if status!=GDExtensionManager.LOAD_STATUS_OK or ClassDB.class_exists("NativeFaultProbe"):
		push_error("Failed to load diagnostic capture, or fault injection unexpectedly exposed: %s"%status)
		quit(2);return
	print("NATIVE_FAULT_CAPTURE armed: ",output)
	super._initialize()

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_fault_capture.gd"]=FileAccess.get_sha256("res://tools/profile_axel_fault_capture.gd")
	return result
