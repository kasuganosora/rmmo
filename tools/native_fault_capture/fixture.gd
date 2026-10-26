extends SceneTree
## Deliberate faults, only for a separate headless subprocess. Never game-loaded.
var worker:Thread
func _initialize()->void:run.call_deferred()
func run()->void:
	var extension:=OS.get_environment("RMMO_FAULT_EXTENSION")
	var status:=GDExtensionManager.load_extension(extension)
	print("CAPTURE_FIXTURE loaded=",status," class=",ClassDB.class_exists("NativeFaultProbe")," main=",OS.get_thread_caller_id())
	if status!=0 or not ClassDB.class_exists("NativeFaultProbe"):quit(2);return
	var mode:=OS.get_environment("RMMO_FAULT_MODE")
	if mode not in ["noop","main_read","worker_read","worker_execute"]:quit(2);return
	if mode=="noop":quit(0);return
	var method:="execute_null" if mode.ends_with("execute") else "read_null"
	if mode.begins_with("worker"):
		worker=Thread.new()
		worker.start(func():print("FAULT_WORKER ",OS.get_thread_caller_id());ClassDB.class_call_static("NativeFaultProbe",method))
		await create_timer(20.).timeout
		quit(99)
	else:ClassDB.class_call_static("NativeFaultProbe",method)
