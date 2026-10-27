extends "res://tools/profile_axel_worker_capacity.gd"
## Diagnostic-only: a single explicitly selected traversal leg, no scheduler changes.
const LABELS:=["method.world_stream.sync","method.world_stream._sync_work","method.world_stream._adopt","method.world_stream._changed_candidates","method.world_stream._candidates","method.world_stream._plan_jobs","method.world_stream._apply","method.world_stream._spawn","method.world_stream.append_ready_jobs","method.world_stream.retire_specs","method.world_stream._finish_loading_sources","method.stream_index._retire_plan","method.stream_index.validate_owned_retire","method.stream_index._commit_owned_retire"]
const PHASES:=["white_native_unload","white_native_return","white_native_reload"]
var trace_phase:=""
var trace_started:=false
var trace_finished:=false
var trace_previous:Dictionary={}

static func capture_action(target:String,current_phase:String,started:bool,finished:bool)->String:
	if finished:return "none"
	if not target in PHASES:return "invalid_configuration"
	if not started and current_phase==target:return "start"
	if started and current_phase!=target:return "stop"
	return "none"

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_stream_sync_trace.gd"]=FileAccess.get_sha256("res://tools/profile_axel_stream_sync_trace.gd")
	return result

func _start_sync_trace()->void:
	if Trace.enabled:
		report.stream_sync_trace_status="incomplete_trace_already_active"
		trace_finished=true
		return
	trace_previous={"minimum_event_us":Trace.minimum_event_us,"methods_enabled":Trace.methods_enabled,"method_labels":Trace.method_labels.duplicate()}
	Trace.minimum_event_us=1000
	Trace.methods_enabled=true
	Trace.method_labels={}
	for label:String in LABELS:Trace.method_labels[label]=true
	Trace.start()
	trace_started=true
	report.stream_sync_trace_started_us=Time.get_ticks_usec()
	report.stream_sync_trace_start_frame=Engine.get_process_frames()
	report.stream_sync_trace_status="capturing"

func _stop_sync_trace(complete:bool)->void:
	if not trace_started or trace_finished:return
	var stopped:=Time.get_ticks_usec()
	var result:Dictionary=Trace.stop()
	Trace.minimum_event_us=int(trace_previous.minimum_event_us)
	Trace.methods_enabled=bool(trace_previous.methods_enabled)
	Trace.method_labels=trace_previous.method_labels
	trace_finished=true
	report.stream_sync_trace=result
	report.stream_sync_trace_stopped_us=Time.get_ticks_usec()
	report.stream_sync_trace_stop_frame=Engine.get_process_frames()
	report.stream_sync_trace_stop_us=Time.get_ticks_usec()-stopped
	report.stream_sync_trace_status="complete_leg" if complete else "incomplete_stopped_at_finish"
	report.stream_sync_trace_contract="Diagnostic wall spans include probe overhead, may overlap/nest, and are not exclusive CPU time. Timestamps use engine ticks; thread IDs are Godot IDs, not Windows TIDs. dropped > 0 means incomplete coverage. Phase bounds are observed geometry ticks."

func tick_geometry()->void:
	if trace_phase.is_empty():
		for arg:String in OS.get_cmdline_user_args():
			if arg.begins_with("--sync-trace-phase="):trace_phase=arg.trim_prefix("--sync-trace-phase=")
	var action:=capture_action(trace_phase,phase,trace_started,trace_finished)
	if action=="invalid_configuration":
		report.stream_sync_trace_status="invalid_configuration"
		trace_finished=true
		check(false,"sync trace requires a valid --sync-trace-phase")
	elif action=="start":_start_sync_trace()
	elif action=="stop":_stop_sync_trace(true)
	super.tick_geometry()

func finish(code:int)->void:
	if trace_started and not trace_finished:_stop_sync_trace(false)
	await super.finish(code)
