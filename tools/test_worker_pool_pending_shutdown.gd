extends SceneTree
## Native OS delays leave ordinary low-priority work pending at shutdown.
## No worker calls GDScript or owns this SceneTree after quit. The external
## runner must require a clean process exit; the marker is not a pass result.
func _initialize()->void:
	var high:=OS.get_cmdline_user_args().has("--high-priority")
	for at:int in 40:
		WorkerThreadPool.add_task(OS.delay_msec.bind(100),high,"shutdown native delay")
	print("PENDING_SHUTDOWN_ENQUEUED 40 high_priority=",high)
	quit()
