extends SceneTree
## No real map/GPU: exercise the same runner phase and finish decisions.
const Runner=preload("res://tools/profile_axel_demand_revisions.gd")
class FakeQueue extends Node:
	func stop_demand_revision_trace()->Dictionary:return {"events":[],"dropped_changes":0,"dropped_refreshes":0}
var passed:=0
var failed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failed+=1
func run()->void:
	var default_config:Dictionary=Runner.trace_configuration(PackedStringArray())
	check(default_config.error.is_empty() and default_config.phase=="white_native_return","native return remains the default")
	var walk:Dictionary=Runner.trace_configuration(PackedStringArray(["--demand-revision-phase=white_walk_return"]))
	check(walk.error.is_empty() and walk.phase=="white_walk_return","explicit walk return is accepted")
	var native:Dictionary=Runner.trace_configuration(PackedStringArray(["--demand-revision-phase=white_native_return"]))
	check(native.error.is_empty() and native.phase=="white_native_return","explicit native return is accepted")
	for arg:String in ["--demand-revision-phase=", "--demand-revision-phase=white_walk_reload", "--demand-revision-phase=../unexpected"]:
		check(not Runner.trace_configuration(PackedStringArray([arg])).error.is_empty(),"unsupported or empty phase is rejected: "+arg)
	check(not Runner.trace_configuration(PackedStringArray(["--demand-revision-phase=white_walk_return","--demand-revision-phase=white_native_return"])).error.is_empty(),"duplicate phase parameters are rejected")
	check(Runner.capture_action(false,"white_walk_return",walk.phase,false,false)=="none","disabled probe never starts")
	check(Runner.capture_action(true,"white_native_return",walk.phase,false,false)=="none","walk probe does not start on the native leg")
	check(Runner.capture_action(true,"white_walk_return",walk.phase,false,false)=="start","walk probe starts at its chosen phase")
	check(Runner.capture_action(true,"white_walk_return",walk.phase,true,false)=="none","walk probe remains active inside the phase")
	check(Runner.capture_action(true,"white_walk_reload",walk.phase,true,false)=="stop","walk probe stops when the selected phase ends")
	check(Runner.capture_action(true,"white_walk_return",walk.phase,true,true)=="none","a completed capture cannot restart")
	check(Runner.capture_action(true,"white_walk_return_straight",walk.phase,false,false)=="start","real straight segment starts the walk return capture")
	check(Runner.capture_action(true,"white_walk_return_straight",walk.phase,true,false)=="none","real straight segment remains active")
	check(Runner.capture_action(true,"white_walk_return_turn",walk.phase,true,false)=="none","transition to real turn segment keeps the same capture")
	check(Runner.capture_action(true,"white_walk_reload",walk.phase,true,false)=="stop","capture stops after both walk return segments")
	check(Runner.capture_action(true,"white_walk_return_other",walk.phase,false,false)=="none","unlisted walk subphases cannot start capture")
	check(Runner.capture_action(true,"white_walk_return_other",walk.phase,true,false)=="stop","unlisted walk subphases do not extend capture")
	check(Runner.capture_action(true,"white_native_return",native.phase,false,false)=="start","native selection retains its original start")
	check(Runner.capture_action(true,"white_native_reload",native.phase,true,false)=="stop","native selection retains its original stop")
	check(Runner.capture_action(true,"white_native_return_straight",native.phase,false,false)=="none","native target does not accept unlisted subphases")
	var probe=Runner.new()
	probe.report.demand_revision_trace_started_us=Time.get_ticks_usec()
	probe.phase="white_walk_return_straight";probe._mark_revision_boundary("start")
	probe.phase="white_walk_return_turn";probe._mark_revision_boundary("transition")
	probe.phase="white_walk_reload";probe._mark_revision_boundary("end")
	var boundaries:Array=probe.report.demand_revision_trace_boundaries
	check(boundaries.size()==3 and boundaries[0].kind=="start" and boundaries[0].phase=="white_walk_return_straight" and boundaries[1].kind=="transition" and boundaries[1].phase=="white_walk_return_turn" and boundaries[2].kind=="end" and boundaries[2].phase=="white_walk_reload","actual straight, turn and exit boundaries are separately recorded")
	check(int(boundaries[0].at_us)<=int(boundaries[1].at_us) and int(boundaries[1].at_us)<=int(boundaries[2].at_us),"boundary times are monotonic relative to capture start")
	for i:int in 65:probe._mark_revision_boundary("transition")
	check(probe.report.demand_revision_trace_boundaries.size()==Runner.MAX_PHASE_BOUNDARIES and int(probe.report.demand_revision_trace_boundaries_dropped)==4,"phase boundary events stay bounded and report all drops")
	probe.free()
	check(Runner.completion_status(walk.phase,{"white_walk_return_straight":true},0)=="incomplete_missing_walk_segment","straight-only walk trace is incomplete")
	check(Runner.completion_status(walk.phase,{"white_walk_return_turn":true},0)=="incomplete_missing_walk_segment","turn-only walk trace is incomplete")
	check(Runner.completion_status(walk.phase,{"white_walk_return_straight":true,"white_walk_return_turn":true},0)=="complete_return_leg","both walk segments prove complete coverage")
	check(Runner.completion_status(walk.phase,{"white_walk_return":true},0)=="complete_return_leg","unsplit parent phase remains a valid whole walk leg")
	check(Runner.completion_status(walk.phase,{"white_walk_return_straight":true,"white_walk_return_turn":true},1)=="incomplete_boundary_overflow","dropped boundary invalidates coverage")
	check(Runner.completion_status(native.phase,{"white_native_return":true},0)=="complete_return_leg","native completion remains unchanged")
	var coverage=Runner.new();var map:=Node3D.new();var queue:=FakeQueue.new();queue.name="DeferredAssets";map.add_child(queue)
	coverage.mesh_map=map;coverage.revision_trace_config=walk
	coverage.revision_capture_seen_phases={"white_walk_return_straight":true};coverage._stop_revision_capture()
	check(coverage.report.demand_revision_trace_status=="incomplete_missing_walk_segment" and coverage.report.demand_revision_trace_seen_phases.has("white_walk_return_straight"),"real stop reports a missing turn segment")
	coverage.revision_capture_seen_phases["white_walk_return_turn"]=true;coverage._stop_revision_capture()
	check(coverage.report.demand_revision_trace_status=="complete_return_leg" and coverage.report.demand_revision_trace_seen_phases.has("white_walk_return_turn"),"real stop reports complete split-leg coverage")
	coverage.report.demand_revision_trace_boundaries_dropped=1;coverage._stop_revision_capture()
	check(coverage.report.demand_revision_trace_status=="incomplete_boundary_overflow","real stop reports truncated boundary coverage")
	map.free();coverage.free()
	check(Runner.finish_action(false,"",false,false)=="none","disabled runner does not invent a capture status")
	check(Runner.finish_action(true,"bad phase",false,false)=="invalid_phase","invalid selection explicitly fails")
	check(Runner.finish_action(true,"",false,false)=="not_started","exit before selected leg is incomplete")
	check(Runner.finish_action(true,"",true,false)=="stop_incomplete","exit during an open capture is incomplete")
	check(Runner.finish_action(true,"",true,true)=="none","completed capture status survives finish")
	print("DEMAND_REVISION_PROFILE_CONFIG passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
