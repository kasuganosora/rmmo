extends SceneTree
## Headless lifecycle/contract test only; no map, GPU, or performance claim.
const Runner=preload("res://tools/profile_axel_return_material_trace.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
var passed:=0
var failed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failed+=1
func run()->void:
	check(Runner.capture_action(false,false,"white_native_return",false,false)=="none","probe remains disabled without its flag")
	check(Runner.capture_action(true,false,"white_native_return",false,false)=="invalid_configuration","texture profiling is required for upload detail")
	check(Runner.capture_action(true,true,"white_native_reload",false,false)=="none","reload cannot start return capture")
	check(Runner.capture_action(true,true,"white_native_return",false,false)=="start","return leg starts capture")
	check(Runner.capture_action(true,true,"white_native_return",true,false)=="none","capture remains active during return")
	check(Runner.capture_action(true,true,"white_native_reload",true,false)=="stop","capture stops on departure from return")
	check(Runner.capture_action(true,true,"white_native_return",true,true)=="none","completed capture cannot restart")
	check(not Trace.enabled,"fixture starts with no shared trace")
	var saved_min:=Trace.minimum_event_us;var saved_methods:=Trace.methods_enabled;var saved_labels:=Trace.method_labels.duplicate()
	Trace.minimum_event_us=321;Trace.methods_enabled=false;Trace.method_labels={"sentinel":true}
	var probe=Runner.new()
	check(probe._start_material_trace() and Trace.enabled,"start enables recorder")
	check(Trace.minimum_event_us==1000 and Trace.methods_enabled and Trace.method_labels.has("method.ground_cpu_mesh.restore"),"start selects bounded material methods")
	var began:=Time.get_ticks_usec()-3000
	Trace.elapsed("deferred.material_step",began,{"uuid":"fixture_uuid","path":"fixture_path","phase":1})
	Trace.elapsed("paint.texture.upload",began,{"path":"fixture_texture","width":64,"height":64,"format":5,"bytes":4096})
	probe._stop_material_trace(true)
	var captured:Dictionary=probe.report.return_material_trace
	check(probe.report.return_material_trace_status=="complete_return_leg" and not Trace.enabled,"complete return stops recorder")
	check(Trace.minimum_event_us==321 and not Trace.methods_enabled and Trace.method_labels.has("sentinel"),"stop restores previous recorder configuration")
	check(captured.dropped==0 and captured.events.size()==2,"trace exposes events and drop count")
	var step:Dictionary=captured.events[0];var upload:Dictionary=captured.events[1]
	check(step.label=="deferred.material_step" and step.details.uuid=="fixture_uuid" and step.details.path=="fixture_path" and step.details.phase==1,"material step preserves identity and phase")
	check(upload.label=="paint.texture.upload" and upload.details.path=="fixture_texture" and upload.details.bytes==4096,"texture upload preserves path and size")
	check(step.thread_id==OS.get_thread_caller_id() and step.start_us==began and step.end_us>=step.start_us,"events carry Godot thread ID and engine ticks")
	probe.free()
	var interrupted=Runner.new();check(interrupted._start_material_trace(),"second recorder can start after stop")
	interrupted._stop_material_trace(false)
	check(interrupted.report.return_material_trace_status=="incomplete_stopped_at_finish" and not Trace.enabled,"interrupted window cannot report complete")
	interrupted.free()
	Trace.start();Trace.elapsed("prior_event",began,{})
	var conflicting=Runner.new()
	check(not conflicting._start_material_trace() and conflicting.report.return_material_trace_status=="incomplete_trace_already_active","existing recorder is not replaced")
	var original:Dictionary=Trace.stop()
	check(original.events.size()==1 and original.events[0].label=="prior_event","existing recorder buffer remains intact")
	conflicting.free()
	Trace.minimum_event_us=saved_min;Trace.methods_enabled=saved_methods;Trace.method_labels=saved_labels
	print("RETURN_MATERIAL_TRACE_CONFIG passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
