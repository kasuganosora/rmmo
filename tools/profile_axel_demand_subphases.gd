extends "res://tools/profile_axel_worker_capacity.gd"
## Diagnostic only: use existing bounded spans during the return leg. No file
## writes or scheduler behavior changes within the observed frame sequence.
var demand_trace_started:=false
var demand_trace_finished:=false
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_demand_subphases.gd"]=FileAccess.get_sha256("res://tools/profile_axel_demand_subphases.gd")
	return result
func tick_geometry()->void:
	if phase=="white_native_return" and not demand_trace_started:
		demand_trace_started=true;Trace.minimum_event_us=2500;Trace.start()
		report.demand_trace_start_us=Time.get_ticks_usec()
	elif demand_trace_started and not demand_trace_finished and phase!="white_native_return":
		_stop_demand_trace()
	super.tick_geometry()
func _stop_demand_trace()->void:
	demand_trace_finished=true;report.demand_return_trace=Trace.stop()
	report.demand_trace_note="Diagnostic wall spans, potentially nested and concurrent; not an ordinary timing or exclusive CPU sample. Preserve dropped count."
func finish(code:int)->void:
	if demand_trace_started and not demand_trace_finished:_stop_demand_trace()
	await super.finish(code)
