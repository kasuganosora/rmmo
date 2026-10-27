extends "res://tools/profile_axel_worker_capacity.gd"
## Diagnostic-only return-leg wall spans. No scheduler or budget changes.
## --return-material-trace requires --texture-stage-profile: the existing
## texture profiler emits path/format/size details into the shared LoadTrace.
const TRACE_ARG:="--return-material-trace"
const PROFILE_ARG:="--texture-stage-profile"
const MATERIAL_LABELS:=["method.surface_materials.make_material","method.surface_materials._make_material","method.ground_cpu_mesh.restore","method.world_document._mesh"]
var material_trace_enabled:=TRACE_ARG in OS.get_cmdline_user_args()
var material_trace_valid:=PROFILE_ARG in OS.get_cmdline_user_args()
var material_trace_started:=false
var material_trace_finished:=false
var material_trace_previous:Dictionary={}

static func capture_action(enabled:bool,profile_enabled:bool,current_phase:String,started:bool,finished:bool)->String:
	if not enabled or finished:return "none"
	if not profile_enabled:return "invalid_configuration"
	if not started and current_phase=="white_native_return":return "start"
	if started and current_phase!="white_native_return":return "stop"
	return "none"

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_return_material_trace.gd"]=FileAccess.get_sha256("res://tools/profile_axel_return_material_trace.gd")
	return result

func _start_material_trace()->bool:
	# Never overwrite another recorder's event buffer. A missing capture is
	# explicitly incomplete rather than an empty set of slow events.
	if Trace.enabled:
		report.return_material_trace_status="incomplete_trace_already_active"
		material_trace_finished=true
		return false
	material_trace_previous={"minimum_event_us":Trace.minimum_event_us,"methods_enabled":Trace.methods_enabled,"method_labels":Trace.method_labels.duplicate()}
	Trace.minimum_event_us=1000
	Trace.methods_enabled=true
	Trace.method_labels={}
	for label:String in MATERIAL_LABELS:Trace.method_labels[label]=true
	Trace.start()
	material_trace_started=true
	report.return_material_trace_started_us=Time.get_ticks_usec()
	report.return_material_trace_start_frame=Engine.get_process_frames()
	report.return_material_trace_status="capturing"
	return true

func _stop_material_trace(complete:bool)->void:
	if not material_trace_started or material_trace_finished:return
	var began_stop:=Time.get_ticks_usec()
	var result:Dictionary=Trace.stop()
	Trace.minimum_event_us=int(material_trace_previous.minimum_event_us)
	Trace.methods_enabled=bool(material_trace_previous.methods_enabled)
	Trace.method_labels=material_trace_previous.method_labels
	material_trace_finished=true
	report.return_material_trace=result
	report.return_material_trace_stopped_us=Time.get_ticks_usec()
	report.return_material_trace_stop_frame=Engine.get_process_frames()
	report.return_material_trace_stop_us=Time.get_ticks_usec()-began_stop
	report.return_material_trace_status="complete_return_leg" if complete else "incomplete_stopped_at_finish"
	report.return_material_trace_contract="Bounded opt-in wall spans between observed return ticks; timestamps share engine ticks, thread IDs are Godot IDs, not Windows TIDs. Spans overlap and include recorder overhead. record_us does not capture all probe/serialization cost. READY and PROGRESS are separate paths. A complete status with dropped > 0 still has incomplete event coverage."

func tick_geometry()->void:
	var action:=capture_action(material_trace_enabled,material_trace_valid,phase,material_trace_started,material_trace_finished)
	if action=="invalid_configuration":
		report.return_material_trace_status="invalid_configuration"
		material_trace_finished=true
		check(false,"return material trace requires --texture-stage-profile")
	elif action=="start":_start_material_trace()
	elif action=="stop":_stop_material_trace(true)
	super.tick_geometry()

func finish(code:int)->void:
	# The parent's finish starts the traversal; a non-started flag here cannot
	# prove its return leg was absent. Final analysis must require an explicit
	# complete_return_leg status and dropped == 0.
	if material_trace_enabled and material_trace_started and not material_trace_finished:_stop_material_trace(false)
	await super.finish(code)
