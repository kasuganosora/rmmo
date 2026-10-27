extends "res://tools/profile_axel_worker_capacity.gd"
## Diagnostic-only: capture actual revision causes for the return leg. The
## bounded event buffer is serialized after the observed leg, not per frame.
var revision_capture_started:=false
var revision_capture_finished:=false
var revision_trace_enabled:= "--demand-revision-trace" in OS.get_cmdline_user_args()

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_demand_revisions.gd"]=FileAccess.get_sha256("res://tools/profile_axel_demand_revisions.gd")
	return result

func tick_geometry()->void:
	if revision_trace_enabled:
		if phase=="white_native_return" and not revision_capture_started:
			var limit:=16384
			for arg:String in OS.get_cmdline_user_args():
				if arg.begins_with("--demand-revision-capacity="):limit=int(arg.trim_prefix("--demand-revision-capacity="))
			var queue:Node=mesh_map.get_node("DeferredAssets")
			queue.start_demand_revision_trace(limit);revision_capture_started=true
			report.demand_revision_trace_started_us=Time.get_ticks_usec()
			report.demand_revision_trace_status="capturing"
		elif revision_capture_started and not revision_capture_finished and phase!="white_native_return":
			_stop_revision_capture()
	super.tick_geometry()

func _stop_revision_capture()->void:
	revision_capture_finished=true
	var began:=Time.get_ticks_usec()
	var queue:Node=mesh_map.get_node_or_null("DeferredAssets") if is_instance_valid(mesh_map) else null
	if queue==null:
		report.demand_revision_trace_error="queue no longer exists"
		report.demand_revision_trace_status="incomplete_missing_queue"
		return
	report.demand_revision_trace=queue.stop_demand_revision_trace()
	report.demand_revision_trace_stopped_us=Time.get_ticks_usec()
	report.demand_revision_trace_stop_us=Time.get_ticks_usec()-began
	report.demand_revision_trace_status="complete_return_leg"
	report.demand_revision_trace_scope="Opt-in bounded revision and actual refresh events for return leg; timing includes instrumentation overhead."

func finish(code:int)->void:
	report.demand_revision_trace_status_contract="Only complete_return_leg confirms a stopped capture. capturing, not_started, a missing field, or an error means coverage is incomplete; do not infer zero revisions."
	if revision_trace_enabled and not revision_capture_started:report.demand_revision_trace_status="not_started"
	if revision_capture_started and not revision_capture_finished:
		_stop_revision_capture();report.demand_revision_trace_status="incomplete_stopped_at_finish"
	await super.finish(code)
