extends SceneTree
const Trace=preload("res://scripts/world3d/load_trace.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	Engine.max_fps=60
	var monitor=preload("res://tools/load_monitor.gd").new();monitor.start(self)
	var worker:=Thread.new()
	worker.start(func():
		var started:=Trace.begin("smoke.worker");OS.delay_msec(650);Trace.elapsed("smoke.worker",started))
	while worker.is_alive():await process_frame
	worker.wait_to_finish()
	var started:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-started<1500000:
		await process_frame;monitor.frame("smoke")
	var report:Dictionary=monitor.finish()
	print("MONITOR_CONSTANTS ",Array(ClassDB.class_get_integer_constant_list("Performance")).filter(func(key):return "PIPELINE" in key)," ",Array(ClassDB.class_get_integer_constant_list("RenderingServer")).filter(func(key):return "PIPELINE" in key))
	var worker_stats:Array=report.trace.stats.filter(func(item):return item.label=="smoke.worker")
	var ok:bool=worker_stats.size()==1 and worker_stats[0].thread_id!=report.main_thread_id and not Trace.enabled and not report.samples.is_empty()
	ok=ok and not RenderingServer.frame_pre_draw.is_connected(monitor._before_draw) and not RenderingServer.frame_post_draw.is_connected(monitor._after_draw) and not node_added.is_connected(monitor._node_added)
	print("LOAD_MONITOR_SMOKE ",JSON.stringify({"ok":ok,"pid":report.pid,"main_tid":report.main_thread_id,"worker":worker_stats,"samples":report.samples.size(),"first":report.samples[0]}))
	quit(0 if ok else 1)
