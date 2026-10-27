extends "res://tools/profile_axel_demand_revisions.gd"
## Only for the private instrumented overlay. Never enables production tracing.
var ticket_enabled:= "--demand-ticket-trace" in OS.get_cmdline_user_args()
var ticket_config:Dictionary=ticket_configuration(OS.get_cmdline_user_args())
var ticket_started:=false
var ticket_finished:=false
var ticket_last_phase:=""
var ticket_seen:Dictionary={}

static func ticket_configuration(args:PackedStringArray)->Dictionary:
	var phase:="white_native_return";var capacity:=16384;var seen_phase:=false;var seen_capacity:=false
	for arg:String in args:
		if arg.begins_with("--demand-ticket-phase="):
			if seen_phase:return {"error":"duplicate ticket phase"}
			seen_phase=true;phase=arg.trim_prefix("--demand-ticket-phase=")
		elif arg.begins_with("--demand-ticket-capacity="):
			if seen_capacity:return {"error":"duplicate ticket capacity"}
			seen_capacity=true;var value:=arg.trim_prefix("--demand-ticket-capacity=")
			if not value.is_valid_int():return {"error":"invalid ticket capacity"}
			capacity=int(value)
	if phase not in TRACE_PHASES:return {"error":"unsupported ticket phase"}
	if capacity<1 or capacity>16384:return {"error":"ticket capacity outside 1..16384"}
	return {"phase":phase,"capacity":capacity,"error":""}

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":
		for path:String in ["res://tools/profile_axel_demand_tickets.gd","res://tools/diagnostics/demand_ticket_trace.gd"]:result[path]=FileAccess.get_sha256(path)
	return result

func _ticket_boundary(kind:String)->void:
	if not report.has("demand_ticket_boundaries"):
		report.demand_ticket_boundaries=[];report.demand_ticket_boundaries_dropped=0
	if kind in ["start","transition"]:ticket_seen[phase]=true
	if report.demand_ticket_boundaries.size()<MAX_PHASE_BOUNDARIES:
		report.demand_ticket_boundaries.append({"kind":kind,"phase":phase,"ticks_us":Time.get_ticks_usec(),"frame":Engine.get_process_frames()})
	else:report.demand_ticket_boundaries_dropped+=1
	ticket_last_phase=phase

func _stop_ticket_capture()->void:
	ticket_finished=true
	var queue:Node=mesh_map.get_node_or_null("DeferredAssets") if is_instance_valid(mesh_map) else null
	if queue==null:
		report.demand_ticket_status="incomplete_missing_queue";return
	var began:=Time.get_ticks_usec()
	report.demand_ticket_trace=queue.stop_demand_ticket_trace()
	report.demand_ticket_stop_us=Time.get_ticks_usec()-began
	report.demand_ticket_seen_phases=ticket_seen.keys()
	report.demand_ticket_status=completion_status(ticket_config.phase,ticket_seen,int(report.get("demand_ticket_boundaries_dropped",0)))
	if int(report.demand_ticket_trace.dropped)>0:report.demand_ticket_status="incomplete_event_overflow"
	report.demand_ticket_scope="Diagnostic project overlay; counter collection and copying contaminate timing. No original game source modified."

func tick_geometry()->void:
	if ticket_enabled and ticket_config.error.is_empty():
		var action:=capture_action(true,phase,ticket_config.phase,ticket_started,ticket_finished)
		if action=="start":
			var queue:Node=mesh_map.get_node("DeferredAssets")
			queue.start_demand_ticket_trace(ticket_config.capacity);ticket_started=true
			report.demand_ticket_phase=ticket_config.phase;report.demand_ticket_capacity=ticket_config.capacity
			report.demand_ticket_status="capturing";_ticket_boundary("start")
		elif action=="stop":_ticket_boundary("end");_stop_ticket_capture()
		elif ticket_started and not ticket_finished and phase!=ticket_last_phase:_ticket_boundary("transition")
	super.tick_geometry()

func finish(code:int)->void:
	var action:=finish_action(ticket_enabled,ticket_config.error,ticket_started,ticket_finished)
	if action=="invalid_phase":report.demand_ticket_status="invalid_configuration";report.demand_ticket_error=ticket_config.error;check(false,ticket_config.error)
	elif action=="not_started":report.demand_ticket_status="not_started"
	elif action=="stop_incomplete":_ticket_boundary("finish_incomplete");_stop_ticket_capture();report.demand_ticket_status="incomplete_stopped_at_finish"
	await super.finish(code)
