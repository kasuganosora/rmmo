extends "res://tools/profile_axel_worker_capacity.gd"
## Diagnostic only. Bound wall spans to the return-reload leg and retain frame
## timestamps; a GDB sample inside a method does not measure its whole cost.
var retirement_trace_started:=false
var retirement_trace_finished:=false

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_reload_retirement.gd"]=FileAccess.get_sha256("res://tools/profile_axel_reload_retirement.gd")
	return result

func tick_geometry()->void:
	if phase=="white_native_reload" and not retirement_trace_started:
		retirement_trace_started=true
		Trace.minimum_event_us=1000;Trace.methods_enabled=true;Trace.method_labels={}
		for label:String in ["deferred_asset_loader._discard_job","asset_worker_drainer.dispose_result","asset_worker_drainer._dispose_owned_packet","asset_worker_drainer.synchronize_transfer","resource_retirement.defer_import_packet"]:
			Trace.method_labels["method."+label]=true
		Trace.start();report.retirement_trace_start_us=Time.get_ticks_usec()
	elif retirement_trace_started and not retirement_trace_finished and phase!="white_native_reload":
		_stop_retirement_trace()
	super.tick_geometry()

func _stop_retirement_trace()->void:
	retirement_trace_finished=true
	report.reload_retirement_trace=Trace.stop()
	Trace.methods_enabled=false;Trace.method_labels={}
	report.reload_retirement_trace_note="Diagnostic wall spans may nest or overlap, include tracing overhead, and cannot be added or used as normal gameplay timing."

func finish(code:int)->void:
	if retirement_trace_started and not retirement_trace_finished:_stop_retirement_trace()
	await super.finish(code)
