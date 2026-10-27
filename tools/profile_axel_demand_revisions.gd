extends "res://tools/profile_axel_worker_capacity.gd"
## Diagnostic-only: capture actual revision causes for a selected return leg.
## The bounded event buffer is serialized after the observed leg, not per frame.
const DEFAULT_PHASE:="white_native_return"
const TRACE_PHASES:=["white_native_return","white_walk_return"]
const WALK_RETURN_PHASES:=["white_walk_return","white_walk_return_straight","white_walk_return_turn"]
const MAX_PHASE_BOUNDARIES:=64
var revision_capture_started:=false
var revision_capture_finished:=false
var revision_capture_last_phase:=""
var revision_capture_seen_phases:Dictionary={}
var revision_trace_enabled:= "--demand-revision-trace" in OS.get_cmdline_user_args()
var revision_trace_config:Dictionary=trace_configuration(OS.get_cmdline_user_args())

static func trace_configuration(arguments:PackedStringArray)->Dictionary:
	var selected:=DEFAULT_PHASE;var specified:=false
	for arg:String in arguments:
		if not arg.begins_with("--demand-revision-phase="):continue
		if specified:return {"phase":"","error":"demand revision phase specified more than once"}
		specified=true;selected=arg.trim_prefix("--demand-revision-phase=")
	if selected not in TRACE_PHASES:return {"phase":"","error":"unsupported demand revision phase: "+selected}
	return {"phase":selected,"error":""}

static func capture_action(enabled:bool,current_phase:String,target_phase:String,started:bool,finished:bool)->String:
	if not enabled or finished:return "none"
	# Predictive streaming splits the six-metre-per-second return into a
	# straight segment and a corner; both belong to the one requested leg.
	# This is an explicit whitelist, never arbitrary prefix matching.
	var matches:bool=current_phase==target_phase or (target_phase=="white_walk_return" and current_phase in WALK_RETURN_PHASES)
	if not started and matches:return "start"
	if started and not matches:return "stop"
	return "none"

static func finish_action(enabled:bool,configuration_error:String,started:bool,finished:bool)->String:
	if not enabled:return "none"
	if not configuration_error.is_empty():return "invalid_phase"
	if not started:return "not_started"
	if not finished:return "stop_incomplete"
	return "none"

static func completion_status(target_phase:String,seen:Dictionary,boundaries_dropped:int)->String:
	if boundaries_dropped>0:return "incomplete_boundary_overflow"
	if target_phase=="white_walk_return" and not seen.has("white_walk_return") and not (seen.has("white_walk_return_straight") and seen.has("white_walk_return_turn")):
		return "incomplete_missing_walk_segment"
	return "complete_return_leg"

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_demand_revisions.gd"]=FileAccess.get_sha256("res://tools/profile_axel_demand_revisions.gd")
	return result

func tick_geometry()->void:
	if revision_trace_enabled and revision_trace_config.error.is_empty():
		var action:=capture_action(true,phase,revision_trace_config.phase,revision_capture_started,revision_capture_finished)
		if action=="start":
			var limit:=16384
			for arg:String in OS.get_cmdline_user_args():
				if arg.begins_with("--demand-revision-capacity="):limit=int(arg.trim_prefix("--demand-revision-capacity="))
			var queue:Node=mesh_map.get_node("DeferredAssets")
			queue.start_demand_revision_trace(limit);revision_capture_started=true
			report.demand_revision_trace_started_us=Time.get_ticks_usec()
			report.demand_revision_trace_phase=revision_trace_config.phase
			report.demand_revision_trace_status="capturing"
			_mark_revision_boundary("start")
		elif action=="stop":
			_mark_revision_boundary("end")
			_stop_revision_capture()
		elif revision_capture_started and not revision_capture_finished and phase!=revision_capture_last_phase:
			_mark_revision_boundary("transition")
	super.tick_geometry()

func _mark_revision_boundary(kind:String)->void:
	# Called only on a phase change. Explicit limits and dropped counts keep the
	# diagnostic bounded even if a host unexpectedly oscillates between phases.
	if not report.has("demand_revision_trace_boundaries"):
		report.demand_revision_trace_boundaries=[];report.demand_revision_trace_boundaries_dropped=0
	if kind in ["start","transition"]:revision_capture_seen_phases[phase]=true
	var boundaries:Array=report.demand_revision_trace_boundaries
	if boundaries.size()<MAX_PHASE_BOUNDARIES:
		var now:=Time.get_ticks_usec()
		boundaries.append({"kind":kind,"phase":phase,"ticks_us":now,"at_us":now-int(report.demand_revision_trace_started_us),"frame":Engine.get_process_frames()})
	else:report.demand_revision_trace_boundaries_dropped+=1
	revision_capture_last_phase=phase

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
	report.demand_revision_trace_seen_phases=revision_capture_seen_phases.keys()
	report.demand_revision_trace_status=completion_status(revision_trace_config.phase,revision_capture_seen_phases,int(report.get("demand_revision_trace_boundaries_dropped",0)))
	report.demand_revision_trace_scope="Opt-in bounded revision and actual refresh events for the selected return leg; timing includes instrumentation overhead."

func finish(code:int)->void:
	report.demand_revision_trace_status_contract="Only complete_return_leg confirms a stopped capture. capturing, not_started, a missing field, or an error means coverage is incomplete; do not infer zero revisions."
	var action:=finish_action(revision_trace_enabled,revision_trace_config.error,revision_capture_started,revision_capture_finished)
	if action=="invalid_phase":
		report.demand_revision_trace_status="invalid_phase"
		report.demand_revision_trace_error=revision_trace_config.error
		check(false,revision_trace_config.error)
	elif action=="not_started":
		report.demand_revision_trace_phase=revision_trace_config.phase
		report.demand_revision_trace_status="not_started"
	elif action=="stop_incomplete":
		_mark_revision_boundary("finish_incomplete")
		_stop_revision_capture();report.demand_revision_trace_status="incomplete_stopped_at_finish"
	await super.finish(code)
